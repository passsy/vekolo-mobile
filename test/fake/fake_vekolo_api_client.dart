import 'dart:convert';

import 'package:vekolo/api/api_context.dart';
import 'package:vekolo/api/vekolo_api_client.dart';
import 'package:vekolo/models/activity.dart';
import 'package:vekolo/models/user.dart';

/// In-memory fake implementation of [VekoloApiClient] for testing
///
/// This fake uses the override pattern where each method has a corresponding
/// nullable function field that can be set to customize behavior in tests.
/// Default implementations return success responses.
class FakeVekoloApiClient implements VekoloApiClient {
  FakeVekoloApiClient({this.baseUrl = 'https://fake-api.test'});

  @override
  final String baseUrl;

  @override
  ApiContext get context => throw UnimplementedError(
    'context should not be accessed in FakeVekoloApiClient. '
    'This is an internal implementation detail.',
  );

  // Call tracking (optional, but useful for verifying behavior in tests)
  final List<String> methodCalls = [];

  // Auth endpoint overrides

  Future<CodeRequestResponse> Function({
    required String email,
    String? name,
    String? sex,
    int? weight,
    int? ftp,
    String? athleteLevel,
    String? athleteType,
    String? birthday,
    int? height,
    String? measurementPreference,
    bool? newsletter,
  })?
  overrideRequestSignupCode;

  @override
  Future<CodeRequestResponse> requestSignupCode({
    required String email,
    String? name,
    String? sex,
    int? weight,
    int? ftp,
    String? athleteLevel,
    String? athleteType,
    String? birthday,
    int? height,
    String? measurementPreference,
    bool? newsletter,
  }) async {
    methodCalls.add('requestSignupCode');
    if (overrideRequestSignupCode != null) {
      return overrideRequestSignupCode!(
        email: email,
        name: name,
        sex: sex,
        weight: weight,
        ftp: ftp,
        athleteLevel: athleteLevel,
        athleteType: athleteType,
        birthday: birthday,
        height: height,
        measurementPreference: measurementPreference,
        newsletter: newsletter,
      );
    }
    // Default: return success
    return CodeRequestResponse.create(
      success: true,
      userExists: false,
      rateLimited: false,
      message: 'Code sent successfully',
    );
  }

  Future<CodeRequestResponse> Function({required String email})? overrideRequestLoginCode;

  @override
  Future<CodeRequestResponse> requestLoginCode({required String email}) async {
    methodCalls.add('requestLoginCode');
    if (overrideRequestLoginCode != null) {
      return overrideRequestLoginCode!(email: email);
    }
    // Default: return success
    return CodeRequestResponse.create(
      success: true,
      userExists: true,
      rateLimited: false,
      message: 'Code sent successfully',
    );
  }

  Future<TokenResponse> Function({required String email, required String code, String? deviceInfo})? overrideRedeemCode;

  @override
  Future<TokenResponse> redeemCode({required String email, required String code, String? deviceInfo}) async {
    methodCalls.add('redeemCode');
    if (overrideRedeemCode != null) {
      return overrideRedeemCode!(email: email, code: code, deviceInfo: deviceInfo);
    }
    // Default: return success with fake tokens and user
    final user = User.create(id: 'fake-user-id', name: 'Fake User', email: email, emailVerified: true);
    final accessToken = FakeVekoloApiClient.createFakeAccessToken(user);
    final refreshToken = RefreshToken('fake-refresh-token');
    return TokenResponse.create(
      success: true,
      accessToken: accessToken.jwt,
      refreshToken: refreshToken.value,
      user: user,
    );
  }

  Future<RefreshTokenResponse> Function({required RefreshToken refreshToken})? overrideRefreshToken;

  @override
  Future<RefreshTokenResponse> refreshToken({required RefreshToken refreshToken}) async {
    methodCalls.add('refreshToken');
    if (overrideRefreshToken != null) {
      return overrideRefreshToken!(refreshToken: refreshToken);
    }
    // Default: return new access token
    final user = User.create(id: 'fake-user-id', name: 'Fake User', email: 'fake@example.com', emailVerified: true);
    final accessToken = FakeVekoloApiClient.createFakeAccessToken(user);
    return RefreshTokenResponse.create(success: true, accessToken: accessToken.jwt);
  }

  Future<RevokeTokenResponse> Function({required RefreshToken refreshToken})? overrideRevokeToken;

  @override
  Future<RevokeTokenResponse> revokeToken({required RefreshToken refreshToken}) async {
    methodCalls.add('revokeToken');
    if (overrideRevokeToken != null) {
      return overrideRevokeToken!(refreshToken: refreshToken);
    }
    // Default: return success
    return RevokeTokenResponse.create(success: true, message: 'Token revoked successfully');
  }

  // User endpoint overrides

  Future<UpdateProfileResponse> Function({int? ftp, int? weight, String? name, String? email})? overrideUpdateProfile;

  @override
  Future<UpdateProfileResponse> updateProfile({int? ftp, int? weight, String? name, String? email}) async {
    methodCalls.add('updateProfile');
    if (overrideUpdateProfile != null) {
      return overrideUpdateProfile!(ftp: ftp, weight: weight, name: name, email: email);
    }
    // Default: return updated user
    final user = User.create(
      id: 'fake-user-id',
      name: name ?? 'Fake User',
      email: email ?? 'fake@example.com',
      emailVerified: true,
      ftp: ftp ?? 200,
      weight: weight ?? 70,
    );
    return UpdateProfileResponse.create(success: true, user: user);
  }

