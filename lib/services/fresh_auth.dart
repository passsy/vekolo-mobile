import 'dart:developer' as developer;

import 'package:deep_pick/deep_pick.dart';
import 'package:fresh_dio/fresh_dio.dart';
import 'package:vekolo/api/vekolo_api_client.dart';
import 'package:vekolo/services/auth_service.dart';

/// Creates a Fresh OAuth2 instance configured for Vekolo API
Fresh<OAuth2Token> createFreshAuth({required VekoloApiClient Function() apiClient}) {
  return Fresh.oAuth2(
    tokenStorage: SecureTokenStorage(),
    refreshToken: (token, httpClient) async {
      // TODO refreshToken() should also return a new refreshToken
      final response = await apiClient().refreshToken(refreshToken: token!.refreshToken!);
      return OAuth2Token(accessToken: response.accessToken, refreshToken: token.refreshToken);
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
        developer.log('[Fresh] Error checking shouldRefresh: $e');
      }
      return false;
    },
    tokenHeader: (token) {
      return {'Authorization': 'Bearer ${token.accessToken}'};
    },
  );
}
