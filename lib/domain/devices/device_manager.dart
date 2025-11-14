/// Manages multiple fitness devices and aggregates their data streams.
///
/// This is the central coordinator for all connected devices. It maintains
/// a collection of devices and assigns them to specific roles (smart trainer,
/// power source, cadence source, heart rate source). It then aggregates data
/// from assigned devices into unified streams.
///
/// Example usage:
/// ```dart
/// final manager = DeviceManager();
///
/// // Add devices
/// await manager.addDevice(myTrainer);
/// await manager.addDevice(myHrMonitor);
///
/// // Assign devices to roles
/// manager.assignSmartTrainer(myTrainer.id);
/// manager.assignHeartRateSource(myHrMonitor.id);
///
/// // Listen to aggregated data
/// manager.powerStream.listen((power) {
///   print('Current power: ${power.watts}W');
/// });
/// ```
///
/// The aggregated streams automatically switch sources when device assignments
/// change, and handle cases where devices don't support specific data types.
///
/// Used by [WorkoutSyncService] for trainer control and by UI screens to
/// display real-time fitness data.
library;

import 'dart:async';

import 'package:async/async.dart';
import 'package:flutter/foundation.dart';
import 'package:state_beacon/state_beacon.dart';
import 'package:chirp/chirp.dart';
import 'package:vekolo/ble/ble_device.dart';
import 'package:vekolo/ble/ble_platform.dart' hide LogLevel;
import 'package:vekolo/ble/ble_scanner.dart';
import 'package:vekolo/ble/transport_registry.dart';
import 'package:vekolo/domain/beacons/staleness_beacon.dart';
import 'package:vekolo/domain/devices/assigned_device.dart';
import 'package:vekolo/domain/devices/fitness_device.dart';
import 'package:vekolo/domain/models/device_info.dart';
import 'package:vekolo/domain/models/fitness_data.dart';
import 'package:vekolo/services/device_assignment_persistence.dart';

/// Manages multiple devices and aggregates data streams.
///
/// This class coordinates device connections, assignments, and data aggregation.
/// It provides a clean API for the rest of the app to work with fitness devices
/// without knowing implementation details.
class DeviceManager {
  DeviceManager({
    required this.platform,
    required this.scanner,
    required this.transportRegistry,
    required this.persistence,
  }) {
    _setupStalenessAwareStreams();
  }

  /// BLE platform for device connection management.
  final BlePlatform platform;

  /// BLE scanner for device discovery and auto-connect.
  final BleScanner scanner;

  /// Transport registry for detecting compatible transports and creating devices.
  final TransportRegistry transportRegistry;

  /// Persistence service for saving/loading device assignments.
  final DeviceAssignmentPersistence persistence;

  /// Staleness threshold - data older than this is considered stale and returns null.
  static const Duration _stalenessThreshold = Duration(seconds: 5);

  // ============================================================================
  // Device Collection
  // ============================================================================

  /// All connected devices managed by this manager.
  final List<FitnessDevice> _devices = [];

  /// Reactive beacon for device list changes.
  final WritableBeacon<List<FitnessDevice>> _devicesBeacon = Beacon.list([]);

  /// Connection state subscriptions for each device (for auto-reconnect monitoring).
  final Map<String, void Function()> _deviceConnectionSubscriptions = {};

  // ============================================================================
  // Device Assignments
  // ============================================================================

  /// Smart trainer for ERG control, can also provide power/cadence data.
  AssignedDevice? _smartTrainer;
  final WritableBeacon<AssignedDevice?> _smartTrainerBeacon = Beacon.writable(null);

  /// Dedicated power meter, overrides trainer's power if assigned.
  AssignedDevice? _powerSource;
  final WritableBeacon<AssignedDevice?> _powerSourceBeacon = Beacon.writable(null);

  /// Dedicated cadence sensor, overrides trainer's cadence if assigned.
  AssignedDevice? _cadenceSource;
  final WritableBeacon<AssignedDevice?> _cadenceSourceBeacon = Beacon.writable(null);

  /// Dedicated speed sensor, overrides trainer's speed if assigned.
  AssignedDevice? _speedSource;
  final WritableBeacon<AssignedDevice?> _speedSourceBeacon = Beacon.writable(null);

  /// Dedicated heart rate monitor.
  AssignedDevice? _heartRateSource;
  final WritableBeacon<AssignedDevice?> _heartRateSourceBeacon = Beacon.writable(null);

  // ============================================================================
  // Beacons for Aggregated Data (with staleness detection)
  // ============================================================================

  /// Staleness-aware beacons for each data stream.
  late final StalenessBeacon<PowerData> _powerBeacon;
  late final StalenessBeacon<CadenceData> _cadenceBeacon;
  late final StalenessBeacon<SpeedData> _speedBeacon;
  late final StalenessBeacon<HeartRateData> _heartRateBeacon;

  // ============================================================================
  // Aggregated Streams (Public API)
  // ============================================================================

