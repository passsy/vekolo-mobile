/// Service that syncs workout targets to the primary trainer.
///
/// This is the KEY COMPONENT that bridges workout playback and device control.
/// It manages the complex task of:
/// - Reacting to workout target changes and syncing them to the trainer
/// - Implementing retry logic with exponential backoff for failed commands
/// - Periodically refreshing targets for devices that require continuous updates
/// - Tracking sync state and errors for UI feedback
///
/// Used by workout playback screens to control ERG mode during structured workouts.
/// The service handles all edge cases: no trainer, trainer doesn't support ERG,
/// connection failures, timeout requirements, etc.
///
/// Example usage:
/// ```dart
/// final syncService = WorkoutSyncService(deviceManager);
///
/// // Start syncing
/// syncService.startSync();
///
/// // Update target from workout
/// syncService.currentTarget.value = ErgCommand(
///   targetWatts: 200,
///   timestamp: DateTime.now(),
/// );
///
/// // Monitor sync status
/// syncService.isSyncing.subscribe((syncing) {
///   print('Syncing: $syncing');
/// });
///
/// // Stop syncing
/// syncService.stopSync();
/// syncService.dispose();
/// ```
library;

import 'dart:async';

import 'package:state_beacon/state_beacon.dart';
import 'package:vekolo/domain/devices/device_manager.dart';
import 'package:vekolo/domain/models/erg_command.dart';

/// Syncs workout targets to the primary trainer with retry and refresh logic.
///
/// This service coordinates between workout playback (which sets targets) and
/// the device manager (which controls the actual trainer). It handles all the
/// messy details of ensuring commands actually reach the trainer reliably.
class WorkoutSyncService {
  /// Creates a workout sync service.
  ///
  /// Requires a [DeviceManager] to access the primary trainer for sending
  /// ERG mode commands.
  WorkoutSyncService(this._deviceManager);

  final DeviceManager _deviceManager;

  // ==========================================================================
  // Public State (Reactive Beacons)
  // ==========================================================================

  /// Current target power from workout playback.
  ///
  /// Set this beacon to update the trainer's target power. The service will
  /// automatically sync the new target to the device when [isSyncing] is true.
  ///
  /// Setting to null effectively clears the target but doesn't send any
  /// command to the trainer. This is useful when a workout is paused or ended.
  final WritableBeacon<ErgCommand?> currentTarget = Beacon.writable(null);

  /// Whether the service is actively syncing targets to the trainer.
  ///
  /// When true:
  /// - Changes to [currentTarget] are automatically synced to the trainer
  /// - Periodic refresh is active if the trainer requires it
  /// - Retry logic is enabled for failed commands
  ///
  /// When false:
  /// - Target changes are ignored
  /// - No commands are sent to the trainer
  /// - Periodic refresh is stopped
  ///
  /// Use [startSync] and [stopSync] to control this state.
  final WritableBeacon<bool> isSyncing = Beacon.writable(false);

  /// Timestamp of the last successful sync to the trainer.
  ///
  /// Updated each time a command is successfully sent. Useful for UI to show
  /// how fresh the sync is, or to detect if sync has stalled.
  ///
  /// Null if no successful sync has occurred yet.
  final WritableBeacon<DateTime?> lastSyncTime = Beacon.writable(null);

  /// Error message from the most recent sync attempt.
  ///
  /// Contains a human-readable description of what went wrong:
  /// - "No trainer connected" - no primary trainer assigned
  /// - "Retry 1/3", "Retry 2/3", "Retry 3/3" - retry in progress
  /// - "Failed after 3 retries" - all retries exhausted
  ///
  /// Null when sync is working normally. UI can show this to explain why
  /// the trainer isn't responding.
  final WritableBeacon<String?> syncError = Beacon.writable(null);

  // ==========================================================================
  // Private State
  // ==========================================================================

  /// Timer for periodic refresh of targets to the trainer.
  ///
  /// Only active when [isSyncing] is true and the trainer requires continuous
  /// refresh. Re-sends the last command at the trainer's preferred interval.
  Timer? _refreshTimer;

  /// Unsubscribe function for currentTarget changes.
  ///
  /// Active when syncing - triggers sync on target changes.
  void Function()? _targetUnsubscribe;

  /// The most recently sent command to the trainer.
  ///
  /// Used by the periodic refresh mechanism to re-send the same target.
  /// Cleared when syncing stops.
  ErgCommand? _lastSentCommand;

  /// Current retry attempt for the active command.
  ///
  /// Incremented on each failed sync attempt, reset on success.
  /// When this reaches [_maxRetries], we give up and report failure.
  int _retryCount = 0;

  /// Maximum number of retry attempts before giving up.
  ///
  /// Conservative value: 3 retries with exponential backoff (1s, 2s, 3s delays)
  /// gives up to 6 seconds total retry time, which should be sufficient for
  /// transient connection issues while not hanging indefinitely.
  static const int _maxRetries = 3;

  // ==========================================================================
  // Public API
  // ==========================================================================

  /// Starts syncing workout targets to the primary trainer.
  ///
  /// Once started:
  /// - Changes to [currentTarget] will automatically sync to the trainer
  /// - Periodic refresh will activate if the trainer needs it
  /// - Retry logic is enabled for failures
  ///
  /// Safe to call multiple times - subsequent calls are no-ops.
  ///
  /// Call [stopSync] to stop syncing when the workout ends or is paused.
  void startSync() {
    if (isSyncing.value) {
      return; // Already syncing
    }

    isSyncing.value = true;

    // React to target changes from workout playback
    _targetUnsubscribe = currentTarget.subscribe((target) {
      if (target != null && isSyncing.value) {
        _syncTargetToDevice(target);
      }
    });

    // Start periodic refresh for devices that need it
    _startRefreshTimer();
  }

