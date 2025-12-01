/// Service that manages workout execution with real-time power control.
///
/// This is the core workout playback engine that:
/// - Executes structured workouts with millisecond precision
/// - Tracks workout state and progress through blocks
/// - Calculates power targets (including ramps) and syncs to trainer
/// - Triggers events (messages, effects) at the right time
/// - Handles pause/resume, skip, and early completion
/// - Supports power scale factor adjustments (FTP calibration)
///
/// Based on the web implementation at `/vekolo-web/app/models/WorkoutPlayer.ts`.
///
/// Example usage:
/// ```dart
/// final player = WorkoutPlayerService(
///   workoutPlan: plan,
///   deviceManager: deviceManager,
///   ftp: 200,
/// );
///
/// // Listen to state changes
/// player.currentBlock$.subscribe((block) {
///   print('Current block: $block');
/// });
///
/// // Start workout
/// player.start();
///
/// // Pause/resume
/// player.pause();
/// player.start();
///
/// // Skip block
/// player.skip();
///
/// // Adjust intensity
/// player.setPowerScaleFactor(1.05); // +5%
///
/// // Complete early
/// player.completeEarly();
///
/// // Cleanup
/// player.dispose();
/// ```
library;

import 'dart:async';

import 'package:chirp/chirp.dart';
import 'package:clock/clock.dart';
import 'package:state_beacon/state_beacon.dart';
import 'package:vekolo/domain/devices/device_manager.dart';
import 'package:vekolo/domain/models/erg_command.dart';
import 'package:vekolo/domain/models/power_history.dart';
import 'package:vekolo/domain/models/workout/workout_models.dart';
import 'package:vekolo/domain/models/workout/workout_utils.dart';
import 'package:vekolo/services/workout_sync_service.dart';

/// Manages workout execution state and coordinates power control.
///
/// This service is responsible for the complete workout playback experience:
/// tracking time, advancing through blocks, calculating power targets,
/// syncing to the trainer, and triggering events.
class WorkoutPlayerService {
  /// Creates a workout player service.
  ///
  /// Requires:
  /// - [workoutPlan] - The workout to execute
  /// - [deviceManager] - For accessing trainer and metrics
  /// - [ftp] - Functional Threshold Power in watts for power calculations
  /// - [powerScaleFactor] - Optional intensity adjustment (default 1.0)
  WorkoutPlayerService({
    required WorkoutPlan workoutPlan,
    required DeviceManager deviceManager,
    required int ftp,
    double powerScaleFactor = 1.0,
  }) : _workoutPlan = workoutPlan,
       _ftp = ftp,
       _deviceManager = deviceManager,
       _syncService = WorkoutSyncService(deviceManager),
       _flattenedPlan = flattenWorkoutPlan(workoutPlan.plan, powerScaleFactor: powerScaleFactor),
       _flattenedEvents = flattenWorkoutEvents(workoutPlan.plan, workoutPlan.events),
       _totalDuration = calculateTotalDuration(workoutPlan.plan) {
    // Set initial scale factor
    this.powerScaleFactor.value = powerScaleFactor;

    // Initialize state
    remainingTime$.value = _totalDuration;
    _updateCurrentAndNextBlock();
    _updateProgress();

    chirp.info(
      'Initialized: ${_flattenedPlan.length} blocks, '
      '${_totalDuration}ms duration, FTP ${_ftp}W',
    );
  }

  // ==========================================================================
  // Dependencies
  // ==========================================================================

  final WorkoutPlan _workoutPlan;
  final int _ftp;
  final WorkoutSyncService _syncService;
  final DeviceManager _deviceManager;

  /// The workout plan being executed.
  WorkoutPlan get workoutPlan => _workoutPlan;

  /// Power history tracker for visualization.
  final PowerHistory powerHistory = PowerHistory();

  // ==========================================================================
  // Flattened Workout Data
  // ==========================================================================