  /// Aggregated power data beacon from assigned power source.
  ///
  /// Emits power data from:
  /// 1. Dedicated [powerSource] if assigned and supports power
  /// 2. Otherwise from [smartTrainer] if it supports power
  /// 3. No data if neither source is assigned or supports power
  ///
  /// Beacon automatically switches when device assignments change.
  ReadableBeacon<PowerData?> get powerStream => _powerBeacon;

  /// Aggregated cadence data beacon from assigned cadence source.
  ///
  /// Emits cadence data from:
  /// 1. Dedicated [cadenceSource] if assigned and supports cadence
  /// 2. Otherwise from [smartTrainer] if it supports cadence
  /// 3. No data if neither source is assigned or supports cadence
  ///
  /// Beacon automatically switches when device assignments change.
  ReadableBeacon<CadenceData?> get cadenceStream => _cadenceBeacon;

  /// Aggregated speed data beacon from assigned speed source.
  ///
  /// Emits speed data from:
  /// 1. Dedicated [speedSource] if assigned and supports speed
  /// 2. Otherwise from [smartTrainer] if it supports speed
  /// 3. No data if neither source is assigned or supports speed
  ///
  /// Beacon automatically switches when device assignments change.
  ReadableBeacon<SpeedData?> get speedStream => _speedBeacon;

  /// Aggregated heart rate data beacon from assigned HR source.
  ///
  /// Emits heart rate data from [heartRateSource] if assigned and supports HR.
  /// No fallback to trainer since trainers don't typically provide HR data.
  ///
  /// Beacon automatically switches when device assignment changes.
  ReadableBeacon<HeartRateData?> get heartRateStream => _heartRateBeacon;

  bool _disposed = false;

  // ============================================================================
  // Device Management API
  // ============================================================================

  /// Adds a device to the manager's collection.
  ///
  /// The device is not automatically assigned to any role. Use assign methods
  /// to designate the device as a power source, cadence source, etc.
  ///
  /// Throws [ArgumentError] if a device with the same ID already exists.
  Future<void> addDevice(FitnessDevice device) async {
    if (_devices.any((d) => d.id == device.id)) {
      throw ArgumentError('Device with id ${device.id} already exists');
    }

    _devices.add(device);
    _devicesBeacon.value = List.unmodifiable(_devices);

    // Monitor device connection state for auto-reconnect
    _setupDeviceConnectionMonitoring(device);
  }

  /// Adds a device or returns the existing device if one with the same ID exists.
  ///
  /// This is useful for reconnection scenarios where a device may have disconnected
  /// but is still in the manager. If a device with the same ID already exists,
  /// that device instance is returned. Otherwise, the new device is added and returned.
  ///
  /// The device is not automatically assigned to any role. Use assign methods
  /// to designate the device as a power source, cadence source, etc.
  ///
  /// Returns the device instance (either existing or newly added).
  Future<FitnessDevice> addOrGetExistingDevice(FitnessDevice device) async {
    final existing = _devices.where((d) => d.id == device.id).firstOrNull;
    if (existing != null) {
      return existing;
    }

    _devices.add(device);
    _devicesBeacon.value = List.unmodifiable(_devices);

    // Monitor device connection state for auto-reconnect
    _setupDeviceConnectionMonitoring(device);

    return device;
  }

  /// Removes a device from the manager and clears any role assignments.
  ///
  /// Disconnects the device before removing it. If the device was assigned to any role
  /// (trainer, power, cadence, HR), that assignment is cleared and the corresponding
  /// aggregated stream will stop emitting data from this device.
  ///
  /// Throws [ArgumentError] if no device with the given ID exists.
  Future<void> removeDevice(String deviceId) async {
    final device = _devices.where((d) => d.id == deviceId).firstOrNull;
    if (device == null) {
      throw ArgumentError('Device with id $deviceId not found');
    }

    // Disconnect before removing
    await disconnectDevice(deviceId);

    // Track if any assignments were cleared
    bool assignmentsChanged = false;

    // Clear all assignments for this device
    if (_smartTrainer?.deviceId == deviceId) {
      _smartTrainer = null;
      _smartTrainerBeacon.value = null;
      assignmentsChanged = true;
    }
    if (_powerSource?.deviceId == deviceId) {
      _powerSource = null;
      _powerSourceBeacon.value = null;
      assignmentsChanged = true;
    }
    if (_cadenceSource?.deviceId == deviceId) {
      _cadenceSource = null;
      _cadenceSourceBeacon.value = null;
      assignmentsChanged = true;
    }
    if (_speedSource?.deviceId == deviceId) {
      _speedSource = null;
      _speedSourceBeacon.value = null;
      assignmentsChanged = true;
    }
    if (_heartRateSource?.deviceId == deviceId) {
      _heartRateSource = null;
      _heartRateSourceBeacon.value = null;
      assignmentsChanged = true;
    }

    // Persist assignment changes
    if (assignmentsChanged) {
      _saveAssignmentsAsync(_buildDeviceAssignments());
      // Remove from auto-connect and stop scanning if needed
      _handleDeviceUnassigned(deviceId);
    }

    // Cancel connection state monitoring
    _deviceConnectionSubscriptions[deviceId]?.call();
    _deviceConnectionSubscriptions.remove(deviceId);

    // Clear manual disconnect flag
    _manuallyDisconnectedDeviceIds.remove(deviceId);

    _devices.remove(device);
    _devicesBeacon.value = List.unmodifiable(_devices);
  }

