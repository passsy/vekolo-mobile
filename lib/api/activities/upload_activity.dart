import 'package:dio/dio.dart';
import 'package:vekolo/api/api_context.dart';
import 'package:vekolo/domain/models/workout_session.dart';
import 'package:vekolo/models/activity.dart';
import 'package:vekolo/models/rekord.dart';

/// Upload a completed workout session as an activity
///
/// `POST /api/activities`
///
/// Converts a local WorkoutSession to an Activity on the server.
/// The server calculates all metrics (averages, totals) from the samples.
Future<UploadActivityResponse> postUploadActivity(
  ApiContext context, {
  required WorkoutSessionMetadata metadata,
  required List<WorkoutSample> samples,
  ActivityVisibility visibility = ActivityVisibility.public,
}) async {
  final response = await context.authDio.post(
    '/api/activities/upload',
    data: {
      'idempotencyKey': metadata.workoutId, // min 21 chars nanoid
      'workoutId': metadata.sourceWorkoutId, // exact workoutId
      // 'workout': { // not needed, can be linked on the server
      //   'title': metadata.workoutName,
      //   'plan': metadata.workoutPlan.toJson()['plan'],
      //   'events': metadata.workoutPlan.toJson()['events'],
      // },
      // 'endTime': metadata.endTime!.toIso8601String(), // unnecessary
      // 'ftp': metadata.ftp, // irrelevant
      // 'visibility': visibility.value, // server side from profile settings

      'startTime': metadata.startTime.toIso8601String(), // ISO 8601

      // dataPoints structure
      // - time: ms since start of workout, but always multiple of 1000 non-null
      // - cadence: cadence in RPM >0 nullable
      // - power: power in watts >0 nullable
      // - heartRate: heart rate in bpm >0 nullable
      // - speed: speed in km/h >0 nullable
      // - distance: meters - from trainer (can be better calculated than once every second. Trainer gives better/faster data)
      'dataPoints': samples.map((sample) => sample.toJson()).toList(),
      'devices': [
        {
          "type": "hrm|cadence|power|speed|control",
          "name": "Polar 1342",
          "manufacturer": "manufacturerId",
        },
      ]
    },
    options: Options(contentType: Headers.jsonContentType),
  );

  if (response.statusCode != 200 && response.statusCode != 201) {
    throw DioException(
      requestOptions: response.requestOptions,
      response: response,
      type: DioExceptionType.badResponse,
      message: 'Failed to upload activity',
    );
  }

  return UploadActivityResponse.init.fromResponse(response);
}

/// Response from uploading an activity
class UploadActivityResponse with RekordMixin {
  UploadActivityResponse.fromData(Map<String, Object?> data) : rekord = Rekord(data);

  factory UploadActivityResponse.create({
    String? id,
    String? createdAt,
    String? url,
  }) {
    return UploadActivityResponse.fromData({
      if (id != null) 'id': id,
      if (createdAt != null) 'createdAt': createdAt,
      if (url != null) 'url': url,
    });
  }

  @override
  final Rekord rekord;
  static final init = UploadActivityResponseInit();

  /// The created activity ID
  String get id => rekord.read('id').asStringOrThrow();

  /// When the activity was created on the server
  String get createdAt => rekord.read('createdAt').asStringOrThrow();

  /// URL to view the activity
  String? get url => rekord.read('url').asStringOrNull();

  @override
  String toString() => 'UploadActivityResponse(id: $id, createdAt: $createdAt)';
}

class UploadActivityResponseInit {}

extension UploadActivityResponseInitExt on UploadActivityResponseInit {
  UploadActivityResponse fromResponse(Response response) {
    final data = response.data;
    if (data is Map<String, Object?>) {
      return UploadActivityResponse.fromData(data);
    }
    return UploadActivityResponse.fromData({'data': data});
  }
}