  final List<dynamic> _flattenedPlan; // List of PowerBlock or RampBlock
  final List<dynamic> _flattenedEvents; // List of FlattenedMessageEvent or FlattenedEffectEvent
  final int _totalDuration;

  // ==========================================================================
  // Playback State
  // ==========================================================================

  /// Current block index in the flattened plan.
  int _currentBlockIndex = 0;

  /// The absolute clock time when the workout first started (or was restored).
  ///
  /// This is set once when [start] is first called and never changes after that
  /// (except when restoring from a saved session via [restoreState]).
  DateTime? _workoutStartTime;

  /// Total time spent paused in milliseconds.
  ///
  /// Accumulated when resuming from pauses. This is added to when the workout
  /// is unpaused to account for the time spent in pause state.
  int _totalPausedDuration = 0;

  /// The clock time when the current pause started, or null if not paused.
  ///
  /// Set when [pause] is called, cleared when [start] resumes the workout.
  DateTime? _currentPauseStartTime;

  /// Cached elapsed time from the last calculation.
  ///
  /// This is updated on each tick via [_calculateElapsedTime].
  /// Use this for internal calculations that need the elapsed time.
  int _workoutElapsedTime = 0;

  /// Timer for the playback loop.
  Timer? _timer;

  /// Timer interval in milliseconds.
  ///
  /// This controls how often the UI updates and power targets are synced.
  /// The workout state is calculated based on elapsed clock time, so larger
  /// intervals are fine - they just mean less frequent UI updates.
  /// 1 second is sufficient for UI updates while being efficient.
  static const int _timerInterval = 1000;

  /// Set of event IDs that have already been triggered.
  ///
  /// Prevents events from being triggered multiple times (e.g., when
  /// scrubbing through the workout or due to timer precision issues).
  final Set<String> _triggeredEventIds = {};

  // ==========================================================================
  // Public State (Reactive Beacons)
  // ==========================================================================

  /// Whether the workout is paused.
  ///
  /// When true, timer is stopped and no state updates occur.
  /// When false, timer is running and workout is progressing.
  final WritableBeacon<bool> isPaused = Beacon.writable(true);

  /// Whether the workout is complete.
  ///
  /// Set to true when all blocks are finished or when [completeEarly] is called.
  final WritableBeacon<bool> isComplete = Beacon.writable(false);

  /// Current block being executed.
  ///
  /// Can be PowerBlock or RampBlock. Null if workout is complete.
  final WritableBeacon<dynamic> currentBlock$ = Beacon.writable(null);

  /// Next block to be executed.
  ///
  /// Can be PowerBlock or RampBlock. Null if current block is the last one.
  final WritableBeacon<dynamic> nextBlock$ = Beacon.writable(null);

  /// Current block index in the flattened plan.
  final WritableBeacon<int> currentBlockIndex$ = Beacon.writable(0);

  /// Current power target in watts.
  ///
  /// Calculated from the current block's power percentage, FTP, and power scale factor.
  /// For ramp blocks, this value interpolates smoothly between start and end power.
  final WritableBeacon<int> powerTarget$ = Beacon.writable(0);

  /// Current cadence target in RPM.
  ///
  /// Null if the current block doesn't specify a cadence target.
  /// For ramp blocks with cadence ramps, interpolates between start and end.
  final WritableBeacon<int?> cadenceTarget$ = Beacon.writable(null);

  /// Minimum cadence in RPM.
  ///
  /// Null if the current block doesn't specify a minimum cadence.
  final WritableBeacon<int?> cadenceLow$ = Beacon.writable(null);

  /// Maximum cadence in RPM.
  ///
  /// Null if the current block doesn't specify a maximum cadence.
  final WritableBeacon<int?> cadenceHigh$ = Beacon.writable(null);

  /// Workout progress as a fraction (0.0 to 1.0).
  ///
  /// Represents how much of the workout has been completed.
  final WritableBeacon<double> progress$ = Beacon.writable(0.0);

  /// Remaining time in the workout (milliseconds).
  ///
  /// Counts down as the workout progresses.
  final WritableBeacon<int> remainingTime$ = Beacon.writable(0);