  // ============================================================================
  // Connection Management
  // ============================================================================

  /// Connects to a device managed by this manager.
  ///
  /// Initiates connection to the device with the given [deviceId]. The device must
  /// already be added to the manager via [addDevice] or [addOrGetExistingDevice].
  ///
  /// If the device was previously manually disconnected, this clears that flag,
  /// allowing auto-reconnect to work again if the device has an assigned role.
  ///
  /// Returns a [CancelableOperation] that can be cancelled during connection.
  /// Cancelling will stop the connection attempt and clean up resources.
  ///
  /// Throws [ArgumentError] if no device with the given ID exists.
  CancelableOperation<void> connectDevice(String deviceId) {
    final device = _findDevice(deviceId);

    // Clear manual disconnect flag when user manually connects
    _manuallyDisconnectedDeviceIds.remove(deviceId);

    return device.connect();
  }

  /// Disconnects from a device managed by this manager.
  ///
  /// Cleanly tears down the connection to the device with the given [deviceId].
  /// The device remains in the manager but is disconnected.
  ///
  /// This is treated as a user-initiated disconnect, so auto-reconnect will NOT
  /// trigger even if the device has an assigned role. To re-enable auto-reconnect,
  /// the user must manually reconnect via [connectDevice].
  ///
  /// Safe to call even if the device is already disconnected.
  ///
  /// Throws [ArgumentError] if no device with the given ID exists.
  Future<void> disconnectDevice(String deviceId) async {
    final device = _findDevice(deviceId);

    // Mark as manually disconnected to prevent auto-reconnect
    _manuallyDisconnectedDeviceIds.add(deviceId);

    await device.disconnect();
  }

  // ============================================================================
  // Device Assignment Methods
  // ============================================================================

  /// Assigns a device as the smart trainer for ERG control.
  ///
  /// The smart trainer can:
  /// - Be controlled via [setTargetPower] for ERG mode workouts
  /// - Serve as fallback power source if no dedicated power meter is assigned
  /// - Serve as fallback cadence source if no dedicated cadence sensor is assigned
  ///
  /// Throws [ArgumentError] if device not found or doesn't support ERG mode.
  /// Pass null to unassign the smart trainer.
  void assignSmartTrainer(String? deviceId) {
    if (deviceId == null) {
      final oldDeviceId = _smartTrainer?.deviceId;
      _smartTrainer = null;
      _smartTrainerBeacon.value = null;
      _saveAssignmentsAsync(_buildDeviceAssignments());
      if (oldDeviceId != null) {
        _handleDeviceUnassigned(oldDeviceId);
      }
      return;
    }

    final device = _findDevice(deviceId);

    if (!device.supportsErgMode) {
      throw ArgumentError('Device $deviceId does not support ERG mode');
    }

    final assigned = AssignedDevice.fromDevice(device);
    _smartTrainer = assigned;
    _smartTrainerBeacon.value = assigned;
    _saveAssignmentsAsync(_buildDeviceAssignments());
  }

  /// Assigns a device as the dedicated power source.
  ///
  /// Power data will come from this device, overriding any power data from
  /// the smart trainer. Useful when using a dedicated power meter that's
  /// more accurate than the trainer's built-in power measurement.
  ///
  /// Throws [ArgumentError] if device not found or doesn't provide power data.
  /// Pass null to unassign the power source.
  void assignPowerSource(String? deviceId) {
    if (deviceId == null) {
      final oldDeviceId = _powerSource?.deviceId;
      _powerSource = null;
      _powerSourceBeacon.value = null;
      _saveAssignmentsAsync(_buildDeviceAssignments());
      if (oldDeviceId != null) {
        _handleDeviceUnassigned(oldDeviceId);
      }
      return;
    }

    final device = _findDevice(deviceId);

    if (!device.capabilities.contains(DeviceDataType.power)) {
      throw ArgumentError('Device $deviceId does not provide power data');
    }

    final assigned = AssignedDevice.fromDevice(device);
    _powerSource = assigned;
    _powerSourceBeacon.value = assigned;
    _saveAssignmentsAsync(_buildDeviceAssignments());
  }

  /// Assigns a device as the dedicated cadence source.
  ///
  /// Cadence data will come from this device, overriding any cadence data from
  /// the smart trainer. Useful when using a dedicated cadence sensor.
  ///
  /// Throws [ArgumentError] if device not found or doesn't provide cadence data.
  void assignCadenceSource(String? deviceId) {
    if (deviceId == null) {
      final oldDeviceId = _cadenceSource?.deviceId;
      _cadenceSource = null;
      _cadenceSourceBeacon.value = null;
      _saveAssignmentsAsync(_buildDeviceAssignments());
      if (oldDeviceId != null) {
        _handleDeviceUnassigned(oldDeviceId);
      }
      return;
    }

    final device = _findDevice(deviceId);

    if (!device.capabilities.contains(DeviceDataType.cadence)) {
      throw ArgumentError('Device $deviceId does not provide cadence data');
    }

    final assigned = AssignedDevice.fromDevice(device);
    _cadenceSource = assigned;
    _cadenceSourceBeacon.value = assigned;
    _saveAssignmentsAsync(_buildDeviceAssignments());
  }

