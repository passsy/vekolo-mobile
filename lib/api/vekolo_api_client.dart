import 'package:dio/dio.dart';
import 'package:vekolo/api/api_context.dart';
import 'package:vekolo/api/auth/redeem_code.dart';
import 'package:vekolo/api/auth/refresh_token.dart';
import 'package:vekolo/api/auth/request_login_code.dart';
import 'package:vekolo/api/auth/request_signup_code.dart';
import 'package:vekolo/api/auth/revoke_token.dart';
import 'package:vekolo/api/pretty_log_interceptor.dart';
import 'package:vekolo/api/user/update_profile.dart';

export 'package:vekolo/api/auth/redeem_code.dart';
export 'package:vekolo/api/auth/refresh_token.dart';
export 'package:vekolo/api/auth/request_login_code.dart';
export 'package:vekolo/api/auth/request_signup_code.dart';
export 'package:vekolo/api/auth/revoke_token.dart';
export 'package:vekolo/api/user/update_profile.dart';

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
  final Dio _dio;
  late final ApiContext _apiContext;

  VekoloApiClient({
    required this.baseUrl,
    Dio? dio,
    bool enableLogging = true,
    Future<String?> Function()? tokenProvider,
  }) : _dio = dio ?? Dio() {
    // Create ApiContext with the same Dio instance
    _apiContext = ApiContext(dio: _dio, getAccessToken: tokenProvider ?? () async => null);

    _dio.options.baseUrl = baseUrl;
    _dio.options.validateStatus = (status) => status != null && status < 500;

    // Add pretty logging interceptor for debugging
    if (enableLogging) {
      _dio.interceptors.add(PrettyLogInterceptor());
    }
  }

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
  }) {
    return postRequestSignupCode(_apiContext, email: email, name: name, sex: sex, weight: weight, ftp: ftp);
  }

  /// Request a magic code for login
  ///
  /// `POST /auth/code/request`
  Future<CodeRequestResponse> requestLoginCode({required String email}) {
    return postRequestLoginCode(_apiContext, email: email);
  }

  /// Redeem a magic code for JWT tokens
  ///
  /// `POST /auth/token/redeem`
  Future<TokenResponse> redeemCode({required String email, required String code, String? deviceInfo}) {
    return postRedeemCode(_apiContext, email: email, code: code, deviceInfo: deviceInfo);
  }

  /// Refresh an access token
  ///
  /// `POST /auth/token/refresh`
  Future<RefreshTokenResponse> refreshToken({required String refreshToken}) {
    return postRefreshToken(_apiContext, refreshToken: refreshToken);
  }

  /// Revoke a refresh token (logout)
  ///
  /// `POST /auth/token/revoke`
  Future<RevokeTokenResponse> revokeToken({required String refreshToken}) {
    return postRevokeToken(_apiContext, refreshToken: refreshToken);
  }

  // User endpoints

  /// Update user profile
  ///
  /// `POST /api/user/update`
  Future<UpdateProfileResponse> updateProfile({int? ftp, int? weight, String? name, String? email}) {
    return postUpdateProfile(_apiContext, ftp: ftp, weight: weight, name: name, email: email);
  }
}
