import 'package:state_beacon/state_beacon.dart';
import 'package:vekolo/domain/devices/fitness_device.dart';
import 'package:vekolo/domain/models/fitness_data.dart';

/// Manages the roster of connected fitness devices and their role assignments.
///
/// Holds which devices are connected and which device is assigned to each role
/// (primary trainer, power source, cadence source, heart rate source).
/// Injected via Ref to avoid global mutable state.
class ConnectedDevices {
  /// All currently connected fitness devices.
  ///
  /// Updated by [DeviceStateManager] when devices are added/removed.
  /// Used by device selection screens to show available devices.
  final devices = Beacon.writable<List<FitnessDevice>>([]);

  /// Currently assigned primary trainer for ERG control.
  ///
  /// Updated when primary trainer is assigned.
  /// Used by UI to show which device is controlling resistance.
  final primaryTrainer = Beacon.writable<FitnessDevice?>(null);

  /// Currently assigned power data source.
  ///
  /// May be a dedicated power meter or the primary trainer.
  final powerSource = Beacon.writable<FitnessDevice?>(null);

  /// Currently assigned cadence data source.
  ///
  /// May be a dedicated cadence sensor or the primary trainer.
  final cadenceSource = Beacon.writable<FitnessDevice?>(null);

  /// Currently assigned heart rate data source.
  ///
  /// Typically a chest strap or wrist-based HR monitor.
  final heartRateSource = Beacon.writable<FitnessDevice?>(null);

  /// Disposes all beacons.
  void dispose() {
    devices.dispose();
    primaryTrainer.dispose();
    powerSource.dispose();
    cadenceSource.dispose();
    heartRateSource.dispose();
  }
}

/// Real-time aggregated sensor telemetry from connected devices.
///
/// Holds the current readings from whichever devices are assigned to provide
/// power, cadence, and heart rate data. This is aggregated telemetry - the
/// readings come from different devices based on role assignments.
/// Injected via Ref to avoid global mutable state.
class LiveTelemetry {
  /// Current power output in watts.
  ///
  /// Aggregated from the assigned power source device.
  /// Updated by [DeviceStateManager] from [DeviceManager.powerStream].
  final power = Beacon.writable<PowerData?>(null);

  /// Current cadence in RPM.
  ///
  /// Aggregated from the assigned cadence source device.
  /// Updated by [DeviceStateManager] from [DeviceManager.cadenceStream].
  final cadence = Beacon.writable<CadenceData?>(null);

  /// Current heart rate in BPM.
  ///
  /// Aggregated from the assigned heart rate source device.
  /// Updated by [DeviceStateManager] from [DeviceManager.heartRateStream].
  final heartRate = Beacon.writable<HeartRateData?>(null);

  /// Disposes all beacons.
  void dispose() {
    power.dispose();
    cadence.dispose();
    heartRate.dispose();
  }
}

/// Workout synchronization state.
///
/// Tracks the status of workout synchronization with the backend/trainer.
/// Injected via Ref to avoid global mutable state.
class WorkoutSyncState {
  /// Current workout sync status message.
  ///
  /// Shows whether a workout is being synced, last sync result, etc.
  /// Updated by [WorkoutSyncService].
  final status = Beacon.writable<String>('Not syncing');

  /// Timestamp of the last successful workout sync.
  ///
  /// Used to show "last synced" information in the UI.
  /// Updated by [WorkoutSyncService].
  final lastSyncTime = Beacon.writable<DateTime?>(null);

  /// Disposes all beacons.
  void dispose() {
    status.dispose();
    lastSyncTime.dispose();
  }
}