  /// Assigns a device as the dedicated speed source.
  ///
  /// Speed data will come from this device, overriding any speed data from
  /// the smart trainer. Useful when using a dedicated speed sensor.
  ///
  /// Throws [ArgumentError] if device not found or doesn't provide speed data.
  void assignSpeedSource(String? deviceId) {
    if (deviceId == null) {
      final oldDeviceId = _speedSource?.deviceId;
      _speedSource = null;
      _speedSourceBeacon.value = null;
      _saveAssignmentsAsync(_buildDeviceAssignments());
      if (oldDeviceId != null) {
        _handleDeviceUnassigned(oldDeviceId);
      }
      return;
    }

    final device = _findDevice(deviceId);

    if (!device.capabilities.contains(DeviceDataType.speed)) {
      throw ArgumentError('Device $deviceId does not provide speed data');
    }

    final assigned = AssignedDevice.fromDevice(device);
    _speedSource = assigned;
    _speedSourceBeacon.value = assigned;
    _saveAssignmentsAsync(_buildDeviceAssignments());
  }

  /// Assigns a device as the heart rate source.
  ///
  /// Heart rate data will come from this device. There's no fallback to the
  /// trainer since trainers don't typically provide HR data.
  ///
  /// Throws [ArgumentError] if device not found or doesn't provide HR data.
  /// Pass null to unassign the heart rate source.
  void assignHeartRateSource(String? deviceId) {
    if (deviceId == null) {
      final oldDeviceId = _heartRateSource?.deviceId;
      _heartRateSource = null;
      _heartRateSourceBeacon.value = null;
      _saveAssignmentsAsync(_buildDeviceAssignments());
      if (oldDeviceId != null) {
        _handleDeviceUnassigned(oldDeviceId);
      }
      return;
    }

    final device = _findDevice(deviceId);

    if (!device.capabilities.contains(DeviceDataType.heartRate)) {
      throw ArgumentError('Device $deviceId does not provide heart rate data');
    }

    final assigned = AssignedDevice.fromDevice(device);
    _heartRateSource = assigned;
    _heartRateSourceBeacon.value = assigned;
    _saveAssignmentsAsync(_buildDeviceAssignments());
  }

  // ============================================================================
  // Query Methods
  // ============================================================================

  /// Returns all devices managed by this manager.
  ///
  /// Returns an unmodifiable view to prevent external modifications.
  List<FitnessDevice> get devices => List.unmodifiable(_devices);

  /// Reactive beacon of all connected devices.
  ReadableBeacon<List<FitnessDevice>> get devicesBeacon => _devicesBeacon;

  /// Reactive beacon of smart trainer assignment.
  ReadableBeacon<AssignedDevice?> get smartTrainerBeacon => _smartTrainerBeacon;

  /// Reactive beacon of power source assignment.
  ReadableBeacon<AssignedDevice?> get powerSourceBeacon => _powerSourceBeacon;

  /// Reactive beacon of cadence source assignment.
  ReadableBeacon<AssignedDevice?> get cadenceSourceBeacon => _cadenceSourceBeacon;

  /// Reactive beacon of speed source assignment.
  ReadableBeacon<AssignedDevice?> get speedSourceBeacon => _speedSourceBeacon;

  /// Reactive beacon of heart rate source assignment.
  ReadableBeacon<AssignedDevice?> get heartRateSourceBeacon => _heartRateSourceBeacon;

  // ============================================================================
  // Auto-Connect State
  // ============================================================================

  /// Devices that should be auto-connected (saved assignments).
  final Set<String> _autoConnectDeviceIds = {};

  /// Devices currently being connected (to prevent duplicate connection attempts).
  final Set<String> _connectingDeviceIds = {};

  /// Devices that were manually disconnected by the user (should not auto-reconnect).
  final Set<String> _manuallyDisconnectedDeviceIds = {};

  /// Subscription for auto-saving assignments when they change.
  void Function()? _assignmentsPersistenceUnsubscribe;

  /// Scan token for auto-connect scanning.
  ScanToken? _autoConnectScanToken;

  /// Subscription to scanner devices for auto-connect.
  VoidCallback? _scannerDevicesUnsubscribe;

  // ============================================================================
  // Helper Methods
  // ============================================================================

