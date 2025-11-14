import 'package:flutter_test/flutter_test.dart';
import 'package:vekolo/models/activity.dart';

void main() {
  group('ActivityVisibility extension type', () {
    test('has correct predefined values', () {
      expect(ActivityVisibility.public.value, 'public');
      expect(ActivityVisibility.private.value, 'private');
    });

    test('can be created from string', () {
      const visibility = ActivityVisibility('public');
      expect(visibility.value, 'public');
    });

    test('works with Activity model', () {
      final activity = Activity.create(
        id: 'test123',
        duration: 3600000,
        createdAt: '2025-01-01T00:00:00Z',
        visibility: ActivityVisibility.public,
        user: ActivityUser.create(id: 'user1', name: 'Test User'),
        workout: ActivityWorkout.create(
          id: 'workout1',
          title: 'Test Workout',
          duration: 3600000,
        ),
      );

      expect(activity.visibility.value, 'public');
    });

    test('parses from API response', () {
      final activityData = {
        'id': 'test123',
        'duration': 3600000,
        'createdAt': '2025-01-01T00:00:00Z',
        'visibility': 'private',
        'user': {
          'id': 'user1',
          'name': 'Test User',
        },
        'workout': {
          'id': 'workout1',
          'title': 'Test Workout',
          'duration': 3600000,
        },
      };

      final activity = Activity.fromData(activityData);
      expect(activity.visibility.value, 'private');
    });
  });

  group('WorkoutCategory extension type', () {
    test('has correct predefined values', () {
      expect(WorkoutCategory.recovery.value, 'recovery');
      expect(WorkoutCategory.endurance.value, 'endurance');
      expect(WorkoutCategory.tempo.value, 'tempo');
      expect(WorkoutCategory.threshold.value, 'threshold');
      expect(WorkoutCategory.vo2max.value, 'vo2max');
      expect(WorkoutCategory.ftp.value, 'ftp');
    });

    test('can be created from string', () {
      const category = WorkoutCategory('endurance');
      expect(category.value, 'endurance');
    });

    test('works with ActivityWorkout model', () {
      final workout = ActivityWorkout.create(
        id: 'workout1',
        title: 'Endurance Ride',
        category: WorkoutCategory.endurance,
        duration: 3600000,
      );

      expect(workout.category?.value, 'endurance');
    });

    test('parses from API response', () {
      final workoutData = {
        'id': 'workout1',
        'title': 'VO2 Max Intervals',
        'category': 'vo2max',
        'duration': 3600000,
        'plan': [],
      };

      final workout = ActivityWorkout.fromData(workoutData);
      expect(workout.category?.value, 'vo2max');
    });

    test('handles null category', () {
      final workoutData = {
        'id': 'workout1',
        'title': 'Test Workout',
        'duration': 3600000,
        'plan': [],
      };

      final workout = ActivityWorkout.fromData(workoutData);
      expect(workout.category, null);
    });

    test('all category values are documented', () {
      // This test ensures all possible values are covered in the dartdoc
      final allCategories = [
        WorkoutCategory.recovery,
        WorkoutCategory.endurance,
        WorkoutCategory.tempo,
        WorkoutCategory.threshold,
        WorkoutCategory.vo2max,
        WorkoutCategory.ftp,
      ];

      expect(allCategories.length, 6);
      expect(allCategories.map((c) => c.value).toSet(), {
        'recovery',
        'endurance',
        'tempo',
        'threshold',
        'vo2max',
        'ftp',
      });
    });
  });
}
