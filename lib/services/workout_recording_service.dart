import 'dart:async';

import 'package:clock/clock.dart';
import 'package:chirp/chirp.dart';
import 'package:vekolo/domain/devices/device_manager.dart';
import 'package:vekolo/domain/models/workout_session.dart';
import 'package:vekolo/services/workout_player_service.dart';
import 'package:vekolo/services/workout_session_persistence.dart';

/// Service for recording workout session data at 1Hz.
///
/// Automatically records power, heart rate, cadence, and speed metrics
/// during workout playback, with crash recovery support.
///
/// Features:
/// - 1Hz sampling (1 sample per second)
/// - Continuous saving to persistent storage
/// - Pause/resume support
/// - Automatic cleanup on dispose
///
/// Usage:
/// ```dart
/// final recordingService = WorkoutRecordingService(
///   playerService: workoutPlayer,
///   deviceManager: deviceManager,
///   persistence: persistence,
///   clock: clock,
/// );
///
/// // Start recording
/// await recordingService.startRecording('Sweet Spot Intervals', ftp: 200);
///
/// // Recording happens automatically every second...
///
/// // Stop recording (workout completed)
/// await recordingService.stopRecording(completed: true);
///
/// // Or resume existing session
/// await recordingService.resumeRecording(sessionId: 'existing-session-id');
///
/// // Always dispose
/// recordingService.dispose();
/// ```
class WorkoutRecordingService {
  WorkoutRecordingService({
    required WorkoutPlayerService playerService,
    required DeviceManager deviceManager,
    required WorkoutSessionPersistence persistence,
  }) : _playerService = playerService,
       _deviceManager = deviceManager,
       _persistence = persistence;

  final WorkoutPlayerService _playerService;
  final DeviceManager _deviceManager;
  final WorkoutSessionPersistence _persistence;

  Timer? _recordingTimer;
  String? _sessionId;
  bool _isRecording = false;
  bool _disposed = false;

  /// Whether recording is currently active.
  bool get isRecording => _isRecording;

  /// Current session ID (null if not recording).
  String? get sessionId => _sessionId;

  /// Start recording a new workout session.
  ///
  /// Creates a new session and begins sampling metrics at 1Hz.
  /// Returns the generated session ID.
  Future<String> startRecording(
    String workoutName, {
    String? userId,
    required int ftp,
    required String sourceWorkoutId,
  }) async {
    if (_isRecording) {
      chirp.info('Already recording session: $_sessionId');
      return _sessionId!;
    }

    chirp.info('Starting recording: $workoutName');

    // Create new session
    _sessionId = await _persistence.createSession(
      workoutName,
      _playerService.workoutPlan,
      userId: userId,
      ftp: ftp,
      sourceWorkoutId: sourceWorkoutId,
    );

    // Start sampling
    _startSampling();

    chirp.info('Recording started: $_sessionId');
    return _sessionId!;
  }

  /// Resume recording an existing session.
  ///
  /// Used for crash recovery - continues recording to an existing session.
  Future<void> resumeRecording({required String sessionId}) async {
    if (_isRecording) {
      chirp.info('Already recording session: $_sessionId');
      return;
    }

    chirp.info('Resuming recording: $sessionId');

    // Verify session exists
    final metadata = await _persistence.loadSessionMetadata(sessionId);
    if (metadata == null) {
      throw StateError('Cannot resume - session not found: $sessionId');
    }

    _sessionId = sessionId;

    // Mark as active in case it was marked as crashed
    await _persistence.updateSessionStatus(sessionId, SessionStatus.active);

    // Start sampling
    _startSampling();

    chirp.info('Recording resumed: $_sessionId');
  }

