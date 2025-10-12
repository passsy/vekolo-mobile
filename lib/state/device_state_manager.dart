import 'dart:async';

import 'package:vekolo/domain/devices/device_manager.dart';
import 'package:vekolo/domain/models/fitness_data.dart';
import 'package:vekolo/state/device_state.dart';

/// Manages the reactive state for device management.
///
/// This class bridges the domain layer ([DeviceManager]) with the UI state layer
/// by subscribing to [DeviceManager] streams and updating beacons for UI
/// consumption. It ensures the UI always reflects the current state of devices
/// and their data.
///
/// The manager handles:
/// - Device list changes (via polling since DeviceManager doesn't emit events)
/// - Device assignment changes (primary trainer, power/cadence/HR sources)
/// - Real-time sensor data updates (power, cadence, heart rate)
///
/// Example usage:
/// ```dart
/// final deviceManager = DeviceManager();
/// final stateManager = DeviceStateManager(deviceManager);
///
/// // Beacons are automatically updated as devices change
/// // UI widgets can watch beacons for reactive updates:
/// final power = context.watch(currentPowerBeacon);
/// ```
///
/// Used by the app initialization to wire up reactive state management.
/// Must be disposed when no longer needed to prevent memory leaks.
class DeviceStateManager {
  /// The underlying device manager providing domain logic.
  final DeviceManager deviceManager;

  /// Active stream subscriptions for cleanup.
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  /// Timer for polling device/assignment changes.
  Timer? _pollTimer;

  /// Creates a new device state manager and initializes stream subscriptions.
  ///
  /// Call [dispose] when done to clean up resources.
  DeviceStateManager(this.deviceManager) {
    _init();
  }

  /// Initializes all stream subscriptions and polling.
  void _init() {
    // Subscribe to real-time sensor data streams
    _subscriptions.add(
      deviceManager.powerStream.listen(
        (PowerData data) {
          currentPowerBeacon.value = data;
        },
        onError: (Object e, StackTrace stackTrace) {
          // On error, clear the current value
          currentPowerBeacon.value = null;
        },
      ),
    );

    _subscriptions.add(
      deviceManager.cadenceStream.listen(
        (CadenceData data) {
          currentCadenceBeacon.value = data;
        },
        onError: (Object e, StackTrace stackTrace) {
          // On error, clear the current value
          currentCadenceBeacon.value = null;
        },
      ),
    );

    _subscriptions.add(
      deviceManager.heartRateStream.listen(
        (HeartRateData data) {
          currentHeartRateBeacon.value = data;
        },
        onError: (Object e, StackTrace stackTrace) {
          // On error, clear the current value
          currentHeartRateBeacon.value = null;
        },
      ),
    );

    // Poll for device list and assignment changes
    // DeviceManager doesn't emit change events, so we poll periodically
    _pollTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      _updateDeviceState();
    });

    // Initial update
    _updateDeviceState();
  }

  /// Updates all device-related beacons from current DeviceManager state.
  void _updateDeviceState() {
    // Update device list
    connectedDevicesBeacon.value = deviceManager.devices;

    // Update device assignments
    primaryTrainerBeacon.value = deviceManager.primaryTrainer;
    powerSourceBeacon.value = deviceManager.powerSource;
    cadenceSourceBeacon.value = deviceManager.cadenceSource;
    heartRateSourceBeacon.value = deviceManager.heartRateSource;
  }

  /// Disposes of all resources used by this manager.
  ///
  /// Cancels all stream subscriptions and stops polling.
  /// Note: Does not dispose beacons as they are global singletons that may be
  /// used by other parts of the app. Beacons should only be disposed when the
  /// entire app is shutting down.
  ///
  /// Call this when the manager is no longer needed to prevent memory leaks.
  void dispose() {
    // Cancel all stream subscriptions
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();

    // Stop polling
    _pollTimer?.cancel();
    _pollTimer = null;

    // Do NOT dispose global beacons - they are singletons used across the app
  }
}