  /// Sets up staleness-aware data streams with automatic null emission.
  ///
  /// For each metric (power, cadence, speed, heart rate), this creates a derived beacon
  /// that selects the appropriate device data source, then wraps it with staleness detection.
  /// When new data arrives:
  /// 1. The data is immediately emitted to the beacon
  /// 2. Any existing staleness timer is cancelled
  /// 3. A new 5-second timer is started
  /// 4. If the timer fires (no new data for 5s), null is emitted
  ///
  /// This ensures that stale data automatically becomes null without requiring
  /// periodic polling or manual subscriptions.
  void _setupStalenessAwareStreams() {
    // Power stream: derived beacon selecting the appropriate device, with staleness detection
    _powerBeacon = Beacon.derived(() {
      final powerSource = _powerSourceBeacon.value?.connectedDevice;
      final smartTrainer = _smartTrainerBeacon.value?.connectedDevice;
      final device = powerSource ?? smartTrainer;
      return device?.powerStream?.value;
    }).withStalenessDetection(threshold: _stalenessThreshold);

    // Cadence stream: derived beacon selecting the appropriate device, with staleness detection
    _cadenceBeacon = Beacon.derived(() {
      final cadenceSource = _cadenceSourceBeacon.value?.connectedDevice;
      final smartTrainer = _smartTrainerBeacon.value?.connectedDevice;
      final device = cadenceSource ?? smartTrainer;
      return device?.cadenceStream?.value;
    }).withStalenessDetection(threshold: _stalenessThreshold);

    // Speed stream: derived beacon selecting the appropriate device, with staleness detection
    _speedBeacon = Beacon.derived(() {
      final speedSource = _speedSourceBeacon.value?.connectedDevice;
      final smartTrainer = _smartTrainerBeacon.value?.connectedDevice;
      final device = speedSource ?? smartTrainer;
      return device?.speedStream?.value;
    }).withStalenessDetection(threshold: _stalenessThreshold);

    // Heart rate stream: derived beacon selecting the appropriate device, with staleness detection
    _heartRateBeacon = Beacon.derived(() {
      final heartRateSource = _heartRateSourceBeacon.value?.connectedDevice;
      return heartRateSource?.heartRateStream?.value;
    }).withStalenessDetection(threshold: _stalenessThreshold);
  }

  /// Finds a device by ID or throws [ArgumentError] if not found.
  FitnessDevice _findDevice(String deviceId) {
    final device = _devices.where((d) => d.id == deviceId).firstOrNull;
    if (device == null) {
      throw ArgumentError('Device with id $deviceId not found');
    }
    return device;
  }

  DeviceAssignments _buildDeviceAssignments() {
    return DeviceAssignments(
      smartTrainer: _smartTrainer != null
          ? DeviceAssignment(
              deviceId: _smartTrainer!.deviceId,
              deviceName: _smartTrainer!.deviceName,
              transport: _smartTrainer!.transport,
            )
          : null,
      powerSource: _powerSource != null
          ? DeviceAssignment(
              deviceId: _powerSource!.deviceId,
              deviceName: _powerSource!.deviceName,
              transport: _powerSource!.transport,
            )
          : null,
      cadenceSource: _cadenceSource != null
          ? DeviceAssignment(
              deviceId: _cadenceSource!.deviceId,
              deviceName: _cadenceSource!.deviceName,
              transport: _cadenceSource!.transport,
            )
          : null,
      speedSource: _speedSource != null
          ? DeviceAssignment(
              deviceId: _speedSource!.deviceId,
              deviceName: _speedSource!.deviceName,
              transport: _speedSource!.transport,
            )
          : null,
      heartRateSource: _heartRateSource != null
          ? DeviceAssignment(
              deviceId: _heartRateSource!.deviceId,
              deviceName: _heartRateSource!.deviceName,
              transport: _heartRateSource!.transport,
            )
          : null,
    );
  }

  /// Saves device assignments asynchronously (fire-and-forget).
  /// Updates the saved assignments beacon, which triggers auto-persistence.
  Future<void> _saveAssignmentsAsync(DeviceAssignments assignments) async {
    try {
      await persistence.saveAssignments(
        smartTrainer: assignments.smartTrainer,
        powerSource: assignments.powerSource,
        cadenceSource: assignments.cadenceSource,
        speedSource: assignments.speedSource,
        heartRateSource: assignments.heartRateSource,
      );
    } catch (e, stack) {
      chirp.error('Failed to persist assignments', error: e, stackTrace: stack);
    }
  }

  // ============================================================================
  // Lifecycle
  // ============================================================================

  /// Initializes auto-connect by loading saved assignments and attempting to reconnect.
  ///
  /// This should be called after the app has fully initialized (e.g., in app._initialize()).
  /// It will:
  /// 1. Load saved device assignments
  /// 2. Check for already discovered devices in scanner
  /// 3. Connect to devices that are already discovered
  /// 4. Start scanning for missing devices
  /// 5. Connect and restore assignments when devices are found
  ///
  /// Errors are logged but don't block initialization. Unavailable devices are silently skipped.
  Future<void> initialize() async {
    final assignments = await persistence.loadAssignments();
    _restoreAssignments(assignments);
    _startAutoConnectIfNeeded(assignments);
  }

