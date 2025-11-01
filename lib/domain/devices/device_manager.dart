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

import 'package:state_beacon/state_beacon.dart';
import 'package:vekolo/domain/devices/fitness_device.dart';
import 'package:vekolo/domain/models/device_info.dart';
import 'package:vekolo/domain/models/fitness_data.dart';

/// Manages multiple devices and aggregates data streams.
///
/// This class coordinates device connections, assignments, and data aggregation.
/// It provides a clean API for the rest of the app to work with fitness devices
/// without knowing implementation details.
class DeviceManager {
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
  /// If the device was assigned to any role (trainer, power, cadence, HR),
  /// that assignment is cleared and the corresponding aggregated stream
  /// will stop emitting data from this device.
  ///
  /// Throws [ArgumentError] if no device with the given ID exists.
  Future<void> removeDevice(String deviceId) async {
    final device = _devices.where((d) => d.id == deviceId).firstOrNull;
    if (device == null) {
      throw ArgumentError('Device with id $deviceId not found');
    }

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

  // ============================================================================
  // Lifecycle
  // ============================================================================

  /// Disposes of all resources used by this manager.
  ///
  /// Disposes all beacons. Derived beacons are automatically cleaned up.
  /// After calling dispose, this manager should not be used anymore.
  ///
  /// Call this when the manager is no longer needed to prevent memory leaks.
  void dispose() {
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
