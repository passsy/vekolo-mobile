import 'package:dio/dio.dart';
import 'package:vekolo/models/rekord.dart';
import 'package:vekolo/models/user.dart';
import 'dart:developer' as developer;

/// Redeem a magic code for JWT tokens
///
/// Exchanges the 6-digit code for access and refresh tokens.
///
/// Throws [DioException] if code is invalid or expired (status 400)
Future<TokenResponse> postRedeemCode(Dio dio, {required String email, required String code, String? deviceInfo}) async {
  try {
    final response = await dio.post(
      '/auth/token/redeem',
      data: {'email': email, 'code': code, if (deviceInfo != null) 'deviceInfo': deviceInfo},
      options: Options(contentType: Headers.jsonContentType),
    );

    if (response.statusCode == 400) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        message: 'Invalid or expired magic code',
      );
    }

    return TokenResponse.fromData(response.data as Map<String, Object?>);
  } catch (e, stackTrace) {
    developer.log('Failed to redeem code', error: e, stackTrace: stackTrace);
    rethrow;
  }
}

/// Response containing JWT tokens and user data
class TokenResponse with RekordMixin {
  TokenResponse.fromData(Map<String, Object?> data) : rekord = Rekord(data);

  factory TokenResponse.create({bool? success, String? accessToken, String? refreshToken, User? user}) {
    return TokenResponse.fromData({
      if (success != null) 'success': success,
      if (accessToken != null) 'accessToken': accessToken,
      if (refreshToken != null) 'refreshToken': refreshToken,
      if (user != null) 'user': user,
    });
  }

  @override
  final Rekord rekord;
  static final init = TokenResponseInit();

  bool get success => rekord.read('success').asBoolOrThrow();

  /// JWT access token (12h validity)
  String get accessToken => rekord.read('accessToken').asStringOrThrow();

  /// Long-lived refresh token (6 months)
  String get refreshToken => rekord.read('refreshToken').asStringOrThrow();

  /// User data from the token
  User get user => rekord.read('user').letOrThrow((pick) => User.fromData(pick.asMapOrThrow<String, Object?>()));

  @override
  String toString() => 'TokenResponse(success: $success, user: ${user.name})';
}

class TokenResponseInit {}