  /// Starts auto-connect scanning if there are saved device assignments.
  void _startAutoConnectIfNeeded(DeviceAssignments assignments) {
    Set<String> _extractDeviceIds(DeviceAssignments assignments) {
      return {
        if (assignments.smartTrainer != null) assignments.smartTrainer!.deviceId,
        if (assignments.powerSource != null) assignments.powerSource!.deviceId,
        if (assignments.cadenceSource != null) assignments.cadenceSource!.deviceId,
        if (assignments.speedSource != null) assignments.speedSource!.deviceId,
        if (assignments.heartRateSource != null) assignments.heartRateSource!.deviceId,
      };
    }

    final deviceIds = _extractDeviceIds(assignments);
    if (deviceIds.isNotEmpty) {
      _autoConnectDeviceIds.addAll(deviceIds);

      chirp.info('Found ${deviceIds.length} device(s) to auto-connect');
      _startAutoConnectScanning();
    }
  }

  /// Connects to a device during auto-connect.
  Future<void> _connectAndRestoreDevice(String deviceId) async {
    // Check if device already exists in manager
    final existingDevice = _devices.where((d) => d.id == deviceId).firstOrNull;
    if (existingDevice != null) {
      // Device already exists, just connect if needed
      if (existingDevice.connectionState.value != ConnectionState.connected) {
        await connectDevice(deviceId).value;
      }
      return;
    }

    // Device doesn't exist, need to create it from discovered device
    final discoveredDevices = scanner.devices.value;
    final discovered = discoveredDevices.where((d) => d.deviceId == deviceId).firstOrNull;
    if (discovered == null) {
      throw Exception('Device $deviceId not found in scanner');
    }

    // Detect compatible transports
    final transports = transportRegistry.detectCompatibleTransports(discovered, deviceId: deviceId);

    if (transports.isEmpty) {
      throw Exception('No compatible transports found for device $deviceId');
    }

    // Create device
    final device = BleDevice(
      id: deviceId,
      name: discovered.name ?? 'Unknown Device',
      transports: transports,
      platform: platform,
      discoveredDevice: discovered,
    );

    // Add to manager
    await addDevice(device);

    // Connect
    await connectDevice(deviceId).value;
  }

  /// Restores role assignments for all connected devices from saved assignments.
  ///
  /// Iterates through all saved assignments and attempts to restore them for
  /// devices that are already connected. Used during initialization.
  void _restoreAssignments(DeviceAssignments assignments) {
    if (assignments.isEmpty) {
      chirp.info('No need to restore (empty) assignments');
      return;
    }
    // Create AssignedDevice wrappers from persisted assignments
    // Devices are not connected yet, so connectedDevice will be null
    // These will be updated with actual device references in _restoreAssignmentsForDevice

    if (assignments.smartTrainer != null) {
      final assignment = assignments.smartTrainer!;
      _smartTrainer = AssignedDevice(
        deviceId: assignment.deviceId,
        deviceName: assignment.deviceName,
        transport: assignment.transport,
      );
      _smartTrainerBeacon.value = _smartTrainer;
    }

    if (assignments.powerSource != null) {
      final assignment = assignments.powerSource!;
      _powerSource = AssignedDevice(
        deviceId: assignment.deviceId,
        deviceName: assignment.deviceName,
        transport: assignment.transport,
      );
      _powerSourceBeacon.value = _powerSource;
      chirp.info(
        'Restored powerSource assignment',
        data: {'deviceId': assignment.deviceId, 'deviceName': assignment.deviceName},
      );
    }

    if (assignments.cadenceSource != null) {
      final assignment = assignments.cadenceSource!;
      _cadenceSource = AssignedDevice(
        deviceId: assignment.deviceId,
        deviceName: assignment.deviceName,
        transport: assignment.transport,
      );
      _cadenceSourceBeacon.value = _cadenceSource;
      chirp.info(
        'Restored cadenceSource assignment',
        data: {'deviceId': assignment.deviceId, 'deviceName': assignment.deviceName},
      );
    }

    if (assignments.speedSource != null) {
      final assignment = assignments.speedSource!;
      _speedSource = AssignedDevice(
        deviceId: assignment.deviceId,
        deviceName: assignment.deviceName,
        transport: assignment.transport,
      );
      _speedSourceBeacon.value = _speedSource;
      chirp.info(
        'Restored speedSource assignment',
        data: {'deviceId': assignment.deviceId, 'deviceName': assignment.deviceName},
      );
    }

    if (assignments.heartRateSource != null) {
      final assignment = assignments.heartRateSource!;
      _heartRateSource = AssignedDevice(
        deviceId: assignment.deviceId,
        deviceName: assignment.deviceName,
        transport: assignment.transport,
      );
      _heartRateSourceBeacon.value = _heartRateSource;
      chirp.info(
        'Restored heartRateSource assignment',
        data: {'deviceId': assignment.deviceId, 'deviceName': assignment.deviceName},
      );
    }

    chirp.info('Restored assignments from persistence (devices not yet connected)');
  }