  /// Elapsed time in the workout (milliseconds).
  ///
  /// Counts up as the workout progresses. Includes paused time.
  final WritableBeacon<int> elapsedTime$ = Beacon.writable(0);

  /// Remaining time in the current block (milliseconds).
  ///
  /// Counts down as the block progresses.
  final WritableBeacon<int> currentBlockRemainingTime$ = Beacon.writable(0);

  /// Power scale factor for intensity adjustment.
  ///
  /// Multiplier applied to all power targets. Range: 0.1 to 5.0.
  /// - 1.0 = 100% intensity (normal)
  /// - 0.9 = 90% intensity (easier)
  /// - 1.1 = 110% intensity (harder)
  ///
  /// When changed, the workout plan is re-flattened with the new factor.
  final WritableBeacon<double> powerScaleFactor = Beacon.writable(1.0);

  /// Stream of triggered events.
  ///
  /// Emits events (MessageEvent or EffectEvent) as they occur during playback.
  /// Subscribe to this to display messages or trigger visual effects.
  final StreamController<dynamic> _triggeredEventController = StreamController<dynamic>.broadcast();

  /// Stream of triggered events during workout execution.
  Stream<dynamic> get triggeredEvent$ => _triggeredEventController.stream;

  // ==========================================================================
  // Public API
  // ==========================================================================

  /// Starts or resumes the workout.
  ///
  /// If this is the first start, initializes timing. If resuming from pause,
  /// continues from the last paused position.
  ///
  /// Starts the timer loop and begins syncing power targets to the trainer.
  ///
  /// Safe to call multiple times - subsequent calls while running are no-ops.
  void start() {
    if (!isPaused.value) {
      return; // Already running
    }

    if (isComplete.value) {
      chirp.info('Cannot start: workout is already complete');
      return;
    }

    if (_currentBlockIndex >= _flattenedPlan.length) {
      chirp.info('Cannot start: no blocks remaining');
      return;
    }

    chirp.info('Starting workout');

    final now = clock.now();

    // First start - record the workout start time
    if (_workoutStartTime == null) {
      _workoutStartTime = now;
      chirp.info('Workout start time set to: $_workoutStartTime');
    }

    // If resuming from pause, add the pause duration to total
    if (_currentPauseStartTime != null) {
      final pauseDuration = now.difference(_currentPauseStartTime!).inMilliseconds;
      _totalPausedDuration += pauseDuration;
      _currentPauseStartTime = null;
      chirp.info('Resumed after ${pauseDuration}ms pause (total paused: ${_totalPausedDuration}ms)');
    }

    isPaused.value = false;

    // Start syncing to trainer
    _syncService.startSync();

    // Start timer loop
    _startTimer();

    // Immediately update state (don't wait for first timer tick)
    _tick();
  }

  /// Pauses the workout.
  ///
  /// Stops the timer loop, freezes elapsed time, and stops syncing to trainer.
  /// Workout state is preserved and can be resumed with [start].
  ///
  /// Safe to call when already paused - will be a no-op.
  void pause() {
    if (isPaused.value) {
      return; // Already paused
    }

    chirp.info('Pausing workout');

    // Record when pause started (used to calculate pause duration on resume)
    _currentPauseStartTime = clock.now();

    // Mark as paused
    isPaused.value = true;

    // Stop timer
    _stopTimer();

    // Stop syncing to trainer
    _syncService.stopSync();
  }

