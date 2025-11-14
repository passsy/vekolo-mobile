import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vekolo/api/activities/get_activities.dart';

void main() {
  group('ActivitiesResponse', () {
    test('parses real API response correctly', () {
      // Real response from the API - response.data contains just the activities array
      final responseData = [
          {
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
          },
      ];

      // Create a mock Response
      final response = Response(
        requestOptions: RequestOptions(path: '/api/activities'),
        statusCode: 200,
        data: responseData,
      );

      // Parse the response
      final activitiesResponse = ActivitiesResponse.init.fromResponse(response);

      // Verify parsing
      expect(activitiesResponse.activities, hasLength(1));

      final activity = activitiesResponse.activities.first;
      expect(activity.id, 'RoN7Qh6caaQI_zry3e5Dd');
      expect(activity.duration, 3643025);
      expect(activity.averagePower, 231.37);
      expect(activity.averageHeartRate, 139.7);
      expect(activity.averageCadence, 90.48);
      expect(activity.averageSpeed, 29.76);
      expect(activity.distance, 30125.99);
      expect(activity.burnedCalories, 839.6);
      expect(activity.maxSpeed, 38.17);
      expect(activity.createdAt, '2025-10-21T18:40:43.961Z');
      expect(activity.visibility.value, 'public');

      // Verify user
      expect(activity.user.id, 'xzx3AHjmOcEXkEHMjd7iY');
      expect(activity.user.name, 'Martin ');
      expect(activity.user.avatar, null);

      // Verify workout
      expect(activity.workout.id, 'H7aOFkEQMAI1pIMyP91Wv');
      expect(activity.workout.title, 'Hermes');
      expect(activity.workout.category?.value, 'endurance');
      expect(activity.workout.duration, 4500000);
      expect(activity.workout.tss, 102);
      expect(activity.workout.starCount, 1);
      expect(activity.workout.summary, 'Explosives SIT-Training mit 2x5 Sprint-Intervallen à 30 Sekunden bei maximaler Power und aktiver Erholung.');

      // Verify workout plan
      expect(activity.workout.plan.plan, hasLength(5));
    });
  });
}
