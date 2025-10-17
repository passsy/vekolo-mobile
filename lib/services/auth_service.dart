import 'dart:convert';

import 'package:clock/clock.dart' as clock;
import 'package:deep_pick/deep_pick.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:state_beacon/state_beacon.dart';
import 'package:vekolo/api/auth/redeem_code.dart';
import 'package:vekolo/api/vekolo_api_client.dart';
import 'package:vekolo/models/user.dart';

/// Service for managing authentication state and secure token storage
class AuthService {
  static const _accessTokenKey = 'access_token';
  static const _refreshTokenKey = 'refresh_token';

  final VekoloApiClient Function() apiClient;

  AuthService({required this.apiClient});

  final _storage = const FlutterSecureStorage();

  /// Signal for the current authenticated user (null if not authenticated)
  final currentUser = Beacon.writable<User?>(null);

  AuthInterceptor get apiInterceptor => AuthInterceptor(this);

  /// Save authentication tokens and user data
  Future<void> saveTokens({required AccessToken accessToken, required RefreshToken refreshToken}) async {
    final user = User.init.fromAccessToken(accessToken);
    currentUser.value = user;
    await _storage.write(key: _accessTokenKey, value: accessToken.jwt);
    await _storage.write(key: _refreshTokenKey, value: refreshToken.jwt);
  }

  /// Update stored access token (after refresh)
  Future<void> updateAccessToken(String accessToken) async {
    await _storage.write(key: _accessTokenKey, value: accessToken);
  }

  /// Get the stored access token
  Future<AccessToken?> getAccessToken() async {
    final jwt = await _storage.read(key: _accessTokenKey);
    if (jwt == null) return null;
    return AccessToken(jwt);
  }

  /// Get the stored refresh token
  Future<RefreshToken?> getRefreshToken() async {
    final jwt = await _storage.read(key: _refreshTokenKey);
    if (jwt == null) return null;
    return RefreshToken(jwt);
  }

  /// Get the stored user data
  Future<User?> getUser() async {
    final accessToken = await getAccessToken();
    if (accessToken == null) return null;

    try {
      return User.init.fromAccessToken(accessToken);
    } catch (e, stackTrace) {
      print('[AuthService] Failed to parse user data: $e');
      print(stackTrace);
      return null;
    }
  }

  /// Clear all stored authentication data (logout)
  Future<void> clearAuth() async {
    await _storage.deleteAll();
    currentUser.value = null;
  }

  /// Loads the user state which was persisted to storage
  Future<void> initialize() async {
    final user = await getUser();
    currentUser.value = user;
  }

  /// Update the current user data
  Future<void> updateUser(User user) async {
    currentUser.value = user;
  }
}

class AuthInterceptor extends Interceptor {
  final AuthService authService;

  AuthInterceptor(this.authService);

  @override
  // ignore: avoid_void_async
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final retry = options.extra['retry'] == true;
    final AccessToken? accessToken;
    try {
      accessToken = await authService.getAccessToken();
    } catch (e) {
      final dioException = DioException(requestOptions: options, message: 'Failed to retrieve access token: $e');
      handler.reject(dioException);
      return;
    }
    if (accessToken != null) {
      options.headers['Authorization'] = 'Bearer ${accessToken.jwt}';
    }
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) async {
    if (response.requestOptions.extra['retry'] == true) {
      // If this response is from a retried request, just pass it through
      handler.next(response);
      return;
    }

    if (response.statusCode == 401) {
      // parse error
      final responseBody = response.data;
      final errorCode = pick(responseBody, 'data', 'errorCode').asStringOrNull();
      if (errorCode == '612136') {
        // Attempt to refresh the token
        final refreshToken = await authService.getRefreshToken();
        try {
          if (refreshToken == null) {
            // No refresh token, clear auth state
            throw Exception('No refresh_token available.');
          } else {
            final secondResponse = await authService.apiClient().refreshToken(refreshToken: refreshToken.jwt);
            await authService.updateAccessToken(secondResponse.accessToken);

            // Retry the original request with the new access token
            final options = response.requestOptions;
            options.extra['retry'] = true;
            options.headers['Authorization'] = 'Bearer ${secondResponse.accessToken}';
            final clonedRequest = await authService.apiClient().context.dio.fetch(options);
            return handler.resolve(clonedRequest);
          }
        } catch (e) {
          // Refresh failed, clear auth state
          await authService.clearAuth();
        }
      }
    }
    handler.next(response);
  }

  @override
  // ignore: avoid_void_async
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode == 401) {
      // parse error
      final responseBody = err.response?.data;
      final errorCode = pick(responseBody, 'data', 'errorCode').asStringOrNull();
      if (errorCode == '612136') {
        // Attempt to refresh the token
        final refreshToken = await authService.getRefreshToken();
        try {
          if (refreshToken == null) {
            // No refresh token, clear auth state
            throw Exception('No refresh_token available.');
          } else {
            final response = await authService.apiClient().refreshToken(refreshToken: refreshToken.jwt);
            await authService.updateAccessToken(response.accessToken);

            // Retry the original request with the new access token
            final options = err.requestOptions;
            options.headers['Authorization'] = 'Bearer ${response.accessToken}';
            final clonedRequest = await authService.apiClient().context.dio.fetch(options);
            return handler.resolve(clonedRequest);
          }
        } catch (e) {
          // Refresh failed, clear auth state
          await authService.clearAuth();
        }
      }
    }
    handler.next(err);
  }
}