  /// Skips the current block and advances to the next one.
  ///
  /// Updates elapsed time to include the full duration of the skipped block,
  /// then advances to the next block. If this was the last block, completes
  /// the workout.
  ///
  /// Safe to call when paused - will skip and remain paused.
  void skip() {
    final currentBlock = currentBlock$.value;
    if (currentBlock == null) {
      chirp.info('Cannot skip: no current block');
      return;
    }

    chirp.info('Skipping block $_currentBlockIndex');

    // Calculate the target elapsed time (end of current block)
    final elapsedUntilCurrentBlock = _getWorkoutElapsedUntilCurrentBlock();
    final blockDuration = _getBlockDuration(currentBlock);
    final targetElapsedTime = elapsedUntilCurrentBlock + blockDuration;

    // Calculate current elapsed time
    final currentElapsedTime = _calculateElapsedTime();

    // Adjust pause duration to make elapsed time jump to target
    // elapsed = now - startTime - pausedDuration
    // targetElapsed = now - startTime - newPausedDuration
    // newPausedDuration = pausedDuration - (targetElapsed - currentElapsed)
    final skipAmount = targetElapsedTime - currentElapsedTime;
    if (skipAmount > 0) {
      _totalPausedDuration -= skipAmount;
    }

    // Update cached elapsed time
    _workoutElapsedTime = targetElapsedTime;

    // Update displays
    elapsedTime$.value = _workoutElapsedTime;
    remainingTime$.value = (_totalDuration - _workoutElapsedTime).clamp(0, _totalDuration);

    // Advance to next block
    _currentBlockIndex++;
    _updateCurrentAndNextBlock();
    _updateProgress();

    // Check if workout is complete
    if (_currentBlockIndex >= _flattenedPlan.length) {
      _completeWorkout();
    }
  }

  /// Adjusts the power scale factor (intensity).
  ///
  /// The factor is clamped to the range [0.1, 5.0] for safety.
  /// When changed, the workout plan is re-flattened with the new factor,
  /// and power targets are recalculated.
  ///
  /// Example:
  /// ```dart
  /// player.setPowerScaleFactor(1.05); // +5% intensity
  /// player.setPowerScaleFactor(0.95); // -5% intensity
  /// ```
  void setPowerScaleFactor(double factor) {
    final clampedFactor = factor.clamp(0.1, 5.0);

    chirp.info('Setting power scale factor: ${clampedFactor.toStringAsFixed(2)}');

    powerScaleFactor.value = clampedFactor;

    // Re-flatten the plan with the new factor
    _flattenedPlan.clear();
    _flattenedPlan.addAll(flattenWorkoutPlan(_workoutPlan.plan, powerScaleFactor: clampedFactor));

    // Update current/next blocks
    _updateCurrentAndNextBlock();
  }

  /// Completes the workout early.
  ///
  /// Marks the workout as complete, stops the timer, and stops syncing
  /// to the trainer. The current elapsed time is preserved.
  ///
  /// Use this when the user manually ends the workout before finishing
  /// all blocks.
  void completeEarly() {
    // Update cached elapsed time before completing
    _workoutElapsedTime = _calculateElapsedTime();
    chirp.info('Completing workout early at ${_workoutElapsedTime}ms');

    _completeWorkout();
  }

  /// Restores the workout state from a saved session (crash recovery).
  ///
  /// This allows resuming a workout from where it was interrupted, by
  /// restoring the elapsed time and current block position.
  ///
  /// The workout will be in a paused state after restoration - call [start]
  /// to resume playback.
  ///
  /// Example:
  /// ```dart
  /// // Restore from saved session
  /// player.restoreState(
  ///   elapsedMs: 123000,  // 2:03 into the workout
  ///   currentBlockIndex: 2,  // Was on block #2
  /// );
  ///
  /// // Now resume playback
  /// player.start();
  /// ```
  void restoreState({required int elapsedMs, required int currentBlockIndex}) {
    chirp.info(
      'Restoring state: elapsedMs=$elapsedMs, '
      'currentBlockIndex=$currentBlockIndex',
    );

    // Validate block index
    if (currentBlockIndex < 0 || currentBlockIndex >= _flattenedPlan.length) {
      chirp.info(
        'Invalid block index $currentBlockIndex, '
        'clamping to valid range',
      );
      _currentBlockIndex = currentBlockIndex.clamp(0, _flattenedPlan.length - 1);
    } else {
      _currentBlockIndex = currentBlockIndex;
    }

    // Restore elapsed time by setting start time and pause duration
    // such that when start() is called, elapsed time will be elapsedMs
    // We set start time to "now" and adjust pause duration to be negative
    // to account for the already-elapsed time
    final now = clock.now();
    _workoutStartTime = now;
    _totalPausedDuration = -elapsedMs;
    _currentPauseStartTime = now; // Will be cleared when start() is called

    // Update cached elapsed time
    _workoutElapsedTime = elapsedMs;
    elapsedTime$.value = _workoutElapsedTime;

    // Update remaining time
    remainingTime$.value = (_totalDuration - _workoutElapsedTime).clamp(0, _totalDuration);

    // Update current/next blocks and progress
    _updateCurrentAndNextBlock();
    _updateProgress();

    // Ensure workout stays paused after restore
    isPaused.value = true;

    chirp.info('State restored successfully');
  }

