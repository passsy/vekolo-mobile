import 'package:vekolo/domain/models/workout/workout_models.dart';
import 'package:vekolo/models/rekord.dart';
import 'package:vekolo/models/user.dart';

/// Activity record from a completed workout
///
/// Represents a completed workout session with performance metrics,
/// associated user, and workout details.
class Activity with RekordMixin {
  Activity.fromData(Map<String, Object?> data) : rekord = Rekord(data);

  factory Activity.create({
    String? id,
    int? averageCadence,
    int? averageHeartRate,
    int? averagePower,
    double? averageSpeed,
    int? burnedCalories,
    String? createdAt,
    int? distance,
    int? duration,
    double? maxSpeed,
    String? stravaActivityId,
    String? visibility,
    ActivityUser? user,
    ActivityWorkout? workout,
  }) {
    return Activity.fromData({
      if (id != null) 'id': id,
      if (averageCadence != null) 'averageCadence': averageCadence,
      if (averageHeartRate != null) 'averageHeartRate': averageHeartRate,
      if (averagePower != null) 'averagePower': averagePower,
      if (averageSpeed != null) 'averageSpeed': averageSpeed,
      if (burnedCalories != null) 'burnedCalories': burnedCalories,
      if (createdAt != null) 'createdAt': createdAt,
      if (distance != null) 'distance': distance,
      if (duration != null) 'duration': duration,
      if (maxSpeed != null) 'maxSpeed': maxSpeed,
      if (stravaActivityId != null) 'stravaActivityId': stravaActivityId,
      if (visibility != null) 'visibility': visibility,
      if (user != null) 'user': user,
      if (workout != null) 'workout': workout,
    });
  }

  @override
  final Rekord rekord;
  static final init = ActivityInit();

  String get id => rekord.read('id').asStringOrThrow();

  int? get averageCadence => rekord.read('averageCadence').asIntOrNull();
  int? get averageHeartRate => rekord.read('averageHeartRate').asIntOrNull();
  int? get averagePower => rekord.read('averagePower').asIntOrNull();
  double? get averageSpeed => rekord.read('averageSpeed').asDoubleOrNull();
  int? get burnedCalories => rekord.read('burnedCalories').asIntOrNull();
  String get createdAt => rekord.read('createdAt').asStringOrThrow();
  int? get distance => rekord.read('distance').asIntOrNull();
  int get duration => rekord.read('duration').asIntOrThrow();
  double? get maxSpeed => rekord.read('maxSpeed').asDoubleOrNull();
  String? get stravaActivityId => rekord.read('stravaActivityId').asStringOrNull();
  String get visibility => rekord.read('visibility').asStringOrThrow();

  ActivityUser get user => ActivityUser.fromData(rekord.read('user').asMapOrThrow<String, Object?>());
  ActivityWorkout get workout => ActivityWorkout.fromData(rekord.read('workout').asMapOrThrow<String, Object?>());

  @override
  String toString() => 'Activity(id: $id, workout: ${workout.title}, user: ${user.name})';
}

class ActivityInit {}

extension ActivityInitExt on ActivityInit {
  Activity fromMap(Map<String, Object?> data) {
    return Activity.fromData(data);
  }
}

/// User information embedded in activity responses
class ActivityUser with RekordMixin {
  ActivityUser.fromData(Map<String, Object?> data) : rekord = Rekord(data);

  factory ActivityUser.create({String? id, String? avatar, String? name, String? stravaId}) {
    return ActivityUser.fromData({
      if (id != null) 'id': id,
      if (avatar != null) 'avatar': avatar,
      if (name != null) 'name': name,
      if (stravaId != null) 'stravaId': stravaId,
    });
  }

  @override
  final Rekord rekord;

  String get id => rekord.read('id').asStringOrThrow();
  String? get avatar => rekord.read('avatar').asStringOrNull();
  String get name => rekord.read('name').asStringOrThrow();
  String? get stravaId => rekord.read('stravaId').asStringOrNull();

  @override
  String toString() => 'ActivityUser(id: $id, name: $name)';
}

/// Workout information embedded in activity responses
class ActivityWorkout with RekordMixin {
  ActivityWorkout.fromData(Map<String, Object?> data) : rekord = Rekord(data);

  factory ActivityWorkout.create({
    String? id,
    String? category,
    int? duration,
    WorkoutPlan? plan,
    String? slug,
    int? starCount,
    String? summary,
    String? title,
    int? tss,
  }) {
    return ActivityWorkout.fromData({
      if (id != null) 'id': id,
      if (category != null) 'category': category,
      if (duration != null) 'duration': duration,
      if (plan != null) 'plan': plan,
      if (slug != null) 'slug': slug,
      if (starCount != null) 'starCount': starCount,
      if (summary != null) 'summary': summary,
      if (title != null) 'title': title,
      if (tss != null) 'tss': tss,
    });
  }

  @override
  final Rekord rekord;

  String get id => rekord.read('id').asStringOrThrow();
  String? get category => rekord.read('category').asStringOrNull();
  int get duration => rekord.read('duration').asIntOrThrow();
  String get slug => rekord.read('slug').asStringOrThrow();
  int get starCount => rekord.read('starCount').asIntOrThrow();
  String? get summary => rekord.read('summary').asStringOrNull();
  String get title => rekord.read('title').asStringOrThrow();
  int? get tss => rekord.read('tss').asIntOrNull();

  /// Workout plan with structured blocks and events
  WorkoutPlan get plan {
    final planMap = rekord.read('plan').asMapOrThrow<String, Object?>();
    return WorkoutPlan.fromJson(planMap);
  }

  @override
  String toString() => 'ActivityWorkout(id: $id, title: $title)';
}
