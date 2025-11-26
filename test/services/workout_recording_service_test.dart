import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vekolo/domain/models/workout/workout_models.dart';
import 'package:vekolo/domain/models/workout_session.dart';
import 'package:vekolo/services/workout_player_service.dart';
import 'package:vekolo/services/workout_recording_service.dart';
import 'package:vekolo/services/workout_session_persistence.dart';

import '../fake/fake_device_manager.dart';
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

/// Extension to run I/O operations with fake timers in widget tests.
extension WidgetTesterFakeTimers on WidgetTester {
  /// Runs I/O operations inside runAsync while keeping timers controllable with pump().
  ///
  /// Captures the fake async zone and forks a custom zone inside runAsync
  /// that delegates createPeriodicTimer back to the fake async zone.
  /// This allows real I/O operations while keeping timers controllable with tester.pump().
  Future<T?> runAsyncWithFakeTimers<T>(Future<T> Function() callback) async {
    final fakeAsyncZone = Zone.current;
    final result = await runAsync(() async {
      return await runZoned(
        callback,
        zoneSpecification: ZoneSpecification(
          createPeriodicTimer: (self, parent, zone, period, callback) {
            return fakeAsyncZone.createPeriodicTimer(period, callback);
          },
          createTimer: (Zone self, ZoneDelegate parent, Zone zone, Duration duration, void Function() f) {
            return fakeAsyncZone.createTimer(duration, callback);
          },
          // TODO also add microtask?
        ),
      );
    });
    return result;
  }
}

