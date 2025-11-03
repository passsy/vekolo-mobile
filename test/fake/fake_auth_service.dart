import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:fresh_dio/fresh_dio.dart' hide RefreshToken;
import 'package:state_beacon/state_beacon.dart';
import 'package:vekolo/api/vekolo_api_client.dart';
import 'package:vekolo/models/user.dart';
import 'package:vekolo/services/auth_service.dart';
import 'package:vekolo/services/fresh_auth.dart';

/// No-op interceptor for fake auth service
class _FakeAuthInterceptor extends Interceptor {}

/// In-memory fake implementation of [AuthService] for testing
///
/// This fake maintains in-memory state that can be inspected during debugging,
/// making it easier to understand test failures compared to mocks.
class FakeAuthService implements AuthService {
  FakeAuthService({
    AccessToken? initialAccessToken,
    RefreshToken? initialRefreshToken,
    User? initialUser,
    AuthenticationStatus initialAuthStatus = AuthenticationStatus.initial,
  }) : _accessToken = initialAccessToken,
       _refreshToken = initialRefreshToken {
    _currentUser.value = initialUser;
    _authenticationStatus.value = initialAuthStatus;
  }

  // In-memory token storage
  AccessToken? _accessToken;
  RefreshToken? _refreshToken;

  // Reactive state
  final _currentUser = Beacon.writable<User?>(null);
  final _authenticationStatus = Beacon.writable(AuthenticationStatus.initial);

  // Call tracking (optional, but useful for verifying behavior in tests)
  final List<String> methodCalls = [];

  // Cached no-op interceptor instance
  late final _apiInterceptor = _FakeAuthInterceptor();

  @override
  WritableBeacon<User?> get currentUser => _currentUser;

  @override
  ReadableBeacon<AuthenticationStatus> get authenticationStatus => _authenticationStatus;

  @override
  Future<void> initialize() async {
    methodCalls.add('initialize');
    final user = await getUser();
    _currentUser.value = user;

    if (user != null) {
      _authenticationStatus.value = AuthenticationStatus.authenticated;
    } else {
      _authenticationStatus.value = AuthenticationStatus.unauthenticated;
    }
  }

  @override
  Future<void> saveTokens({required AccessToken accessToken, required RefreshToken refreshToken}) async {
    methodCalls.add('saveTokens');
    _accessToken = accessToken;
    _refreshToken = refreshToken;

    final user = User.init.fromAccessToken(accessToken);
    _currentUser.value = user;
    _authenticationStatus.value = AuthenticationStatus.authenticated;
  }

  @override
  Future<AccessToken?> getAccessToken() async {
    methodCalls.add('getAccessToken');
    return _accessToken;
  }

  @override
  Future<RefreshToken?> getRefreshToken() async {
    methodCalls.add('getRefreshToken');
    return _refreshToken;
  }

  @override
  Future<User?> getUser() async {
    methodCalls.add('getUser');
    if (_accessToken == null) return null;

    try {
      return User.init.fromAccessToken(_accessToken!);
    } catch (e, stackTrace) {
      print('[FakeAuthService] Failed to parse user data: $e');
      print(stackTrace);
      return null;
    }
  }

  @override
  Future<void> clearAuth() async {
    methodCalls.add('clearAuth');
    _accessToken = null;
    _refreshToken = null;
    _currentUser.value = null;
    _authenticationStatus.value = AuthenticationStatus.unauthenticated;
  }

  @override
  Future<void> updateUser(User user) async {
    methodCalls.add('updateUser');
    _currentUser.value = user;
  }

  @override
  Future<void> refreshAccessToken() async {
    methodCalls.add('refreshAccessToken');
    if (_refreshToken == null) {
      throw Exception('No refresh token available');
    }
    // In a real fake, you might want to generate a new token here
    // For now, we keep the existing token
  }

  @override
  void dispose() {
    methodCalls.add('dispose');
    _currentUser.dispose();
    _authenticationStatus.dispose();
  }

  // Test helper methods

  /// Helper to create a fake JWT token for testing
  static AccessToken createFakeAccessToken(User user, {DateTime? expiryDate}) {
    final exp = expiryDate ?? DateTime.now().add(const Duration(hours: 6));
    final payload = {'user': user.rekord.asMap(), 'exp': exp.millisecondsSinceEpoch ~/ 1000};

    // Create a fake JWT (header.payload.signature)
    // This is not cryptographically valid but works for parsing in tests
    final header = base64Url.encode(utf8.encode(jsonEncode({'alg': 'HS256', 'typ': 'JWT'})));
    final encodedPayload = base64Url.encode(utf8.encode(jsonEncode(payload)));
    final signature = 'fake_signature';

    return AccessToken('$header.$encodedPayload.$signature');
  }

  /// Clear method call history
  void clearMethodCalls() {
    methodCalls.clear();
  }

  // Properties not directly exposed by AuthService but needed for interface compatibility
  // These return no-op implementations since they're not used in typical tests

  @override
  VekoloApiClient Function() get apiClient => throw UnimplementedError('apiClient not implemented in FakeAuthService');

  @override
  Interceptor get apiInterceptor => _apiInterceptor;

  @override
  Fresh<VekoloToken> get fresh => throw UnimplementedError('fresh not implemented in FakeAuthService');
}
