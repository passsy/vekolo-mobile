import 'package:vekolo/app/logger.dart';

import 'package:clock/clock.dart';
import 'package:deep_pick/deep_pick.dart';
import 'package:fresh_dio/fresh_dio.dart' hide RefreshToken;
import 'package:vekolo/api/vekolo_api_client.dart';
import 'package:vekolo/services/auth_service.dart';

/// Creates a Fresh OAuth2 instance configured for Vekolo API
Fresh<VekoloToken> createFreshAuth({required VekoloApiClient Function() apiClient}) {
  return Fresh.oAuth2<VekoloToken>(
    tokenStorage: SecureTokenStorage(),
    refreshToken: (token, httpClient) async {
      final response = await apiClient().refreshToken(refreshToken: token!.typedRefreshToken);
      return VekoloToken(accessToken: response.accessToken, refreshToken: token.typedRefreshToken);
    },
    shouldRefreshBeforeRequest: (options, VekoloToken? token) {
      final refreshTime = Clock().fromNow(minutes: 1);
      if (token != null) {
        final accessToken = AccessToken(token.accessToken);

        final exp = accessToken.expiryDate;
        if (exp.isBefore(refreshTime)) {
          return true;
        }
      }
      final expiresAt = token?.expiresAt;
      if (expiresAt != null) {
        if (expiresAt.isBefore(refreshTime)) {
          return true;
        }
      }
      return false;
    },
    shouldRefresh: (response) {
      try {
        // Check for token expiration error code
        if (response?.statusCode == 401) {
          final errorCode = pick(response?.data, 'data', 'errorCode').asStringOrNull();
          if (errorCode == '612136') {
            return true;
          }
        }
      } catch (e) {
        _FreshAuthLogger().logClass('Error checking shouldRefresh: $e');
      }
      return false;
    },
    tokenHeader: (token) {
      return {'Authorization': 'Bearer ${token.accessToken}'};
    },
  );
}

class VekoloToken extends Token {
  VekoloToken({required AccessToken accessToken, required RefreshToken refreshToken})
    : typedAccessToken = accessToken,
      typedRefreshToken = refreshToken,
      super(accessToken: accessToken.jwt, refreshToken: refreshToken?.value);

  final AccessToken typedAccessToken;

  final RefreshToken typedRefreshToken;

  @override
  String get tokenType => 'Bearer';

  @override
  DateTime get expiresAt {
    return typedAccessToken.expiryDate;
  }
}

/// Helper class to provide context for logging in top-level functions
class _FreshAuthLogger {
  @override
  String toString() => 'FreshAuth';
}
