import 'package:flutter_test/flutter_test.dart';
import 'package:vekolo/domain/devices/device_manager.dart';
import 'package:vekolo/domain/models/workout/workout_models.dart';
import 'package:vekolo/services/device_assignment_persistence.dart';
import 'package:vekolo/services/workout_player_service.dart';
import '../ble/fake_ble_platform.dart';
import '../ble/fake_ble_permissions.dart';
import '../helpers/shared_preferences_helper.dart';
import 'package:vekolo/ble/ble_scanner.dart';
import 'package:vekolo/ble/transport_registry.dart';
import '../robot/my_fake_async.dart';

void main() {
  group('WorkoutPlayerService', () {
    DeviceManager createDeviceManager() {
      final platform = FakeBlePlatform();
      final scanner = BleScanner(platform: platform, permissions: FakeBlePermissions());
      final transportRegistry = TransportRegistry();
      final prefs = createTestSharedPreferencesAsync();
      final persistence = DeviceAssignmentPersistence(prefs);
      final deviceManager = DeviceManager(
        platform: platform,
        scanner: scanner,
        transportRegistry: transportRegistry,
        persistence: persistence,
      );
      addTearDown(() async => await deviceManager.dispose());
      return deviceManager;
    }

    group('Initialization', () {
      test('initializes with correct state', () {
        myFakeAsync((async) {
          final deviceManager = createDeviceManager();
          final plan = WorkoutPlan(plan: [PowerBlock(id: 'block1', duration: 60000, power: 0.8)]);

          final player = WorkoutPlayerService(workoutPlan: plan, deviceManager: deviceManager, ftp: 200);

          expect(player.isPaused.value, true);
          expect(player.isComplete.value, false);
          expect(player.currentBlock$.value, isA<PowerBlock>());
          expect(player.nextBlock$.value, null);
          expect(player.currentBlockIndex$.value, 0);
          expect(player.powerTarget$.value, 0);
          expect(player.progress$.value, 0.0);
          expect(player.remainingTime$.value, 60000);
          expect(player.elapsedTime$.value, 0);
          expect(player.powerScaleFactor.value, 1.0);

          player.dispose();
        });
      });

      test('initializes with custom power scale factor', () {
        myFakeAsync((async) {
          final deviceManager = createDeviceManager();
          final plan = WorkoutPlan(plan: [PowerBlock(id: 'block1', duration: 60000, power: 1.0)]);

          final player = WorkoutPlayerService(
            workoutPlan: plan,
            deviceManager: deviceManager,
            ftp: 200,
            powerScaleFactor: 1.1,
          );

          expect(player.powerScaleFactor.value, 1.1);

          player.dispose();
        });
      });

      test('flattens workout plan correctly', () {
        myFakeAsync((async) {
          final deviceManager = createDeviceManager();
          final plan = WorkoutPlan(
            plan: [
              PowerBlock(id: 'warmup', duration: 30000, power: 0.5),
              WorkoutInterval(
                id: 'intervals',
                repeat: 2,
                parts: [
                  PowerBlock(id: 'work', duration: 10000, power: 1.2),
                  PowerBlock(id: 'rest', duration: 10000, power: 0.6),
                ],
              ),
              PowerBlock(id: 'cooldown', duration: 30000, power: 0.5),
            ],
          );

          final player = WorkoutPlayerService(workoutPlan: plan, deviceManager: deviceManager, ftp: 200);

          // Should be: warmup, work1, rest1, work2, rest2, cooldown = 6 blocks
          // Total duration: 30 + 10 + 10 + 10 + 10 + 30 = 100 seconds
          expect(player.remainingTime$.value, 100000);

          player.dispose();
        });
      });
    });

    group('Power Target Calculation', () {
      test('calculates power target for power block', () {
        myFakeAsync((async) {
          final deviceManager = createDeviceManager();
          final plan = WorkoutPlan(
            plan: [
              PowerBlock(
                id: 'block1',
                duration: 10000,
                power: 0.8, // 80% FTP
              ),
            ],
          );

          final player = WorkoutPlayerService(workoutPlan: plan, deviceManager: deviceManager, ftp: 200);

          player.start();
          // start() calls _tick() immediately, so powerTarget should be set

          // Power should be 0.8 * 200 = 160W
          expect(player.powerTarget$.value, 160);

          player.dispose();
        });
      });

      test('calculates power target with scale factor', () {
        myFakeAsync((async) {
          final deviceManager = createDeviceManager();
          final plan = WorkoutPlan(
            plan: [
              PowerBlock(
                id: 'block1',
                duration: 10000,
                power: 1.0, // 100% FTP
              ),
            ],
          );

          final player = WorkoutPlayerService(
            workoutPlan: plan,
            deviceManager: deviceManager,
            ftp: 200,
            powerScaleFactor: 1.1, // +10%
          );

          player.start();
          // start() calls _tick() immediately

          // Power should be 1.0 * 200 * 1.1 = 220W
          expect(player.powerTarget$.value, 220);

          player.dispose();
        });
      });

      test('interpolates power for ramp block', () {
        myFakeAsync((async) {
          final deviceManager = createDeviceManager();
          final plan = WorkoutPlan(
            plan: [
              RampBlock(
                id: 'ramp1',
                duration: 10000, // 10 seconds
                powerStart: 0.5, // 50% FTP
                powerEnd: 1.0, // 100% FTP
              ),
            ],
          );

          final player = WorkoutPlayerService(workoutPlan: plan, deviceManager: deviceManager, ftp: 200);

          player.start();

          // At start: should be 100W (50% of 200)
          expect(player.powerTarget$.value, 100);

          // At halfway (5 seconds): should be ~150W (75% of 200)
          async.elapse(Duration(seconds: 5));
          expect(player.powerTarget$.value, closeTo(150, 5));

          // Near end (9 seconds): should be approaching 200W (100% of 200)
          async.elapse(Duration(seconds: 4));
          expect(player.powerTarget$.value, closeTo(190, 10));

          player.dispose();
        });
      });
    });

    group('Cadence Targets', () {
      test('sets cadence targets for power block', () {
        myFakeAsync((async) {
          final deviceManager = createDeviceManager();
          final plan = WorkoutPlan(
            plan: [PowerBlock(id: 'block1', duration: 10000, power: 0.8, cadence: 90, cadenceLow: 80, cadenceHigh: 100)],
          );

          final player = WorkoutPlayerService(workoutPlan: plan, deviceManager: deviceManager, ftp: 200);

          player.start();
          // start() calls _tick() immediately

          expect(player.cadenceTarget$.value, 90);
          expect(player.cadenceLow$.value, 80);
          expect(player.cadenceHigh$.value, 100);

          player.dispose();
        });
      });

      test('interpolates cadence for ramp block', () {
        myFakeAsync((async) {
          final deviceManager = createDeviceManager();
          final plan = WorkoutPlan(
            plan: [
              RampBlock(id: 'ramp1', duration: 10000, powerStart: 0.5, powerEnd: 1.0, cadenceStart: 80, cadenceEnd: 100),
            ],
          );

          final player = WorkoutPlayerService(workoutPlan: plan, deviceManager: deviceManager, ftp: 200);

          player.start();

          // At start: should be 80 RPM
          expect(player.cadenceTarget$.value, 80);

          // Near end (9 seconds): should be approaching 100 RPM
          async.elapse(Duration(seconds: 9));
          final endCadence = player.cadenceTarget$.value;
          expect(endCadence, isNotNull);
          expect(endCadence, greaterThan(95));

          player.dispose();
        });
      });
    });

    group('Timer and State Updates', () {
      test('updates elapsed time during playback', () {
        myFakeAsync((async) {
          final deviceManager = createDeviceManager();
          final plan = WorkoutPlan(plan: [PowerBlock(id: 'block1', duration: 10000, power: 0.8)]);

          final player = WorkoutPlayerService(workoutPlan: plan, deviceManager: deviceManager, ftp: 200);

          expect(player.elapsedTime$.value, 0);

          player.start();
          async.elapse(Duration(seconds: 3));

          // Should have elapsed 3 seconds
          expect(player.elapsedTime$.value, 3000);

          player.dispose();
        });
      });

      test('updates remaining time during playback', () {
        myFakeAsync((async) {
          final deviceManager = createDeviceManager();
          final plan = WorkoutPlan(plan: [PowerBlock(id: 'block1', duration: 10000, power: 0.8)]);

          final player = WorkoutPlayerService(workoutPlan: plan, deviceManager: deviceManager, ftp: 200);

          expect(player.remainingTime$.value, 10000);

          player.start();
          async.elapse(Duration(seconds: 5));

          // Should have 5 seconds remaining
          expect(player.remainingTime$.value, 5000);

          player.dispose();
        });
      });

      test('updates progress during playback', () {
        myFakeAsync((async) {
          final deviceManager = createDeviceManager();
          final plan = WorkoutPlan(plan: [PowerBlock(id: 'block1', duration: 10000, power: 0.8)]);

          final player = WorkoutPlayerService(workoutPlan: plan, deviceManager: deviceManager, ftp: 200);

          expect(player.progress$.value, 0.0);

          player.start();
          async.elapse(Duration(seconds: 5));

          // Should be 50% complete
          expect(player.progress$.value, 0.5);

          player.dispose();
        });
      });
    });

    group('Block Advancement', () {
      test('advances to next block automatically', () {
        myFakeAsync((async) {
          final deviceManager = createDeviceManager();
          final plan = WorkoutPlan(
            plan: [
              PowerBlock(
                id: 'block1',
                duration: 3000, // 3 seconds
                power: 0.5,
              ),
              PowerBlock(id: 'block2', duration: 3000, power: 0.8),
            ],
          );

          final player = WorkoutPlayerService(workoutPlan: plan, deviceManager: deviceManager, ftp: 200);

          expect(player.currentBlockIndex$.value, 0);
          expect((player.currentBlock$.value as PowerBlock).id, 'block1');

          player.start();

          // Elapse past first block
          async.elapse(Duration(seconds: 4));

          // Should have advanced to block2
          expect(player.currentBlockIndex$.value, 1);
          expect((player.currentBlock$.value as PowerBlock).id, 'block2');

          player.dispose();
        });
      });

      test('completes workout after last block', () {
        myFakeAsync((async) {
          final deviceManager = createDeviceManager();
          final plan = WorkoutPlan(plan: [PowerBlock(id: 'block1', duration: 3000, power: 0.8)]);

          final player = WorkoutPlayerService(workoutPlan: plan, deviceManager: deviceManager, ftp: 200);

          expect(player.isComplete.value, false);

          player.start();

          // Elapse past the block
          async.elapse(Duration(seconds: 4));

          // Should be complete and paused
          expect(player.isComplete.value, true);
          expect(player.isPaused.value, true);

          player.dispose();
        });
      });
    });

    group('Pause and Resume', () {
      test('pauses workout', () {
        myFakeAsync((async) {
          final deviceManager = createDeviceManager();
          final plan = WorkoutPlan(plan: [PowerBlock(id: 'block1', duration: 60000, power: 0.8)]);

          final player = WorkoutPlayerService(workoutPlan: plan, deviceManager: deviceManager, ftp: 200);

          player.start();
          async.elapse(Duration(seconds: 3));

          player.pause();

          final elapsedAtPause = player.elapsedTime$.value;
          expect(player.isPaused.value, true);
          expect(elapsedAtPause, 3000);

          // Wait a bit while paused
          async.elapse(Duration(seconds: 5));

          // Elapsed time should not have changed
          expect(player.elapsedTime$.value, elapsedAtPause);

          player.dispose();
        });
      });

      test('resumes workout from paused state', () {
        myFakeAsync((async) {
          final deviceManager = createDeviceManager();
          final plan = WorkoutPlan(plan: [PowerBlock(id: 'block1', duration: 60000, power: 0.8)]);

          final player = WorkoutPlayerService(workoutPlan: plan, deviceManager: deviceManager, ftp: 200);

          player.start();
          async.elapse(Duration(seconds: 3));

          player.pause();
          final elapsedAtPause = player.elapsedTime$.value;
          expect(elapsedAtPause, 3000);

          async.elapse(Duration(seconds: 5));

          // Resume
          player.start();
          async.elapse(Duration(seconds: 2));

          // Should have continued from paused point
          expect(player.isPaused.value, false);
          expect(player.elapsedTime$.value, 5000); // 3 + 2

          player.dispose();
        });
      });
    });

    group('Skip', () {
      test('skips current block', () {
        myFakeAsync((async) {
          final deviceManager = createDeviceManager();
          final plan = WorkoutPlan(
            plan: [
              PowerBlock(id: 'block1', duration: 60000, power: 0.5),
              PowerBlock(id: 'block2', duration: 60000, power: 0.8),
            ],
          );

          final player = WorkoutPlayerService(workoutPlan: plan, deviceManager: deviceManager, ftp: 200);

          expect(player.currentBlockIndex$.value, 0);
          expect((player.currentBlock$.value as PowerBlock).id, 'block1');

          player.skip();

          expect(player.currentBlockIndex$.value, 1);
          expect((player.currentBlock$.value as PowerBlock).id, 'block2');
          expect(player.elapsedTime$.value, 60000); // Should have added block1's duration

          player.dispose();
        });
      });

      test('skipping last block completes workout', () {
        myFakeAsync((async) {
          final deviceManager = createDeviceManager();
          final plan = WorkoutPlan(plan: [PowerBlock(id: 'block1', duration: 60000, power: 0.8)]);

          final player = WorkoutPlayerService(workoutPlan: plan, deviceManager: deviceManager, ftp: 200);

          expect(player.isComplete.value, false);

          player.skip();

          expect(player.isComplete.value, true);
          expect(player.isPaused.value, true);

          player.dispose();
        });
      });
    });

    group('Power Scale Factor', () {
      test('adjusts power scale factor', () {
        myFakeAsync((async) {
          final deviceManager = createDeviceManager();
          final plan = WorkoutPlan(plan: [PowerBlock(id: 'block1', duration: 60000, power: 1.0)]);

          final player = WorkoutPlayerService(workoutPlan: plan, deviceManager: deviceManager, ftp: 200);

          player.start();

          // Initial power: 1.0 * 200 = 200W
          expect(player.powerTarget$.value, 200);

          // Increase by 10%
          player.setPowerScaleFactor(1.1);
          async.elapse(Duration(seconds: 1)); // Trigger a tick to update power

          // New power: 1.0 * 200 * 1.1 = 220W
          expect(player.powerTarget$.value, 220);

          // Decrease by 10%
          player.setPowerScaleFactor(0.9);
          async.elapse(Duration(seconds: 1)); // Trigger a tick to update power

          // New power: 1.0 * 200 * 0.9 = 180W
          expect(player.powerTarget$.value, 180);

          player.dispose();
        });
      });

      test('clamps power scale factor to valid range', () {
        myFakeAsync((async) {
          final deviceManager = createDeviceManager();
          final plan = WorkoutPlan(plan: [PowerBlock(id: 'block1', duration: 60000, power: 1.0)]);

          final player = WorkoutPlayerService(workoutPlan: plan, deviceManager: deviceManager, ftp: 200);

          // Try to set too low
          player.setPowerScaleFactor(0.05);
          expect(player.powerScaleFactor.value, 0.1);

          // Try to set too high
          player.setPowerScaleFactor(10.0);
          expect(player.powerScaleFactor.value, 5.0);

          player.dispose();
        });
      });
    });

    group('Complete Early', () {
      test('completes workout early', () {
        myFakeAsync((async) {
          final deviceManager = createDeviceManager();
          final plan = WorkoutPlan(plan: [PowerBlock(id: 'block1', duration: 60000, power: 0.8)]);

          final player = WorkoutPlayerService(workoutPlan: plan, deviceManager: deviceManager, ftp: 200);

          player.start();
          async.elapse(Duration(seconds: 3));

          expect(player.isComplete.value, false);

          player.completeEarly();

          expect(player.isComplete.value, true);
          expect(player.isPaused.value, true);
          expect(player.elapsedTime$.value, 3000);

          player.dispose();
        });
      });
    });

    group('Event Triggering', () {
      test('triggers message events at correct times', () async {
        // This test uses real async because the stream controller
        // schedules listeners via microtasks
        final deviceManager = createDeviceManager();
        final plan = WorkoutPlan(
          plan: [PowerBlock(id: 'block1', duration: 60000, power: 0.8)],
          events: [
            MessageEvent(
              id: 'msg1',
              parentBlockId: 'block1',
              relativeTimeOffset: 0, // Trigger immediately when started
              text: 'Push harder!',
            ),
          ],
        );

        final player = WorkoutPlayerService(workoutPlan: plan, deviceManager: deviceManager, ftp: 200);

        final triggeredEvents = <dynamic>[];
        player.triggeredEvent$.listen((event) {
          triggeredEvents.add(event);
        });

        player.start();

        // Wait for stream to deliver event
        await Future.delayed(Duration.zero);
        await Future.delayed(Duration.zero);

        expect(triggeredEvents.length, 1);
        expect(triggeredEvents[0], isA<FlattenedMessageEvent>());
        expect((triggeredEvents[0] as FlattenedMessageEvent).text, 'Push harder!');

        player.dispose();
      });

      test('does not retrigger events', () async {
        final deviceManager = createDeviceManager();
        final plan = WorkoutPlan(
          plan: [PowerBlock(id: 'block1', duration: 60000, power: 0.8)],
          events: [MessageEvent(id: 'msg1', parentBlockId: 'block1', relativeTimeOffset: 0, text: 'Test')],
        );

        final player = WorkoutPlayerService(workoutPlan: plan, deviceManager: deviceManager, ftp: 200);

        final triggeredEvents = <dynamic>[];
        player.triggeredEvent$.listen((event) {
          triggeredEvents.add(event);
        });

        player.start();
        await Future.delayed(Duration.zero);
        await Future.delayed(Duration.zero);

        final countAfterStart = triggeredEvents.length;
        expect(countAfterStart, 1);

        // Manually trigger another tick (simulate time passage)
        // Since the event was already triggered, it should not re-trigger
        player.pause();
        player.start();
        await Future.delayed(Duration.zero);
        await Future.delayed(Duration.zero);

        // Should still only have 1 event
        expect(triggeredEvents.length, 1);

        player.dispose();
      });

      test('triggers effect events at correct times', () async {
        final deviceManager = createDeviceManager();
        final plan = WorkoutPlan(
          plan: [PowerBlock(id: 'block1', duration: 60000, power: 0.8)],
          events: [
            EffectEvent(id: 'effect1', parentBlockId: 'block1', relativeTimeOffset: 0, effect: EffectType.fireworks),
          ],
        );

        final player = WorkoutPlayerService(workoutPlan: plan, deviceManager: deviceManager, ftp: 200);

        final triggeredEvents = <dynamic>[];
        player.triggeredEvent$.listen((event) {
          triggeredEvents.add(event);
        });

        player.start();
        await Future.delayed(Duration.zero);
        await Future.delayed(Duration.zero);

        expect(triggeredEvents.length, 1);
        expect(triggeredEvents[0], isA<FlattenedEffectEvent>());
        expect((triggeredEvents[0] as FlattenedEffectEvent).effect, EffectType.fireworks);

        player.dispose();
      });
    });

    group('Edge Cases', () {
      test('handles empty workout plan', () {
        myFakeAsync((async) {
          final deviceManager = createDeviceManager();
          final plan = WorkoutPlan(plan: []);

          final player = WorkoutPlayerService(workoutPlan: plan, deviceManager: deviceManager, ftp: 200);

          expect(player.currentBlock$.value, null);
          expect(player.remainingTime$.value, 0);
          expect(player.progress$.value, 0.0);

          // Should not start
          player.start();
          expect(player.isPaused.value, true);

          player.dispose();
        });
      });

      test('handles multiple pause/resume cycles', () {
        myFakeAsync((async) {
          final deviceManager = createDeviceManager();
          final plan = WorkoutPlan(plan: [PowerBlock(id: 'block1', duration: 60000, power: 0.8)]);

          final player = WorkoutPlayerService(workoutPlan: plan, deviceManager: deviceManager, ftp: 200);

          // Cycle 1
          player.start();
          async.elapse(Duration(seconds: 3));
          player.pause();
          final elapsed1 = player.elapsedTime$.value;
          expect(elapsed1, 3000);

          // Cycle 2 - wait while paused, then resume
          async.elapse(Duration(seconds: 5));
          player.start();
          async.elapse(Duration(seconds: 3));
          player.pause();
          final elapsed2 = player.elapsedTime$.value;
          expect(elapsed2, 6000); // 3 + 3

          // Cycle 3 - wait while paused, then resume
          async.elapse(Duration(seconds: 5));
          player.start();
          async.elapse(Duration(seconds: 3));
          final elapsed3 = player.elapsedTime$.value;
          expect(elapsed3, 9000); // 3 + 3 + 3

          // Each cycle should add elapsed time
          expect(elapsed2, greaterThan(elapsed1));
          expect(elapsed3, greaterThan(elapsed2));

          player.dispose();
        });
      });

      test('cannot start completed workout', () {
        myFakeAsync((async) {
          final deviceManager = createDeviceManager();
          final plan = WorkoutPlan(plan: [PowerBlock(id: 'block1', duration: 3000, power: 0.8)]);

          final player = WorkoutPlayerService(workoutPlan: plan, deviceManager: deviceManager, ftp: 200);

          player.start();
          async.elapse(Duration(seconds: 5));

          expect(player.isComplete.value, true);

          // Try to start again
          player.start();

          // Should still be paused and complete
          expect(player.isPaused.value, true);
          expect(player.isComplete.value, true);

          player.dispose();
        });
      });

      test('dispose cleans up resources', () {
        myFakeAsync((async) {
          final deviceManager = createDeviceManager();
          final plan = WorkoutPlan(plan: [PowerBlock(id: 'block1', duration: 60000, power: 0.8)]);

          final player = WorkoutPlayerService(workoutPlan: plan, deviceManager: deviceManager, ftp: 200);

          player.start();
          player.dispose();

          // Should not throw when accessing beacons after dispose
          // (beacons are disposed, but reading final value should be safe)
          expect(() => player.isPaused.value, returnsNormally);
        });
      });
    });

    group('State Restoration (Crash Recovery)', () {
      test('restoreState restores elapsed time and block index', () {
        myFakeAsync((async) {
          final deviceManager = createDeviceManager();
          final plan = WorkoutPlan(
            plan: [
              PowerBlock(id: 'warmup', duration: 60000, power: 0.5),
              PowerBlock(id: 'work', duration: 120000, power: 0.8),
              PowerBlock(id: 'cooldown', duration: 60000, power: 0.4),
            ],
          );

          final player = WorkoutPlayerService(workoutPlan: plan, deviceManager: deviceManager, ftp: 200);

          // Restore to 2 minutes in, on block 1 (the work block)
          player.restoreState(elapsedMs: 120000, currentBlockIndex: 1);

          expect(player.elapsedTime$.value, 120000);
          expect(player.currentBlockIndex$.value, 1);
          expect(player.isPaused.value, true); // Should stay paused after restore
          expect((player.currentBlock$.value as PowerBlock).id, 'work');
          expect(player.remainingTime$.value, 240000 - 120000); // Total 240s - 120s elapsed

          player.dispose();
        });
      });

      test('restoreState updates progress and remaining time', () {
        myFakeAsync((async) {
          final deviceManager = createDeviceManager();
          final plan = WorkoutPlan(
            plan: [
              PowerBlock(id: 'block1', duration: 100000, power: 0.5),
              PowerBlock(id: 'block2', duration: 100000, power: 0.8),
            ],
          );

          final player = WorkoutPlayerService(workoutPlan: plan, deviceManager: deviceManager, ftp: 200);

          // Restore to halfway through
          player.restoreState(elapsedMs: 100000, currentBlockIndex: 1);

          expect(player.progress$.value, closeTo(0.5, 0.01)); // 50% through workout
          expect(player.remainingTime$.value, 100000); // 100s remaining

          player.dispose();
        });
      });

      test('restoreState clamps invalid block index', () {
        myFakeAsync((async) {
          final deviceManager = createDeviceManager();
          final plan = WorkoutPlan(
            plan: [
              PowerBlock(id: 'block1', duration: 60000, power: 0.5),
              PowerBlock(id: 'block2', duration: 60000, power: 0.8),
            ],
          );

          final player = WorkoutPlayerService(workoutPlan: plan, deviceManager: deviceManager, ftp: 200);

          // Try to restore to invalid block index
          player.restoreState(elapsedMs: 120000, currentBlockIndex: 10);

          expect(player.currentBlockIndex$.value, 1); // Clamped to last valid block
          expect(player.currentBlock$.value, isNotNull);

          player.dispose();
        });
      });

      test('restoreState allows workout to be resumed with start()', () {
        myFakeAsync((async) {
          final deviceManager = createDeviceManager();
          final plan = WorkoutPlan(
            plan: [
              PowerBlock(id: 'block1', duration: 60000, power: 0.5),
              PowerBlock(id: 'block2', duration: 60000, power: 0.8),
            ],
          );

          final player = WorkoutPlayerService(workoutPlan: plan, deviceManager: deviceManager, ftp: 200);

          // Restore state
          player.restoreState(elapsedMs: 30000, currentBlockIndex: 0);

          expect(player.isPaused.value, true);

          // Should be able to resume
          player.start();
          expect(player.isPaused.value, false);

          async.elapse(Duration(seconds: 3));

          // Time should advance from restored position
          expect(player.elapsedTime$.value, 33000); // 30000 + 3000

          player.dispose();
        });
      });

      test('restoreState with zero elapsed time starts from beginning', () {
        myFakeAsync((async) {
          final deviceManager = createDeviceManager();
          final plan = WorkoutPlan(plan: [PowerBlock(id: 'block1', duration: 60000, power: 0.5)]);

          final player = WorkoutPlayerService(workoutPlan: plan, deviceManager: deviceManager, ftp: 200);

          player.restoreState(elapsedMs: 0, currentBlockIndex: 0);

          expect(player.elapsedTime$.value, 0);
          expect(player.currentBlockIndex$.value, 0);
          expect(player.remainingTime$.value, 60000);

          player.dispose();
        });
      });
    });
  });
}
