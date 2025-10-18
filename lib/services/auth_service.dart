import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:fresh_dio/fresh_dio.dart';
import 'package:state_beacon/state_beacon.dart';
import 'package:vekolo/api/vekolo_api_client.dart' as vekolo;
import 'package:vekolo/models/user.dart';

/// Token storage implementation using FlutterSecureStorage
class SecureTokenStorage extends TokenStorage<OAuth2Token> {
  static const _tokenKey = 'oauth2_token';
  final _storage = const FlutterSecureStorage();

  @override
  Future<void> delete() async {
    await _storage.delete(key: _tokenKey);
  }

  @override
  Future<OAuth2Token?> read() async {
    final json = await _storage.read(key: _tokenKey);
    if (json == null) return null;
    try {
      final data = jsonDecode(json) as Map<String, dynamic>;
      return OAuth2Token(accessToken: data['accessToken'] as String, refreshToken: data['refreshToken'] as String?);
    } catch (e, stackTrace) {
      print('[SecureTokenStorage] Failed to parse token: $e');
      print(stackTrace);
      return null;
    }
  }

  @override
  Future<void> write(OAuth2Token token) async {
    final json = jsonEncode({'accessToken': token.accessToken, 'refreshToken': token.refreshToken});
    await _storage.write(key: _tokenKey, value: json);
  }
}

/// Service for managing authentication state and secure token storage
class AuthService {
  AuthService({required this.fresh});

  final Fresh<OAuth2Token> fresh;

  /// Get the Fresh interceptor for Dio (for authenticated requests only)
  Interceptor get apiInterceptor => fresh;

  /// Signal for the current authenticated user (null if not authenticated)
  final currentUser = Beacon.writable<User?>(null);

  late final ReadableBeacon<AuthenticationStatus> authenticationStatus = Beacon.streamRaw(
    () => fresh.authenticationStatus,
  );

  /// Loads the user state which was persisted to storage
  Future<void> initialize() async {
    final user = await getUser();
    currentUser.value = user;
  }

  /// Save authentication tokens and user data
  Future<void> saveTokens({required vekolo.AccessToken accessToken, required vekolo.RefreshToken refreshToken}) async {
    final user = User.init.fromAccessToken(accessToken);
    currentUser.value = user;

    // Save to fresh's token storage
    await fresh.setToken(OAuth2Token(accessToken: accessToken.jwt, refreshToken: refreshToken.jwt));
  }

  /// Get the stored access token
  Future<vekolo.AccessToken?> getAccessToken() async {
    final token = await fresh.token;
    if (token == null) return null;
    return vekolo.AccessToken(token.accessToken);
  }

  /// Get the stored refresh token
  Future<vekolo.RefreshToken?> getRefreshToken() async {
    final token = await fresh.token;
    if (token == null) return null;
    return vekolo.RefreshToken(token.refreshToken ?? '');
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
