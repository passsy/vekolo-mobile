import 'dart:convert';
import 'dart:io';

import 'package:chirp/chirp.dart';
import 'package:clock/clock.dart';
import 'package:nanoid2/nanoid2.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vekolo/domain/models/workout/workout_models.dart';
import 'package:vekolo/domain/models/workout_session.dart';

/// Service for persisting workout sessions with crash recovery support.
///
/// Implements local-first storage using:
/// - SharedPreferences: Single active workout ID for O(1) crash detection
/// - File system: One folder per workout with metadata.json + samples.jsonl
///
/// Storage structure:
/// ```
/// <app_documents>/workouts/
/// ├── V1StGXR8_Z5jdHi6B-myT/          # Workout folder (nanoid)
/// │   ├── metadata.json                # Workout metadata
/// │   └── samples.jsonl                # Recorded samples (append-only)
/// └── ...
/// ```
///
/// SharedPreferences only stores the active workout ID:
/// ```json
/// {
///   "vekolo.workout_sessions.active": "V1StGXR8_Z5jdHi6B-myT"
/// }
/// ```
class WorkoutSessionPersistence {
  WorkoutSessionPersistence({required SharedPreferencesAsync prefs}) : _prefs = prefs;

  final SharedPreferencesAsync _prefs;

  static const String _activeWorkoutKey = 'vekolo.workout_sessions.active';
  static const String _workoutsDirectoryName = 'workouts';

  // Sample buffering for performance (write every N samples)
  static const int _sampleBufferSize = 5;
  final Map<String, List<WorkoutSample>> _sampleBuffers = {};