  /// Restores role assignments for a specific device that was just connected during auto-connect.
  ///
  /// Updates existing AssignedDevice wrappers to reference the now-connected device.
  /// Used when a device is discovered and connected during auto-connect scanning.
  void _restoreAssignmentsForDevice(String deviceId) {
    final device = _findDevice(deviceId);

    // Update existing AssignedDevice wrappers with the connected device reference
    if (_smartTrainer?.deviceId == deviceId) {
      _smartTrainer = _smartTrainer!.withConnectedDevice(device);
      _smartTrainerBeacon.value = _smartTrainer;
      chirp.info('Updated smartTrainer with connected device');
    }

    if (_powerSource?.deviceId == deviceId) {
      _powerSource = _powerSource!.withConnectedDevice(device);
      _powerSourceBeacon.value = _powerSource;
      chirp.info('Updated powerSource with connected device');
    }

    if (_cadenceSource?.deviceId == deviceId) {
      _cadenceSource = _cadenceSource!.withConnectedDevice(device);
      _cadenceSourceBeacon.value = _cadenceSource;
      chirp.info('Updated cadenceSource with connected device');
    }

    if (_speedSource?.deviceId == deviceId) {
      _speedSource = _speedSource!.withConnectedDevice(device);
      _speedSourceBeacon.value = _speedSource;
      chirp.info('Updated speedSource with connected device');
    }

    if (_heartRateSource?.deviceId == deviceId) {
      _heartRateSource = _heartRateSource!.withConnectedDevice(device);
      _heartRateSourceBeacon.value = _heartRateSource;
      chirp.info('Updated heartRateSource with connected device');
    }
  }

  /// Starts scanning for devices that need to be auto-connected.
  void _startAutoConnectScanning() {
    if (_autoConnectScanToken != null) {
      return; // Already scanning
    }

    chirp.info(
      'Starting scan for ${_autoConnectDeviceIds.length} device(s)',
      data: {'deviceIds': _autoConnectDeviceIds},
    );

    _autoConnectScanToken = scanner.startScan();

    // Monitor scanner for discovered devices
    _scannerDevicesUnsubscribe = scanner.devices.subscribe((discoveredDevices) {
      for (final discovered in discoveredDevices) {
        if (_autoConnectDeviceIds.contains(discovered.deviceId)) {
          // Skip devices that were manually disconnected
          if (_manuallyDisconnectedDeviceIds.contains(discovered.deviceId)) {
            chirp.info('Skipping auto-connect for manually disconnected device ${discovered.deviceId}');
            _autoConnectDeviceIds.remove(discovered.deviceId);
            chirp.debug('Waiting for remaining auto-connect devices', data: {'remaining': _autoConnectDeviceIds});
            // Check if we should stop scanning after removing this device
            _checkAndStopAutoConnectScanning();
            continue;
          }

          // Check if device is already connected or being connected
          final existingDevice = _devices.where((d) => d.id == discovered.deviceId).firstOrNull;
          if (existingDevice != null && existingDevice.connectionState.value == ConnectionState.connected) {
            // Device already connected, skip and remove from pending list
            _autoConnectDeviceIds.remove(discovered.deviceId);
            chirp.debug('Waiting for remaining auto-connect devices', data: {'remaining': _autoConnectDeviceIds});
            // Check if we should stop scanning after removing this device
            _checkAndStopAutoConnectScanning();
            continue;
          }

          // Check if device is already being connected
          if (_connectingDeviceIds.contains(discovered.deviceId)) {
            // Connection already in progress, skip
            continue;
          }

          // Found a device we're looking for - mark as connecting and connect it
          _connectingDeviceIds.add(discovered.deviceId);
          chirp.info('Starting auto-connection to ${discovered.deviceId}');

          _connectAndRestoreDevice(discovered.deviceId)
              .then((_) {
                final connectedDeviceId = discovered.deviceId;
                _autoConnectDeviceIds.remove(connectedDeviceId);
                chirp.debug('Waiting for remaining auto-connect devices', data: {'remaining': _autoConnectDeviceIds});
                _connectingDeviceIds.remove(connectedDeviceId);
                if (_disposed) {
                  return;
                }

                // Restore assignments for the device that was just connected
                _restoreAssignmentsForDevice(connectedDeviceId);

                // Check if we should stop scanning after successful connection
                _checkAndStopAutoConnectScanning();
              })
              .catchError((error, stackTrace) {
                // Remove from connecting set on error
                _connectingDeviceIds.remove(discovered.deviceId);
                chirp.error(
                  'Failed to auto-connect ${discovered.deviceId}',
                  error: error,
                  stackTrace: stackTrace as StackTrace?,
                  data: {'device': discovered},
                );
              });
        }
      }
    });
  }

