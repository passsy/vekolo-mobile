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
import 'dart:developer' as developer;

import 'package:async/async.dart';
import 'package:flutter/foundation.dart';
import 'package:state_beacon/state_beacon.dart';
import 'package:vekolo/ble/ble_device.dart';
import 'package:vekolo/ble/ble_platform.dart';
import 'package:vekolo/ble/ble_scanner.dart';
import 'package:vekolo/ble/transport_registry.dart';
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
  DeviceManager({required this.platform, required this.scanner, required this.transportRegistry});

  /// BLE platform for device connection management.
  final BlePlatform platform;

  /// BLE scanner for device discovery and auto-connect.
  final BleScanner scanner;

  /// Transport registry for detecting compatible transports and creating devices.
  final TransportRegistry transportRegistry;

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
  FitnessDevice? _primaryTrainer;
  final WritableBeacon<FitnessDevice?> _primaryTrainerBeacon = Beacon.writable(null);

  /// Dedicated power meter, overrides trainer's power if assigned.
  FitnessDevice? _powerSource;
  final WritableBeacon<FitnessDevice?> _powerSourceBeacon = Beacon.writable(null);

  /// Dedicated cadence sensor, overrides trainer's cadence if assigned.
  FitnessDevice? _cadenceSource;
  final WritableBeacon<FitnessDevice?> _cadenceSourceBeacon = Beacon.writable(null);

  /// Dedicated speed sensor, overrides trainer's speed if assigned.
  FitnessDevice? _speedSource;
  final WritableBeacon<FitnessDevice?> _speedSourceBeacon = Beacon.writable(null);

  /// Dedicated heart rate monitor.
  FitnessDevice? _heartRateSource;
  final WritableBeacon<FitnessDevice?> _heartRateSourceBeacon = Beacon.writable(null);

  // ============================================================================
  // Beacons for Aggregated Data (Derived from assigned devices)
  // ============================================================================

  late final ReadableBeacon<PowerData?> _powerBeacon = Beacon.derived(() {
    // Track assignment beacons so derived updates when assignments change
    final powerSource = _powerSourceBeacon.value;
    final primaryTrainer = _primaryTrainerBeacon.value;
    final device = powerSource ?? primaryTrainer;
    return device?.powerStream?.value;
  });

  late final ReadableBeacon<CadenceData?> _cadenceBeacon = Beacon.derived(() {
    final cadenceSource = _cadenceSourceBeacon.value;
    final primaryTrainer = _primaryTrainerBeacon.value;
    final device = cadenceSource ?? primaryTrainer;
    return device?.cadenceStream?.value;
  });

  late final ReadableBeacon<SpeedData?> _speedBeacon = Beacon.derived(() {
    final speedSource = _speedSourceBeacon.value;
    final primaryTrainer = _primaryTrainerBeacon.value;
    final device = speedSource ?? primaryTrainer;
    return device?.speedStream?.value;
  });

  late final ReadableBeacon<HeartRateData?> _heartRateBeacon = Beacon.derived(() {
    final heartRateSource = _heartRateSourceBeacon.value;
    return heartRateSource?.heartRateStream?.value;
  });

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
    if (_primaryTrainer?.id == deviceId) {
      _primaryTrainer = null;
      _primaryTrainerBeacon.value = null;
    }
    if (_powerSource?.id == deviceId) {
      _powerSource = null;
      _powerSourceBeacon.value = null;
    }
    if (_cadenceSource?.id == deviceId) {
      _cadenceSource = null;
      _cadenceSourceBeacon.value = null;
    }
    if (_speedSource?.id == deviceId) {
      _speedSource = null;
      _speedSourceBeacon.value = null;
    }
    if (_heartRateSource?.id == deviceId) {
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

    _primaryTrainer = device;
    _primaryTrainerBeacon.value = device;
    _saveAssignmentsAsync();
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

    _powerSource = device;
    _powerSourceBeacon.value = device;
    _saveAssignmentsAsync();
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

    _cadenceSource = device;
    _cadenceSourceBeacon.value = device;
    _saveAssignmentsAsync();
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

    _speedSource = device;
    _speedSourceBeacon.value = device;
    _saveAssignmentsAsync();
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

    _heartRateSource = device;
    _heartRateSourceBeacon.value = device;
    _saveAssignmentsAsync();
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

  /// Returns the currently assigned primary trainer, or null if none assigned.
  FitnessDevice? get primaryTrainer => _primaryTrainer;

  /// Reactive beacon of primary trainer assignment.
  ReadableBeacon<FitnessDevice?> get primaryTrainerBeacon => _primaryTrainerBeacon;

  /// Returns the currently assigned power source, or null if none assigned.
  FitnessDevice? get powerSource => _powerSource;

  /// Reactive beacon of power source assignment.
  ReadableBeacon<FitnessDevice?> get powerSourceBeacon => _powerSourceBeacon;

  /// Returns the currently assigned cadence source, or null if none assigned.
  FitnessDevice? get cadenceSource => _cadenceSource;

  /// Reactive beacon of cadence source assignment.
  ReadableBeacon<FitnessDevice?> get cadenceSourceBeacon => _cadenceSourceBeacon;

  /// Returns the currently assigned speed source, or null if none assigned.
  FitnessDevice? get speedSource => _speedSource;

  /// Reactive beacon of speed source assignment.
  ReadableBeacon<FitnessDevice?> get speedSourceBeacon => _speedSourceBeacon;

  /// Returns the currently assigned heart rate source, or null if none assigned.
  FitnessDevice? get heartRateSource => _heartRateSource;

  /// Reactive beacon of heart rate source assignment.
  ReadableBeacon<FitnessDevice?> get heartRateSourceBeacon => _heartRateSourceBeacon;

  // ============================================================================
  // Auto-Connect State
  // ============================================================================

  /// Devices that should be auto-connected (saved assignments).
  final Set<String> _autoConnectDeviceIds = {};

  /// Scan token for auto-connect scanning.
  ScanToken? _autoConnectScanToken;

  /// Subscription to scanner devices for auto-connect.
  VoidCallback? _scannerDevicesUnsubscribe;

  // ============================================================================
  // Helper Methods
  // ============================================================================

  /// Finds a device by ID or throws [ArgumentError] if not found.
  FitnessDevice _findDevice(String deviceId) {
    final device = _devices.where((d) => d.id == deviceId).firstOrNull;
    if (device == null) {
      throw ArgumentError('Device with id $deviceId not found');
    }
    return device;
  }

  /// Saves device assignments asynchronously (fire-and-forget).
  Future<void> _saveAssignmentsAsync() async {
    try {
      await saveDeviceAssignments(this);
    } catch (error, stackTrace) {
      developer.log(
        '[DeviceManager] Failed to save assignments: $error',
        name: 'DeviceManager',
        error: error,
        stackTrace: stackTrace,
      );
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
    developer.log('[DeviceManager] Initializing auto-connect', name: 'DeviceManager');

    try {
      final assignments = await loadDeviceAssignments();
      if (assignments.isEmpty) {
        developer.log('[DeviceManager] No saved assignments to restore', name: 'DeviceManager');
        return;
      }

      _autoConnectDeviceIds.addAll(assignments.keys);
      developer.log('[DeviceManager] Found ${assignments.length} device(s) to auto-connect', name: 'DeviceManager');

      // Check for already discovered devices
      final discoveredDevices = scanner.devices.value;
      final devicesToConnect = <String>{};
      final devicesToScan = <String>{};

      for (final deviceId in _autoConnectDeviceIds) {
        final discovered = discoveredDevices.where((d) => d.deviceId == deviceId).firstOrNull;
        if (discovered != null) {
          devicesToConnect.add(deviceId);
        } else {
          devicesToScan.add(deviceId);
        }
      }

      // Connect to already discovered devices
      for (final deviceId in devicesToConnect) {
        try {
          await _connectAndRestoreDevice(deviceId, assignments[deviceId]!);
        } catch (e, stackTrace) {
          developer.log(
            '[DeviceManager] Failed to connect to $deviceId: $e',
            name: 'DeviceManager',
            error: e,
            stackTrace: stackTrace,
          );
        }
      }

      // Start scanning for missing devices if any
      if (devicesToScan.isNotEmpty) {
        _startAutoConnectScanning(devicesToScan, assignments);
      }
    } catch (e, stackTrace) {
      developer.log(
        '[DeviceManager] Failed to initialize auto-connect: $e',
        name: 'DeviceManager',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Connects to a device and restores its assignments.
  Future<void> _connectAndRestoreDevice(String deviceId, Set<String> roles) async {
    // Check if device already exists in manager
    final existingDevice = _devices.where((d) => d.id == deviceId).firstOrNull;
    if (existingDevice != null) {
      // Device already exists, just connect and restore assignments
      if (existingDevice.connectionState.value != ConnectionState.connected) {
        await connectDevice(deviceId).value;
      }
      _restoreAssignments(deviceId, roles);
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

    // Restore assignments
    _restoreAssignments(deviceId, roles);
  }

  /// Restores role assignments for a device.
  void _restoreAssignments(String deviceId, Set<String> roles) {
    final device = _findDevice(deviceId);

    for (final role in roles) {
      try {
        switch (role) {
          case 'primaryTrainer':
            if (device.supportsErgMode) {
              assignPrimaryTrainer(deviceId);
            }
            break;
          case 'powerSource':
            if (device.capabilities.contains(DeviceDataType.power)) {
              assignPowerSource(deviceId);
            }
            break;
          case 'cadenceSource':
            if (device.capabilities.contains(DeviceDataType.cadence)) {
              assignCadenceSource(deviceId);
            }
            break;
          case 'speedSource':
            if (device.capabilities.contains(DeviceDataType.speed)) {
              assignSpeedSource(deviceId);
            }
            break;
          case 'heartRateSource':
            if (device.capabilities.contains(DeviceDataType.heartRate)) {
              assignHeartRateSource(deviceId);
            }
            break;
        }
      } catch (e) {
        developer.log('[DeviceManager] Failed to restore role $role for $deviceId: $e', name: 'DeviceManager');
      }
    }
  }

  /// Starts scanning for devices that need to be auto-connected.
  void _startAutoConnectScanning(Set<String> deviceIds, Map<String, Set<String>> assignments) {
    if (_autoConnectScanToken != null) {
      return; // Already scanning
    }

    developer.log('[DeviceManager] Starting scan for ${deviceIds.length} missing device(s)', name: 'DeviceManager');

    _autoConnectScanToken = scanner.startScan();

    // Monitor scanner for discovered devices
    _scannerDevicesUnsubscribe = scanner.devices.subscribe((discoveredDevices) {
      for (final discovered in discoveredDevices) {
        if (deviceIds.contains(discovered.deviceId)) {
          // Found a device we're looking for
          _connectAndRestoreDevice(discovered.deviceId, assignments[discovered.deviceId]!)
              .then((_) {
                deviceIds.remove(discovered.deviceId);
                _autoConnectDeviceIds.remove(discovered.deviceId);

                // Stop scanning if all devices found or all sensors are assigned
                if (_shouldStopAutoConnectScanning() && _autoConnectScanToken != null) {
                  scanner.stopScan(_autoConnectScanToken!);
                  _autoConnectScanToken = null;
                  _scannerDevicesUnsubscribe?.call();
                  _scannerDevicesUnsubscribe = null;
                  developer.log(
                    '[DeviceManager] All devices connected or sensors assigned, stopping scan',
                    name: 'DeviceManager',
                  );
                }
              })
              .catchError((error, stackTrace) {
                developer.log(
                  '[DeviceManager] Failed to auto-connect ${discovered.deviceId}: $error',
                  name: 'DeviceManager',
                  error: error,
                  stackTrace: stackTrace as StackTrace?,
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

    // Dispose aggregated data beacons
    _powerBeacon.dispose();
    _cadenceBeacon.dispose();
    _speedBeacon.dispose();
    _heartRateBeacon.dispose();

    // Dispose state beacons
    _devicesBeacon.dispose();
    _primaryTrainerBeacon.dispose();
    _powerSourceBeacon.dispose();
    _cadenceSourceBeacon.dispose();
    _speedSourceBeacon.dispose();
    _heartRateSourceBeacon.dispose();
  }
}
