import 'package:dio/dio.dart';

/// Extracts a user-friendly error message from any exception
///
/// Handles DioException specially to extract API response messages and status codes.
/// For other exceptions, returns the fallback message.
/// You can provide a custom [customMessage] lambda to handle specific error scenarios.
String extractDioErrorMessage(
  Exception error, {
  String? fallbackMessage,
  String Function(DioException)? customMessage,
}) {
  // Handle non-DioException errors
  if (error is! DioException) {
    return fallbackMessage ?? 'An unexpected error occurred. Please try again.';
  }

  final statusCode = error.response?.statusCode;

  // Check for custom message handler first
  if (customMessage != null) {
    final message = customMessage(error);
    if (message.isNotEmpty) {
      return message;
    }
  }

  // Try to extract error message from API response
  if (error.response?.data != null && error.response!.data is Map) {
    final data = error.response!.data as Map<String, dynamic>;
    if (data['message'] != null) {
      final message = data['message'] as String;
      return 'Error ($statusCode): $message';
    }
  }

  // Fallback to generic error messages based on error type
  switch (error.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
      return fallbackMessage ?? 'Connection timeout. Please check your internet connection.';
    case DioExceptionType.connectionError:
      return fallbackMessage ?? 'Unable to connect to the server. Please check your internet connection.';
    case DioExceptionType.badResponse:
      if (statusCode == 404) {
        return 'Error ($statusCode): Resource not found. Please try again later.';
      } else if (statusCode == 500) {
        return 'Error ($statusCode): Server error. Please try again later.';
      }
      return fallbackMessage ?? 'Error ($statusCode): An error occurred. Please try again.';
    case DioExceptionType.cancel:
      return 'Request cancelled.';
    case DioExceptionType.badCertificate:
      return 'Security error. Please check your connection.';
    case DioExceptionType.unknown:
    default:
      return fallbackMessage ?? 'An unexpected error occurred. Please try again.';
  }
}
