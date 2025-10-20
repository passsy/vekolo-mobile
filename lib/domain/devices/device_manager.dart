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

  // ============================================================================
  // Device Assignments
  // ============================================================================

  /// Primary trainer for ERG control, can also provide power/cadence data.
  FitnessDevice? _primaryTrainer;

  /// Dedicated power meter, overrides trainer's power if assigned.
  FitnessDevice? _powerSource;

  /// Dedicated cadence sensor, overrides trainer's cadence if assigned.
  FitnessDevice? _cadenceSource;

  /// Dedicated speed sensor, overrides trainer's speed if assigned.
  FitnessDevice? _speedSource;

  /// Dedicated heart rate monitor.
  FitnessDevice? _heartRateSource;

  // ============================================================================
  // Stream Controllers for Aggregated Data
  // ============================================================================

  final StreamController<PowerData> _powerController = StreamController<PowerData>.broadcast();
  final StreamController<CadenceData> _cadenceController = StreamController<CadenceData>.broadcast();
  final StreamController<SpeedData> _speedController = StreamController<SpeedData>.broadcast();
  final StreamController<HeartRateData> _heartRateController = StreamController<HeartRateData>.broadcast();

  // ============================================================================
  // Active Stream Subscriptions
  // ============================================================================

  /// Active subscription to power data from assigned device.
  StreamSubscription<PowerData>? _powerSubscription;

  /// Active subscription to cadence data from assigned device.
  StreamSubscription<CadenceData>? _cadenceSubscription;

  /// Active subscription to speed data from assigned device.
  StreamSubscription<SpeedData>? _speedSubscription;

  /// Active subscription to heart rate data from assigned device.
  StreamSubscription<HeartRateData>? _heartRateSubscription;

  // ============================================================================
  // Aggregated Streams (Public API)
  // ============================================================================

  /// Aggregated power data stream from assigned power source.
  ///
  /// Emits power data from:
  /// 1. Dedicated [powerSource] if assigned and supports power
  /// 2. Otherwise from [primaryTrainer] if it supports power
  /// 3. No data if neither source is assigned or supports power
  ///
  /// Stream automatically switches when device assignments change.
  Stream<PowerData> get powerStream => _powerController.stream;

  /// Aggregated cadence data stream from assigned cadence source.
  ///
  /// Emits cadence data from:
  /// 1. Dedicated [cadenceSource] if assigned and supports cadence
  /// 2. Otherwise from [primaryTrainer] if it supports cadence
  /// 3. No data if neither source is assigned or supports cadence
  ///
  /// Stream automatically switches when device assignments change.
  Stream<CadenceData> get cadenceStream => _cadenceController.stream;

  /// Aggregated speed data stream from assigned speed source.
  ///
  /// Emits speed data from:
  /// 1. Dedicated [speedSource] if assigned and supports speed
  /// 2. Otherwise from [primaryTrainer] if it supports speed
  /// 3. No data if neither source is assigned or supports speed
  ///
  /// Stream automatically switches when device assignments change.
  Stream<SpeedData> get speedStream => _speedController.stream;

  /// Aggregated heart rate data stream from assigned HR source.
  ///
  /// Emits heart rate data from [heartRateSource] if assigned and supports HR.
  /// No fallback to trainer since trainers don't typically provide HR data.
  ///
  /// Stream automatically switches when device assignment changes.
  Stream<HeartRateData> get heartRateStream => _heartRateController.stream;

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
      _updatePowerStream();
      _updateCadenceStream();
      _updateSpeedStream();
    }
    if (_powerSource?.id == deviceId) {
      _powerSource = null;
      _updatePowerStream();
    }
    if (_cadenceSource?.id == deviceId) {
      _cadenceSource = null;
      _updateCadenceStream();
    }
    if (_speedSource?.id == deviceId) {
      _speedSource = null;
      _updateSpeedStream();
    }
    if (_heartRateSource?.id == deviceId) {
      _heartRateSource = null;
      _updateHeartRateStream();
    }

    _devices.remove(device);
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
      _updatePowerStream();
      _updateCadenceStream();
      _updateSpeedStream();
      return;
    }

    final device = _findDevice(deviceId);

    if (!device.supportsErgMode) {
      throw ArgumentError('Device $deviceId does not support ERG mode');
    }

    _primaryTrainer = device;

    // Primary trainer affects power, cadence, and speed streams if no dedicated sources
    if (_powerSource == null) {
      _updatePowerStream();
    }
    if (_cadenceSource == null) {
      _updateCadenceStream();
    }
    if (_speedSource == null) {
      _updateSpeedStream();
    }
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
      _updatePowerStream();
      return;
    }

    final device = _findDevice(deviceId);

    if (!device.capabilities.contains(DeviceDataType.power)) {
      throw ArgumentError('Device $deviceId does not provide power data');
    }

    _powerSource = device;
    _updatePowerStream();
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
      _updateCadenceStream();
      return;
    }

    final device = _findDevice(deviceId);

    if (!device.capabilities.contains(DeviceDataType.cadence)) {
      throw ArgumentError('Device $deviceId does not provide cadence data');
    }

    _cadenceSource = device;
    _updateCadenceStream();
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
      _updateSpeedStream();
      return;
    }

    final device = _findDevice(deviceId);

    if (!device.capabilities.contains(DeviceDataType.speed)) {
      throw ArgumentError('Device $deviceId does not provide speed data');
    }

    _speedSource = device;
    _updateSpeedStream();
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
      _updateHeartRateStream();
      return;
    }

    final device = _findDevice(deviceId);

    if (!device.capabilities.contains(DeviceDataType.heartRate)) {
      throw ArgumentError('Device $deviceId does not provide heart rate data');
    }

    _heartRateSource = device;
    _updateHeartRateStream();
  }

  // ============================================================================
  // Query Methods
  // ============================================================================

  /// Returns all devices managed by this manager.
  ///
  /// Returns an unmodifiable view to prevent external modifications.
  List<FitnessDevice> get devices => List.unmodifiable(_devices);

  /// Returns the currently assigned primary trainer, or null if none assigned.
  FitnessDevice? get primaryTrainer => _primaryTrainer;

  /// Returns the currently assigned power source, or null if none assigned.
  FitnessDevice? get powerSource => _powerSource;

  /// Returns the currently assigned cadence source, or null if none assigned.
  FitnessDevice? get cadenceSource => _cadenceSource;

  /// Returns the currently assigned speed source, or null if none assigned.
  FitnessDevice? get speedSource => _speedSource;

  /// Returns the currently assigned heart rate source, or null if none assigned.
  FitnessDevice? get heartRateSource => _heartRateSource;

  // ============================================================================
  // Stream Management (Private)
  // ============================================================================

  /// Updates the power stream to listen to the correct device.
  ///
  /// Priority:
  /// 1. Dedicated power source if assigned
  /// 2. Primary trainer if it provides power
  /// 3. No stream (cancel subscription) if neither available
  void _updatePowerStream() {
    // Cancel existing subscription
    _powerSubscription?.cancel();
    _powerSubscription = null;

    // Determine which device to use for power
    final FitnessDevice? powerDevice = _powerSource ?? _primaryTrainer;

    // Subscribe to device's power stream if available
    final Stream<PowerData>? stream = powerDevice?.powerStream;
    if (stream != null) {
      _powerSubscription = stream.listen(
        _powerController.add,
        onError: (Object e, StackTrace stackTrace) {
          // Forward errors to the aggregated stream
          _powerController.addError(e, stackTrace);
        },
      );
    }
  }

  /// Updates the cadence stream to listen to the correct device.
  ///
  /// Priority:
  /// 1. Dedicated cadence source if assigned
  /// 2. Primary trainer if it provides cadence
  /// 3. No stream (cancel subscription) if neither available
  void _updateCadenceStream() {
    // Cancel existing subscription
    _cadenceSubscription?.cancel();
    _cadenceSubscription = null;

    // Determine which device to use for cadence
    final FitnessDevice? cadenceDevice = _cadenceSource ?? _primaryTrainer;

    // Subscribe to device's cadence stream if available
    final Stream<CadenceData>? stream = cadenceDevice?.cadenceStream;
    if (stream != null) {
      _cadenceSubscription = stream.listen(
        _cadenceController.add,
        onError: (Object e, StackTrace stackTrace) {
          // Forward errors to the aggregated stream
          _cadenceController.addError(e, stackTrace);
        },
      );
    }
  }

  /// Updates the speed stream to listen to the correct device.
  ///
  /// Priority:
  /// 1. Dedicated speed source if assigned
  /// 2. Primary trainer if it provides speed
  /// 3. No stream (cancel subscription) if neither available
  void _updateSpeedStream() {
    // Cancel existing subscription
    _speedSubscription?.cancel();
    _speedSubscription = null;

    // Determine which device to use for speed
    final FitnessDevice? speedDevice = _speedSource ?? _primaryTrainer;

    // Subscribe to device's speed stream if available
    final Stream<SpeedData>? stream = speedDevice?.speedStream;
    if (stream != null) {
      _speedSubscription = stream.listen(
        _speedController.add,
        onError: (Object e, StackTrace stackTrace) {
          // Forward errors to the aggregated stream
          _speedController.addError(e, stackTrace);
        },
      );
    }
  }

  /// Updates the heart rate stream to listen to the correct device.
  ///
  /// Uses the assigned heart rate source. No fallback since trainers
  /// typically don't provide HR data.
  void _updateHeartRateStream() {
    // Cancel existing subscription
    _heartRateSubscription?.cancel();
    _heartRateSubscription = null;

    // Subscribe to HR device's stream if available
    final Stream<HeartRateData>? stream = _heartRateSource?.heartRateStream;
    if (stream != null) {
      _heartRateSubscription = stream.listen(
        _heartRateController.add,
        onError: (Object e, StackTrace stackTrace) {
          // Forward errors to the aggregated stream
          _heartRateController.addError(e, stackTrace);
        },
      );
    }
  }

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
  /// Cancels all active stream subscriptions and closes stream controllers.
  /// After calling dispose, this manager should not be used anymore.
  ///
  /// Call this when the manager is no longer needed to prevent memory leaks.
  void dispose() {
    _powerSubscription?.cancel();
    _cadenceSubscription?.cancel();
    _speedSubscription?.cancel();
    _heartRateSubscription?.cancel();

    _powerController.close();
    _cadenceController.close();
    _speedController.close();
    _heartRateController.close();
  }
}
