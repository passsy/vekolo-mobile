import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:vekolo/api/api_context.dart';
import 'package:vekolo/models/rekord.dart';
import 'package:vekolo/models/user.dart';
import 'package:clock/clock.dart';

/// Redeem a magic code for JWT tokens
///
/// Exchanges the 6-digit code for access and refresh tokens.
///
/// Throws [DioException] if code is invalid or expired (status 400)
Future<TokenResponse> postRedeemCode(
  ApiContext context, {
  required String email,
  required String code,
  String? deviceInfo,
}) async {
  final response = await context.dio.post(
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

  return TokenResponse.init.fromResponse(response);
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

  /// JWT access token (6h validity)
  AccessToken get accessToken => AccessToken(rekord.read('accessToken').asStringOrThrow());

  /// Long-lived refresh token (6 months)
  RefreshToken get refreshToken => RefreshToken(rekord.read('refreshToken').asStringOrThrow());

  @override
  String toString() => 'TokenResponse(success: $success, user: ${accessToken.decode()})';
}

class TokenResponseInit {}

extension TokenResponseInitExt on TokenResponseInit {
  TokenResponse fromResponse(Response response) {
    return TokenResponse.fromData(response.data as Map<String, Object?>);
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

extension type RefreshToken(String jwt) {}
