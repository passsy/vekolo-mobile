import 'package:flutter/foundation.dart';
import 'package:vekolo/domain/devices/device_manager.dart';
import 'package:vekolo/domain/devices/fitness_device.dart';
import 'package:vekolo/domain/models/fitness_data.dart';
import 'package:vekolo/state/device_state.dart';

/// Manages the reactive state for device management.
///
/// This class bridges the domain layer ([DeviceManager]) with the state layer
/// by subscribing to [DeviceManager] beacons and updating state beacons for UI
/// consumption. It ensures the UI always reflects the current state of devices
/// and their data.
///
/// The manager handles:
/// - Device list changes (via DeviceManager beacons)
/// - Device assignment changes (primary trainer, power/cadence/HR sources)
/// - Real-time sensor data updates (power, cadence, heart rate)
///
/// Example usage:
/// ```dart
/// final deviceManager = DeviceManager();
/// final devices = ConnectedDevices();
/// final telemetry = LiveTelemetry();
/// final syncState = WorkoutSyncState();
/// final stateManager = DeviceStateManager(deviceManager, devices, telemetry, syncState);
///
/// // Beacons are automatically updated as devices change
/// // UI widgets can watch beacons for reactive updates:
/// final power = context.watch(telemetry.powerBeacon);
/// ```
///
/// Used by the app initialization to wire up reactive state management.
/// Must be disposed when no longer needed to prevent memory leaks.
class DeviceStateManager {
  /// The underlying device manager providing domain logic.
  final DeviceManager deviceManager;

  /// Connected devices roster and role assignments.
  final ConnectedDevices devices;

  /// Live aggregated sensor telemetry.
  final LiveTelemetry telemetry;

  /// Workout synchronization state.
  final WorkoutSyncState syncState;

  /// Active beacon subscriptions for cleanup.
  final List<VoidCallback> _subscriptions = [];

  /// Creates a new device state manager and initializes stream subscriptions.
  ///
  /// Call [dispose] when done to clean up resources.
  DeviceStateManager(
    this.deviceManager,
    this.devices,
    this.telemetry,
    this.syncState,
  ) {
    _init();
  }

  /// Initializes all beacon subscriptions.
  void _init() {
    // Subscribe to real-time sensor data beacons
    _subscriptions.add(
      deviceManager.powerStream.subscribe((PowerData? data) {
        telemetry.power.value = data;
      }),
    );

    _subscriptions.add(
      deviceManager.cadenceStream.subscribe((CadenceData? data) {
        telemetry.cadence.value = data;
      }),
    );

    _subscriptions.add(
      deviceManager.heartRateStream.subscribe((HeartRateData? data) {
        telemetry.heartRate.value = data;
      }),
    );

    // Subscribe to device list and assignment beacons
    _subscriptions.add(
      deviceManager.devicesBeacon.subscribe((List<FitnessDevice> deviceList) {
        devices.devices.value = deviceList;
      }),
    );

    _subscriptions.add(
      deviceManager.primaryTrainerBeacon.subscribe((FitnessDevice? device) {
        devices.primaryTrainer.value = device;
      }),
    );

    _subscriptions.add(
      deviceManager.powerSourceBeacon.subscribe((FitnessDevice? device) {
        devices.powerSource.value = device;
      }),
    );

    _subscriptions.add(
      deviceManager.cadenceSourceBeacon.subscribe((FitnessDevice? device) {
        devices.cadenceSource.value = device;
      }),
    );

    _subscriptions.add(
      deviceManager.heartRateSourceBeacon.subscribe((FitnessDevice? device) {
        devices.heartRateSource.value = device;
      }),
    );
  }

  /// Disposes of all resources used by this manager.
  ///
  /// Cancels all beacon subscriptions.
  /// Note: Does not dispose state beacons - that's the responsibility
  /// of whoever owns the state instances (typically via Ref disposal).
  ///
  /// Call this when the manager is no longer needed to prevent memory leaks.
  void dispose() {
    // Cancel all beacon subscriptions
    for (final unsubscribe in _subscriptions) {
      unsubscribe();
    }
    _subscriptions.clear();
  }
}
