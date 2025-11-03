import 'package:flutter_test/flutter_test.dart';
import 'package:vekolo/domain/devices/device_manager.dart';
import 'package:vekolo/domain/models/workout/workout_models.dart';
import 'package:vekolo/services/workout_player_service.dart';
import '../ble/fake_ble_platform.dart';
import '../ble/fake_ble_permissions.dart';
import 'package:vekolo/ble/ble_scanner.dart';
import 'package:vekolo/ble/transport_registry.dart';

void main() {
  group('WorkoutPlayerService', () {
    DeviceManager createDeviceManager() {
      final platform = FakeBlePlatform();
      final scanner = BleScanner(platform: platform, permissions: FakeBlePermissions());
      final transportRegistry = TransportRegistry();
      final deviceManager = DeviceManager(
        platform: platform,
        scanner: scanner,
        transportRegistry: transportRegistry,
      );
      addTearDown(() async => await deviceManager.dispose());
      return deviceManager;
    }

    group('Initialization', () {
      test('initializes with correct state', () {
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

      test('initializes with custom power scale factor', () {
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

      test('flattens workout plan correctly', () {
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

    group('Power Target Calculation', () {
      test('calculates power target for power block', () async {
        final deviceManager = createDeviceManager();
        final plan = WorkoutPlan(
          plan: [
            PowerBlock(
              id: 'block1',
              duration: 1000,
              power: 0.8, // 80% FTP
            ),
          ],
        );

        final player = WorkoutPlayerService(workoutPlan: plan, deviceManager: deviceManager, ftp: 200);

        player.start();
        await Future.delayed(Duration(milliseconds: 200));

        // Power should be 0.8 * 200 = 160W
        expect(player.powerTarget$.value, 160);

        player.dispose();
      });

      test('calculates power target with scale factor', () async {
        final deviceManager = createDeviceManager();
        final plan = WorkoutPlan(
          plan: [
            PowerBlock(
              id: 'block1',
              duration: 1000,
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
        await Future.delayed(Duration(milliseconds: 200));

        // Power should be 1.0 * 200 * 1.1 = 220W
        expect(player.powerTarget$.value, 220);

        player.dispose();
      });

      test('interpolates power for ramp block', () async {
        final deviceManager = createDeviceManager();
        final plan = WorkoutPlan(
          plan: [
            RampBlock(
              id: 'ramp1',
              duration: 1000, // 1 second
              powerStart: 0.5, // 50% FTP
              powerEnd: 1.0, // 100% FTP
            ),
          ],
        );

        final player = WorkoutPlayerService(workoutPlan: plan, deviceManager: deviceManager, ftp: 200);

        player.start();

        // At start: should be ~100W (50% of 200)
        await Future.delayed(Duration(milliseconds: 150));
        expect(player.powerTarget$.value, greaterThanOrEqualTo(100));
        expect(player.powerTarget$.value, lessThan(120));

        // At halfway: should be ~150W (75% of 200)
        await Future.delayed(Duration(milliseconds: 400));
        expect(player.powerTarget$.value, greaterThanOrEqualTo(130));
        expect(player.powerTarget$.value, lessThanOrEqualTo(170));

        // Near end: should be approaching 200W (100% of 200)
        await Future.delayed(Duration(milliseconds: 400));
        expect(player.powerTarget$.value, greaterThan(170));

        player.dispose();
      });
    });

    group('Cadence Targets', () {
      test('sets cadence targets for power block', () async {
        final deviceManager = createDeviceManager();
        final plan = WorkoutPlan(
          plan: [PowerBlock(id: 'block1', duration: 1000, power: 0.8, cadence: 90, cadenceLow: 80, cadenceHigh: 100)],
        );

        final player = WorkoutPlayerService(workoutPlan: plan, deviceManager: deviceManager, ftp: 200);

        player.start();
        await Future.delayed(Duration(milliseconds: 200));

        expect(player.cadenceTarget$.value, 90);
        expect(player.cadenceLow$.value, 80);
        expect(player.cadenceHigh$.value, 100);

        player.dispose();
      });

      test('interpolates cadence for ramp block', () async {
        final deviceManager = createDeviceManager();
        final plan = WorkoutPlan(
          plan: [
            RampBlock(id: 'ramp1', duration: 1000, powerStart: 0.5, powerEnd: 1.0, cadenceStart: 80, cadenceEnd: 100),
          ],
        );

        final player = WorkoutPlayerService(workoutPlan: plan, deviceManager: deviceManager, ftp: 200);

        player.start();

        // At start: should be ~80 RPM
        await Future.delayed(Duration(milliseconds: 150));
        final startCadence = player.cadenceTarget$.value;
        expect(startCadence, isNotNull);
        if (startCadence != null) {
          expect(startCadence, greaterThanOrEqualTo(80));
          expect(startCadence, lessThan(90));
        }

        // Near end: should be approaching 100 RPM
        await Future.delayed(Duration(milliseconds: 750));
        final endCadence = player.cadenceTarget$.value;
        expect(endCadence, isNotNull);
        if (endCadence != null) {
          expect(endCadence, greaterThan(90));
        }

        player.dispose();
      });
    });

    group('Timer and State Updates', () {
      test('updates elapsed time during playback', () async {
        final deviceManager = createDeviceManager();
        final plan = WorkoutPlan(plan: [PowerBlock(id: 'block1', duration: 10000, power: 0.8)]);

        final player = WorkoutPlayerService(workoutPlan: plan, deviceManager: deviceManager, ftp: 200);

        expect(player.elapsedTime$.value, 0);

        player.start();
        await Future.delayed(Duration(milliseconds: 500));

        // Should have elapsed at least 300ms (timer ticks every 100ms, so 3+ ticks in 500ms)
        expect(player.elapsedTime$.value, greaterThanOrEqualTo(300));
        expect(player.elapsedTime$.value, lessThan(700));

        player.dispose();
      });

      test('updates remaining time during playback', () async {
        final deviceManager = createDeviceManager();
        final plan = WorkoutPlan(plan: [PowerBlock(id: 'block1', duration: 1000, power: 0.8)]);

        final player = WorkoutPlayerService(workoutPlan: plan, deviceManager: deviceManager, ftp: 200);

        expect(player.remainingTime$.value, 1000);

        player.start();
        await Future.delayed(Duration(milliseconds: 500));

        // Should have ~500ms remaining
        expect(player.remainingTime$.value, lessThan(700));
        expect(player.remainingTime$.value, greaterThanOrEqualTo(300));

        player.dispose();
      });

      test('updates progress during playback', () async {
        final deviceManager = createDeviceManager();
        final plan = WorkoutPlan(plan: [PowerBlock(id: 'block1', duration: 1000, power: 0.8)]);

        final player = WorkoutPlayerService(workoutPlan: plan, deviceManager: deviceManager, ftp: 200);

        expect(player.progress$.value, 0.0);

        player.start();
        await Future.delayed(Duration(milliseconds: 500));

        // Should be roughly 40-60% complete
        expect(player.progress$.value, greaterThan(0.3));
        expect(player.progress$.value, lessThan(0.7));

        player.dispose();
      });
    });

    group('Block Advancement', () {
      test('advances to next block automatically', () async {
        final deviceManager = createDeviceManager();
        final plan = WorkoutPlan(
          plan: [
            PowerBlock(
              id: 'block1',
              duration: 300, // 300ms
              power: 0.5,
            ),
            PowerBlock(id: 'block2', duration: 300, power: 0.8),
          ],
        );

        final player = WorkoutPlayerService(workoutPlan: plan, deviceManager: deviceManager, ftp: 200);

        expect(player.currentBlockIndex$.value, 0);
        expect((player.currentBlock$.value as PowerBlock).id, 'block1');

        player.start();

        // Wait for first block to complete
        await Future.delayed(Duration(milliseconds: 400));

        // Should have advanced to block2
        expect(player.currentBlockIndex$.value, 1);
        expect((player.currentBlock$.value as PowerBlock).id, 'block2');

        player.dispose();
      });

      test('completes workout after last block', () async {
        final deviceManager = createDeviceManager();
        final plan = WorkoutPlan(plan: [PowerBlock(id: 'block1', duration: 300, power: 0.8)]);

        final player = WorkoutPlayerService(workoutPlan: plan, deviceManager: deviceManager, ftp: 200);

        expect(player.isComplete.value, false);

        player.start();

        // Wait for block to complete
        await Future.delayed(Duration(milliseconds: 500));

        // Should be complete and paused
        expect(player.isComplete.value, true);
        expect(player.isPaused.value, true);

        player.dispose();
      });
    });

    group('Pause and Resume', () {
      test('pauses workout', () async {
        final deviceManager = createDeviceManager();
        final plan = WorkoutPlan(plan: [PowerBlock(id: 'block1', duration: 10000, power: 0.8)]);

        final player = WorkoutPlayerService(workoutPlan: plan, deviceManager: deviceManager, ftp: 200);

        player.start();
        await Future.delayed(Duration(milliseconds: 300));

        player.pause();

        final elapsedAtPause = player.elapsedTime$.value;
        expect(player.isPaused.value, true);

        // Wait a bit
        await Future.delayed(Duration(milliseconds: 300));

        // Elapsed time should not have changed
        expect(player.elapsedTime$.value, elapsedAtPause);

        player.dispose();
      });

      test('resumes workout from paused state', () async {
        final deviceManager = createDeviceManager();
        final plan = WorkoutPlan(plan: [PowerBlock(id: 'block1', duration: 10000, power: 0.8)]);

        final player = WorkoutPlayerService(workoutPlan: plan, deviceManager: deviceManager, ftp: 200);

        player.start();
        await Future.delayed(Duration(milliseconds: 300));

        player.pause();
        final elapsedAtPause = player.elapsedTime$.value;

        await Future.delayed(Duration(milliseconds: 300));

        // Resume
        player.start();
        await Future.delayed(Duration(milliseconds: 300));

        // Should have continued from paused point
        expect(player.isPaused.value, false);
        expect(player.elapsedTime$.value, greaterThan(elapsedAtPause));

        player.dispose();
      });
    });

    group('Skip', () {
      test('skips current block', () {
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

      test('skipping last block completes workout', () {
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

    group('Power Scale Factor', () {
      test('adjusts power scale factor', () async {
        final deviceManager = createDeviceManager();
        final plan = WorkoutPlan(plan: [PowerBlock(id: 'block1', duration: 1000, power: 1.0)]);

        final player = WorkoutPlayerService(workoutPlan: plan, deviceManager: deviceManager, ftp: 200);

        player.start();
        await Future.delayed(Duration(milliseconds: 200));

        // Initial power: 1.0 * 200 = 200W
        expect(player.powerTarget$.value, 200);

        // Increase by 10%
        player.setPowerScaleFactor(1.1);
        await Future.delayed(Duration(milliseconds: 200));

        // New power: 1.0 * 200 * 1.1 = 220W
        expect(player.powerTarget$.value, 220);

        // Decrease by 10%
        player.setPowerScaleFactor(0.9);
        await Future.delayed(Duration(milliseconds: 200));

        // New power: 1.0 * 200 * 0.9 = 180W
        expect(player.powerTarget$.value, 180);

        player.dispose();
      });

      test('clamps power scale factor to valid range', () {
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

    group('Complete Early', () {
      test('completes workout early', () async {
        final deviceManager = createDeviceManager();
        final plan = WorkoutPlan(plan: [PowerBlock(id: 'block1', duration: 10000, power: 0.8)]);

        final player = WorkoutPlayerService(workoutPlan: plan, deviceManager: deviceManager, ftp: 200);

        player.start();
        await Future.delayed(Duration(milliseconds: 300));

        expect(player.isComplete.value, false);

        player.completeEarly();

        expect(player.isComplete.value, true);
        expect(player.isPaused.value, true);
        expect(player.elapsedTime$.value, greaterThan(0));
        expect(player.elapsedTime$.value, lessThan(10000));

        player.dispose();
      });
    });

    group('Event Triggering', () {
      test('triggers message events at correct times', () async {
        final deviceManager = createDeviceManager();
        final plan = WorkoutPlan(
          plan: [PowerBlock(id: 'block1', duration: 2000, power: 0.8)],
          events: [
            MessageEvent(
              id: 'msg1',
              parentBlockId: 'block1',
              relativeTimeOffset: 500, // 500ms into block
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

        // Wait for event to trigger
        await Future.delayed(Duration(milliseconds: 700));

        expect(triggeredEvents.length, 1);
        expect(triggeredEvents[0], isA<FlattenedMessageEvent>());
        expect((triggeredEvents[0] as FlattenedMessageEvent).text, 'Push harder!');

        player.dispose();
      });

      test('does not retrigger events', () async {
        final deviceManager = createDeviceManager();
        final plan = WorkoutPlan(
          plan: [PowerBlock(id: 'block1', duration: 2000, power: 0.8)],
          events: [MessageEvent(id: 'msg1', parentBlockId: 'block1', relativeTimeOffset: 100, text: 'Test')],
        );

        final player = WorkoutPlayerService(workoutPlan: plan, deviceManager: deviceManager, ftp: 200);

        final triggeredEvents = <dynamic>[];
        player.triggeredEvent$.listen((event) {
          triggeredEvents.add(event);
        });

        player.start();

        // Wait well past event time
        await Future.delayed(Duration(milliseconds: 1000));

        // Should only trigger once
        expect(triggeredEvents.length, 1);

        player.dispose();
      });

      test('triggers effect events at correct times', () async {
        final deviceManager = createDeviceManager();
        final plan = WorkoutPlan(
          plan: [PowerBlock(id: 'block1', duration: 2000, power: 0.8)],
          events: [
            EffectEvent(id: 'effect1', parentBlockId: 'block1', relativeTimeOffset: 500, effect: EffectType.fireworks),
          ],
        );

        final player = WorkoutPlayerService(workoutPlan: plan, deviceManager: deviceManager, ftp: 200);

        final triggeredEvents = <dynamic>[];
        player.triggeredEvent$.listen((event) {
          triggeredEvents.add(event);
        });

        player.start();

        // Wait for event to trigger
        await Future.delayed(Duration(milliseconds: 700));

        expect(triggeredEvents.length, 1);
        expect(triggeredEvents[0], isA<FlattenedEffectEvent>());
        expect((triggeredEvents[0] as FlattenedEffectEvent).effect, EffectType.fireworks);

        player.dispose();
      });
    });

    group('Edge Cases', () {
      test('handles empty workout plan', () {
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

      test('handles multiple pause/resume cycles', () async {
        final deviceManager = createDeviceManager();
        final plan = WorkoutPlan(plan: [PowerBlock(id: 'block1', duration: 10000, power: 0.8)]);

        final player = WorkoutPlayerService(workoutPlan: plan, deviceManager: deviceManager, ftp: 200);

        // Cycle 1
        player.start();
        await Future.delayed(Duration(milliseconds: 200));
        player.pause();
        final elapsed1 = player.elapsedTime$.value;

        // Cycle 2
        await Future.delayed(Duration(milliseconds: 200));
        player.start();
        await Future.delayed(Duration(milliseconds: 200));
        player.pause();
        final elapsed2 = player.elapsedTime$.value;

        // Cycle 3
        await Future.delayed(Duration(milliseconds: 200));
        player.start();
        await Future.delayed(Duration(milliseconds: 200));
        final elapsed3 = player.elapsedTime$.value;

        // Each cycle should add elapsed time
        expect(elapsed2, greaterThan(elapsed1));
        expect(elapsed3, greaterThan(elapsed2));

        player.dispose();
      });

      test('cannot start completed workout', () async {
        final deviceManager = createDeviceManager();
        final plan = WorkoutPlan(plan: [PowerBlock(id: 'block1', duration: 300, power: 0.8)]);

        final player = WorkoutPlayerService(workoutPlan: plan, deviceManager: deviceManager, ftp: 200);

        player.start();
        await Future.delayed(Duration(milliseconds: 500));

        expect(player.isComplete.value, true);

        // Try to start again
        player.start();

        // Should still be paused and complete
        expect(player.isPaused.value, true);
        expect(player.isComplete.value, true);

        player.dispose();
      });

      test('dispose cleans up resources', () {
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
}
