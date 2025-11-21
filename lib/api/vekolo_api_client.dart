import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:fresh_dio/fresh_dio.dart' show Fresh;
import 'package:vekolo/api/activities/get_activities.dart';
import 'package:vekolo/api/activities/upload_activity.dart';
import 'package:vekolo/api/api_context.dart';
import 'package:vekolo/domain/models/workout_session.dart';
import 'package:vekolo/models/activity.dart';
import 'package:vekolo/api/auth/redeem_code.dart';
import 'package:vekolo/api/auth/refresh_token.dart';
import 'package:vekolo/api/auth/request_login_code.dart';
import 'package:vekolo/api/auth/request_signup_code.dart';
import 'package:vekolo/api/auth/revoke_token.dart';
import 'package:vekolo/api/user/update_profile.dart';
import 'package:vekolo/api/workouts/get_workout.dart';

export 'package:vekolo/api/activities/get_activities.dart';
export 'package:vekolo/api/activities/upload_activity.dart';
export 'package:vekolo/api/auth/redeem_code.dart';
export 'package:vekolo/api/auth/refresh_token.dart';
export 'package:vekolo/api/auth/request_login_code.dart';
export 'package:vekolo/api/auth/request_signup_code.dart';
export 'package:vekolo/api/auth/revoke_token.dart';
export 'package:vekolo/api/user/update_profile.dart';
export 'package:vekolo/api/workouts/get_workout.dart';

/// Stateless API client for Vekolo backend
///
/// This client does not manage tokens or state internally.
/// Tokens should be managed externally via the tokenProvider callback.
///
/// Each endpoint is implemented in its own file following the pattern:
/// - lib/api/auth/request_signup_code.dart
/// - lib/api/auth/request_login_code.dart
/// - lib/api/auth/redeem_code.dart
/// - lib/api/auth/refresh_token.dart
/// - lib/api/auth/revoke_token.dart
class VekoloApiClient {
  final String baseUrl;

  VekoloApiClient({required this.baseUrl, List<Interceptor> interceptors = const []}) {
    // Create authenticated Dio instance (with all interceptors including auth)
    final Dio authenticatedDio = Dio();
    authenticatedDio.options.baseUrl = baseUrl;
    authenticatedDio.options.validateStatus = (status) => status != null && status < 500;
    authenticatedDio.interceptors.addAll(interceptors);

    // Create public Dio instance (without auth interceptor)
    // Only includes non-auth interceptors (logging, error handling, etc.)
    final Dio publicDio = Dio();
    publicDio.options.baseUrl = baseUrl;
    publicDio.options.validateStatus = (status) => status != null && status < 500;
    // Add all interceptors except auth-related ones
    publicDio.interceptors.addAll(interceptors.where((it) => it is! Fresh));

    _context = ApiContext(authDio: authenticatedDio, publicDio: publicDio);
  }

  late final ApiContext _context;

  /// Internal context for API requests - not part of the public API
  @visibleForTesting
  ApiContext get context => _context;

  // Auth endpoints

  /// Request a magic code for signup
  ///
  /// `POST /auth/code/request`
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
  }) {
    return postRequestSignupCode(
      _context,
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

  /// Request a magic code for login
  ///
  /// `POST /auth/code/request`
  Future<CodeRequestResponse> requestLoginCode({required String email}) {
    return postRequestLoginCode(_context, email: email);
  }

  /// Redeem a magic code for JWT tokens
  ///
  /// `POST /auth/token/redeem`
  Future<TokenResponse> redeemCode({required String email, required String code, String? deviceInfo}) {
    return postRedeemCode(_context, email: email, code: code, deviceInfo: deviceInfo);
  }

  /// Refresh an access token
  ///
  /// `POST /auth/token/refresh`
  Future<RefreshTokenResponse> refreshToken({required RefreshToken refreshToken}) {
    return postRefreshToken(_context, refreshToken: refreshToken);
  }

  /// Revoke a refresh token (logout)
  ///
  /// `POST /auth/token/revoke`
  Future<RevokeTokenResponse> revokeToken({required RefreshToken refreshToken}) {
    return postRevokeToken(_context, refreshToken: refreshToken);
  }

  // User endpoints

  /// Update user profile
  ///
  /// `POST /api/user/update`
  Future<UpdateProfileResponse> updateProfile({int? ftp, int? weight, String? name, String? email}) {
    return postUpdateProfile(_context, ftp: ftp, weight: weight, name: name, email: email);
  }

  // Activity endpoints

  /// Get activities
  ///
  /// `GET /api/activities`
  ///
  /// Fetches activities based on the timeline filter:
  /// - `null` or 'public': Public activities only
  /// - 'mixed': Public activities + user's private activities (requires auth)
  /// - 'mine': Only user's activities (requires auth)
  Future<ActivitiesResponse> activities({String? timeline}) {
    return getActivities(_context, timeline: timeline);
  }

  /// Upload a completed workout session as an activity
  ///
  /// `POST /api/activities`
  ///
  /// Converts a local WorkoutSession to an Activity on the server.
  /// The server calculates all metrics (averages, totals) from the samples.
  Future<UploadActivityResponse> uploadActivity({
    required WorkoutSessionMetadata metadata,
    required List<WorkoutSample> samples,
    ActivityVisibility visibility = ActivityVisibility.public,
  }) {
    return postUploadActivity(
      _context,
      metadata: metadata,
      samples: samples,
      visibility: visibility,
    );
  }

  // Workout endpoints

  /// Get a workout by ID or slug
  ///
  /// `GET /api/workouts/:slug`
  ///
  /// Returns the workout details including the workout plan.
  /// Results are cached in memory by default. Set [useCache] to false to bypass the cache.
  Future<GetWorkoutResponse> workout({required String slug, bool useCache = true}) {
    return getWorkout(_context, slug: slug, useCache: useCache);
  }
}
