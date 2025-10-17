import 'package:dio/dio.dart';
import 'package:vekolo/api/api_context.dart';
import 'package:vekolo/api/auth/request_signup_code.dart';
import 'dart:developer' as developer;

/// Request a magic code for login
///
/// Sends an email with a 6-digit code to sign in to an existing account.
Future<CodeRequestResponse> postRequestLoginCode(ApiContext context, {required String email}) async {
  try {
    final response = await context.dio.post(
      '/auth/code/request',
      data: {'type': 'login', 'email': email},
      options: Options(contentType: Headers.jsonContentType, validateStatus: (status) => status == 200),
    );

    return CodeRequestResponse.fromData(response.data as Map<String, Object?>);
  } catch (e, stackTrace) {
    developer.log('Failed to request login code', error: e, stackTrace: stackTrace);
    rethrow;
  }
}
