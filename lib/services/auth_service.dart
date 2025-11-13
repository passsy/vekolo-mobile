import 'dart:convert';

import 'package:chirp/chirp.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:fresh_dio/fresh_dio.dart' hide RefreshToken;
import 'package:state_beacon/state_beacon.dart';
import 'package:vekolo/api/vekolo_api_client.dart';
import 'package:vekolo/models/user.dart';
import 'package:vekolo/services/fresh_auth.dart';

/// Token storage implementation using FlutterSecureStorage
class SecureTokenStorage extends TokenStorage<VekoloToken> {
  static const _tokenKey = 'oauth2_token';
  final _storage = const FlutterSecureStorage();

  @override
  Future<void> delete() async {
    await _storage.delete(key: _tokenKey);
  }

  @override
  Future<VekoloToken?> read() async {
    final json = await _storage.read(key: _tokenKey);
    if (json == null) return null;
    try {
      final data = jsonDecode(json) as Map<String, dynamic>;
      return VekoloToken(
        accessToken: AccessToken(data['accessToken'] as String),
        refreshToken: RefreshToken(data['refreshToken'] as String),
      );
    } catch (e, stackTrace) {
      chirp.error('Failed to parse token', error: e, stackTrace: stackTrace);
      return null;
    }
  }

  @override
  Future<void> write(VekoloToken token) async {
    final json = jsonEncode({'accessToken': token.accessToken, 'refreshToken': token.refreshToken});
    await _storage.write(key: _tokenKey, value: json);
  }
}

/// Service for managing authentication state and secure token storage
class AuthService {
  AuthService({required this.fresh, required VekoloApiClient Function() this.apiClient})
    : authenticationStatus = Beacon.streamRaw(
        () => fresh.authenticationStatus,
        initialValue: AuthenticationStatus.initial,
      );

  final Fresh<VekoloToken> fresh;

  final VekoloApiClient Function() apiClient;

  /// Get the Fresh interceptor for Dio (for authenticated requests only)
  Interceptor get apiInterceptor => fresh;

  /// Signal for the current authenticated user (null if not authenticated)
  final currentUser = Beacon.writable<User?>(null);

  final ReadableBeacon<AuthenticationStatus> authenticationStatus;

  /// Loads the user state which was persisted to storage
  Future<void> initialize() async {
    final user = await getUser();
    currentUser.value = user;
  }

  /// Refresh the access token using the stored refresh token
  ///
  /// This also refreshes the current user data, which are part of the access token (JWT)
  Future<void> refreshAccessToken() async {
    final refreshToken = await getRefreshToken();
    if (refreshToken == null) {
      throw Exception('No refresh token available');
    }
    final response = await apiClient().refreshToken(refreshToken: refreshToken);
    await saveTokens(accessToken: response.accessToken, refreshToken: refreshToken);
  }

  /// Save authentication tokens and user data
  Future<void> saveTokens({required AccessToken accessToken, required RefreshToken refreshToken}) async {
    final user = User.init.fromAccessToken(accessToken);
    currentUser.value = user;

    // Save to fresh's token storage
    await fresh.setToken(VekoloToken(accessToken: accessToken, refreshToken: refreshToken));
  }

  /// Get the stored access token
  Future<AccessToken?> getAccessToken() async {
    final token = await fresh.token;
    if (token == null) return null;
    return AccessToken(token.accessToken);
  }

  /// Get the stored refresh token
  Future<RefreshToken?> getRefreshToken() async {
    final token = await fresh.token;
    if (token == null) return null;
    return RefreshToken(token.refreshToken ?? '');
  }

  /// Get the stored user data
  Future<User?> getUser() async {
    final accessToken = await getAccessToken();
    if (accessToken == null) return null;

    try {
      return User.init.fromAccessToken(accessToken);
    } catch (e, stackTrace) {
      chirp.error('Failed to parse user data', error: e, stackTrace: stackTrace);
      return null;
    }
  }

  /// Clear all stored authentication data (logout)
  Future<void> clearAuth() async {
    await fresh.setToken(null);
    currentUser.value = null;
  }

  /// Update the current user data
  Future<void> updateUser(User user) async {
    currentUser.value = user;
  }

  void dispose() {
    fresh.close();
    currentUser.dispose();
  }
}