  /// Sets up monitoring for device connection state to enable auto-reconnect.
  ///
  /// When a device with an assigned role disconnects unexpectedly (e.g., device
  /// powered off, out of range, connection lost), it will be added back to the
  /// auto-connect list and scanning will be started to detect when the device
  /// comes back online.
  ///
  /// User-initiated disconnects (via [disconnectDevice]) do NOT trigger auto-reconnect.
  /// The user must manually reconnect via [connectDevice] to restore auto-reconnect.
  void _setupDeviceConnectionMonitoring(FitnessDevice device) {
    final unsubscribe = device.connectionState.subscribe((state) {
      if (state == ConnectionState.disconnected) {
        // Skip auto-reconnect for user-initiated disconnects
        if (_manuallyDisconnectedDeviceIds.contains(device.id)) {
          chirp.info('Device ${device.id} was manually disconnected, skipping auto-reconnect');
          return;
        }

        // Check if device has an assigned role
        final hasAssignedRole =
            _smartTrainer?.deviceId == device.id ||
            _powerSource?.deviceId == device.id ||
            _cadenceSource?.deviceId == device.id ||
            _speedSource?.deviceId == device.id ||
            _heartRateSource?.deviceId == device.id;

        if (hasAssignedRole) {
          chirp.info('Assigned device ${device.id} disconnected unexpectedly, enabling auto-reconnect');
          _autoConnectDeviceIds.add(device.id);
          _startAutoConnectScanning();
        }
      }
    });

    // Store subscription so we can cancel it later
    _deviceConnectionSubscriptions[device.id] = unsubscribe;
  }

  /// Handles unassigning a device - removes from auto-connect if no longer needed.
  ///
  /// Should be called whenever a device is unassigned from any role.
  /// Only removes from auto-connect if the device is not assigned to any other role.
  void _handleDeviceUnassigned(String deviceId) {
    // Check if device is still assigned to any role
    final stillAssigned =
        _smartTrainer?.deviceId == deviceId ||
        _powerSource?.deviceId == deviceId ||
        _cadenceSource?.deviceId == deviceId ||
        _speedSource?.deviceId == deviceId ||
        _heartRateSource?.deviceId == deviceId;

    if (!stillAssigned) {
      // Device is no longer assigned to any role, remove from auto-connect
      if (_autoConnectDeviceIds.remove(deviceId)) {
        chirp.info(
          'Removed device from auto-connect',
          data: {'deviceId': deviceId, 'remaining': _autoConnectDeviceIds},
        );
      }

      // Check if we should stop scanning
      _checkAndStopAutoConnectScanning();
    } else {
      chirp.debug('Device still assigned to other role(s), keeping in auto-connect', data: {'deviceId': deviceId});
    }
  }

  /// Checks if auto-connect scanning should stop and stops it if needed.
  ///
  /// This should be called after any change to device connection state or assignments.
  void _checkAndStopAutoConnectScanning() {
    if (_shouldStopAutoConnectScanning() && _autoConnectScanToken != null) {
      scanner.stopScan(_autoConnectScanToken!);
      _autoConnectScanToken = null;
      _scannerDevicesUnsubscribe?.call();
      _scannerDevicesUnsubscribe = null;
      chirp.info('All devices connected or sensors assigned, stopping scan');
    }
  }

  /// Checks if auto-connect scanning should stop.
  ///
  /// Returns true if all devices we're looking for have been found.
  /// Note: We don't check if "all sensors are assigned" because that would be too strict.
  /// Users may not have all sensor types, and we should stop scanning once we've found
  /// all the devices that were saved in assignments.
  bool _shouldStopAutoConnectScanning() {
    // Stop if all devices we were looking for have been found (or removed/skipped)
    return _autoConnectDeviceIds.isEmpty;
  }

  /// Disposes of all resources used by this manager.
  ///
  /// Disconnects all managed devices via BlePlatform and disposes all beacons.
  /// Derived beacons are automatically cleaned up.
  /// After calling dispose, this manager should not be used anymore.
  ///
  /// Call this when the manager is no longer needed to prevent memory leaks.
  Future<void> dispose() async {
    chirp.info('dispose()');
    _disposed = true;

    // Cancel all device connection state subscriptions
    for (final unsubscribe in _deviceConnectionSubscriptions.values) {
      unsubscribe();
    }
    _deviceConnectionSubscriptions.clear();

    // Stop auto-connect scanning
    if (_autoConnectScanToken != null) {
      scanner.stopScan(_autoConnectScanToken!);
      _autoConnectScanToken = null;
    }
    _scannerDevicesUnsubscribe?.call();
    _scannerDevicesUnsubscribe = null;

    // Stop auto-persistence of assignments
    _assignmentsPersistenceUnsubscribe?.call();
    _assignmentsPersistenceUnsubscribe = null;

    // Dispose staleness-aware beacons (cancels subscriptions and timers)
    _powerBeacon.dispose();
    _cadenceBeacon.dispose();
    _speedBeacon.dispose();
    _heartRateBeacon.dispose();

    // Disconnect all devices via BlePlatform
    await Future.wait(
      _devices.map((device) async {
        try {
          await device.disconnect();
        } catch (e, stack) {
          chirp.error('Failed to disconnect device ${device.name}', error: e, stackTrace: stack);
        }
      }),
    );

    // Dispose state beacons
    _devicesBeacon.dispose();
    _smartTrainerBeacon.dispose();
    _powerSourceBeacon.dispose();
    _cadenceSourceBeacon.dispose();
    _speedSourceBeacon.dispose();
    _heartRateSourceBeacon.dispose();
  }
}
