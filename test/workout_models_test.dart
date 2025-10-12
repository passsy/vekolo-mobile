import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:vekolo/domain/models/workout/workout_models.dart';
import 'package:vekolo/domain/models/workout/workout_utils.dart';

void main() {
  group('WorkoutModels JSON serialization', () {
    test('PowerBlock roundtrip', () {
      final block = PowerBlock(
        id: 'abc12345',
        duration: 300000,
        power: 0.85,
        description: 'Steady state',
        cadence: 90,
      );

      final json = block.toJson();
      final restored = PowerBlock.fromJson(json);

      expect(restored.id, block.id);
      expect(restored.duration, block.duration);
      expect(restored.power, block.power);
      expect(restored.description, block.description);
      expect(restored.cadence, block.cadence);
      expect(restored, equals(block));
    });

    test('RampBlock roundtrip', () {
      final block = RampBlock(
        id: 'xyz98765',
        duration: 600000,
        powerStart: 0.6,
        powerEnd: 0.9,
        description: 'Warm up',
        cadenceStart: 80,
        cadenceEnd: 95,
      );

      final json = block.toJson();
      final restored = RampBlock.fromJson(json);

      expect(restored.id, block.id);
      expect(restored.duration, block.duration);
      expect(restored.powerStart, block.powerStart);
      expect(restored.powerEnd, block.powerEnd);
      expect(restored.description, block.description);
      expect(restored, equals(block));
    });

    test('WorkoutInterval roundtrip', () {
      final interval = WorkoutInterval(
        id: 'int12345',
        repeat: 3,
        description: 'VO2max intervals',
        parts: [
          PowerBlock(
            id: 'work1234',
            duration: 180000,
            power: 1.05,
            description: 'Work',
          ),
          PowerBlock(
            id: 'rest1234',
            duration: 120000,
            power: 0.6,
            description: 'Recovery',
          ),
        ],
      );

      final json = interval.toJson();
      final restored = WorkoutInterval.fromJson(json);

      expect(restored.id, interval.id);
      expect(restored.repeat, interval.repeat);
      expect(restored.description, interval.description);
      expect(restored.parts.length, 2);
      expect((restored.parts[0] as PowerBlock).power, 1.05);
      expect(restored, equals(interval));
    });

    test('MessageEvent roundtrip', () {
      final event = MessageEvent(
        id: 'msg12345',
        parentBlockId: 'block123',
        relativeTimeOffset: 30000,
        text: 'Push harder!',
        duration: 5000,
      );

      final json = event.toJson();
      final restored = MessageEvent.fromJson(json);

      expect(restored.id, event.id);
      expect(restored.parentBlockId, event.parentBlockId);
      expect(restored.relativeTimeOffset, event.relativeTimeOffset);
      expect(restored.text, event.text);
      expect(restored.duration, event.duration);
      expect(restored, equals(event));
    });

    test('EffectEvent roundtrip', () {
      final event = EffectEvent(
        id: 'eff12345',
        parentBlockId: 'block456',
        relativeTimeOffset: 60000,
        effect: EffectType.fireworks,
      );

      final json = event.toJson();
      final restored = EffectEvent.fromJson(json);

      expect(restored.id, event.id);
      expect(restored.parentBlockId, event.parentBlockId);
      expect(restored.relativeTimeOffset, event.relativeTimeOffset);
      expect(restored.effect, event.effect);
      expect(restored, equals(event));
    });

    test('WorkoutPlan roundtrip', () {
      final plan = WorkoutPlan(
        plan: [
          RampBlock(
            id: 'warmup01',
            duration: 300000,
            powerStart: 0.5,
            powerEnd: 0.75,
            description: 'Warm up',
          ),
          WorkoutInterval(
            id: 'int12345',
            repeat: 2,
            description: 'Intervals',
            parts: [
              PowerBlock(
                id: 'work1234',
                duration: 120000,
                power: 1.0,
                cadence: 95,
              ),
              PowerBlock(
                id: 'rest1234',
                duration: 60000,
                power: 0.6,
              ),
            ],
          ),
          RampBlock(
            id: 'cooldown',
            duration: 300000,
            powerStart: 0.7,
            powerEnd: 0.5,
            description: 'Cool down',
          ),
        ],
        events: [
          MessageEvent(
            id: 'msg00001',
            parentBlockId: 'warmup01',
            relativeTimeOffset: 60000,
            text: 'Get ready!',
          ),
          EffectEvent(
            id: 'eff00001',
            parentBlockId: 'cooldown',
            relativeTimeOffset: 290000,
            effect: EffectType.fireworks,
          ),
        ],
      );

      final json = plan.toJson();
      final restored = WorkoutPlan.fromJson(json);

      expect(restored.plan.length, 3);
      expect(restored.events.length, 2);
      expect((restored.plan[0] as RampBlock).id, 'warmup01');
      expect((restored.plan[1] as WorkoutInterval).repeat, 2);
      expect((restored.events[0] as MessageEvent).text, 'Get ready!');
    });

    test('Complete JSON string roundtrip', () {
      final workout = WorkoutPlan(
        plan: [
          PowerBlock(
            id: 'block001',
            duration: 300000,
            power: 0.8,
            description: 'Steady',
            cadence: 90,
          ),
        ],
        events: [
          MessageEvent(
            id: 'msg00001',
            parentBlockId: 'block001',
            relativeTimeOffset: 150000,
            text: 'Halfway there!',
          ),
        ],
      );

      // Convert to JSON string
      final jsonString = jsonEncode(workout.toJson());

      // Parse back from JSON string
      final parsed = jsonDecode(jsonString) as Map<String, dynamic>;
      final restored = WorkoutPlan.fromJson(parsed);

      expect(restored.plan.length, 1);
      expect(restored.events.length, 1);
      expect((restored.plan[0] as PowerBlock).power, 0.8);
      expect((restored.events[0] as MessageEvent).text, 'Halfway there!');
    });
  });

  group('WorkoutUtils', () {
    test('flattenWorkoutPlan expands intervals', () {
      final plan = [
        PowerBlock(
          id: 'warmup01',
          duration: 300000,
          power: 0.6,
        ),
        WorkoutInterval(
          id: 'int12345',
          repeat: 3,
          parts: [
            PowerBlock(id: 'work1234', duration: 60000, power: 1.0),
            PowerBlock(id: 'rest1234', duration: 60000, power: 0.5),
          ],
        ),
      ];

      final flattened = flattenWorkoutPlan(plan);

      // Should have 1 warmup + (2 parts × 3 repeats) = 7 blocks
      expect(flattened.length, 7);
      expect((flattened[0] as PowerBlock).id, 'warmup01');
      expect((flattened[1] as PowerBlock).power, 1.0);
      expect((flattened[2] as PowerBlock).power, 0.5);
    });

    test('flattenWorkoutPlan applies power scale factor', () {
      final plan = [
        PowerBlock(id: 'block1', duration: 60000, power: 1.0),
        RampBlock(
          id: 'block2',
          duration: 60000,
          powerStart: 0.8,
          powerEnd: 1.0,
        ),
      ];

      final flattened = flattenWorkoutPlan(plan, powerScaleFactor: 0.9);

      expect((flattened[0] as PowerBlock).power, closeTo(0.9, 0.001));
      expect((flattened[1] as RampBlock).powerStart, closeTo(0.72, 0.001));
      expect((flattened[1] as RampBlock).powerEnd, closeTo(0.9, 0.001));
    });

    test('calculateTotalDuration sums all blocks', () {
      final plan = [
        PowerBlock(id: 'block1', duration: 300000, power: 0.6),
        WorkoutInterval(
          id: 'int1',
          repeat: 2,
          parts: [
            PowerBlock(id: 'work1', duration: 120000, power: 1.0),
            PowerBlock(id: 'rest1', duration: 60000, power: 0.5),
          ],
        ),
      ];

      final duration = calculateTotalDuration(plan);

      // 300000 + (120000 + 60000) × 2 = 660000
      expect(duration, 660000);
    });

    test('flattenWorkoutEvents converts to absolute time', () {
      final plan = [
        PowerBlock(id: 'block1', duration: 300000, power: 0.6),
        PowerBlock(id: 'block2', duration: 180000, power: 0.8),
        PowerBlock(id: 'block3', duration: 120000, power: 0.5),
      ];

      final events = [
        MessageEvent(
          id: 'msg1',
          parentBlockId: 'block1',
          relativeTimeOffset: 60000,
          text: 'First message',
        ),
        MessageEvent(
          id: 'msg2',
          parentBlockId: 'block2',
          relativeTimeOffset: 90000,
          text: 'Second message',
        ),
      ];

      final flattened = flattenWorkoutEvents(plan, events);

      expect(flattened.length, 2);
      // First event: block1 starts at 0, offset 60000 = 60000
      expect((flattened[0] as FlattenedMessageEvent).timeOffset, 60000);
      // Second event: block2 starts at 300000, offset 90000 = 390000
      expect((flattened[1] as FlattenedMessageEvent).timeOffset, 390000);
    });

    test('calculatePowerAtTime for PowerBlock', () {
      final block = PowerBlock(id: 'test', duration: 60000, power: 0.85);

      expect(calculatePowerAtTime(block, 0), 0.85);
      expect(calculatePowerAtTime(block, 30000), 0.85);
      expect(calculatePowerAtTime(block, 60000), 0.85);
    });

    test('calculatePowerAtTime for RampBlock', () {
      final block = RampBlock(
        id: 'test',
        duration: 60000,
        powerStart: 0.6,
        powerEnd: 1.0,
      );

      expect(calculatePowerAtTime(block, 0), closeTo(0.6, 0.001));
      expect(calculatePowerAtTime(block, 30000), closeTo(0.8, 0.001));
      expect(calculatePowerAtTime(block, 60000), closeTo(1.0, 0.001));
    });

    test('mapAbsoluteTimeToBlockRelative', () {
      final plan = [
        PowerBlock(id: 'block1', duration: 300000, power: 0.6),
        PowerBlock(id: 'block2', duration: 180000, power: 0.8),
      ];

      final pos1 = mapAbsoluteTimeToBlockRelative(plan, 150000);
      expect(pos1?.blockId, 'block1');
      expect(pos1?.offset, 150000);

      final pos2 = mapAbsoluteTimeToBlockRelative(plan, 350000);
      expect(pos2?.blockId, 'block2');
      expect(pos2?.offset, closeTo(50000, 100)); // Rounded to 100ms

      final pos3 = mapAbsoluteTimeToBlockRelative(plan, 500000);
      expect(pos3, isNull); // Beyond workout duration
    });

    test('calculatePowerStats', () {
      final plan = [
        PowerBlock(id: 'block1', duration: 60000, power: 0.6),
        RampBlock(
          id: 'block2',
          duration: 60000,
          powerStart: 0.5,
          powerEnd: 1.2,
        ),
        WorkoutInterval(
          id: 'int1',
          repeat: 2,
          parts: [
            PowerBlock(id: 'work1', duration: 60000, power: 1.5),
          ],
        ),
      ];

      final stats = calculatePowerStats(plan);

      expect(stats.minPower, 0.5);
      expect(stats.maxPower, 1.5);
    });

    test('findBlockById finds top-level blocks', () {
      final plan = [
        PowerBlock(id: 'block1', duration: 60000, power: 0.6),
        RampBlock(id: 'block2', duration: 60000, powerStart: 0.5, powerEnd: 0.8),
      ];

      final found = findBlockById(plan, 'block2');
      expect(found, isNotNull);
      expect((found as RampBlock).id, 'block2');
    });

    test('findBlockById finds blocks inside intervals', () {
      final plan = [
        WorkoutInterval(
          id: 'int1',
          repeat: 2,
          parts: [
            PowerBlock(id: 'nested1', duration: 60000, power: 1.0),
          ],
        ),
      ];

      final found = findBlockById(plan, 'nested1');
      expect(found, isNotNull);
      expect((found as PowerBlock).id, 'nested1');
    });
  });
}
