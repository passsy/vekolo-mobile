/// Example workout demonstrating model usage.
///
/// This file shows how to create workout plans and use the utility functions.
library;

import 'dart:convert';
import 'package:vekolo/domain/models/workout/workout_models.dart';
import 'package:vekolo/domain/models/workout/workout_utils.dart';

/// Example VO2max interval workout.
///
/// Structure:
/// - 10min warm-up (50% → 75% FTP)
/// - 3x (3min @ 110% FTP, 3min @ 50% FTP)
/// - 5min cool-down (70% → 50% FTP)
WorkoutPlan createVo2maxIntervalWorkout() {
  return WorkoutPlan(
    plan: [
      // Warm-up
      RampBlock(
        id: 'warmup01',
        duration: 600000, // 10 minutes
        powerStart: 0.5,
        powerEnd: 0.75,
        description: 'Warm up',
        cadenceStart: 80,
        cadenceEnd: 90,
      ),
      // Main set: 3 intervals
      WorkoutInterval(
        id: 'vo2max01',
        repeat: 3,
        description: 'VO2max intervals',
        parts: [
          PowerBlock(
            id: 'work0001',
            duration: 180000, // 3 minutes
            power: 1.10,
            cadence: 95,
            description: 'Max effort',
          ),
          PowerBlock(
            id: 'rest0001',
            duration: 180000, // 3 minutes
            power: 0.5,
            cadence: 85,
            description: 'Recovery',
          ),
        ],
      ),
      // Cool-down
      RampBlock(
        id: 'cooldown',
        duration: 300000, // 5 minutes
        powerStart: 0.7,
        powerEnd: 0.5,
        description: 'Cool down',
        cadenceStart: 90,
        cadenceEnd: 80,
      ),
    ],
    events: [
      MessageEvent(
        id: 'msg00001',
        parentBlockId: 'warmup01',
        relativeTimeOffset: 300000, // 5 minutes into warmup
        text: 'Get ready for intervals!',
        duration: 5000,
      ),
      MessageEvent(
        id: 'msg00002',
        parentBlockId: 'vo2max01',
        relativeTimeOffset: 170000, // 10s before first work block ends
        text: 'Last 10 seconds!',
        duration: 10000,
      ),
      EffectEvent(
        id: 'eff00001',
        parentBlockId: 'cooldown',
        relativeTimeOffset: 295000, // Near end of workout
        effect: EffectType.fireworks,
      ),
    ],
  );
}

/// Example sweet spot training workout.
///
/// Structure:
/// - 5min warm-up (50% → 70% FTP)
/// - 2x (10min @ 88% FTP, 5min @ 60% FTP)
/// - 5min cool-down (70% → 50% FTP)
WorkoutPlan createSweetSpotWorkout() {
  return WorkoutPlan(
    plan: [
      RampBlock(
        id: 'warmup02',
        duration: 300000,
        powerStart: 0.5,
        powerEnd: 0.7,
        description: 'Warm up',
      ),
      WorkoutInterval(
        id: 'sweetspot',
        repeat: 2,
        description: 'Sweet spot',
        parts: [
          PowerBlock(
            id: 'ss_work01',
            duration: 600000, // 10 minutes
            power: 0.88,
            cadence: 90,
            description: 'Sweet spot',
          ),
          PowerBlock(
            id: 'ss_rest01',
            duration: 300000, // 5 minutes
            power: 0.6,
            description: 'Easy spin',
          ),
        ],
      ),
      RampBlock(
        id: 'cooldown2',
        duration: 300000,
        powerStart: 0.7,
        powerEnd: 0.5,
        description: 'Cool down',
      ),
    ],
    events: [
      MessageEvent(
        id: 'msg00003',
        parentBlockId: 'sweetspot',
        relativeTimeOffset: 300000,
        text: 'Halfway through the interval!',
      ),
    ],
  );
}

