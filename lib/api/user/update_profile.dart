import 'dart:developer' as developer;
import 'package:dio/dio.dart';
import 'package:vekolo/api/api_context.dart';
import 'package:vekolo/models/rekord.dart';
import 'package:vekolo/models/user.dart';

/// Update user profile
///
/// `POST /api/user/update`
Future<UpdateProfileResponse> postUpdateProfile(
  ApiContext context, {
  int? ftp,
  int? weight,
  String? name,
  String? email,
}) async {
  try {
    final accessToken = await context.getAccessToken();
    if (accessToken == null) {
      throw Exception('Not authenticated');
    }

    final response = await context.dio.post(
      '/api/user/update',
      data: {
        if (ftp != null) 'ftp': ftp,
        if (weight != null) 'weight': weight,
        if (name != null) 'name': name,
        if (email != null) 'email': email,
      },
      options: Options(contentType: Headers.jsonContentType, headers: {'Authorization': 'Bearer $accessToken'}),
    );

    return UpdateProfileResponse.fromData(response.data as Map<String, Object?>);
  } catch (e, stackTrace) {
    developer.log('Failed to update profile', error: e, stackTrace: stackTrace);
    rethrow;
  }
}

/// Response from updating user profile
class UpdateProfileResponse with RekordMixin {
  UpdateProfileResponse.fromData(Map<String, Object?> data) : rekord = Rekord(data);

  factory UpdateProfileResponse.create({bool? success, User? user}) {
    return UpdateProfileResponse.fromData({if (success != null) 'success': success, if (user != null) 'user': user});
  }

  @override
  final Rekord rekord;
  static final init = UpdateProfileResponseInit();

  bool get success => rekord.read('success').asBoolOrThrow();

  /// Updated user data
  User get user => rekord.read('user').letOrThrow((pick) => User.fromData(pick.asMapOrThrow<String, Object?>()));

  @override
  String toString() => 'UpdateProfileResponse(success: $success, user: ${user.name})';
}

class UpdateProfileResponseInit {}