  /// Disposes of all resources used by this service.
  ///
  /// Stops the timer, disposes all beacons, and cleans up the sync service.
  /// After calling this, the service should not be used anymore.
  void dispose() {
    chirp.info('Disposing WorkoutPlayerService');

    _stopTimer();
    _syncService.dispose();
    _triggeredEventController.close();

    // Dispose beacons
    isPaused.dispose();
    isComplete.dispose();
    currentBlock$.dispose();
    nextBlock$.dispose();
    currentBlockIndex$.dispose();
    powerTarget$.dispose();
    cadenceTarget$.dispose();
    cadenceLow$.dispose();
    cadenceHigh$.dispose();
    progress$.dispose();
    remainingTime$.dispose();
    elapsedTime$.dispose();
    currentBlockRemainingTime$.dispose();
    powerScaleFactor.dispose();
  }

  // ==========================================================================
  // Private Implementation - Timer Management
  // ==========================================================================

  /// Starts the timer loop.
  void _startTimer() {
    _stopTimer(); // Ensure no existing timer

    _timer = Timer.periodic(Duration(milliseconds: _timerInterval), (timer) => _tick());
  }

  /// Stops the timer loop.
  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  /// Timer tick - called periodically during playback.
  ///
  /// This is the core of the workout player. On each tick:
  /// 1. Calculate elapsed time from clock (handles large time jumps)
  /// 2. Advance through completed blocks
  /// 3. Update remaining time and progress
  /// 4. Calculate power target for current block
  /// 5. Check and trigger events
  ///
  /// The state is calculated based on elapsed clock time, so this method
  /// correctly handles large time jumps (e.g., in tests) by advancing
  /// through multiple blocks if needed.
  void _tick() {
    if (isPaused.value || _currentBlockIndex >= _flattenedPlan.length) {
      return;
    }

    // Calculate elapsed time from clock (handles large time jumps correctly)
    _workoutElapsedTime = _calculateElapsedTime();

    // Advance through any completed blocks (handles large time jumps)
    _advanceToCurrentBlock();

    // Check if workout is complete after advancing
    if (_currentBlockIndex >= _flattenedPlan.length) {
      return;
    }

    // Update remaining time and progress
    final newRemainingTime = (_totalDuration - _workoutElapsedTime).clamp(0, _totalDuration);
    if (newRemainingTime != remainingTime$.value) {
      remainingTime$.value = newRemainingTime;
      _updateProgress();
    }
    // Always update elapsedTime$ beacon for crash recovery metadata
    elapsedTime$.value = _workoutElapsedTime;

    // Calculate power target for current block
    final currentBlock = _flattenedPlan[_currentBlockIndex];
    if (currentBlock != null) {
      final blockElapsedTime = _workoutElapsedTime - _getWorkoutElapsedUntilCurrentBlock();
      _updatePowerTarget(currentBlock, blockElapsedTime);
    }

    // Record power history
    _recordPowerHistory();

    // Check for events to trigger
    _checkEvents(_workoutElapsedTime);
  }

