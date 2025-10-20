import 'package:vekolo/api/vekolo_api_client.dart';
import 'package:vekolo/models/rekord.dart';

class User with RekordMixin {
  User.fromData(Map<String, Object?> data) : rekord = Rekord(data);

  factory User.create({
    String? id,
    String? activityVisibility,
    String? email,
    bool? emailVerified,
    String? name,
    String? profileVisibility,
    String? avatar,
    int? ftp,
    String? measurementPreference,
    int? weight,
    String? sex,
    String? stravaId,
    bool? stravaSync,
    String? stravaUsername,
    int? totalActivitiesCount,
    String? totalDistanceCount,
    int? totalDurationCount,
  }) {
    return User.fromData({
      if (id != null) 'id': id,
      if (activityVisibility != null) 'activityVisibility': activityVisibility,
      if (email != null) 'email': email,
      if (emailVerified != null) 'emailVerified': emailVerified,
      if (name != null) 'name': name,
      if (profileVisibility != null) 'profileVisibility': profileVisibility,
      if (avatar != null) 'avatar': avatar,
      if (ftp != null) 'ftp': ftp,
      if (measurementPreference != null) 'measurementPreference': measurementPreference,
      if (weight != null) 'weight': weight,
      if (sex != null) 'sex': sex,
      if (stravaId != null) 'stravaId': stravaId,
      if (stravaSync != null) 'stravaSync': stravaSync,
      if (stravaUsername != null) 'stravaUsername': stravaUsername,
      if (totalActivitiesCount != null) 'totalActivitiesCount': totalActivitiesCount,
      if (totalDistanceCount != null) 'totalDistanceCount': totalDistanceCount,
      if (totalDurationCount != null) 'totalDurationCount': totalDurationCount,
    });
  }

  @override
  final Rekord rekord;
  static final init = UserInit();

  // Core identity fields
  String get id => rekord.read('id').asStringOrThrow();
  String get name => rekord.read('name').asStringOrThrow();
  String get email => rekord.read('email').asStringOrThrow();
  bool get emailVerified => rekord.read('emailVerified').asBoolOrThrow();

  /// Can be 'free' or 'pro'
  ///
  /// There is no distinction between monthly and yearly subscribers
  String get plan => rekord.read('plan').asStringOrThrow();

  // Profile settings
  String get activityVisibility => rekord.read('activityVisibility').asStringOrThrow();
  String get profileVisibility => rekord.read('profileVisibility').asStringOrThrow();
  String? get avatar => rekord.read('avatar').asStringOrNull();

  // Physical stats
  int get ftp => rekord.read('ftp').asIntOrThrow();
  int get weight => rekord.read('weight').asIntOrThrow();
  String get sex => rekord.read('sex').asStringOrThrow();
  String get measurementPreference => rekord.read('measurementPreference').asStringOrThrow();

  // Strava integration
  String? get stravaId => rekord.read('stravaId').asStringOrNull();
  bool get stravaSync => rekord.read('stravaSync').asBoolOrThrow();
  String? get stravaUsername => rekord.read('stravaUsername').asStringOrNull();

  // Activity stats
  int get totalActivitiesCount => rekord.read('totalActivitiesCount').asIntOrThrow();
  String get totalDistanceCount => rekord.read('totalDistanceCount').asStringOrThrow();
  int get totalDurationCount => rekord.read('totalDurationCount').asIntOrThrow();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is User && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'User(id: $id, name: $name, email: $email)';
}

class UserInit {}

extension UserInitExt on UserInit {
  User fromAccessToken(AccessToken accessToken) {
    final user = pick(accessToken.decode(), 'user').asMapOrThrow<String, Object?>();
    return User.fromData(user);
  }
}
