import 'package:dio/dio.dart';
import 'package:vekolo/api/api_context.dart';
import 'package:vekolo/api/auth/request_signup_code.dart';

/// Request a magic code for login
///
/// Sends an email with a 6-digit code to sign in to an existing account.
Future<CodeRequestResponse> postRequestLoginCode(ApiContext context, {required String email}) async {
  final response = await context.publicDio.post(
    '/auth/code/request',
    data: {'type': 'login', 'email': email},
    options: Options(contentType: Headers.jsonContentType, validateStatus: (status) => status == 200),
  );

  return CodeRequestResponse.init.fromResponse(response);
}
