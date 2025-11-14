import 'package:flutter_test/flutter_test.dart';
import 'package:vekolo/models/activity.dart';
import 'package:vekolo/pages/home_page_v2/tabs/activities_tab.dart';

void main() {
  group('generateIntervalsFromPlan', () {
    test('generates correct intervals for real workout plan with repeating intervals', () {
      // Real workout data from the API response
      final activityData = {
        'averageCadence': 90.48,
        'averageHeartRate': 139.7,
        'averagePower': 231.37,
        'averageSpeed': 29.76,
        'burnedCalories': 839.6,
        'createdAt': '2025-10-21T18:40:43.961Z',
        'distance': 30125.99,
        'duration': 3643025,
        'id': 'RoN7Qh6caaQI_zry3e5Dd',
        'maxSpeed': 38.17,
        'stravaActivityId': null,
        'user': {
          'avatar': null,
          'id': 'xzx3AHjmOcEXkEHMjd7iY',
          'name': 'Martin ',
          'stravaId': null,
        },
        'visibility': 'public',
        'workout': {
          'category': 'endurance',
          'duration': 4500000,
          'id': 'H7aOFkEQMAI1pIMyP91Wv',
          'plan': [
            {
              'description': 'Warm-up',
              'duration': 600000,
              'id': '0Efi5VO2',
              'powerEnd': 0.75,
              'powerStart': 0.5,
              'type': 'ramp',
            },
            {
              'description': 'SIT Set 1',
              'id': 'TwRTxhQ0',
              'parts': [
                {
                  'duration': 30000,
                  'id': 'upHxYiXd',
                  'power': 1.6676557863501484,
                  'type': 'power',
                },
                {
                  'duration': 270000,
                  'id': 'zScKPA2Z',
                  'power': 0.658753709198813,
                  'type': 'power',
                },
              ],
              'repeat': 5,
              'type': 'interval',
            },
            {
              'description': 'Erholung zwischen den Sets',
              'duration': 300000,
              'id': 'q009WEja',
              'power': 0.57,
              'type': 'power',
            },
            {
              'description': 'SIT Set 2',
              'id': 'aI8vTSHL',
              'parts': [
                {
                  'duration': 30000,
                  'id': 'B3kyT77v',
                  'power': 1.6676557863501484,
                  'type': 'power',
                },
                {
                  'duration': 270000,
                  'id': 'Wqkr3dAf',
                  'power': 0.658753709198813,
                  'type': 'power',
                },
              ],
              'repeat': 5,
              'type': 'interval',
            },
            {
              'description': 'Cool-down',
              'duration': 600000,
              'id': 'nqNh7gtg',
              'powerEnd': 0.4,
              'powerStart': 0.6,
              'type': 'ramp',
            },
          ],
          'slug': null,
          'starCount': 1,
          'summary': 'Explosives SIT-Training mit 2x5 Sprint-Intervallen à 30 Sekunden bei maximaler Power und aktiver Erholung.',
          'title': 'Hermes',
          'tss': 102,
        },
      };

      final activity = Activity.fromData(activityData);
      final plan = activity.workout.plan;

      // Expected structure based on web implementation (flattenWorkoutPlan):
      // 1. Warm-up ramp: 1 block (10 minutes)
      // 2. SIT Set 1: 5 repeats × 2 parts = 10 blocks
      //    - Each repeat: 0.5 min high power + 4.5 min recovery
      // 3. Recovery power: 1 block (5 minutes)
      // 4. SIT Set 2: 5 repeats × 2 parts = 10 blocks
      //    - Each repeat: 0.5 min high power + 4.5 min recovery
      // 5. Cool-down ramp: 1 block (10 minutes)
      // Total: 23 blocks

      final intervals = generateIntervalsFromPlan(plan);

      // Verify total number of intervals
      expect(intervals.length, 23, reason: 'Should have 23 total blocks (1 warmup + 10 SIT1 + 1 recovery + 10 SIT2 + 1 cooldown)');

      // Verify structure
      // Block 0: Warm-up ramp (10 minutes)
      expect(intervals[0].duration, 10, reason: 'Warm-up should be 10 minutes');
      expect(intervals[0].intensity, closeTo(0.625, 0.01), reason: 'Ramp average should be (0.5 + 0.75) / 2');

      // Blocks 1-10: SIT Set 1 (5 repeats of 2 parts)
      // Each repeat: 30s @ 1.67 FTP + 270s @ 0.66 FTP
      for (var i = 0; i < 5; i++) {
        final baseIdx = 1 + i * 2;
        // High power block (30s = 0.5 minutes, rounded to 1)
        expect(intervals[baseIdx].duration, 1, reason: 'SIT Set 1 repeat ${i + 1} high power should be 1 minute (rounded from 0.5)');
        expect(intervals[baseIdx].intensity, closeTo(1.67, 0.01), reason: 'SIT Set 1 high power should be ~1.67 FTP');

        // Recovery block (270s = 4.5 minutes, rounded to 5)
        expect(intervals[baseIdx + 1].duration, 5, reason: 'SIT Set 1 repeat ${i + 1} recovery should be 5 minutes (rounded from 4.5)');
        expect(intervals[baseIdx + 1].intensity, closeTo(0.66, 0.01), reason: 'SIT Set 1 recovery should be ~0.66 FTP');
      }

      // Block 11: Recovery between sets (5 minutes)
      expect(intervals[11].duration, 5, reason: 'Recovery between sets should be 5 minutes');
      expect(intervals[11].intensity, 0.57, reason: 'Recovery power should be 0.57 FTP');

      // Blocks 12-21: SIT Set 2 (5 repeats of 2 parts)
      for (var i = 0; i < 5; i++) {
        final baseIdx = 12 + i * 2;
        // High power block
        expect(intervals[baseIdx].duration, 1, reason: 'SIT Set 2 repeat ${i + 1} high power should be 1 minute (rounded from 0.5)');
        expect(intervals[baseIdx].intensity, closeTo(1.67, 0.01), reason: 'SIT Set 2 high power should be ~1.67 FTP');

        // Recovery block
        expect(intervals[baseIdx + 1].duration, 5, reason: 'SIT Set 2 repeat ${i + 1} recovery should be 5 minutes (rounded from 4.5)');
        expect(intervals[baseIdx + 1].intensity, closeTo(0.66, 0.01), reason: 'SIT Set 2 recovery should be ~0.66 FTP');
      }

      // Block 22: Cool-down ramp (10 minutes)
      expect(intervals[22].duration, 10, reason: 'Cool-down should be 10 minutes');
      expect(intervals[22].intensity, closeTo(0.5, 0.01), reason: 'Cooldown ramp average should be (0.6 + 0.4) / 2');
    });
  });
}
