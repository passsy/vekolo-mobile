import 'package:dio/dio.dart';
import 'package:vekolo/api/api_context.dart';
import 'package:vekolo/domain/models/device_info.dart';
import 'package:vekolo/domain/models/workout_session.dart';
import 'package:vekolo/models/rekord.dart';

/// Upload a completed workout session as an activity
///
/// `POST /api/activities/upload`
///
/// Converts a local WorkoutSession to an Activity on the server.
/// The server calculates all metrics (averages, totals) from the samples.
Future<UploadActivityResponse> postUploadActivity(
  ApiContext context, {
  required WorkoutSessionMetadata metadata,
  required List<WorkoutSample> samples,
  required List<UploadDevice> devices,
}) async {
  final response = await context.authDio.post(
    '/api/activities/upload',
    data: {
      'idempotencyKey': metadata.workoutId,
      'workoutId': metadata.sourceWorkoutId,
      'startTime': metadata.startTime.toIso8601String(),
      'dataPoints': samples.map(_sampleToDataPoint).toList(),
      'devices': devices.map((d) => d.toJson()).toList(),
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

/// Converts a [WorkoutSample] to the server's dataPoint format.
Map<String, dynamic> _sampleToDataPoint(WorkoutSample sample) {
  return {
    'time': sample.elapsedMs,
    'cadence': sample.cadence,
    'power': sample.powerActual,
    'heartRate': sample.heartRate,
    'speed': sample.speed,
    'distance': null, // Distance not tracked per-sample yet
  };
}

// ============================================================================
// Request types
// ============================================================================

/// Device type as expected by the server API.
///
/// Maps to server enum: 'hrm', 'cadence', 'power', 'speed', 'control'
enum UploadDeviceType {
  /// Heart rate monitor
  hrm('hrm'),

  /// Cadence sensor
  cadence('cadence'),

  /// Power meter
  power('power'),

  /// Speed sensor
  speed('speed'),

  /// Smart trainer (controllable)
  control('control');

  const UploadDeviceType(this.value);
  final String value;
}

/// Device info for upload API.
class UploadDevice {
  const UploadDevice({
    required this.name,
    required this.type,
    required this.manufacturer,
  });

  /// Creates from [DeviceInfo].
  factory UploadDevice.fromDeviceInfo(DeviceInfo info) {
    return UploadDevice(
      name: info.name,
      type: _mapDeviceType(info.type),
      manufacturer: 'unknown', // BLE doesn't expose manufacturer reliably
    );
  }

  final String name;
  final UploadDeviceType type;
  final String manufacturer;

  Map<String, dynamic> toJson() => {
        'name': name,
        'type': type.value,
        'manufacturer': manufacturer,
      };
}

UploadDeviceType _mapDeviceType(DeviceType type) {
  return switch (type) {
    DeviceType.trainer => UploadDeviceType.control,
    DeviceType.powerMeter => UploadDeviceType.power,
    DeviceType.cadenceSensor => UploadDeviceType.cadence,
    DeviceType.heartRateMonitor => UploadDeviceType.hrm,
  };
}

// ============================================================================
// Response types
// ============================================================================

/// Response from uploading an activity
class UploadActivityResponse with RekordMixin {
  UploadActivityResponse.fromData(Map<String, Object?> data) : rekord = Rekord(data);

  factory UploadActivityResponse.create({String? id, String? createdAt, String? url}) {
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
