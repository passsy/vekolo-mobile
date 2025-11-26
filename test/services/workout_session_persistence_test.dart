import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vekolo/domain/models/workout/workout_models.dart';
import 'package:vekolo/domain/models/workout_session.dart';
import 'package:vekolo/services/workout_session_persistence.dart';

import '../helpers/shared_preferences_helper.dart';

/// Fake path provider for testing
class FakePathProviderPlatform extends Fake with MockPlatformInterfaceMixin implements PathProviderPlatform {
  FakePathProviderPlatform(this.tempDir);

  final Directory tempDir;

  @override
  Future<String?> getApplicationDocumentsPath() async {
    return tempDir.path;
  }
}

void main() {
  final testTime = DateTime.parse('2025-01-15T10:00:00.000Z');

  /// Creates test dependencies. Call this at the start of each test.
  /// Automatically registers cleanup with addTearDown.
  Future<({Directory tempDir, WorkoutSessionPersistence persistence})> createTestDependencies() async {
    // Create temporary directory for test files
    final tempDir = await Directory.systemTemp.createTemp('workout_session_test_');

    // Setup fake path provider
    PathProviderPlatform.instance = FakePathProviderPlatform(tempDir);

    // Setup SharedPreferences
    createTestSharedPreferencesAsync();

    // Setup persistence
    final persistence = WorkoutSessionPersistence(prefs: SharedPreferencesAsync());

    // Register cleanup
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    return (tempDir: tempDir, persistence: persistence);
  }

  group('Crash Detection (SharedPreferences)', () {
    test('getActiveWorkoutId returns null when no active workout', () async {
      final deps = await createTestDependencies();

      final activeId = await deps.persistence.getActiveWorkoutId();
      expect(activeId, isNull);
    });

    test('setActiveWorkout and getActiveWorkoutId work correctly', () async {
      final deps = await createTestDependencies();

      await deps.persistence.setActiveWorkout('test-workout-123');

      final activeId = await deps.persistence.getActiveWorkoutId();
      expect(activeId, 'test-workout-123');
    });

    test('clearActiveWorkout removes active workout', () async {
      final deps = await createTestDependencies();

      await deps.persistence.setActiveWorkout('test-workout-123');
      await deps.persistence.clearActiveWorkout();

      final activeId = await deps.persistence.getActiveWorkoutId();
      expect(activeId, isNull);
    });

    test('getActiveSession returns null when no active workout', () async {
      final deps = await createTestDependencies();

      final session = await deps.persistence.getActiveSession();
      expect(session, isNull);
    });

    test('getActiveSession returns null and cleans up if metadata missing', () async {
      final deps = await createTestDependencies();

      // Set active workout ID but don't create metadata file
      await deps.persistence.setActiveWorkout('missing-workout');

      final session = await deps.persistence.getActiveSession();
      expect(session, isNull);

      // Verify cleanup happened
      final activeId = await deps.persistence.getActiveWorkoutId();
      expect(activeId, isNull);
    });
  });

  group('Session Lifecycle', () {
    final testWorkoutPlan = WorkoutPlan(
      plan: [
        const PowerBlock(id: 'warmup', duration: 300000, power: 0.5),
        const PowerBlock(id: 'main', duration: 600000, power: 0.85),
      ],
    );

    test('createSession creates directory structure and metadata', () async {
      final deps = await createTestDependencies();

      final workoutId = await deps.persistence.createSession(
        'Test Workout',
        testWorkoutPlan,
        userId: 'user-123',
        ftp: 200,
        sourceWorkoutId: 'test-workout',
      );

      // Verify workout ID format (nanoid is 21 characters)
      expect(workoutId.length, 21);

      // Verify directory created
      final workoutDir = await deps.persistence.getWorkoutDirectory(workoutId);
      expect(await workoutDir.exists(), isTrue);

      // Verify metadata file created
      final metadataFile = await deps.persistence.getMetadataFile(workoutId);
      expect(await metadataFile.exists(), isTrue);

      // Verify active workout set
      final activeId = await deps.persistence.getActiveWorkoutId();
      expect(activeId, workoutId);

      // Verify metadata content
      final metadata = await deps.persistence.loadSessionMetadata(workoutId);
      expect(metadata, isNotNull);
      expect(metadata!.workoutId, workoutId);
      expect(metadata.workoutName, 'Test Workout');
      expect(metadata.status, SessionStatus.active);
      expect(metadata.userId, 'user-123');
      expect(metadata.ftp, 200);
      expect(metadata.totalSamples, 0);
      expect(metadata.currentBlockIndex, 0);
      expect(metadata.elapsedMs, 0);
    });

    test('loadSessionMetadata returns null for non-existent workout', () async {
      final deps = await createTestDependencies();

      final metadata = await deps.persistence.loadSessionMetadata('non-existent');
      expect(metadata, isNull);
    });

    test('updateSessionStatus updates metadata and clears active flag', () async {
      final deps = await createTestDependencies();

      final workoutId = await deps.persistence.createSession('Test Workout', testWorkoutPlan, ftp: 200, sourceWorkoutId: 'test-workout');

      // Update to completed
      await deps.persistence.updateSessionStatus(workoutId, SessionStatus.completed);

      // Verify status updated
      final metadata = await deps.persistence.loadSessionMetadata(workoutId);
      expect(metadata!.status, SessionStatus.completed);
      expect(metadata.endTime, isNotNull);

      // Verify active flag cleared
      final activeId = await deps.persistence.getActiveWorkoutId();
      expect(activeId, isNull);
    });

    test('updateSessionStatus to abandoned clears active flag', () async {
      final deps = await createTestDependencies();

      final workoutId = await deps.persistence.createSession('Test Workout', testWorkoutPlan, ftp: 200, sourceWorkoutId: 'test-workout');

      await deps.persistence.updateSessionStatus(workoutId, SessionStatus.abandoned);

      // Verify active flag cleared
      final activeId = await deps.persistence.getActiveWorkoutId();
      expect(activeId, isNull);
    });

    test('deleteSession removes entire workout folder', () async {
      final deps = await createTestDependencies();

      final workoutId = await deps.persistence.createSession('Test Workout', testWorkoutPlan, ftp: 200, sourceWorkoutId: 'test-workout');

      // Verify folder exists
      final workoutDir = await deps.persistence.getWorkoutDirectory(workoutId);
      expect(await workoutDir.exists(), isTrue);

      // Delete session
      await deps.persistence.deleteSession(workoutId);

      // Verify folder deleted
      expect(await workoutDir.exists(), isFalse);

      // Verify active flag cleared
      final activeId = await deps.persistence.getActiveWorkoutId();
      expect(activeId, isNull);
    });

    test('getActiveSession loads complete session from metadata', () async {
      final deps = await createTestDependencies();

      final workoutId = await deps.persistence.createSession(
        'Test Workout',
        testWorkoutPlan,
        userId: 'user-123',
        ftp: 200,
        sourceWorkoutId: 'test-workout',
      );

      final session = await deps.persistence.getActiveSession();
      expect(session, isNotNull);
      expect(session!.id, workoutId);
      expect(session.workoutName, 'Test Workout');
      expect(session.status, SessionStatus.active);
      expect(session.elapsedMs, 0);
      expect(session.currentBlockIndex, 0);
    });
  });

  group('Sample Storage (JSONL)', () {
    final testWorkoutPlan = WorkoutPlan(plan: [const PowerBlock(id: 'test', duration: 300000, power: 0.5)]);

    test('appendSample buffers and writes samples', () async {
      final deps = await createTestDependencies();

      final workoutId = await deps.persistence.createSession('Test', testWorkoutPlan, ftp: 200, sourceWorkoutId: 'test-workout');

      // Add samples (less than buffer size)
      final sample1 = WorkoutSample(
        timestamp: testTime,
        elapsedMs: 1000,
        powerActual: 100,
        powerTarget: 100,
        powerScaleFactor: 1.0,
      );
      await deps.persistence.appendSample(workoutId, sample1);

      // Flush manually
      await deps.persistence.flushAllSampleBuffers();

      // Verify sample written
      final samples = await deps.persistence.loadAllSamples(workoutId);
      expect(samples.length, 1);
      expect(samples[0].powerActual, 100);
    });

    test('appendSample auto-flushes when buffer full', () async {
      final deps = await createTestDependencies();

      final workoutId = await deps.persistence.createSession('Test', testWorkoutPlan, ftp: 200, sourceWorkoutId: 'test-workout');

      // Add exactly buffer size samples (should trigger auto-flush)
      for (int i = 0; i < 5; i++) {
        final sample = WorkoutSample(
          timestamp: testTime.add(Duration(seconds: i)),
          elapsedMs: i * 1000,
          powerActual: 100 + i,
          powerTarget: 100,
          powerScaleFactor: 1.0,
        );
        await deps.persistence.appendSample(workoutId, sample);
      }

      // Verify samples written (no manual flush needed)
      final samples = await deps.persistence.loadAllSamples(workoutId);
      expect(samples.length, 5);
    });

    test('appendSamples writes batch directly', () async {
      final deps = await createTestDependencies();

      final workoutId = await deps.persistence.createSession('Test', testWorkoutPlan, ftp: 200, sourceWorkoutId: 'test-workout');

      final samples = List.generate(
        10,
        (i) => WorkoutSample(
          timestamp: testTime.add(Duration(seconds: i)),
          elapsedMs: i * 1000,
          powerActual: 100 + i,
          powerTarget: 100,
          powerScaleFactor: 1.0,
        ),
      );

      await deps.persistence.appendSamples(workoutId, samples);

      // Verify all samples written
      final loadedSamples = await deps.persistence.loadAllSamples(workoutId);
      expect(loadedSamples.length, 10);
      expect(loadedSamples[0].powerActual, 100);
      expect(loadedSamples[9].powerActual, 109);
    });

    test('loadSamples streams samples without loading all into memory', () async {
      final deps = await createTestDependencies();

      final workoutId = await deps.persistence.createSession('Test', testWorkoutPlan, ftp: 200, sourceWorkoutId: 'test-workout');

      // Add many samples
      final samples = List.generate(
        100,
        (i) => WorkoutSample(
          timestamp: testTime.add(Duration(seconds: i)),
          elapsedMs: i * 1000,
          powerActual: i,
          powerTarget: 100,
          powerScaleFactor: 1.0,
        ),
      );
      await deps.persistence.appendSamples(workoutId, samples);

      // Stream samples
      final streamedSamples = <WorkoutSample>[];
      await for (final sample in deps.persistence.loadSamples(workoutId)) {
        streamedSamples.add(sample);
      }

      expect(streamedSamples.length, 100);
      expect(streamedSamples[0].powerActual, 0);
      expect(streamedSamples[99].powerActual, 99);
    });

    test('samples with null values (stale metrics) are persisted correctly', () async {
      final deps = await createTestDependencies();

      final workoutId = await deps.persistence.createSession('Test', testWorkoutPlan, ftp: 200, sourceWorkoutId: 'test-workout');

      final staleSample = WorkoutSample(
        timestamp: testTime,
        elapsedMs: 1000,
        powerTarget: 100,
        heartRate: 145, // Valid
        powerScaleFactor: 1.0,
      );

      await deps.persistence.appendSamples(workoutId, [staleSample]);

      // Load and verify
      final samples = await deps.persistence.loadAllSamples(workoutId);
      expect(samples.length, 1);
      expect(samples[0].powerActual, isNull);
      expect(samples[0].cadence, isNull);
      expect(samples[0].speed, isNull);
      expect(samples[0].heartRate, 145);
    });
  });

  group('Directory Management', () {
    final testWorkoutPlan = WorkoutPlan(plan: [const PowerBlock(id: 'test', duration: 300000, power: 0.5)]);

    test('listWorkoutIds returns empty list when no workouts', () async {
      final deps = await createTestDependencies();

      final ids = await deps.persistence.listWorkoutIds();
      expect(ids, isEmpty);
    });

    test('listWorkoutIds returns all workout IDs', () async {
      final deps = await createTestDependencies();

      // Create multiple workouts
      final id1 = await deps.persistence.createSession('Workout 1', testWorkoutPlan, ftp: 200, sourceWorkoutId: 'test-workout');
      final id2 = await deps.persistence.createSession('Workout 2', testWorkoutPlan, ftp: 200, sourceWorkoutId: 'test-workout');
      final id3 = await deps.persistence.createSession('Workout 3', testWorkoutPlan, ftp: 200, sourceWorkoutId: 'test-workout');

      final ids = await deps.persistence.listWorkoutIds();
      expect(ids.length, 3);
      expect(ids, containsAll([id1, id2, id3]));
    });
  });
}
