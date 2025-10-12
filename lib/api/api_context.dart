import 'package:dio/dio.dart';

/// Context object passed to all API request methods
///
/// Contains the Dio instance for making HTTP requests and a callback
/// for retrieving the current access token for authenticated endpoints.
class ApiContext {
  /// The Dio instance for making HTTP requests
  final Dio dio;

  /// Callback for retrieving the current access token
  /// Returns null if no user is authenticated
  final Future<String?> Function() getAccessToken;

  const ApiContext({required this.dio, required this.getAccessToken});
}
