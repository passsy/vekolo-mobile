import 'package:context_plus/context_plus.dart' as context_plus;
import 'package:state_beacon/state_beacon.dart';
import 'package:vekolo/domain/devices/device_manager.dart';
import 'package:vekolo/domain/devices/fitness_device.dart';
import 'package:vekolo/domain/models/fitness_data.dart';
import 'package:vekolo/services/workout_sync_service.dart';
import 'package:vekolo/state/device_state_manager.dart';

// ============================================================================
// Service References
// ============================================================================

/// Ref for dependency injection of DeviceManager.
///
/// Used throughout the app to access the central device coordinator.
/// Initialize with mock devices for testing or leave empty for production.
final deviceManagerRef = context_plus.Ref<DeviceManager>();

/// Ref for dependency injection of WorkoutSyncService.
///
/// Manages workout synchronization with the backend and coordinates
/// trainer control during workouts.
final workoutSyncServiceRef = context_plus.Ref<WorkoutSyncService>();

/// Ref for dependency injection of DeviceStateManager.
///
/// Bridges DeviceManager events to reactive UI state beacons.
/// Automatically disposed when the context is removed.
final deviceStateManagerRef = context_plus.Ref<DeviceStateManager>();

// ============================================================================
// UI State Beacons - Device List & Assignments
// ============================================================================

/// All currently connected fitness devices.
///
/// Updated by [DeviceStateManager] when devices are added/removed from
/// [DeviceManager]. Used by device selection screens to show available devices.
final connectedDevicesBeacon = Beacon.writable<List<FitnessDevice>>([]);

/// Currently assigned primary trainer for ERG control.
///
/// Updated when [DeviceManager.assignPrimaryTrainer] is called.
/// Used by UI to show which device is controlling resistance.
final primaryTrainerBeacon = Beacon.writable<FitnessDevice?>(null);

/// Currently assigned power data source.
///
/// May be a dedicated power meter or the primary trainer.
/// Updated when [DeviceManager.assignPowerSource] is called.
final powerSourceBeacon = Beacon.writable<FitnessDevice?>(null);

/// Currently assigned cadence data source.
///
/// May be a dedicated cadence sensor or the primary trainer.
/// Updated when [DeviceManager.assignCadenceSource] is called.
final cadenceSourceBeacon = Beacon.writable<FitnessDevice?>(null);

/// Currently assigned heart rate data source.
///
/// Typically a chest strap or wrist-based HR monitor.
/// Updated when [DeviceManager.assignHeartRateSource] is called.
final heartRateSourceBeacon = Beacon.writable<FitnessDevice?>(null);

// ============================================================================
// UI State Beacons - Real-time Sensor Data
// ============================================================================

/// Current power output in watts.
///
/// Updated from [DeviceManager.powerStream] by [DeviceStateManager].
/// Used by workout screens to display real-time power data.
final currentPowerBeacon = Beacon.writable<PowerData?>(null);

/// Current cadence in RPM.
///
/// Updated from [DeviceManager.cadenceStream] by [DeviceStateManager].
/// Used by workout screens to display real-time cadence data.
final currentCadenceBeacon = Beacon.writable<CadenceData?>(null);

/// Current heart rate in BPM.
///
/// Updated from [DeviceManager.heartRateStream] by [DeviceStateManager].
/// Used by workout screens to display real-time heart rate data.
final currentHeartRateBeacon = Beacon.writable<HeartRateData?>(null);

// ============================================================================
// UI State Beacons - Sync Status
// ============================================================================

/// Current workout sync status message.
///
/// Shows whether a workout is being synced, last sync result, etc.
/// Updated by [WorkoutSyncService] (to be implemented in Phase 5.2).
final syncStatusBeacon = Beacon.writable<String>('Not syncing');

/// Timestamp of the last successful workout sync.
///
/// Used to show "last synced" information in the UI.
/// Updated by [WorkoutSyncService] (to be implemented in Phase 5.2).
final lastSyncBeacon = Beacon.writable<DateTime?>(null);
