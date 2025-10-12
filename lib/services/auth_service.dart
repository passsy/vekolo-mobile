import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:state_beacon/state_beacon.dart';
import 'package:vekolo/models/user.dart';

/// Service for managing authentication state and secure token storage
class AuthService {
  static const _accessTokenKey = 'access_token';
  static const _refreshTokenKey = 'refresh_token';
  static const _userKey = 'user';

  final _storage = const FlutterSecureStorage();

  /// Signal for the current authenticated user (null if not authenticated)
  final currentUser = Beacon.writable<User?>(null);

  /// Save authentication tokens and user data
  Future<void> saveTokens({required String accessToken, required String refreshToken, required User user}) async {
    await Future.wait([
      _storage.write(key: _accessTokenKey, value: accessToken),
      _storage.write(key: _refreshTokenKey, value: refreshToken),
      _storage.write(key: _userKey, value: jsonEncode(user.toJson())),
    ]);
    // Update signal
    currentUser.value = user;
  }

  /// Get the stored access token
  Future<String?> getAccessToken() async {
    return await _storage.read(key: _accessTokenKey);
  }

  /// Get the stored refresh token
  Future<String?> getRefreshToken() async {
    return await _storage.read(key: _refreshTokenKey);
  }

  /// Get the stored user data
  Future<User?> getUser() async {
    final userJson = await _storage.read(key: _userKey);
    if (userJson == null) return null;

    try {
      final data = jsonDecode(userJson) as Map<String, dynamic>;
      return User.fromData(data);
    } catch (e, stackTrace) {
      print('[AuthService] Failed to parse user data: $e');
      print(stackTrace);
      return null;
    }
  }

  /// Check if user is authenticated (has tokens)
  Future<bool> isAuthenticated() async {
    final accessToken = await getAccessToken();
    final refreshToken = await getRefreshToken();
    return accessToken != null && refreshToken != null;
  }

  /// Clear all stored authentication data (logout)
  Future<void> clearAuth() async {
    await _storage.deleteAll();
    // Update signal
    currentUser.value = null;
  }

  /// Initialize auth state from storage (call on app startup)
  Future<void> initialize() async {
    final user = await getUser();
    currentUser.value = user;
  }

  /// Update stored access token (after refresh)
  Future<void> updateAccessToken(String accessToken) async {
    await _storage.write(key: _accessTokenKey, value: accessToken);
  }

  /// Update stored user data and signal
  Future<void> updateUser(User user) async {
    await _storage.write(key: _userKey, value: jsonEncode(user.toJson()));
    currentUser.value = user;
  }
}
