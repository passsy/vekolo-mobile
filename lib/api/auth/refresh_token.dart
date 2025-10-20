import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:fresh_dio/fresh_dio.dart';
import 'package:vekolo/api/api_context.dart';
import 'package:vekolo/api/vekolo_api_client.dart';
import 'package:vekolo/models/rekord.dart';
import 'package:vekolo/models/user.dart';

/// Refresh an access token
///
/// Gets a new access token when the current one expires.
///
/// Throws [DioException] if refresh token is invalid or expired (status 401)
Future<RefreshTokenResponse> postRefreshToken(ApiContext context, {required RefreshToken refreshToken}) async {
  final response = await context.publicDio.post(
    '/auth/token/refresh',
    data: {'refreshToken': refreshToken.value},
    options: Options(
      contentType: Headers.jsonContentType,
      headers: {
        'Accept': ['application/json'],
      },
    ),
  );

  if (response.statusCode == 401) {
    // {
    //   "error" : true,
    //   "url" : "https://vekolo-development.up.railway.app/auth/token/refresh",
    //   "statusCode" : 401,
    //   "statusMessage" : "Invalid or expired refresh token",
    //   "message" : "Invalid or expired refresh token",
    //   "data" : {
    //     "errorCode" : "915205"
    //   }
    // }
    final errorCode = pick(response.data, 'data', 'errorCode').asStringOrNull();
    if (errorCode == '915205') {
      // notify fresh that the token is revoked/expired
      // causes a forced logout
      throw RevokeTokenException();
    }
  }

  return RefreshTokenResponse.init.fromResponse(response);
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

  /// New JWT access token (6h validity)
  AccessToken get accessToken => rekord.read('accessToken').letOrThrow((it) => AccessToken(it.asStringOrThrow()));

  @override
  String toString() => 'RefreshTokenResponse(success: $success)';
}

class RefreshTokenResponseInit {}

extension RefreshTokenResponseInitExt on RefreshTokenResponseInit {
  RefreshTokenResponse fromResponse(Response response) {
    return RefreshTokenResponse.fromData(response.data as Map<String, Object?>);
  }
}

extension type AccessToken(String jwt) {
  /// Decode JWT payload without verification
  Map<String, dynamic> decode() {
    final parts = jwt.split('.');
    if (parts.length != 3) {
      throw FormatException('Invalid JWT token format');
    }

    // Decode the payload (middle part)
    final payload = parts[1];
    // Add padding if needed for base64 decoding
    final normalized = base64Url.normalize(payload);
    final decoded = utf8.decode(base64Url.decode(normalized));
    return jsonDecode(decoded) as Map<String, dynamic>;
  }

  /// might be moved into a separate id token later
  User parseUser() {
    return User.init.fromAccessToken(this);
  }

  DateTime get expiryDate {
    final payload = decode();
    final exp = payload['exp'];
    if (exp is int) {
      return DateTime.fromMillisecondsSinceEpoch(exp * 1000);
    }
    throw FormatException('Invalid or missing exp claim in JWT token');
  }
}

extension type const RefreshToken(String value) {}
