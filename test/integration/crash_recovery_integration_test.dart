import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:vekolo/domain/devices/device_manager.dart';
import 'package:vekolo/domain/models/workout/workout_models.dart';
import 'package:vekolo/domain/models/workout_session.dart';
import 'package:vekolo/services/device_assignment_persistence.dart';
import 'package:vekolo/services/workout_player_service.dart';
import 'package:vekolo/services/workout_recording_service.dart';
import 'package:vekolo/services/workout_session_persistence.dart';
import '../ble/fake_ble_permissions.dart';
import '../ble/fake_ble_platform.dart';
import '../helpers/shared_preferences_helper.dart';
import 'package:vekolo/ble/ble_scanner.dart';
import 'package:vekolo/ble/transport_registry.dart';

/// Fake PathProviderPlatform for testing
class FakePathProviderPlatform extends Fake with MockPlatformInterfaceMixin implements PathProviderPlatform {
  final Directory tempDir;

  FakePathProviderPlatform(this.tempDir);

  @override
  Future<String?> getApplicationDocumentsPath() async {
    return tempDir.path;
  }
}

void main() {
  group('Crash Recovery Integration', () {
    late Directory tempDir;
    late WorkoutSessionPersistence persistence;
    late DeviceManager deviceManager;

    setUp(() async {
      // Create temp directory for file storage
      tempDir = await Directory.systemTemp.createTemp('workout_test_');
      PathProviderPlatform.instance = FakePathProviderPlatform(tempDir);

      // Set up persistence
      final prefs = createTestSharedPreferencesAsync();
      persistence = WorkoutSessionPersistence(prefs: prefs);

      // Set up device manager
      final platform = FakeBlePlatform();
      final scanner = BleScanner(platform: platform, permissions: FakeBlePermissions());
      final transportRegistry = TransportRegistry();
      final devicePersistence = DeviceAssignmentPersistence(prefs);
      deviceManager = DeviceManager(
        platform: platform,
        scanner: scanner,
        transportRegistry: transportRegistry,
        persistence: devicePersistence,
      );
    });

    tearDown(() async {
      await deviceManager.dispose();
      // Clean up temp directory
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('full crash recovery flow - start, crash, resume', () async {
      final plan = WorkoutPlan(
        plan: [
          PowerBlock(id: 'warmup', duration: 60000, power: 0.5),
          PowerBlock(id: 'work', duration: 120000, power: 0.8),
          PowerBlock(id: 'cooldown', duration: 60000, power: 0.4),
        ],
      );

      // === PHASE 1: Start workout and record ===
      final player1 = WorkoutPlayerService(workoutPlan: plan, deviceManager: deviceManager, ftp: 200);

      final recorder1 = WorkoutRecordingService(
        playerService: player1,
        deviceManager: deviceManager,
        persistence: persistence,
      );

      // Start recording
      final sessionId = await recorder1.startRecording('Test Workout', ftp: 200, sourceWorkoutId: 'test-workout');
      expect(sessionId, isNotEmpty);

      // Verify session created
      final activeSession1 = await persistence.getActiveSession();
      expect(activeSession1, isNotNull);
      expect(activeSession1!.id, sessionId);

      // Simulate workout progression
      player1.start();
      await Future.delayed(Duration(milliseconds: 1200)); // Let some samples record

      // Manually update player state to simulate progression to 65 seconds in
      player1.restoreState(elapsedMs: 65000, currentBlockIndex: 1);

      // Update metadata manually to match player state
      final metadata1 = await persistence.loadSessionMetadata(sessionId);
      expect(metadata1, isNotNull);
      await persistence.updateSessionMetadata(
        metadata1!.copyWith(
          elapsedMs: 65000, // 1:05 into workout
          currentBlockIndex: 1, // On second block
        ),
      );

      // Flush samples before "crash"
      await persistence.flushAllSampleBuffers();

      // === PHASE 2: Simulate crash (dispose without completing) ===
      await recorder1.dispose();
      player1.dispose();

      // Session should still be marked as active (crash detected)
      final crashedSession = await persistence.getActiveSession();
      expect(crashedSession, isNotNull);
      expect(crashedSession!.status, SessionStatus.active);
      expect(crashedSession.elapsedMs, 65000);
      expect(crashedSession.currentBlockIndex, 1);

      // === PHASE 3: App restart and resume ===
      final player2 = WorkoutPlayerService(workoutPlan: plan, deviceManager: deviceManager, ftp: 200);

      final recorder2 = WorkoutRecordingService(
        playerService: player2,
        deviceManager: deviceManager,
        persistence: persistence,
      );

      // Restore player state
      player2.restoreState(elapsedMs: crashedSession.elapsedMs, currentBlockIndex: crashedSession.currentBlockIndex);

      // Verify state restored
      expect(player2.elapsedTime$.value, 65000);
      expect(player2.currentBlockIndex$.value, 1);
      expect(player2.isPaused.value, true);

      // Resume recording
      await recorder2.resumeRecording(sessionId: crashedSession.id);
      expect(recorder2.isRecording, true);
      expect(recorder2.sessionId, crashedSession.id);

      // Resume playback
      player2.start();
      expect(player2.isPaused.value, false);

      await Future.delayed(Duration(milliseconds: 100));

      // Time should advance from restored point
      expect(player2.elapsedTime$.value, greaterThan(65000));

      // === PHASE 4: Complete workout normally ===
      await recorder2.stopRecording(completed: true);

      // Session should be marked completed and active flag cleared
      final completedSession = await persistence.getActiveSession();
      expect(completedSession, isNull); // Active flag cleared

      final finalMetadata = await persistence.loadSessionMetadata(sessionId);
      expect(finalMetadata!.status, SessionStatus.completed);

      player2.dispose();
    });

    test('discard session marks as abandoned', () async {
      final plan = WorkoutPlan(plan: [PowerBlock(id: 'b1', duration: 60000, power: 0.5)]);

      // Start workout
      final player = WorkoutPlayerService(workoutPlan: plan, deviceManager: deviceManager, ftp: 200);
      final recorder = WorkoutRecordingService(
        playerService: player,
        deviceManager: deviceManager,
        persistence: persistence,
      );

      final sessionId = await recorder.startRecording('Test', ftp: 200, sourceWorkoutId: 'test-workout');
      player.start();
      await Future.delayed(Duration(milliseconds: 100));

      // Simulate crash
      await recorder.dispose();
      player.dispose();

      // User chooses to discard
      await persistence.updateSessionStatus(sessionId, SessionStatus.abandoned);

      // Verify
      final metadata = await persistence.loadSessionMetadata(sessionId);
      expect(metadata!.status, SessionStatus.abandoned);

      // Active flag should be cleared
      final activeSession = await persistence.getActiveSession();
      expect(activeSession, isNull);
    });

    test('start fresh deletes old session', () async {
      final plan = WorkoutPlan(plan: [PowerBlock(id: 'b1', duration: 60000, power: 0.5)]);

      // Start workout
      final player = WorkoutPlayerService(workoutPlan: plan, deviceManager: deviceManager, ftp: 200);
      final recorder = WorkoutRecordingService(
        playerService: player,
        deviceManager: deviceManager,
        persistence: persistence,
      );

      final sessionId = await recorder.startRecording('Test', ftp: 200, sourceWorkoutId: 'test-workout');
      await recorder.dispose();
      player.dispose();

      // Verify session exists
      expect(await persistence.loadSessionMetadata(sessionId), isNotNull);

      // User chooses start fresh
      await persistence.deleteSession(sessionId);

      // Verify session deleted
      expect(await persistence.loadSessionMetadata(sessionId), isNull);
      expect(await persistence.getActiveSession(), isNull);
    });

    test('samples are recorded during workout', () async {
      final plan = WorkoutPlan(plan: [PowerBlock(id: 'b1', duration: 60000, power: 0.5)]);

      final player = WorkoutPlayerService(workoutPlan: plan, deviceManager: deviceManager, ftp: 200);
      final recorder = WorkoutRecordingService(
        playerService: player,
        deviceManager: deviceManager,
        persistence: persistence,
      );

      final sessionId = await recorder.startRecording('Test', ftp: 200, sourceWorkoutId: 'test-workout');
      player.start();

      // Wait for a few samples to be recorded
      await Future.delayed(Duration(seconds: 3));

      // Flush samples
      await persistence.flushAllSampleBuffers();

      // Load samples
      final samples = await persistence.loadAllSamples(sessionId);

      // Should have at least 2 samples (1Hz recording)
      expect(samples.length, greaterThanOrEqualTo(2));

      // Verify sample structure
      expect(samples.first.powerTarget, 100); // 0.5 * 200 FTP
      expect(samples.first.elapsedMs, greaterThan(0));
      expect(samples.first.timestamp, isNotNull);

      await recorder.stopRecording(completed: true);
      player.dispose();
    });

    test('metadata is updated periodically during recording', () async {
      final plan = WorkoutPlan(
        plan: [
          PowerBlock(id: 'b1', duration: 60000, power: 0.5),
          PowerBlock(id: 'b2', duration: 60000, power: 0.8),
        ],
      );

      final player = WorkoutPlayerService(workoutPlan: plan, deviceManager: deviceManager, ftp: 200);
      final recorder = WorkoutRecordingService(
        playerService: player,
        deviceManager: deviceManager,
        persistence: persistence,
      );

      final sessionId = await recorder.startRecording('Test', ftp: 200, sourceWorkoutId: 'test-workout');
      player.start();

      // Wait for metadata update interval (10 seconds + buffer)
      await Future.delayed(Duration(seconds: 12));

      final metadata = await persistence.loadSessionMetadata(sessionId);
      expect(metadata, isNotNull);
      // Metadata should be updated at least once (more lenient check)
      expect(metadata!.elapsedMs, greaterThan(9000));
      expect(metadata.lastUpdated, isNotNull);

      await recorder.stopRecording(completed: true);
      player.dispose();
    });

    test('session survives player restart without resume', () async {
      final plan = WorkoutPlan(plan: [PowerBlock(id: 'b1', duration: 60000, power: 0.5)]);

      // First session
      final player1 = WorkoutPlayerService(workoutPlan: plan, deviceManager: deviceManager, ftp: 200);
      final recorder1 = WorkoutRecordingService(
        playerService: player1,
        deviceManager: deviceManager,
        persistence: persistence,
      );

      final sessionId = await recorder1.startRecording('Test', ftp: 200, sourceWorkoutId: 'test-workout');
      player1.start();
      await Future.delayed(Duration(milliseconds: 500));
      await recorder1.dispose();
      player1.dispose();

      // Check crash detected
      final crashedSession = await persistence.getActiveSession();
      expect(crashedSession, isNotNull);

      // New player without resume (simulating "Start Fresh")
      await persistence.deleteSession(sessionId);

      final activeAfterDelete = await persistence.getActiveSession();
      expect(activeAfterDelete, isNull);
    });
  });
}
