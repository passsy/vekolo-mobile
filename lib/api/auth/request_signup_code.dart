import 'package:dio/dio.dart';
import 'package:vekolo/api/api_context.dart';
import 'package:vekolo/models/rekord.dart';

/// Request a magic code for signup
///
/// Sends an email with a 6-digit code to create a new account.
Future<CodeRequestResponse> postRequestSignupCode(
  ApiContext context, {
  required String email,
  String? name,
  String? sex,
  int? weight,
  int? ftp,
  String? athleteLevel,
  String? athleteType,
  String? birthday,
  int? height,
  String? measurementPreference,
  bool? newsletter,
}) async {
  final response = await context.publicDio.post(
    '/auth/code/request',
    data: {
      'type': 'signup',
      'email': email,
      if (name != null) 'name': name,
      if (sex != null) 'sex': sex,
      if (weight != null) 'weight': weight,
      if (ftp != null) 'ftp': ftp,
      if (athleteLevel != null) 'athleteLevel': athleteLevel,
      if (athleteType != null) 'athleteType': athleteType,
      if (birthday != null) 'birthday': birthday,
      if (height != null) 'height': height,
      if (measurementPreference != null) 'measurementPreference': measurementPreference,
      if (newsletter != null) 'newsletter': newsletter,
    },
    options: Options(contentType: Headers.jsonContentType, validateStatus: (status) => status == 200),
  );
  return CodeRequestResponse.init.fromResponse(response);
}

/// Response for code request (signup/login)
class CodeRequestResponse with RekordMixin {
  CodeRequestResponse.fromData(Map<String, Object?> data) : rekord = Rekord(data);

  factory CodeRequestResponse.create({bool? success, bool? userExists, bool? rateLimited, String? message}) {
    return CodeRequestResponse.fromData({
      if (success != null) 'success': success,
      if (userExists != null) 'userExists': userExists,
      if (rateLimited != null) 'rateLimited': rateLimited,
      if (message != null) 'message': message,
    });
  }

  @override
  final Rekord rekord;
  static final init = CodeRequestResponseInit();

  /// True if the code was sent successfully
  bool get success => rekord.read('success').asBoolOrThrow();

  /// True if the email is already registered (signup only)
  bool? get userExists => rekord.read('userExists').asBoolOrNull();

  /// True if the request was rate limited
  bool? get rateLimited => rekord.read('rateLimited').asBoolOrNull();

  /// Descriptive message about the request result
  String get message => rekord.read('message').asStringOrThrow();

  @override
  String toString() => 'CodeRequestResponse(success: $success, message: $message)';
}

class CodeRequestResponseInit {}

extension CodeRequestResponseInitExt on CodeRequestResponseInit {
  CodeRequestResponse fromResponse(Response response) {
    return CodeRequestResponse.fromData(response.data as Map<String, Object?>);
  }
}
