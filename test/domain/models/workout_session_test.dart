import 'package:flutter_test/flutter_test.dart';
import 'package:vekolo/domain/models/workout/workout_models.dart';
import 'package:vekolo/domain/models/workout_session.dart';

void main() {
  group('SessionStatus', () {
    test('fromString parses valid values', () {
      expect(SessionStatus.fromString('active'), SessionStatus.active);
      expect(SessionStatus.fromString('completed'), SessionStatus.completed);
      expect(SessionStatus.fromString('abandoned'), SessionStatus.abandoned);
      expect(SessionStatus.fromString('crashed'), SessionStatus.crashed);
    });

    test('fromString throws on invalid value', () {
      expect(() => SessionStatus.fromString('invalid'), throwsArgumentError);
    });

    test('value property returns correct string', () {
      expect(SessionStatus.active.value, 'active');
      expect(SessionStatus.completed.value, 'completed');
      expect(SessionStatus.abandoned.value, 'abandoned');
      expect(SessionStatus.crashed.value, 'crashed');
    });
  });

  group('WorkoutSessionMetadata', () {
    final testWorkoutPlan = WorkoutPlan(
      plan: [
        const PowerBlock(
          id: 'warmup',
          duration: 300000, // 5 minutes
          power: 0.5,
        ),
        const PowerBlock(
          id: 'main',
          duration: 600000, // 10 minutes
          power: 0.85,
        ),
      ],
    );

    final testMetadata = WorkoutSessionMetadata(
      workoutId: 'V1StGXR8_Z5jdHi6B-myT',
      workoutName: 'Sweet Spot Intervals',
      workoutPlan: testWorkoutPlan,
      startTime: DateTime.parse('2025-01-15T10:00:00.000Z'),
      status: SessionStatus.active,
      userId: 'user-123',
      sourceWorkoutId: 'workout-abc123',
      ftp: 200,
      totalSamples: 123,
      currentBlockIndex: 1,
      elapsedMs: 123000,
      lastUpdated: DateTime.parse('2025-01-15T10:02:03.000Z'),
    );

    test('toJson serializes all fields correctly', () {
      final json = testMetadata.toJson();

      expect(json['workoutId'], 'V1StGXR8_Z5jdHi6B-myT');
      expect(json['workoutName'], 'Sweet Spot Intervals');
      expect(json['workoutPlanJson'], isA<Map<String, dynamic>>());
      expect(json['startTime'], '2025-01-15T10:00:00.000Z');
      expect(json['endTime'], isNull);
      expect(json['status'], 'active');
      expect(json['userId'], 'user-123');
      expect(json['ftp'], 200);
      expect(json['totalSamples'], 123);
      expect(json['currentBlockIndex'], 1);
      expect(json['elapsedMs'], 123000);
      expect(json['lastUpdated'], '2025-01-15T10:02:03.000Z');
    });

    test('toJson omits null fields correctly', () {
      final metadataWithoutOptionals = WorkoutSessionMetadata(
        workoutId: testMetadata.workoutId,
        workoutName: testMetadata.workoutName,
        workoutPlan: testMetadata.workoutPlan,
        startTime: testMetadata.startTime,
        status: testMetadata.status,
        sourceWorkoutId: testMetadata.sourceWorkoutId,
        ftp: testMetadata.ftp,
        totalSamples: testMetadata.totalSamples,
        currentBlockIndex: testMetadata.currentBlockIndex,
        elapsedMs: testMetadata.elapsedMs,
        lastUpdated: testMetadata.lastUpdated,
      );
      final json = metadataWithoutOptionals.toJson();

      expect(json.containsKey('userId'), isFalse);
      expect(json.containsKey('endTime'), isFalse);
    });

    test('fromJson deserializes correctly', () {
      final json = testMetadata.toJson();
      final deserialized = WorkoutSessionMetadata.fromJson(json);

      expect(deserialized.workoutId, testMetadata.workoutId);
      expect(deserialized.workoutName, testMetadata.workoutName);
      expect(deserialized.workoutPlan.plan.length, testMetadata.workoutPlan.plan.length);
      expect(deserialized.startTime, testMetadata.startTime);
      expect(deserialized.endTime, testMetadata.endTime);
      expect(deserialized.status, testMetadata.status);
      expect(deserialized.userId, testMetadata.userId);
      expect(deserialized.ftp, testMetadata.ftp);
      expect(deserialized.totalSamples, testMetadata.totalSamples);
      expect(deserialized.currentBlockIndex, testMetadata.currentBlockIndex);
      expect(deserialized.elapsedMs, testMetadata.elapsedMs);
      expect(deserialized.lastUpdated, testMetadata.lastUpdated);
    });

    test('copyWith creates new instance with updated fields', () {
      final updated = testMetadata.copyWith(
        status: SessionStatus.completed,
        endTime: DateTime.parse('2025-01-15T10:30:00.000Z'),
        totalSamples: 456,
      );

      expect(updated.status, SessionStatus.completed);
      expect(updated.endTime, DateTime.parse('2025-01-15T10:30:00.000Z'));
      expect(updated.totalSamples, 456);
      // Other fields unchanged
      expect(updated.workoutId, testMetadata.workoutId);
      expect(updated.workoutName, testMetadata.workoutName);
      expect(updated.ftp, testMetadata.ftp);
    });

    test('round-trip serialization preserves data', () {
      final json = testMetadata.toJson();
      final deserialized = WorkoutSessionMetadata.fromJson(json);
      final json2 = deserialized.toJson();

      expect(json2, equals(json));
    });
  });

  group('WorkoutSession', () {
    final testWorkoutPlan = WorkoutPlan(plan: [const PowerBlock(id: 'warmup', duration: 300000, power: 0.5)]);

    final testMetadata = WorkoutSessionMetadata(
      workoutId: 'V1StGXR8_Z5jdHi6B-myT',
      workoutName: 'Test Workout',
      workoutPlan: testWorkoutPlan,
      startTime: DateTime.parse('2025-01-15T10:00:00.000Z'),
      status: SessionStatus.active,
      sourceWorkoutId: 'workout-test123',
      ftp: 200,
      totalSamples: 50,
      currentBlockIndex: 0,
      elapsedMs: 50000,
      lastUpdated: DateTime.parse('2025-01-15T10:00:50.000Z'),
    );

    test('fromMetadata creates session from metadata', () {
      final session = WorkoutSession.fromMetadata(testMetadata);

      expect(session.id, testMetadata.workoutId);
      expect(session.workoutName, testMetadata.workoutName);
      expect(session.workoutPlan, testMetadata.workoutPlan);
      expect(session.startTime, testMetadata.startTime);
      expect(session.status, testMetadata.status);
      expect(session.elapsedMs, testMetadata.elapsedMs);
      expect(session.currentBlockIndex, testMetadata.currentBlockIndex);
      expect(session.lastSampleTime, testMetadata.lastUpdated);
    });
  });

  group('WorkoutSample', () {
    final testSample = WorkoutSample(
      timestamp: DateTime.parse('2025-01-15T10:00:05.000Z'),
      elapsedMs: 5000,
      powerActual: 195,
      powerTarget: 200,
      cadence: 88,
      speed: 35.2,
      heartRate: 145,
      powerScaleFactor: 1.0,
    );

    test('toJson serializes all fields correctly', () {
      final json = testSample.toJson();

      expect(json['timestamp'], '2025-01-15T10:00:05.000Z');
      expect(json['elapsedMs'], 5000);
      expect(json['powerActual'], 195);
      expect(json['powerTarget'], 200);
      expect(json['cadence'], 88);
      expect(json['speed'], 35.2);
      expect(json['heartRate'], 145);
      expect(json['powerScaleFactor'], 1.0);
    });

    test('toJson handles null values (stale metrics)', () {
      final staleSample = WorkoutSample(
        timestamp: DateTime.parse('2025-01-15T10:00:10.000Z'),
        elapsedMs: 10000,
        powerTarget: 200,
        heartRate: 145, // Still valid
        powerScaleFactor: 1.0,
      );

      final json = staleSample.toJson();

      expect(json['powerActual'], isNull);
      expect(json['cadence'], isNull);
      expect(json['speed'], isNull);
      expect(json['heartRate'], 145);
    });

    test('fromJson deserializes correctly', () {
      final json = testSample.toJson();
      final deserialized = WorkoutSample.fromJson(json);

      expect(deserialized.timestamp, testSample.timestamp);
      expect(deserialized.elapsedMs, testSample.elapsedMs);
      expect(deserialized.powerActual, testSample.powerActual);
      expect(deserialized.powerTarget, testSample.powerTarget);
      expect(deserialized.cadence, testSample.cadence);
      expect(deserialized.speed, testSample.speed);
      expect(deserialized.heartRate, testSample.heartRate);
      expect(deserialized.powerScaleFactor, testSample.powerScaleFactor);
    });

    test('round-trip serialization preserves data', () {
      final json = testSample.toJson();
      final deserialized = WorkoutSample.fromJson(json);
      final json2 = deserialized.toJson();

      expect(json2, equals(json));
    });

    test('JSON is compact (single line for JSONL)', () {
      final json = testSample.toJson();
      // Verify it's a Map, not a formatted string
      expect(json, isA<Map<String, dynamic>>());
      // The actual JSONL formatting (newline-separated) happens in persistence layer
    });
  });
}