  /// Advances the block index to match the current elapsed time.
  ///
  /// This handles large time jumps by skipping through completed blocks
  /// until we find the block that should be active at the current time.
  void _advanceToCurrentBlock() {
    while (_currentBlockIndex < _flattenedPlan.length) {
      final elapsedUntilCurrentBlock = _getWorkoutElapsedUntilCurrentBlock();
      final blockDuration = _getBlockDuration(_flattenedPlan[_currentBlockIndex]);
      final blockEndTime = elapsedUntilCurrentBlock + blockDuration;

      if (_workoutElapsedTime < blockEndTime) {
        // Current block is still active
        break;
      }

      // Block is complete, advance to next
      _currentBlockIndex++;
      _updateCurrentAndNextBlock();
    }

    // Check if we've completed all blocks
    if (_currentBlockIndex >= _flattenedPlan.length) {
      _completeWorkout();
    }
  }

  // ==========================================================================
  // Private Implementation - Block Handling
  // ==========================================================================

  /// Updates power target and cadence for the current block.
  ///
  /// Routes to specific handlers based on block type.
  /// Block advancement is handled separately by [_advanceToCurrentBlock].
  void _updatePowerTarget(dynamic block, int blockElapsedTime) {
    if (block is PowerBlock) {
      _updatePowerBlockTarget(block, blockElapsedTime);
    } else if (block is RampBlock) {
      _updateRampBlockTarget(block, blockElapsedTime);
    }
  }

  /// Updates power target for a power block (constant power).
  void _updatePowerBlockTarget(PowerBlock block, int blockElapsedTime) {
    // Calculate power target in watts
    // Note: block.power already has powerScaleFactor applied from flattening
    final powerWatts = (block.power * _ftp).round();
    powerTarget$.value = powerWatts;

    // Set cadence targets
    cadenceTarget$.value = block.cadence;
    cadenceLow$.value = block.cadenceLow;
    cadenceHigh$.value = block.cadenceHigh;

    // Update remaining time in current block
    final blockRemainingTime = (block.duration - blockElapsedTime).clamp(0, block.duration);
    currentBlockRemainingTime$.value = blockRemainingTime;

    // Update sync service with new target
    _syncService.currentTarget.value = ErgCommand(targetWatts: powerWatts, timestamp: clock.now());
  }

  /// Updates power target for a ramp block (gradually changing power).
  void _updateRampBlockTarget(RampBlock block, int blockElapsedTime) {
    // Calculate interpolated power target
    // Note: block.powerStart/End already have powerScaleFactor applied from flattening
    final progress = (blockElapsedTime / block.duration).clamp(0.0, 1.0);
    final relativePower = block.powerStart + progress * (block.powerEnd - block.powerStart);
    final powerWatts = (relativePower * _ftp).round();
    powerTarget$.value = powerWatts;

    // Calculate interpolated cadence target if both start and end are set
    int? cadenceTarget;
    if (block.cadenceStart != null && block.cadenceEnd != null) {
      final cadence = block.cadenceStart! + progress * (block.cadenceEnd! - block.cadenceStart!);
      cadenceTarget = cadence.round();
    }
    cadenceTarget$.value = cadenceTarget;
    cadenceLow$.value = block.cadenceLow;
    cadenceHigh$.value = block.cadenceHigh;

    // Update remaining time in current block
    final blockRemainingTime = (block.duration - blockElapsedTime).clamp(0, block.duration);
    currentBlockRemainingTime$.value = blockRemainingTime;

    // Update sync service with new target
    _syncService.currentTarget.value = ErgCommand(targetWatts: powerWatts, timestamp: clock.now());
  }

  // ==========================================================================
  // Private Implementation - Event Handling
  // ==========================================================================