  /// Stops syncing targets to the trainer.
  ///
  /// Cancels periodic refresh, clears retry state, and stops reacting to
  /// [currentTarget] changes. The current [currentTarget] value is preserved
  /// but not sent to the trainer.
  ///
  /// Safe to call even if not currently syncing - will be a no-op.
  ///
  /// Call this when:
  /// - Workout is paused or stopped
  /// - User navigates away from the workout
  /// - App is backgrounded
  void stopSync() {
    isSyncing.value = false;

    // Cancel target change subscription
    _targetUnsubscribe?.call();
    _targetUnsubscribe = null;

    // Cancel periodic refresh
    _refreshTimer?.cancel();
    _refreshTimer = null;

    // Clear state
    _lastSentCommand = null;
    _retryCount = 0;
  }

  /// Releases all resources used by this service.
  ///
  /// Stops syncing if active and disposes all beacons. After calling this,
  /// the service should not be used anymore.
  ///
  /// Call this when the service is no longer needed (e.g., app shutdown,
  /// service replacement) to prevent memory leaks.
  void dispose() {
    stopSync();
    currentTarget.dispose();
    isSyncing.dispose();
    lastSyncTime.dispose();
    syncError.dispose();
  }

  // ==========================================================================
  // Private Implementation
  // ==========================================================================

  /// Syncs the target to the device with retry logic.
  ///
  /// This is the core sync mechanism that:
  /// 1. Validates the trainer is available, connected, and supports ERG mode
  /// 2. Sends the target power command to the trainer
  /// 3. On success: updates sync state and resets retry count
  /// 4. On failure: implements exponential backoff retry up to [_maxRetries]
  ///
  /// Retry delays scale with attempt number: 1s, 2s, 3s for attempts 1-3.
  /// This gives transient issues time to resolve while not hanging indefinitely.
  Future<void> _syncTargetToDevice(ErgCommand command) async {
    final trainer = _deviceManager.primaryTrainer;

    // Validate trainer exists and supports ERG mode
    if (trainer == null) {
      syncError.value = 'No trainer connected';
      return;
    }

    if (!trainer.supportsErgMode) {
      syncError.value = 'Trainer does not support ERG mode';
      return;
    }

    try {
      // Send command to trainer
      // Note: setTargetPower will throw if device is not connected
      await trainer.setTargetPower(command.targetWatts);

      // Success - update state
      _lastSentCommand = command;
      lastSyncTime.value = DateTime.now();
      syncError.value = null;
      _retryCount = 0;
    } catch (e, stackTrace) {
      // Log error with full stack trace for debugging
      print('[WorkoutSyncService.syncTargetToDevice] Failed to set target power to ${command.targetWatts}W: $e');
      print(stackTrace);

      // Check if it's a "device not connected" error - don't retry those
      if (e is StateError && e.message == 'Device not connected') {
        syncError.value = 'Device not connected';
        _retryCount = 0;
        return;
      }

      // Retry with exponential backoff for other errors
      if (_retryCount < _maxRetries) {
        _retryCount++;
        final delay = _retryCount; // 1s, 2s, 3s for retries 1-3
        syncError.value = 'Retry $_retryCount/$_maxRetries';

        print('[WorkoutSyncService.syncTargetToDevice] Retrying in ${delay}s (attempt $_retryCount/$_maxRetries)');

        // Wait and retry
        await Future.delayed(Duration(seconds: delay));

        // Only retry if still syncing (user might have stopped)
        if (isSyncing.value) {
          await _syncTargetToDevice(command);
        }
      } else {
        // All retries exhausted
        syncError.value = 'Failed after $_maxRetries retries';
        _retryCount = 0;
        print('[WorkoutSyncService.syncTargetToDevice] Giving up after $_maxRetries failed attempts');
      }
    }
  }

  /// Starts the periodic refresh timer for trainers that need it.
  ///
  /// Some trainers (FTMS, ANT+ FE-C) may timeout if commands aren't regularly
  /// resent. This timer re-sends the last command at the trainer's preferred
  /// refresh interval to keep the target active.
  ///
  /// The timer is only created if:
  /// - A primary trainer is assigned
  /// - The trainer's [requiresContinuousRefresh] is true
  ///
  /// If conditions aren't met, this is a no-op. The timer is automatically
  /// cancelled when [stopSync] is called.
  void _startRefreshTimer() {
    final trainer = _deviceManager.primaryTrainer;

    // Only create timer if trainer exists and needs refresh
    if (trainer == null || !trainer.requiresContinuousRefresh) {
      return;
    }

    // Cancel any existing timer
    _refreshTimer?.cancel();

    print(
      '[WorkoutSyncService.startRefreshTimer] Starting periodic refresh every ${trainer.refreshInterval.inSeconds}s',
    );

    // Create periodic timer at trainer's preferred interval
    _refreshTimer = Timer.periodic(trainer.refreshInterval, (timer) {
      // Re-send last command if we're syncing and have a command to send
      if (_lastSentCommand != null && isSyncing.value) {
        print('[WorkoutSyncService.refreshTimer] Refreshing target: ${_lastSentCommand!.targetWatts}W');
        _syncTargetToDevice(_lastSentCommand!);
      }
    });
  }
}