void main() {
  final testWorkoutPlan = WorkoutPlan(
    plan: [
      const PowerBlock(id: 'warmup', duration: 300000, power: 0.5), // 5 min
      const PowerBlock(id: 'main', duration: 600000, power: 0.85), // 10 min
    ],
  );

  /// Creates all test dependencies. Call this at the start of each test.
  /// Automatically registers cleanup with addTearDown.
  Future<
    ({
      Directory tempDir,
      WorkoutSessionPersistence persistence,
      FakeDeviceManager deviceManager,
      WorkoutPlayerService playerService,
      WorkoutRecordingService recordingService,
    })
  >
  createTestDependencies(WidgetTester tester) async {
    // Create temporary directory for test files
    final tempDir = (await tester.runAsync(() {
      return Directory.systemTemp.createTemp('workout_recording_test_');
    }))!;

    // Setup fake path provider
    PathProviderPlatform.instance = FakePathProviderPlatform(tempDir);

    // Setup SharedPreferences
    createTestSharedPreferencesAsync();

    // Setup persistence
    final persistence = WorkoutSessionPersistence(prefs: SharedPreferencesAsync());

    // Setup fake device manager
    final deviceManager = FakeDeviceManager();

    // Setup workout player service
    final playerService = WorkoutPlayerService(workoutPlan: testWorkoutPlan, deviceManager: deviceManager, ftp: 200);

    // Setup recording service (clock is optional, defaults to Clock() which is zone-aware)
    final recordingService = WorkoutRecordingService(
      playerService: playerService,
      deviceManager: deviceManager,
      persistence: persistence,
    );

    // Register cleanup
    addTearDown(() async {
      await recordingService.dispose();
      playerService.dispose();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    return (
      tempDir: tempDir,
      persistence: persistence,
      deviceManager: deviceManager,
      playerService: playerService,
      recordingService: recordingService,
    );
  }

  group('Recording Lifecycle', () {
    testWidgets('startRecording creates new session and starts sampling', (tester) async {
      final deps = await createTestDependencies(tester);

      expect(deps.recordingService.isRecording, isFalse);
      expect(deps.recordingService.sessionId, isNull);

      final sessionId = await tester.runAsyncWithFakeTimers(
        () => deps.recordingService.startRecording('Test Workout', ftp: 200, userId: 'user-123', sourceWorkoutId: 'test-workout'),
      );

      expect(sessionId, isNotNull);
      expect(sessionId!.length, 21); // nanoid length
      expect(deps.recordingService.isRecording, isTrue);
      expect(deps.recordingService.sessionId, sessionId);

      // Verify session created in persistence
      final activeId = await tester.runAsync(() => deps.persistence.getActiveWorkoutId());
      expect(activeId, sessionId);

      // Verify metadata created
      final metadata = await tester.runAsync(() => deps.persistence.loadSessionMetadata(sessionId));
      expect(metadata, isNotNull);
      expect(metadata!.workoutName, 'Test Workout');
      expect(metadata.status, SessionStatus.active);

      // Stop recording to clean up timer
      await tester.runAsync(() => deps.recordingService.stopRecording(completed: false));
    });

    testWidgets('startRecording when already recording returns existing session', (tester) async {
      final deps = await createTestDependencies(tester);

      final sessionId1 = await tester.runAsyncWithFakeTimers(
        () => deps.recordingService.startRecording('Test', ftp: 200, sourceWorkoutId: 'test-workout'),
      );
      final sessionId2 = await tester.runAsyncWithFakeTimers(
        () => deps.recordingService.startRecording('Test2', ftp: 200, sourceWorkoutId: 'test-workout-2'),
      );

      expect(sessionId1, sessionId2);

      // Stop recording to clean up timer
      await tester.runAsync(() => deps.recordingService.stopRecording(completed: false));
    });

    testWidgets('resumeRecording continues existing session', (tester) async {
      final deps = await createTestDependencies(tester);

      // Create a session manually
      final sessionId = await tester.runAsync(
        () => deps.persistence.createSession('Test Workout', testWorkoutPlan, ftp: 200, sourceWorkoutId: 'test-workout'),
      );
      await tester.runAsync(() => deps.persistence.updateSessionStatus(sessionId!, SessionStatus.crashed));

      // Resume recording
      await tester.runAsyncWithFakeTimers(() => deps.recordingService.resumeRecording(sessionId: sessionId!));

      expect(deps.recordingService.isRecording, isTrue);
      expect(deps.recordingService.sessionId, sessionId);

      // Verify status updated to active
      final metadata = await tester.runAsync(() => deps.persistence.loadSessionMetadata(sessionId!));
      expect(metadata!.status, SessionStatus.active);

      // Stop recording to clean up timer
      await tester.runAsync(() => deps.recordingService.stopRecording(completed: false));
    });

    testWidgets('resumeRecording throws if session not found', (tester) async {
      final deps = await createTestDependencies(tester);

      await tester.runAsync(() async {
        await expectLater(
          () => deps.recordingService.resumeRecording(sessionId: 'non-existent'),
          throwsA(isA<StateError>()),
        );
      });
    });

    testWidgets('stopRecording with completed=true marks session as completed', (tester) async {
      final deps = await createTestDependencies(tester);

      final sessionId = await tester.runAsyncWithFakeTimers(
        () => deps.recordingService.startRecording('Test', ftp: 200, sourceWorkoutId: 'test-workout'),
      );

      expect(sessionId, isNotNull);

      await tester.runAsync(() => deps.recordingService.stopRecording(completed: true));

      expect(deps.recordingService.isRecording, isFalse);
      expect(deps.recordingService.sessionId, isNull);

      // Verify session status
      final metadata = await tester.runAsync(() => deps.persistence.loadSessionMetadata(sessionId!));
      expect(metadata!.status, SessionStatus.completed);
      expect(metadata.endTime, isNotNull);

      // Verify active flag cleared
      final activeId = await tester.runAsync(() => deps.persistence.getActiveWorkoutId());
      expect(activeId, isNull);
    });

    testWidgets('stopRecording with completed=false marks session as abandoned', (tester) async {
      final deps = await createTestDependencies(tester);

      final sessionId = await tester.runAsyncWithFakeTimers(
        () => deps.recordingService.startRecording('Test', ftp: 200, sourceWorkoutId: 'test-workout'),
      );

      await tester.runAsync(() => deps.recordingService.stopRecording(completed: false));

      final metadata = await tester.runAsync(() => deps.persistence.loadSessionMetadata(sessionId!));
      expect(metadata!.status, SessionStatus.abandoned);
    });

    testWidgets('stopRecording when not recording does nothing', (tester) async {
      final deps = await createTestDependencies(tester);

      await tester.runAsync(() => deps.recordingService.stopRecording(completed: true));
      // Should not throw
    });
  });

  group('Sample Recording', () {
    testWidgets('records samples at 1Hz', (tester) async {
      final deps = await createTestDependencies(tester);

      // Set device data
      deps.deviceManager.setPower(195);
      deps.deviceManager.setCadence(88);
      deps.deviceManager.setSpeed(35.2);
      deps.deviceManager.setHeartRate(145);

      // Start player and recording
      deps.playerService.start();

      // Start recording with fake timers
      final sessionId = await tester.runAsyncWithFakeTimers(
        () => deps.recordingService.startRecording('Test', ftp: 200, sourceWorkoutId: 'test-workout'),
      );

      // Now pump to trigger timer callbacks
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));

      // Pause player service to cancel its timer
      deps.playerService.pause();

      // Dispose to flush samples
      await tester.runAsync(() => deps.recordingService.dispose());

      // Verify samples recorded
      final samples = await tester.runAsync(() => deps.persistence.loadAllSamples(sessionId!));
      expect(samples!.length, greaterThanOrEqualTo(3));

      // Verify sample content
      final firstSample = samples.first;
      expect(firstSample.powerActual, 195);
      expect(firstSample.cadence, 88);
      expect(firstSample.speed, 35.2);
      expect(firstSample.heartRate, 145);
      expect(firstSample.powerScaleFactor, 1.0);
    });

    testWidgets('records null for unavailable metrics', (tester) async {
      final deps = await createTestDependencies(tester);

      // Don't set any device data - all should be null
      deps.playerService.start();
      final sessionId = await tester.runAsyncWithFakeTimers(
        () => deps.recordingService.startRecording('Test', ftp: 200, sourceWorkoutId: 'test-workout'),
      );

      // Elapse 1 sample
      await tester.pump(const Duration(milliseconds: 1100));
      deps.playerService.pause();
      await tester.runAsync(() => deps.recordingService.dispose());

      final samples = await tester.runAsync(() => deps.persistence.loadAllSamples(sessionId!));
      expect(samples!.isNotEmpty, isTrue);

      final sample = samples.first;
      expect(sample.powerActual, isNull);
      expect(sample.cadence, isNull);
      expect(sample.speed, isNull);
      expect(sample.heartRate, isNull);
    });

    testWidgets('records power target from player service', (tester) async {
      final deps = await createTestDependencies(tester);

      deps.playerService.start();
      final sessionId = await tester.runAsyncWithFakeTimers(
        () => deps.recordingService.startRecording('Test', ftp: 200, sourceWorkoutId: 'test-workout'),
      );

      await tester.pump(const Duration(milliseconds: 1100));
      deps.playerService.pause();
      await tester.runAsync(() => deps.recordingService.dispose());

      final samples = await tester.runAsync(() => deps.persistence.loadAllSamples(sessionId!));
      expect(samples!.isNotEmpty, isTrue);

      // First block is warmup at 0.5 FTP = 100W
      final sample = samples.first;
      expect(sample.powerTarget, 100); // 200 * 0.5
    });

    testWidgets('records elapsed time from player service', (tester) async {
      final deps = await createTestDependencies(tester);

      deps.playerService.start();
      final sessionId = await tester.runAsyncWithFakeTimers(
        () => deps.recordingService.startRecording('Test', ftp: 200, sourceWorkoutId: 'test-workout'),
      );

      await tester.pump(const Duration(milliseconds: 2100));
      deps.playerService.pause();
      await tester.runAsync(() => deps.recordingService.dispose());

      final samples = await tester.runAsync(() => deps.persistence.loadAllSamples(sessionId!));
      expect(samples!.length, greaterThanOrEqualTo(2));

      // Verify elapsed time increases
      expect(samples[0].elapsedMs, lessThan(samples[1].elapsedMs));
    });
  });

  group('Metadata Updates', () {
    testWidgets('updates metadata periodically during recording', (tester) async {
      final deps = await createTestDependencies(tester);

      deps.playerService.start();
      final sessionId = await tester.runAsyncWithFakeTimers(
        () => deps.recordingService.startRecording('Test', ftp: 200, sourceWorkoutId: 'test-workout'),
      );

      // Elapse time for more than 10 samples (metadata updates every 10 samples)
      await tester.pump(const Duration(milliseconds: 11000));

      // Wait for async metadata update to complete
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));

      final metadata = await tester.runAsync(() => deps.persistence.loadSessionMetadata(sessionId!));
      expect(metadata!.totalSamples, greaterThan(0));

      deps.playerService.pause();
      await tester.runAsync(() => deps.recordingService.dispose());
    });

    testWidgets('updates metadata with current block index', (tester) async {
      final deps = await createTestDependencies(tester);

      deps.playerService.start();
      final sessionId = await tester.runAsyncWithFakeTimers(
        () => deps.recordingService.startRecording('Test', ftp: 200, sourceWorkoutId: 'test-workout'),
      );

      // Advance to next block
      deps.playerService.skip();

      // Elapse time for metadata update
      await tester.pump(const Duration(milliseconds: 11000));

      // Wait for async metadata update to complete
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));

      final metadata = await tester.runAsync(() => deps.persistence.loadSessionMetadata(sessionId!));
      expect(metadata!.currentBlockIndex, greaterThan(0));

      deps.playerService.pause();
      await tester.runAsync(() => deps.recordingService.dispose());
    });
  });

  group('Disposal', () {
    testWidgets('dispose flushes pending samples', (tester) async {
      final deps = await createTestDependencies(tester);

      deps.deviceManager.setPower(100);
      deps.playerService.start();
      final sessionId = await tester.runAsyncWithFakeTimers(
        () => deps.recordingService.startRecording('Test', ftp: 200, sourceWorkoutId: 'test-workout'),
      );

      // Wait for 2 samples
      await tester.pump(const Duration(milliseconds: 2100));

      deps.playerService.pause();
      await tester.runAsync(() => deps.recordingService.dispose());

      // Verify samples flushed
      final samples = await tester.runAsync(() => deps.persistence.loadAllSamples(sessionId!));
      expect(samples!.length, greaterThanOrEqualTo(2));
    });

    testWidgets('dispose updates final metadata', (tester) async {
      final deps = await createTestDependencies(tester);

      deps.playerService.start();
      final sessionId = await tester.runAsyncWithFakeTimers(
        () => deps.recordingService.startRecording('Test', ftp: 200, sourceWorkoutId: 'test-workout'),
      );

      await tester.pump(const Duration(milliseconds: 1100));

      final metadataBefore = await tester.runAsync(() => deps.persistence.loadSessionMetadata(sessionId!));
      final elapsedBefore = metadataBefore!.elapsedMs;

      await tester.pump(const Duration(milliseconds: 1000));
      deps.playerService.pause();
      await tester.runAsync(() => deps.recordingService.dispose());

      final metadataAfter = await tester.runAsync(() => deps.persistence.loadSessionMetadata(sessionId!));
      final elapsedAfter = metadataAfter!.elapsedMs;

      // Elapsed time should have increased
      expect(elapsedAfter, greaterThan(elapsedBefore));
    });

    testWidgets('dispose stops recording timer', (tester) async {
      final deps = await createTestDependencies(tester);

      deps.playerService.start();
      final sessionId = await tester.runAsyncWithFakeTimers(
        () => deps.recordingService.startRecording('Test', ftp: 200, sourceWorkoutId: 'test-workout'),
      );

      await tester.pump(const Duration(milliseconds: 1100));
      deps.playerService.pause();
      await tester.runAsync(() => deps.recordingService.dispose());

      // Wait a bit more
      await tester.pump(const Duration(milliseconds: 2000));

      // Verify no new samples after disposal
      final samplesAfterDispose = await tester.runAsync(() => deps.persistence.loadAllSamples(sessionId!));
      final countAfterDispose = samplesAfterDispose!.length;

      await tester.pump(const Duration(milliseconds: 2000));
      final samplesLater = await tester.runAsync(() => deps.persistence.loadAllSamples(sessionId!));

      expect(samplesLater!.length, countAfterDispose);
    });

    testWidgets('dispose can be called multiple times safely', (tester) async {
      final deps = await createTestDependencies(tester);

      deps.playerService.start();
      await tester.runAsyncWithFakeTimers(() => deps.recordingService.startRecording('Test', ftp: 200, sourceWorkoutId: 'test-workout'));

      deps.playerService.pause();
      await tester.runAsync(() => deps.recordingService.dispose());
      await tester.runAsync(() => deps.recordingService.dispose());
      await tester.runAsync(() => deps.recordingService.dispose());

      // Should not throw
    });
  });
}