  /// Stop recording.
  ///
  /// Flushes any pending samples and updates session status.
  /// Use [completed] = true when workout finished normally,
  /// false when abandoned or stopped early.
  Future<void> stopRecording({required bool completed}) async {
    if (!_isRecording) {
      chirp.info('Not recording, nothing to stop');
      return;
    }

    chirp.info('Stopping recording (completed: $completed)');

    // Stop sampling timer
    _recordingTimer?.cancel();
    _recordingTimer = null;
    _isRecording = false;

    // Flush any pending samples
    await _persistence.flushAllSampleBuffers();

    // Update session status
    if (_sessionId != null) {
      await _persistence.updateSessionStatus(
        _sessionId!,
        completed ? SessionStatus.completed : SessionStatus.abandoned,
      );
    }

    chirp.info('Recording stopped: $_sessionId');
    _sessionId = null;
  }

  /// Start the 1Hz sampling timer.
  void _startSampling() {
    if (_recordingTimer != null) {
      chirp.info('Sampling already started');
      return;
    }

    _isRecording = true;

    // Sample every 1 second
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _recordSample();
    });

    chirp.info('Sampling started (1Hz)');
  }

  /// Record a single sample.
  ///
  /// Reads current values from beacons (no subscriptions!) and writes to persistence.
  void _recordSample() {
    // Guard against timer firing during/after dispose
    if (_disposed) {
      return;
    }

    if (_sessionId == null) {
      chirp.info('Cannot record sample - no session ID');
      return;
    }

    // Collect sample from player service and device manager
    final sample = WorkoutSample(
      timestamp: clock.now(),
      elapsedMs: _playerService.elapsedTime$.value,
      powerActual: _deviceManager.powerStream.value?.watts,
      powerTarget: _playerService.powerTarget$.value,
      cadence: _deviceManager.cadenceStream.value?.rpm,
      speed: _deviceManager.speedStream.value?.kmh,
      heartRate: _deviceManager.heartRateStream.value?.bpm,
      powerScaleFactor: _playerService.powerScaleFactor.value,
    );

    // Write to persistence (buffered, auto-flushes)
    _persistence.appendSample(_sessionId!, sample);

    // Update metadata periodically (every 10 samples = 10 seconds)
    _updateMetadataPeriodically();
  }

  int _samplesSinceMetadataUpdate = 0;
  static const int _metadataUpdateInterval = 10; // Update metadata every 10 samples

  /// Update metadata periodically to track workout progress.
  ///
  /// Updates currentBlockIndex and elapsedMs for crash recovery.
  Future<void> _updateMetadataPeriodically() async {
    _samplesSinceMetadataUpdate++;

    if (_samplesSinceMetadataUpdate >= _metadataUpdateInterval) {
      _samplesSinceMetadataUpdate = 0;

      if (_sessionId == null || _disposed) {
        return;
      }

      // Capture values synchronously before any async operations.
      // This ensures we save the correct elapsed time even if the service
      // is disposed while waiting for persistence I/O.
      final sessionId = _sessionId!;
      final elapsed = _playerService.elapsedTime$.value;
      final blockIndex = _playerService.currentBlockIndex$.value;
      final now = clock.now();

      final metadata = await _persistence.loadSessionMetadata(sessionId);
      if (metadata == null) {
        return;
      }

      final updated = metadata.copyWith(
        currentBlockIndex: blockIndex,
        elapsedMs: elapsed,
        lastUpdated: now,
      );

      await _persistence.updateSessionMetadata(updated);
    }
  }

  /// Dispose and cleanup.
  ///
  /// IMPORTANT: Always call this when done with the service.
  /// Stops recording and flushes pending samples.
  Future<void> dispose() async {
    chirp.info('Disposing');

    // Mark as disposed first to prevent timer callbacks from accessing beacons
    _disposed = true;

    // Stop timer
    _recordingTimer?.cancel();
    _recordingTimer = null;

    // Flush any pending samples (but don't mark as completed)
    // Note: We don't update metadata here since player service beacons may already be disposed
    if (_isRecording && _sessionId != null) {
      await _persistence.flushAllSampleBuffers();
    }

    _isRecording = false;
    _sessionId = null;

    chirp.info('Disposed');
  }
}