  /// Checks for events that should trigger at the current time.
  ///
  /// Events are triggered once based on their absolute time offset.
  /// Once triggered, they are added to [_triggeredEventIds] to prevent
  /// re-triggering.
  void _checkEvents(int globalElapsedTime) {
    for (final flattenedEvent in _flattenedEvents) {
      String eventId;
      int timeOffset;

      if (flattenedEvent is FlattenedMessageEvent) {
        eventId = flattenedEvent.id;
        timeOffset = flattenedEvent.timeOffset;
      } else if (flattenedEvent is FlattenedEffectEvent) {
        eventId = flattenedEvent.id;
        timeOffset = flattenedEvent.timeOffset;
      } else {
        continue;
      }

      // Check if event should trigger now
      if (globalElapsedTime >= timeOffset && !_triggeredEventIds.contains(eventId)) {
        // Trigger event
        _triggeredEventController.add(flattenedEvent);
        _triggeredEventIds.add(eventId);

        chirp.info('Triggered event: $eventId at ${globalElapsedTime}ms');
      }
    }
  }

  // ==========================================================================
  // Private Implementation - State Updates
  // ==========================================================================

  /// Updates the current and next block beacons.
  void _updateCurrentAndNextBlock() {
    if (_currentBlockIndex < _flattenedPlan.length) {
      currentBlock$.value = _flattenedPlan[_currentBlockIndex];
    } else {
      currentBlock$.value = null;
    }

    if (_currentBlockIndex + 1 < _flattenedPlan.length) {
      nextBlock$.value = _flattenedPlan[_currentBlockIndex + 1];
    } else {
      nextBlock$.value = null;
    }

    currentBlockIndex$.value = _currentBlockIndex;
  }

  /// Updates the progress beacon.
  void _updateProgress() {
    progress$.value = _totalDuration > 0 ? (_workoutElapsedTime / _totalDuration).clamp(0.0, 1.0) : 0.0;

    // Update current block remaining time
    final currentBlock = currentBlock$.value;
    if (currentBlock != null) {
      final blockDuration = _getBlockDuration(currentBlock);
      final blockElapsed = _workoutElapsedTime - _getWorkoutElapsedUntilCurrentBlock();
      currentBlockRemainingTime$.value = (blockDuration - blockElapsed).clamp(0, blockDuration);
    } else {
      currentBlockRemainingTime$.value = 0;
    }
  }

  /// Calculates the current workout elapsed time in milliseconds.
  ///
  /// The elapsed time is calculated from the workout start time minus
  /// any time spent paused. This approach ensures correct behavior
  /// with large time jumps in tests.
  int _calculateElapsedTime() {
    if (_workoutStartTime == null) {
      return 0;
    }

    final now = clock.now();
    final totalWallTime = now.difference(_workoutStartTime!).inMilliseconds;

    // If currently paused, don't count time since pause started
    int currentPauseDuration = 0;
    if (_currentPauseStartTime != null) {
      currentPauseDuration = now.difference(_currentPauseStartTime!).inMilliseconds;
    }

    return totalWallTime - _totalPausedDuration - currentPauseDuration;
  }

  /// Completes the workout.
  void _completeWorkout() {
    chirp.info('Workout complete at ${_workoutElapsedTime}ms');

    isPaused.value = true;
    isComplete.value = true;

    _stopTimer();
    _syncService.stopSync();
  }

  // ==========================================================================
  // Private Implementation - Helpers
  // ==========================================================================

  /// Gets the total elapsed time up to (but not including) the current block.
  int _getWorkoutElapsedUntilCurrentBlock() {
    var elapsed = 0;
    for (var i = 0; i < _currentBlockIndex && i < _flattenedPlan.length; i++) {
      elapsed += _getBlockDuration(_flattenedPlan[i]);
    }
    return elapsed;
  }

  /// Gets the duration of a block.
  int _getBlockDuration(dynamic block) {
    if (block is PowerBlock) {
      return block.duration;
    } else if (block is RampBlock) {
      return block.duration;
    }
    return 0;
  }

  /// Records power history data point.
  ///
  /// Called on each tick to record current power vs target power.
  void _recordPowerHistory() {
    final actualPower = _deviceManager.powerStream.value?.watts ?? 0;
    final targetPower = powerTarget$.value;

    powerHistory.record(timestamp: _workoutElapsedTime, actualWatts: actualPower, targetWatts: targetPower);
  }
}