  /// Get the workouts base directory path.
  ///
  /// Returns: `<app_documents>/workouts/`
  Future<Directory> _getWorkoutsBaseDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final workoutsDir = Directory('${appDir.path}/$_workoutsDirectoryName');
    return workoutsDir;
  }

  /// Get the directory for a specific workout.
  ///
  /// Returns: `<app_documents>/workouts/{workoutId}/`
  Future<Directory> getWorkoutDirectory(String workoutId) async {
    final baseDir = await _getWorkoutsBaseDirectory();
    return Directory('${baseDir.path}/$workoutId');
  }

  /// Get the metadata file for a specific workout.
  ///
  /// Returns: `<app_documents>/workouts/{workoutId}/metadata.json`
  Future<File> getMetadataFile(String workoutId) async {
    final workoutDir = await getWorkoutDirectory(workoutId);
    return File('${workoutDir.path}/metadata.json');
  }

  /// Get the samples file for a specific workout.
  ///
  /// Returns: `<app_documents>/workouts/{workoutId}/samples.jsonl`
  Future<File> getSamplesFile(String workoutId) async {
    final workoutDir = await getWorkoutDirectory(workoutId);
    return File('${workoutDir.path}/samples.jsonl');
  }

  // ==========================================================================
  // Crash Detection (SharedPreferences)
  // ==========================================================================

  /// Get the ID of the currently active workout (for crash detection).
  ///
  /// Returns the workout ID if a workout is active, null otherwise.
  Future<String?> getActiveWorkoutId() async {
    return await _prefs.getString(_activeWorkoutKey);
  }

  /// Set the active workout ID (for crash detection).
  ///
  /// Call this when a workout starts recording.
  Future<void> setActiveWorkout(String workoutId) async {
    await _prefs.setString(_activeWorkoutKey, workoutId);
    chirp.info('Set active workout: $workoutId');
  }

  /// Clear the active workout ID (for crash detection).
  ///
  /// Call this when a workout completes, is abandoned, or is discarded.
  Future<void> clearActiveWorkout() async {
    await _prefs.remove(_activeWorkoutKey);
    chirp.info('Cleared active workout');
  }

  /// Get the active workout session (for crash recovery).
  ///
  /// Returns:
  /// - WorkoutSession if an active workout exists and its metadata can be loaded
  /// - null if no active workout or if metadata file is missing
  ///
  /// If metadata file is missing but active flag exists, cleans up the orphaned flag.
  Future<WorkoutSession?> getActiveSession() async {
    final workoutId = await getActiveWorkoutId();
    if (workoutId == null) {
      return null;
    }

    chirp.info('Found active workout ID: $workoutId');

    // Load metadata from file
    final metadata = await loadSessionMetadata(workoutId);
    if (metadata == null) {
      // Metadata file missing - cleanup orphaned active flag
      chirp.info('Metadata file missing for active workout $workoutId, cleaning up');
      await clearActiveWorkout();
      return null;
    }

    return WorkoutSession.fromMetadata(metadata);
  }

  // ==========================================================================
  // Session Lifecycle
  // ==========================================================================

  /// Create a new workout session.
  ///
  /// Creates:
  /// - New workout folder
  /// - metadata.json with initial data
  /// - Sets active workout ID in SharedPreferences
  ///
  /// Returns the generated workout ID (nanoid).
  Future<String> createSession(
    String workoutName,
    WorkoutPlan plan, {
    String? userId,
    required int ftp,
    String? sourceWorkoutId,
  }) async {
    // Generate unique ID using nanoid
    final workoutId = nanoid();
    chirp.info('Creating session: $workoutId ($workoutName)');

    // Create workout directory
    final workoutDir = await getWorkoutDirectory(workoutId);
    await workoutDir.create(recursive: true);

    // Create initial metadata
    final metadata = WorkoutSessionMetadata(
      workoutId: workoutId,
      workoutName: workoutName,
      workoutPlan: plan,
      startTime: clock.now(),
      status: SessionStatus.active,
      userId: userId,
      sourceWorkoutId: sourceWorkoutId,
      ftp: ftp,
      totalSamples: 0,
      currentBlockIndex: 0,
      elapsedMs: 0,
      lastUpdated: clock.now(),
    );

    // Save metadata
    await _saveMetadata(metadata);

    // Mark as active in SharedPreferences
    await setActiveWorkout(workoutId);

    chirp.info('Session created: $workoutId');
    return workoutId;
  }

  /// Load session metadata from file.
  ///
  /// Returns null if metadata file doesn't exist or is corrupted.
  Future<WorkoutSessionMetadata?> loadSessionMetadata(String workoutId) async {
    final metadataFile = await getMetadataFile(workoutId);

    if (!await metadataFile.exists()) {
      chirp.info('Metadata file not found: $workoutId');
      return null;
    }

    try {
      final jsonString = await metadataFile.readAsString();
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      return WorkoutSessionMetadata.fromJson(json);
    } catch (e, stackTrace) {
      chirp.error('Failed to load metadata for $workoutId', error: e, stackTrace: stackTrace);
      return null;
    }
  }

  /// Update session status.
  ///
  /// Updates the status in metadata.json and clears active flag if completed/abandoned.
  Future<void> updateSessionStatus(String workoutId, SessionStatus status) async {
    chirp.info('Updating session $workoutId status to ${status.value}');

    final metadata = await loadSessionMetadata(workoutId);
    if (metadata == null) {
      chirp.info('Cannot update status - metadata not found: $workoutId');
      return;
    }

    final updatedMetadata = metadata.copyWith(
      status: status,
      endTime: (status == SessionStatus.completed || status == SessionStatus.abandoned) ? clock.now() : null,
      lastUpdated: clock.now(),
    );

    await _saveMetadata(updatedMetadata);

    // Clear active flag if workout is no longer active
    if (status != SessionStatus.active) {
      await clearActiveWorkout();
    }
  }

  /// Update session metadata (for progress tracking during workout).
  ///
  /// Updates currentBlockIndex, elapsedMs, and totalSamples.
  Future<void> updateSessionMetadata(WorkoutSessionMetadata metadata) async {
    await _saveMetadata(metadata);
  }

  /// Delete a workout session entirely.
  ///
  /// Removes the entire workout folder (metadata + samples).
  Future<void> deleteSession(String workoutId) async {
    chirp.info('Deleting session: $workoutId');

    final workoutDir = await getWorkoutDirectory(workoutId);
    if (await workoutDir.exists()) {
      await workoutDir.delete(recursive: true);
      chirp.info('Session deleted: $workoutId');
    }

    // Clear active flag if this was the active workout
    final activeId = await getActiveWorkoutId();
    if (activeId == workoutId) {
      await clearActiveWorkout();
    }
  }

  /// Save metadata to file.
  Future<void> _saveMetadata(WorkoutSessionMetadata metadata) async {
    final metadataFile = await getMetadataFile(metadata.workoutId);
    final json = jsonEncode(metadata.toJson());

    // Ensure parent directory exists before writing
    final parentDir = metadataFile.parent;
    if (!await parentDir.exists()) {
      await parentDir.create(recursive: true);
    }

    // Use flush: true to ensure data is written to disk immediately
    // This prevents race conditions in tests and crash scenarios
    metadataFile.writeAsStringSync(json, flush: true);
  }

  // ==========================================================================
  // Sample Storage (JSONL)
  // ==========================================================================

  /// Append a single sample to the samples file.
  ///
  /// Samples are buffered and written in batches for performance.
  Future<void> appendSample(String workoutId, WorkoutSample sample) async {
    // Add to buffer
    final buffer = _sampleBuffers.putIfAbsent(workoutId, () => []);
    buffer.add(sample);

    // Flush if buffer is full
    if (buffer.length >= _sampleBufferSize) {
      await _flushSampleBuffer(workoutId);
    }
  }

  /// Append multiple samples at once (batch write).
  Future<void> appendSamples(String workoutId, List<WorkoutSample> samples) async {
    if (samples.isEmpty) return;

    final samplesFile = await getSamplesFile(workoutId);

    // Ensure parent directory exists before writing
    final parentDir = samplesFile.parent;
    if (!await parentDir.exists()) {
      chirp.info('Parent directory for samples does not exist, skipping write for $workoutId');
      return;
    }

    final sink = samplesFile.openWrite(mode: FileMode.append);

    try {
      for (final sample in samples) {
        final json = jsonEncode(sample.toJson());
        sink.writeln(json); // Each sample = one line
      }
      await sink.flush();
    } finally {
      await sink.close();
    }

    // Update metadata with new sample count
    await _updateMetadataSampleCount(workoutId, samples.length);
  }

  /// Flush the sample buffer for a workout.
  ///
  /// Writes all buffered samples to disk.
  Future<void> _flushSampleBuffer(String workoutId) async {
    final buffer = _sampleBuffers[workoutId];
    if (buffer == null || buffer.isEmpty) return;

    chirp.info('Flushing ${buffer.length} samples for $workoutId');
    await appendSamples(workoutId, buffer);
    buffer.clear();
  }

  /// Flush all sample buffers.
  ///
  /// Call this on app pause or workout stop.
  Future<void> flushAllSampleBuffers() async {
    final workoutIds = _sampleBuffers.keys.toList();
    for (final workoutId in workoutIds) {
      await _flushSampleBuffer(workoutId);
    }
  }

  /// Update the totalSamples count in metadata.
  Future<void> _updateMetadataSampleCount(String workoutId, int additionalSamples) async {
    final metadata = await loadSessionMetadata(workoutId);
    if (metadata == null) return;

    final updated = metadata.copyWith(
      totalSamples: metadata.totalSamples + additionalSamples,
      lastUpdated: clock.now(),
    );

    await _saveMetadata(updated);
  }

  /// Load all samples for a workout as a stream.
  ///
  /// Reads JSONL file line-by-line without loading all into memory.
  Stream<WorkoutSample> loadSamples(String workoutId) async* {
    final samplesFile = await getSamplesFile(workoutId);
    if (!await samplesFile.exists()) {
      return;
    }

    final lines = samplesFile.openRead().transform(utf8.decoder).transform(const LineSplitter());

    await for (final line in lines) {
      if (line.trim().isEmpty) continue;

      try {
        final json = jsonDecode(line) as Map<String, dynamic>;
        yield WorkoutSample.fromJson(json);
      } catch (e, stackTrace) {
        chirp.error('Failed to parse sample line', error: e, stackTrace: stackTrace);
      }
    }
  }

  /// Load all samples for a workout into memory.
  ///
  /// Use [loadSamples] stream for large workout files.
  Future<List<WorkoutSample>> loadAllSamples(String workoutId) async {
    final samples = <WorkoutSample>[];
    await for (final sample in loadSamples(workoutId)) {
      samples.add(sample);
    }
    return samples;
  }

  // ==========================================================================
  // Directory Management
  // ==========================================================================

  /// List all workout IDs.
  ///
  /// Returns folder names in the workouts directory.
  Future<List<String>> listWorkoutIds() async {
    final baseDir = await _getWorkoutsBaseDirectory();

    if (!await baseDir.exists()) {
      return [];
    }

    final entities = await baseDir.list().toList();
    return entities.whereType<Directory>().map((dir) => dir.path.split('/').last).toList();
  }
}
