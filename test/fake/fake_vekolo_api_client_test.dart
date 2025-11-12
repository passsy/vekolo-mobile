import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vekolo/api/vekolo_api_client.dart';
import 'package:vekolo/models/user.dart';

import 'fake_vekolo_api_client.dart';

void main() {
  group('FakeVekoloApiClient', () {
    late FakeVekoloApiClient apiClient;

    setUp(() {
      apiClient = FakeVekoloApiClient();
    });

    group('requestSignupCode', () {
      test('returns success by default', () async {
        final response = await apiClient.requestSignupCode(email: 'test@example.com', name: 'Test User');

        expect(response.success, isTrue);
        expect(response.userExists, isFalse);
        expect(response.rateLimited, isFalse);
        expect(apiClient.methodCalls, contains('requestSignupCode'));
      });

      test('can override to return rate limited', () async {
        apiClient.overrideRequestSignupCode = ({
          required email,
          name,
          sex,
          weight,
          ftp,
          athleteLevel,
          athleteType,
          birthday,
          height,
          measurementPreference,
          newsletter,
        }) async {
          return CodeRequestResponse.create(
            success: false,
            userExists: false,
            rateLimited: true,
            message: 'Too many requests',
          );
        };

        final response = await apiClient.requestSignupCode(email: 'test@example.com');

        expect(response.success, isFalse);
        expect(response.rateLimited, isTrue);
        expect(response.message, equals('Too many requests'));
      });

      test('can override to throw exception', () {
        apiClient.overrideRequestSignupCode = ({
          required email,
          name,
          sex,
          weight,
          ftp,
          athleteLevel,
          athleteType,
          birthday,
          height,
          measurementPreference,
          newsletter,
        }) {
          throw DioException(
            requestOptions: RequestOptions(path: '/auth/code/request'),
            type: DioExceptionType.connectionTimeout,
            message: 'Network error',
          );
        };

        expect(() => apiClient.requestSignupCode(email: 'test@example.com'), throwsA(isA<DioException>()));
      });
    });

    group('requestLoginCode', () {
      test('returns success by default', () async {
        final response = await apiClient.requestLoginCode(email: 'test@example.com');

        expect(response.success, isTrue);
        expect(response.userExists, isTrue);
        expect(apiClient.methodCalls, contains('requestLoginCode'));
      });
    });

    group('redeemCode', () {
      test('returns tokens and user by default', () async {
        final response = await apiClient.redeemCode(email: 'test@example.com', code: '123456');

        expect(response.success, isTrue);
        expect(response.accessToken.jwt, isNotEmpty);
        expect(response.refreshToken.value, equals('fake-refresh-token'));

        // Verify the access token can be decoded
        final user = response.accessToken.parseUser();
        expect(user.email, equals('test@example.com'));
      });

      test('can override to return different user', () async {
        final customUser = User.create(
          id: 'custom-id',
          name: 'Custom User',
          email: 'custom@example.com',
          emailVerified: true,
        );

        apiClient.overrideRedeemCode = ({required email, required code, deviceInfo}) async {
          final accessToken = FakeVekoloApiClient.createFakeAccessToken(customUser);
          return TokenResponse.create(
            success: true,
            accessToken: accessToken.jwt,
            refreshToken: 'custom-refresh-token',
            user: customUser,
          );
        };

        final response = await apiClient.redeemCode(email: 'test@example.com', code: '123456');

        final user = response.accessToken.parseUser();
        expect(user.id, equals('custom-id'));
        expect(user.name, equals('Custom User'));
      });
    });

    group('refreshToken', () {
      test('returns new access token by default', () async {
        final response = await apiClient.refreshToken(refreshToken: RefreshToken('old-token'));

        expect(response.success, isTrue);
        expect(response.accessToken.jwt, isNotEmpty);
        expect(apiClient.methodCalls, contains('refreshToken'));
      });

      test('can override to simulate expired token', () {
        apiClient.overrideRefreshToken = ({required refreshToken}) {
          throw DioException(
            requestOptions: RequestOptions(path: '/auth/token/refresh'),
            response: Response(
              requestOptions: RequestOptions(path: '/auth/token/refresh'),
              statusCode: 401,
              data: {
                'error': true,
                'message': 'Invalid or expired refresh token',
                'data': {'errorCode': '915205'},
              },
            ),
            type: DioExceptionType.badResponse,
          );
        };

        expect(() => apiClient.refreshToken(refreshToken: RefreshToken('expired-token')), throwsA(isA<DioException>()));
      });
    });

    group('revokeToken', () {
      test('returns success by default', () async {
        final response = await apiClient.revokeToken(refreshToken: RefreshToken('token-to-revoke'));

        expect(response.success, isTrue);
        expect(response.message, equals('Token revoked successfully'));
        expect(apiClient.methodCalls, contains('revokeToken'));
      });
    });

    group('updateProfile', () {
      test('returns updated user by default', () async {
        final response = await apiClient.updateProfile(name: 'Updated Name', ftp: 250, weight: 75);

        expect(response.success, isTrue);
        expect(response.user.name, equals('Updated Name'));
        expect(response.user.ftp, equals(250));
        expect(response.user.weight, equals(75));
        expect(apiClient.methodCalls, contains('updateProfile'));
      });

      test('can override to return validation error', () {
        apiClient.overrideUpdateProfile = ({ftp, weight, name, email}) {
          throw DioException(
            requestOptions: RequestOptions(path: '/api/user/update'),
            response: Response(
              requestOptions: RequestOptions(path: '/api/user/update'),
              statusCode: 400,
              data: {'error': true, 'message': 'Invalid FTP value'},
            ),
            type: DioExceptionType.badResponse,
          );
        };

        expect(() => apiClient.updateProfile(ftp: -100), throwsA(isA<DioException>()));
      });
    });

    group('method call tracking', () {
      test('tracks all method calls in order', () async {
        await apiClient.requestSignupCode(email: 'test@example.com');
        await apiClient.redeemCode(email: 'test@example.com', code: '123456');
        await apiClient.updateProfile(name: 'Test');

        expect(apiClient.methodCalls, equals(['requestSignupCode', 'redeemCode', 'updateProfile']));
      });

      test('can clear method calls', () async {
        await apiClient.requestSignupCode(email: 'test@example.com');
        expect(apiClient.methodCalls, isNotEmpty);

        apiClient.clearMethodCalls();
        expect(apiClient.methodCalls, isEmpty);
      });
    });

    test('createFakeAccessToken generates valid JWT structure', () {
      final user = User.create(id: 'user-789', name: 'JWT Test User', email: 'jwt@example.com', emailVerified: true);

      final accessToken = FakeVekoloApiClient.createFakeAccessToken(user);

      // Verify it can be decoded
      final Map<String, dynamic> decoded = accessToken.decode();
      final Map<String, dynamic> userMap = decoded['user'] as Map<String, dynamic>;
      expect(userMap['id'], equals('user-789'));
      expect(userMap['name'], equals('JWT Test User'));
      expect(userMap['email'], equals('jwt@example.com'));
      expect(decoded['exp'], isA<int>());

      // Verify user can be parsed from token
      final parsedUser = accessToken.parseUser();
      expect(parsedUser.id, equals(user.id));
      expect(parsedUser.name, equals(user.name));
      expect(parsedUser.email, equals(user.email));
    });

    test('createFakeAccessToken respects custom expiry date', () {
      final user = User.create(id: 'user-exp', name: 'Expiry Test', email: 'exp@example.com', emailVerified: true);

      final customExpiry = DateTime(2025, 12, 31, 23, 59, 59);
      final accessToken = FakeVekoloApiClient.createFakeAccessToken(user, expiryDate: customExpiry);

      expect(accessToken.expiryDate, equals(customExpiry));
    });
  });
}
