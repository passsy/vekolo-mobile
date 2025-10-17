// Example usage of the stateless VekoloApiClient with Rekord pattern
//
// This file demonstrates how to use the API client for authentication flows.
// The client is stateless - it doesn't store tokens or manage state internally.
//
// All models use the Rekord pattern for robust API parsing that handles
// missing or corrupted fields gracefully.

import 'package:vekolo/api/vekolo_api_client.dart';

void main() async {
  // Initialize the client with your base URL
  final client = VekoloApiClient(
    baseUrl: 'https://your-domain.com', // or http://localhost:3000 for dev
    tokenProvider: () async => null, // No token initially
  );

  // Example 1: Sign up flow
  await signupFlow(client);

  // Example 2: Login flow
  await loginFlow(client);

  // Example 3: Refresh token when expired
  await refreshTokenExample(client);

  // Example 4: Logout
  await logoutExample(client);
}

// Example 1: Complete signup flow
Future<void> signupFlow(VekoloApiClient client) async {
  try {
    // Step 1: Request magic code for signup
    final codeResponse = await client.requestSignupCode(
      email: 'user@example.com',
      name: 'John Doe',
      sex: 'm',
      weight: 70,
      ftp: 200,
    );

    // Rekord pattern allows graceful field access
    if (!codeResponse.success) {
      if (codeResponse.userExists == true) {
        print('User already exists, use login instead');
        return;
      }
      if (codeResponse.rateLimited == true) {
        print('Rate limited: ${codeResponse.message}');
        return;
      }
      print('Failed: ${codeResponse.message}');
      return;
    }

    print('Magic code sent! Check your email.');

    // Step 2: User enters the 6-digit code from email
    const userEnteredCode = '123456'; // From email

    // Step 3: Redeem the code for tokens
    final tokenResponse = await client.redeemCode(
      email: 'user@example.com',
      code: userEnteredCode,
      deviceInfo: 'Flutter App v1.0.0',
    );

    // Step 4: Access nested User object through Rekord
    final accessToken = tokenResponse.accessToken;
    final user = accessToken.parseUser();

    print('Logged in as ${user.name}');
    print('Email: ${user.email}');
    print('FTP: ${user.ftp}W');
    print('Access token: ${tokenResponse.accessToken}');
    print('Refresh token: ${tokenResponse.refreshToken}');

    // TODO: Store these tokens in flutter_secure_storage
  } catch (e, stackTrace) {
    print('Signup failed: $e');
    print(stackTrace);
  }
}

// Example 2: Complete login flow
Future<void> loginFlow(VekoloApiClient client) async {
  try {
    // Step 1: Request magic code for login
    final codeResponse = await client.requestLoginCode(email: 'user@example.com');

    if (!codeResponse.success) {
      if (codeResponse.userExists == false) {
        print('User not found, please sign up first');
        return;
      }
      if (codeResponse.rateLimited == true) {
        print('Rate limited: ${codeResponse.message}');
        return;
      }
      print('Failed: ${codeResponse.message}');
      return;
    }

    print('Magic code sent! Check your email.');

    // Step 2: User enters the 6-digit code from email
    const userEnteredCode = '123456'; // From email

    // Step 3: Redeem the code for tokens
    final tokenResponse = await client.redeemCode(
      email: 'user@example.com',
      code: userEnteredCode,
      deviceInfo: 'Flutter App v1.0.0',
    );

    // Rekord pattern makes nested access clean
    print('Logged in as ${tokenResponse.accessToken.parseUser().name}');

    // TODO: Store these tokens in flutter_secure_storage
  } catch (e, stackTrace) {
    print('Login failed: $e');
    print(stackTrace);
  }
}

// Example 3: Refresh token when expired
Future<void> refreshTokenExample(VekoloApiClient client) async {
  try {
    // Load refresh token from secure storage
    const storedRefreshToken = 'your-stored-refresh-token';

    // Get a new access token
    final response = await client.refreshToken(refreshToken: storedRefreshToken);

    final newAccessToken = response.accessToken;
    print('New access token: $newAccessToken');

    // TODO: Store the new access token in flutter_secure_storage
  } catch (e, stackTrace) {
    print('Token refresh failed: $e');
    print(stackTrace);

    // If refresh fails (401), the refresh token is invalid/expired
    // User needs to log in again
  }
}

// Example 4: Logout (revoke refresh token)
Future<void> logoutExample(VekoloApiClient client) async {
  try {
    // Load refresh token from secure storage
    const storedRefreshToken = 'your-stored-refresh-token';

    // Revoke the token on the server
    final response = await client.revokeToken(refreshToken: storedRefreshToken);

    print(response.message);

    // TODO: Clear all tokens from flutter_secure_storage
    // TODO: Navigate to login screen
  } catch (e, stackTrace) {
    print('Logout failed: $e');
    print(stackTrace);

    // Even if this fails, still clear local tokens and log out
  }
}

// Example 5: Rekord pattern advantages in testing
//
// With Rekord, you only need to provide the fields you actually test
void rekordTestingExample() {
  // Traditional approach would require ALL required fields
  // Even if you only test the name field

  // With Rekord - minimal setup, only what you need!
  // This would crash if you tried to access missing fields,
  // but that's fine because your test doesn't need them
}