  // Activity endpoint overrides

  Future<ActivitiesResponse> Function({String? timeline})? overrideActivities;

  @override
  Future<ActivitiesResponse> activities({String? timeline}) async {
    methodCalls.add('activities');
    if (overrideActivities != null) {
      return overrideActivities!(timeline: timeline);
    }
    // Default: return 3 sample activities
    return ActivitiesResponse.create(activities: _createSampleActivities());
  }

  /// Create sample activities for testing
  static List<Activity> _createSampleActivities() {
    final user = ActivityUser.create(id: 'user1', name: 'Pascal Welsch');

    return [
      // Activity 1: VO2max intervals
      Activity.create(
        id: 'activity1',
        createdAt: DateTime.now().subtract(const Duration(days: 1)).toIso8601String(),
        duration: 600000, // 10 minutes
        averagePower: 180.0,
        averageCadence: 85.0,
        averageHeartRate: 150.0,
        visibility: ActivityVisibility.public,
        user: user,
        workout: ActivityWorkout.fromData({
          'id': 'workout1',
          'title': 'VO2max Blaster',
          'slug': 'vo2max-blaster',
          'summary': '10 sets of 30/30 intervals at 142% FTP',
          'category': 'vo2max',
          'duration': 600000,
          'tss': 25,
          'starCount': 42,
          'plan': [
            {
              'id': 'interval1',
              'type': 'interval',
              'repeat': 10,
              'parts': [
                {'id': 'work', 'type': 'power', 'description': 'Work', 'duration': 30000, 'power': 1.42},
                {'id': 'recovery', 'type': 'power', 'description': 'Recovery', 'duration': 30000, 'power': 0.74},
              ],
            },
          ],
        }),
      ),

      // Activity 2: Sweet Spot (matches test expectations)
      Activity.create(
        id: 'activity2',
        createdAt: DateTime.now().subtract(const Duration(days: 2)).toIso8601String(),
        duration: 1800000, // 30 minutes
        averagePower: 210.0,
        averageCadence: 90.0,
        averageHeartRate: 145.0,
        visibility: ActivityVisibility.public,
        user: user,
        workout: ActivityWorkout.fromData({
          'id': 'workout2',
          'title': 'Sweet Spot Workout',
          'slug': 'sweet-spot-workout',
          'summary': '3 x 6 min at 90% FTP',
          'category': 'threshold',
          'duration': 1800000,
          'tss': 55,
          'starCount': 78,
          'plan': [
            {'id': 'warmup', 'type': 'power', 'description': 'Warm-up', 'duration': 300000, 'power': 0.6},
            {
              'id': 'main',
              'type': 'interval',
              'repeat': 3,
              'parts': [
                {'id': 'work', 'type': 'power', 'description': 'Sweet Spot', 'duration': 360000, 'power': 0.9},
                {'id': 'recovery', 'type': 'power', 'description': 'Recovery', 'duration': 120000, 'power': 0.6},
              ],
            },
            {'id': 'cooldown', 'type': 'power', 'description': 'Cool-down', 'duration': 300000, 'power': 0.5},
          ],
        }),
      ),

      // Activity 3: Endurance
      Activity.create(
        id: 'activity3',
        createdAt: DateTime.now().subtract(const Duration(days: 3)).toIso8601String(),
        duration: 3600000, // 60 minutes
        averagePower: 140.0,
        averageCadence: 80.0,
        averageHeartRate: 130.0,
        visibility: ActivityVisibility.public,
        user: user,
        workout: ActivityWorkout.fromData({
          'id': 'workout3',
          'title': 'Easy Endurance Ride',
          'slug': 'easy-endurance-ride',
          'summary': '60 minutes at 65% FTP',
          'category': 'endurance',
          'duration': 3600000,
          'tss': 45,
          'starCount': 156,
          'plan': [
            {'id': 'warmup', 'type': 'power', 'description': 'Warm-up', 'duration': 300000, 'power': 0.5},
            {'id': 'main', 'type': 'power', 'description': 'Endurance', 'duration': 2700000, 'power': 0.65},
            {'id': 'cooldown', 'type': 'power', 'description': 'Cool-down', 'duration': 600000, 'power': 0.5},
          ],
        }),
      ),
    ];
  }

  // Test helper methods

  /// Helper to create a fake JWT token for testing
  static AccessToken createFakeAccessToken(User user, {DateTime? expiryDate}) {
    final exp = expiryDate ?? DateTime.now().add(const Duration(hours: 6));
    final payload = {'user': user.rekord.asMap(), 'exp': exp.millisecondsSinceEpoch ~/ 1000};

    // Create a fake JWT (header.payload.signature)
    // This is not cryptographically valid but works for parsing in tests
    final header = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9'; // {"alg":"HS256","typ":"JWT"}
    final encodedPayload = base64UrlEncode(jsonEncode(payload));
    final signature = 'fake_signature';

    return AccessToken('$header.$encodedPayload.$signature');
  }

  static String base64UrlEncode(String input) {
    final bytes = utf8.encode(input);
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  /// Clear method call history
  void clearMethodCalls() {
    methodCalls.clear();
  }
}