/// Example FTP test workout.
///
/// Structure:
/// - 15min warm-up with progressive build
/// - 20min all-out effort @ 100% FTP
/// - 5min cool-down
WorkoutPlan createFtpTestWorkout() {
  return WorkoutPlan(
    plan: [
      RampBlock(
        id: 'ftp_warmup',
        duration: 900000, // 15 minutes
        powerStart: 0.4,
        powerEnd: 0.85,
        description: 'Progressive warm-up',
      ),
      PowerBlock(
        id: 'ftp_test',
        duration: 1200000, // 20 minutes
        power: 1.0,
        cadence: 95,
        cadenceLow: 85,
        cadenceHigh: 105,
        description: 'FTP test - all out!',
      ),
      RampBlock(
        id: 'ftp_cooldown',
        duration: 300000, // 5 minutes
        powerStart: 0.6,
        powerEnd: 0.4,
        description: 'Cool down',
      ),
    ],
    events: [
      MessageEvent(
        id: 'msg_ftp1',
        parentBlockId: 'ftp_warmup',
        relativeTimeOffset: 840000,
        text: 'Get ready for the test!',
      ),
      MessageEvent(
        id: 'msg_ftp2',
        parentBlockId: 'ftp_test',
        relativeTimeOffset: 0,
        text: 'Go! Give it everything you have!',
        duration: 8000,
      ),
      MessageEvent(
        id: 'msg_ftp3',
        parentBlockId: 'ftp_test',
        relativeTimeOffset: 600000,
        text: 'Halfway there! Stay strong!',
      ),
      MessageEvent(
        id: 'msg_ftp4',
        parentBlockId: 'ftp_test',
        relativeTimeOffset: 1140000,
        text: 'Final minute! Empty the tank!',
      ),
      EffectEvent(
        id: 'eff_ftp1',
        parentBlockId: 'ftp_cooldown',
        relativeTimeOffset: 290000,
        effect: EffectType.fireworks,
      ),
    ],
  );
}

/// Example usage demonstrating all utility functions.
void demonstrateUsage() {
  // Create a workout
  final workout = createVo2maxIntervalWorkout();

  // Calculate total duration
  final totalDuration = calculateTotalDuration(workout.plan);
  print('Workout duration: ${totalDuration ~/ 1000 ~/ 60} minutes');

  // Flatten the plan for rendering/playback
  final flattenedBlocks = flattenWorkoutPlan(workout.plan);
  print('Total blocks (with intervals expanded): ${flattenedBlocks.length}');

  // Apply power scale factor (e.g., reduce intensity by 10%)
  final easierBlocks = flattenWorkoutPlan(workout.plan, powerScaleFactor: 0.9);
  print('Easier workout: ${(easierBlocks[1] as PowerBlock).power * 100}% FTP');

  // Get power stats
  final stats = calculatePowerStats(workout.plan);
  print('Power range: ${(stats.minPower * 100).toInt()}% - ${(stats.maxPower * 100).toInt()}% FTP');

  // Flatten events for playback
  final flattenedEvents = flattenWorkoutEvents(workout.plan, workout.events);
  print('Total events: ${flattenedEvents.length}');
  for (final event in flattenedEvents) {
    if (event is FlattenedMessageEvent) {
      print('  Message at ${event.timeOffset ~/ 1000}s: "${event.text}"');
    }
  }

  // Map absolute time to block position
  final position = mapAbsoluteTimeToBlockRelative(workout.plan, 900000); // 15 minutes
  if (position != null) {
    print('At 15:00, you are in block ${position.blockId}, ${position.offset ~/ 1000}s into it');
  }

  // Calculate power at a specific time in a ramp block
  final ramp = workout.plan[0] as RampBlock;
  final powerAt5min = calculatePowerAtTime(ramp, 300000);
  print('Power at 5min into warmup: ${(powerAt5min * 100).toInt()}% FTP');

  // JSON serialization roundtrip
  final jsonString = jsonEncode(workout.toJson());
  print('\nJSON size: ${jsonString.length} bytes');

  final restored = WorkoutPlan.fromJson(jsonDecode(jsonString) as Map<String, dynamic>);
  print('Roundtrip successful: ${restored.plan.length} items, ${restored.events.length} events');
}

/// JSON example for reference.
const String exampleWorkoutJson = '''
{
  "plan": [
    {
      "id": "warmup01",
      "type": "ramp",
      "description": "Warm up",
      "duration": 600000,
      "powerStart": 0.5,
      "powerEnd": 0.75,
      "cadenceStart": 80,
      "cadenceEnd": 90
    },
    {
      "id": "vo2max01",
      "type": "interval",
      "description": "VO2max intervals",
      "repeat": 3,
      "parts": [
        {
          "id": "work0001",
          "type": "power",
          "description": "Max effort",
          "duration": 180000,
          "power": 1.10,
          "cadence": 95
        },
        {
          "id": "rest0001",
          "type": "power",
          "description": "Recovery",
          "duration": 180000,
          "power": 0.5,
          "cadence": 85
        }
      ]
    }
  ],
  "events": [
    {
      "id": "msg00001",
      "type": "message",
      "parentBlockId": "warmup01",
      "relativeTimeOffset": 300000,
      "text": "Get ready for intervals!",
      "duration": 5000
    }
  ]
}
''';
