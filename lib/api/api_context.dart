import 'package:dio/dio.dart';

/// Context object passed to all API request methods
///
/// Contains two Dio instances: one for authenticated requests with auth interceptors,
/// and one for public endpoints (login, signup, etc.) without auth interceptors.
class ApiContext {
  /// The Dio instance for authenticated HTTP requests (includes auth interceptor)
  final Dio authDio;

  /// The Dio instance for public HTTP requests (no auth interceptor)
  /// Use this for endpoints like login, signup, refresh token, etc.
  final Dio publicDio;

  const ApiContext({required this.authDio, required this.publicDio});
}
