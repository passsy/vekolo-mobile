import 'package:dio/dio.dart';
import 'package:vekolo/api/api_context.dart';
import 'package:vekolo/models/activity.dart';
import 'package:vekolo/models/rekord.dart';

/// Get activities from the API
///
/// Fetches activities based on the timeline filter:
/// - `null` or 'public': Public activities only
/// - 'mixed': Public activities + user's private activities (requires auth)
/// - 'mine': Only user's activities (requires auth)
///
/// Returns up to 25 activities ordered by creation date (newest first).
Future<ActivitiesResponse> getActivities(ApiContext context, {String? timeline}) async {
  // Use authDio if timeline is provided (authenticated request)
  // Use publicDio for public timeline or no timeline
  final dio = (timeline != null && timeline != 'public') ? context.authDio : context.publicDio;

  final response = await dio.get('/api/activities', queryParameters: {if (timeline != null) 'timeline': timeline});

  if (response.statusCode != 200) {
    throw DioException(
      requestOptions: response.requestOptions,
      response: response,
      type: DioExceptionType.badResponse,
      message: 'Failed to fetch activities',
    );
  }

  return ActivitiesResponse.init.fromResponse(response);
}

/// Response containing a list of activities
class ActivitiesResponse with RekordMixin {
  ActivitiesResponse.fromData(Map<String, Object?> data) : rekord = Rekord(data);

  factory ActivitiesResponse.create({List<Activity>? activities}) {
    return ActivitiesResponse.fromData({if (activities != null) 'activities': activities});
  }

  @override
  final Rekord rekord;
  static final init = ActivitiesResponseInit();

  /// List of activities
  List<Activity> get activities {
    final activitiesList = rekord
        .read('activities')
        .asListOrEmpty<Map<String, Object?>>((pick) => pick.asMapOrThrow<String, Object?>());
    return activitiesList.map((data) => Activity.fromData(data)).toList();
  }

  @override
  String toString() => 'ActivitiesResponse(activities: ${activities.length})';
}

class ActivitiesResponseInit {}

extension ActivitiesResponseInitExt on ActivitiesResponseInit {
  ActivitiesResponse fromResponse(Response response) {
    return ActivitiesResponse.fromData({'activities': response.data});
  }
}
