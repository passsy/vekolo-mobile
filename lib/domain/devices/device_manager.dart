/// Manages multiple fitness devices and aggregates their data streams.
///
/// This is the central coordinator for all connected devices. It maintains
/// a collection of devices and assigns them to specific roles (primary trainer,
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
/// manager.assignPrimaryTrainer(myTrainer.id);
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
import 'package:vekolo/app/logger.dart';
import 'package:vekolo/ble/ble_device.dart';
import 'package:vekolo/ble/ble_platform.dart';
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

  // ============================================================================
  // Device Assignments
  // ============================================================================

  /// Primary trainer for ERG control, can also provide power/cadence data.
  AssignedDevice? _primaryTrainer;
  final WritableBeacon<AssignedDevice?> _primaryTrainerBeacon = Beacon.writable(null);

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
  /// 2. Otherwise from [primaryTrainer] if it supports power
  /// 3. No data if neither source is assigned or supports power
  ///
  /// Beacon automatically switches when device assignments change.
  ReadableBeacon<PowerData?> get powerStream => _powerBeacon;

  /// Aggregated cadence data beacon from assigned cadence source.
  ///
  /// Emits cadence data from:
  /// 1. Dedicated [cadenceSource] if assigned and supports cadence
  /// 2. Otherwise from [primaryTrainer] if it supports cadence
  /// 3. No data if neither source is assigned or supports cadence
  ///
  /// Beacon automatically switches when device assignments change.
  ReadableBeacon<CadenceData?> get cadenceStream => _cadenceBeacon;

  /// Aggregated speed data beacon from assigned speed source.
  ///
  /// Emits speed data from:
  /// 1. Dedicated [speedSource] if assigned and supports speed
  /// 2. Otherwise from [primaryTrainer] if it supports speed
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

    // Clear all assignments for this device
    if (_primaryTrainer?.deviceId == deviceId) {
      _primaryTrainer = null;
      _primaryTrainerBeacon.value = null;
    }
    if (_powerSource?.deviceId == deviceId) {
      _powerSource = null;
      _powerSourceBeacon.value = null;
    }
    if (_cadenceSource?.deviceId == deviceId) {
      _cadenceSource = null;
      _cadenceSourceBeacon.value = null;
    }
    if (_speedSource?.deviceId == deviceId) {
      _speedSource = null;
      _speedSourceBeacon.value = null;
    }
    if (_heartRateSource?.deviceId == deviceId) {
      _heartRateSource = null;
      _heartRateSourceBeacon.value = null;
    }

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
  /// Returns a [CancelableOperation] that can be cancelled during connection.
  /// Cancelling will stop the connection attempt and clean up resources.
  ///
  /// Throws [ArgumentError] if no device with the given ID exists.
  CancelableOperation<void> connectDevice(String deviceId) {
    final device = _findDevice(deviceId);
    return device.connect();
  }

  /// Disconnects from a device managed by this manager.
  ///
  /// Cleanly tears down the connection to the device with the given [deviceId].
  /// The device remains in the manager but is disconnected.
  ///
  /// Safe to call even if the device is already disconnected.
  ///
  /// Throws [ArgumentError] if no device with the given ID exists.
  Future<void> disconnectDevice(String deviceId) async {
    final device = _findDevice(deviceId);
    await device.disconnect();
  }

  // ============================================================================
  // Device Assignment Methods
  // ============================================================================

  /// Assigns a device as the primary trainer for ERG control.
  ///
  /// The primary trainer can:
  /// - Be controlled via [setTargetPower] for ERG mode workouts
  /// - Serve as fallback power source if no dedicated power meter is assigned
  /// - Serve as fallback cadence source if no dedicated cadence sensor is assigned
  ///
  /// Throws [ArgumentError] if device not found or doesn't support ERG mode.
  /// Pass null to unassign the primary trainer.
  void assignPrimaryTrainer(String? deviceId) {
    if (deviceId == null) {
      _primaryTrainer = null;
      _primaryTrainerBeacon.value = null;
      return;
    }

    final device = _findDevice(deviceId);

    if (!device.supportsErgMode) {
      throw ArgumentError('Device $deviceId does not support ERG mode');
    }

    final assigned = AssignedDevice.fromDevice(device);
    _primaryTrainer = assigned;
    _primaryTrainerBeacon.value = assigned;
    _saveAssignmentsAsync(_buildDeviceAssignments());
  }

  /// Assigns a device as the dedicated power source.
  ///
  /// Power data will come from this device, overriding any power data from
  /// the primary trainer. Useful when using a dedicated power meter that's
  /// more accurate than the trainer's built-in power measurement.
  ///
  /// Throws [ArgumentError] if device not found or doesn't provide power data.
  /// Pass null to unassign the power source.
  void assignPowerSource(String? deviceId) {
    if (deviceId == null) {
      _powerSource = null;
      _powerSourceBeacon.value = null;
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
  /// the primary trainer. Useful when using a dedicated cadence sensor.
  ///
  /// Throws [ArgumentError] if device not found or doesn't provide cadence data.
  void assignCadenceSource(String? deviceId) {
    if (deviceId == null) {
      _cadenceSource = null;
      _cadenceSourceBeacon.value = null;
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
  /// the primary trainer. Useful when using a dedicated speed sensor.
  ///
  /// Throws [ArgumentError] if device not found or doesn't provide speed data.
  void assignSpeedSource(String? deviceId) {
    if (deviceId == null) {
      _speedSource = null;
      _speedSourceBeacon.value = null;
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
      _heartRateSource = null;
      _heartRateSourceBeacon.value = null;
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

  /// Reactive beacon of primary trainer assignment.
  ReadableBeacon<AssignedDevice?> get primaryTrainerBeacon => _primaryTrainerBeacon;

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
      final primaryTrainer = _primaryTrainerBeacon.value?.connectedDevice;
      final device = powerSource ?? primaryTrainer;
      return device?.powerStream?.value;
    }).withStalenessDetection(threshold: _stalenessThreshold);

    // Cadence stream: derived beacon selecting the appropriate device, with staleness detection
    _cadenceBeacon = Beacon.derived(() {
      final cadenceSource = _cadenceSourceBeacon.value?.connectedDevice;
      final primaryTrainer = _primaryTrainerBeacon.value?.connectedDevice;
      final device = cadenceSource ?? primaryTrainer;
      return device?.cadenceStream?.value;
    }).withStalenessDetection(threshold: _stalenessThreshold);

    // Speed stream: derived beacon selecting the appropriate device, with staleness detection
    _speedBeacon = Beacon.derived(() {
      final speedSource = _speedSourceBeacon.value?.connectedDevice;
      final primaryTrainer = _primaryTrainerBeacon.value?.connectedDevice;
      final device = speedSource ?? primaryTrainer;
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
      primaryTrainer: _primaryTrainer != null
          ? DeviceAssignment(
              deviceId: _primaryTrainer!.deviceId,
              deviceName: _primaryTrainer!.deviceName,
              transport: _primaryTrainer!.transport,
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
        primaryTrainer: assignments.primaryTrainer,
        powerSource: assignments.powerSource,
        cadenceSource: assignments.cadenceSource,
        speedSource: assignments.speedSource,
        heartRateSource: assignments.heartRateSource,
      );
    } catch (e, stack) {
      talker.error('[DeviceManager] Failed to persist assignments: $e', e, stack);
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
        if (assignments.primaryTrainer != null) assignments.primaryTrainer!.deviceId,
        if (assignments.powerSource != null) assignments.powerSource!.deviceId,
        if (assignments.cadenceSource != null) assignments.cadenceSource!.deviceId,
        if (assignments.speedSource != null) assignments.speedSource!.deviceId,
        if (assignments.heartRateSource != null) assignments.heartRateSource!.deviceId,
      };
    }

    final deviceIds = _extractDeviceIds(assignments);
    _autoConnectDeviceIds.addAll(deviceIds);

    talker.info('[DeviceManager] Found ${deviceIds.length} device(s) to auto-connect');
    _startAutoConnectScanning();
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
    // Create AssignedDevice wrappers from persisted assignments
    // Devices are not connected yet, so connectedDevice will be null
    // These will be updated with actual device references in _restoreAssignmentsForDevice

    if (assignments.primaryTrainer != null) {
      final assignment = assignments.primaryTrainer!;
      _primaryTrainer = AssignedDevice(
        deviceId: assignment.deviceId,
        deviceName: assignment.deviceName,
        transport: assignment.transport,
      );
      _primaryTrainerBeacon.value = _primaryTrainer;
    }

    if (assignments.powerSource != null) {
      final assignment = assignments.powerSource!;
      _powerSource = AssignedDevice(
        deviceId: assignment.deviceId,
        deviceName: assignment.deviceName,
        transport: assignment.transport,
      );
      _powerSourceBeacon.value = _powerSource;
    }

    if (assignments.cadenceSource != null) {
      final assignment = assignments.cadenceSource!;
      _cadenceSource = AssignedDevice(
        deviceId: assignment.deviceId,
        deviceName: assignment.deviceName,
        transport: assignment.transport,
      );
      _cadenceSourceBeacon.value = _cadenceSource;
    }

    if (assignments.speedSource != null) {
      final assignment = assignments.speedSource!;
      _speedSource = AssignedDevice(
        deviceId: assignment.deviceId,
        deviceName: assignment.deviceName,
        transport: assignment.transport,
      );
      _speedSourceBeacon.value = _speedSource;
    }

    if (assignments.heartRateSource != null) {
      final assignment = assignments.heartRateSource!;
      _heartRateSource = AssignedDevice(
        deviceId: assignment.deviceId,
        deviceName: assignment.deviceName,
        transport: assignment.transport,
      );
      _heartRateSourceBeacon.value = _heartRateSource;
    }

    talker.info('[DeviceManager] Restored assignments from persistence (devices not yet connected)');
  }

  /// Restores role assignments for a specific device that was just connected during auto-connect.
  ///
  /// Updates existing AssignedDevice wrappers to reference the now-connected device.
  /// Used when a device is discovered and connected during auto-connect scanning.
  void _restoreAssignmentsForDevice(String deviceId) {
    final device = _findDevice(deviceId);

    // Update existing AssignedDevice wrappers with the connected device reference
    if (_primaryTrainer?.deviceId == deviceId) {
      _primaryTrainer = _primaryTrainer!.withConnectedDevice(device);
      _primaryTrainerBeacon.value = _primaryTrainer;
      talker.info('[DeviceManager] Updated primaryTrainer with connected device');
    }

    if (_powerSource?.deviceId == deviceId) {
      _powerSource = _powerSource!.withConnectedDevice(device);
      _powerSourceBeacon.value = _powerSource;
      talker.info('[DeviceManager] Updated powerSource with connected device');
    }

    if (_cadenceSource?.deviceId == deviceId) {
      _cadenceSource = _cadenceSource!.withConnectedDevice(device);
      _cadenceSourceBeacon.value = _cadenceSource;
      talker.info('[DeviceManager] Updated cadenceSource with connected device');
    }

    if (_speedSource?.deviceId == deviceId) {
      _speedSource = _speedSource!.withConnectedDevice(device);
      _speedSourceBeacon.value = _speedSource;
      talker.info('[DeviceManager] Updated speedSource with connected device');
    }

    if (_heartRateSource?.deviceId == deviceId) {
      _heartRateSource = _heartRateSource!.withConnectedDevice(device);
      _heartRateSourceBeacon.value = _heartRateSource;
      talker.info('[DeviceManager] Updated heartRateSource with connected device');
    }
  }

  /// Starts scanning for devices that need to be auto-connected.
  void _startAutoConnectScanning() {
    if (_autoConnectScanToken != null) {
      return; // Already scanning
    }

    talker.info('[DeviceManager] Starting scan for ${_autoConnectDeviceIds.length} device(s)');

    _autoConnectScanToken = scanner.startScan();

    // Monitor scanner for discovered devices
    _scannerDevicesUnsubscribe = scanner.devices.subscribe((discoveredDevices) {
      for (final discovered in discoveredDevices) {
        if (_autoConnectDeviceIds.contains(discovered.deviceId)) {
          // Check if device is already connected or being connected
          final existingDevice = _devices.where((d) => d.id == discovered.deviceId).firstOrNull;
          if (existingDevice != null && existingDevice.connectionState.value == ConnectionState.connected) {
            // Device already connected, skip and remove from pending list
            _autoConnectDeviceIds.remove(discovered.deviceId);
            continue;
          }

          // Check if device is already being connected
          if (_connectingDeviceIds.contains(discovered.deviceId)) {
            // Connection already in progress, skip
            continue;
          }

          // Found a device we're looking for - mark as connecting and connect it
          _connectingDeviceIds.add(discovered.deviceId);
          talker.info('[DeviceManager] Starting connection to ${discovered.deviceId}');

          _connectAndRestoreDevice(discovered.deviceId)
              .then((_) {
                final connectedDeviceId = discovered.deviceId;
                _autoConnectDeviceIds.remove(connectedDeviceId);
                _connectingDeviceIds.remove(connectedDeviceId);

                // Restore assignments for the device that was just connected
                _restoreAssignmentsForDevice(connectedDeviceId);

                // Stop scanning if all devices found or all sensors are assigned
                if (_shouldStopAutoConnectScanning() && _autoConnectScanToken != null) {
                  scanner.stopScan(_autoConnectScanToken!);
                  _autoConnectScanToken = null;
                  _scannerDevicesUnsubscribe?.call();
                  _scannerDevicesUnsubscribe = null;
                  talker.info('[DeviceManager] All devices connected or sensors assigned, stopping scan');
                }
              })
              .catchError((error, stackTrace) {
                // Remove from connecting set on error
                _connectingDeviceIds.remove(discovered.deviceId);
                talker.error(
                  '[DeviceManager] Failed to auto-connect ${discovered.deviceId}: $error',
                  error,
                  stackTrace as StackTrace?,
                );
              });
        }
      }
    });
  }

  /// Checks if auto-connect scanning should stop.
  ///
  /// Returns true if all devices are found or all sensors are assigned.
  bool _shouldStopAutoConnectScanning() {
    // Stop if all devices we were looking for have been found
    if (_autoConnectDeviceIds.isEmpty) {
      return true;
    }

    // Stop if all sensors are assigned (primary trainer, power, cadence, speed, HR)
    final hasPrimaryTrainer = _primaryTrainer != null;
    final hasPowerSource = _powerSource != null;
    final hasCadenceSource = _cadenceSource != null;
    final hasSpeedSource = _speedSource != null;
    final hasHeartRateSource = _heartRateSource != null;

    // All sensors assigned means we have at least a trainer (required) and
    // all other optional sensors that were previously assigned
    if (hasPrimaryTrainer && hasPowerSource && hasCadenceSource && hasSpeedSource && hasHeartRateSource) {
      return true;
    }

    return false;
  }

  /// Disposes of all resources used by this manager.
  ///
  /// Disconnects all managed devices via BlePlatform and disposes all beacons.
  /// Derived beacons are automatically cleaned up.
  /// After calling dispose, this manager should not be used anymore.
  ///
  /// Call this when the manager is no longer needed to prevent memory leaks.
  Future<void> dispose() async {
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
          await platform.disconnect(device.id);
        } catch (_) {
          // Ignore errors - disconnect is safe to call even if not connected
        }
      }),
    );

    // Dispose state beacons
    _devicesBeacon.dispose();
    _primaryTrainerBeacon.dispose();
    _powerSourceBeacon.dispose();
    _cadenceSourceBeacon.dispose();
    _speedSourceBeacon.dispose();
    _heartRateSourceBeacon.dispose();
  }
}
