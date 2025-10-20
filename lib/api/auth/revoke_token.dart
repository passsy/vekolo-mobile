import 'package:dio/dio.dart';
import 'package:vekolo/api/api_context.dart';
import 'package:vekolo/api/vekolo_api_client.dart';
import 'package:vekolo/models/rekord.dart';

/// Revoke a refresh token (logout)
///
/// Invalidates the refresh token on the server.
///
/// Note: Even if this fails, local tokens should still be cleared.
Future<RevokeTokenResponse> postRevokeToken(ApiContext context, {required RefreshToken refreshToken}) async {
  final response = await context.publicDio.post(
    '/auth/token/revoke',
    data: {'refreshToken': refreshToken.value},
    options: Options(contentType: Headers.jsonContentType),
  );

  return RevokeTokenResponse.init.fromResponse(response);
}

/// Response for token revocation
class RevokeTokenResponse with RekordMixin {
  RevokeTokenResponse.fromData(Map<String, Object?> data) : rekord = Rekord(data);

  factory RevokeTokenResponse.create({bool? success, String? message}) {
    return RevokeTokenResponse.fromData({
      if (success != null) 'success': success,
      if (message != null) 'message': message,
    });
  }

  @override
  final Rekord rekord;
  static final init = RevokeTokenResponseInit();

  /// True if the token was successfully revoked
  bool get success => rekord.read('success').asBoolOrThrow();

  /// Descriptive message about the revocation result
  String get message => rekord.read('message').asStringOrThrow();

  @override
  String toString() => 'RevokeTokenResponse(success: $success, message: $message)';
}

class RevokeTokenResponseInit {}

extension RevokeTokenResponseInitExt on RevokeTokenResponseInit {
  RevokeTokenResponse fromResponse(Response response) {
    return RevokeTokenResponse.fromData(response.data as Map<String, Object?>);
  }
}
