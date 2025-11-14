import 'package:vekolo/domain/models/workout/workout_models.dart';
import 'package:vekolo/models/rekord.dart';

/// Activity visibility level
///
/// Possible values:
/// - `public`: Visible to all users
/// - `private`: Only visible to the owner
extension type const ActivityVisibility(String value) {
  static const public = ActivityVisibility('public');
  static const private = ActivityVisibility('private');
}

/// Workout category/intensity level
///
/// Possible values:
/// - `recovery`: Low intensity recovery workout
/// - `endurance`: Aerobic endurance training
/// - `tempo`: Tempo/threshold training
/// - `threshold`: Lactate threshold training
/// - `vo2max`: VO2max intervals
/// - `ftp`: Functional Threshold Power test or training
extension type const WorkoutCategory(String value) {
  static const recovery = WorkoutCategory('recovery');
  static const endurance = WorkoutCategory('endurance');
  static const tempo = WorkoutCategory('tempo');
  static const threshold = WorkoutCategory('threshold');
  static const vo2max = WorkoutCategory('vo2max');
  static const ftp = WorkoutCategory('ftp');
}

/// Activity record from a completed workout
///
/// Represents a completed workout session with performance metrics,
/// associated user, and workout details.
class Activity with RekordMixin {
  Activity.fromData(Map<String, Object?> data) : rekord = Rekord(data);

  factory Activity.create({
    String? id,
    double? averageCadence,
    double? averageHeartRate,
    double? averagePower,
    double? averageSpeed,
    double? burnedCalories,
    String? createdAt,
    double? distance,
    int? duration,
    double? maxSpeed,
    String? stravaActivityId,
    ActivityVisibility? visibility,
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
      if (visibility != null) 'visibility': visibility.value,
      if (user != null) 'user': user,
      if (workout != null) 'workout': workout,
    });
  }

  @override
  final Rekord rekord;
  static final init = ActivityInit();

  String get id => rekord.read('id').asStringOrThrow();

  double? get averageCadence => rekord.read('averageCadence').asDoubleOrNull();
  double? get averageHeartRate => rekord.read('averageHeartRate').asDoubleOrNull();
  double? get averagePower => rekord.read('averagePower').asDoubleOrNull();
  double? get averageSpeed => rekord.read('averageSpeed').asDoubleOrNull();
  double? get burnedCalories => rekord.read('burnedCalories').asDoubleOrNull();
  String get createdAt => rekord.read('createdAt').asStringOrThrow();
  double? get distance => rekord.read('distance').asDoubleOrNull();
  int get duration => rekord.read('duration').asIntOrThrow();
  double? get maxSpeed => rekord.read('maxSpeed').asDoubleOrNull();
  String? get stravaActivityId => rekord.read('stravaActivityId').asStringOrNull();
  ActivityVisibility get visibility => ActivityVisibility(rekord.read('visibility').asStringOrThrow());

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
    WorkoutCategory? category,
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
      if (category != null) 'category': category.value,
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
  WorkoutCategory? get category {
    final value = rekord.read('category').asStringOrNull();
    return value != null ? WorkoutCategory(value) : null;
  }
  int get duration => rekord.read('duration').asIntOrThrow();
  String get slug => rekord.read('slug').asStringOrThrow();
  int get starCount => rekord.read('starCount').asIntOrThrow();
  String? get summary => rekord.read('summary').asStringOrNull();
  String get title => rekord.read('title').asStringOrThrow();
  int? get tss => rekord.read('tss').asIntOrNull();

  /// Workout plan with structured blocks and events
  WorkoutPlan get plan {
    final planList = rekord.read('plan').asListOrThrow<Map<String, Object?>>((pick) => pick.asMapOrThrow<String, Object?>());
    // Wrap the list in an object as expected by WorkoutPlan.fromJson
    return WorkoutPlan.fromJson({'plan': planList});
  }

  @override
  String toString() => 'ActivityWorkout(id: $id, title: $title)';
}
