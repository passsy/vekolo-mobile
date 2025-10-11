import 'package:dio/dio.dart';
import 'package:vekolo/models/rekord.dart';
import 'dart:developer' as developer;

/// Refresh an access token
///
/// Gets a new access token when the current one expires.
///
/// Throws [DioException] if refresh token is invalid or expired (status 401)
Future<RefreshTokenResponse> postRefreshToken(Dio dio, {required String refreshToken}) async {
  try {
    final response = await dio.post(
      '/auth/token/refresh',
      data: {'refreshToken': refreshToken},
      options: Options(contentType: Headers.jsonContentType),
    );

    if (response.statusCode == 401) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        message: 'Invalid or expired refresh token',
      );
    }

    return RefreshTokenResponse.fromData(response.data as Map<String, Object?>);
  } catch (e, stackTrace) {
    developer.log('Failed to refresh token', error: e, stackTrace: stackTrace);
    rethrow;
  }
}

/// Response containing a new access token
class RefreshTokenResponse with RekordMixin {
  RefreshTokenResponse.fromData(Map<String, Object?> data) : rekord = Rekord(data);

  factory RefreshTokenResponse.create({bool? success, String? accessToken}) {
    return RefreshTokenResponse.fromData({
      if (success != null) 'success': success,
      if (accessToken != null) 'accessToken': accessToken,
    });
  }

  @override
  final Rekord rekord;
  static final init = RefreshTokenResponseInit();

  bool get success => rekord.read('success').asBoolOrThrow();

  /// New JWT access token (12h validity)
  String get accessToken => rekord.read('accessToken').asStringOrThrow();

  @override
  String toString() => 'RefreshTokenResponse(success: $success)';
}

class RefreshTokenResponseInit {}
