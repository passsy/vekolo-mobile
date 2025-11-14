import 'package:dio/dio.dart';
import 'package:vekolo/api/api_context.dart';
import 'package:vekolo/domain/models/workout/workout_models.dart';

/// In-memory cache for workout responses
final Map<String, GetWorkoutResponse> _workoutCache = {};

/// Get a single workout by ID or slug from the API
///
/// `GET /api/workouts/:slug`
///
/// Returns the workout details including the workout plan.
/// The slug parameter can be either a workout ID or a workout slug.
/// Results are cached in memory to avoid redundant API calls.
Future<GetWorkoutResponse> getWorkout(ApiContext context, {required String slug, bool useCache = true}) async {
  // Check cache first
  if (useCache && _workoutCache.containsKey(slug)) {
    return _workoutCache[slug]!;
  }

  final response = await context.publicDio.get('/api/workouts/$slug');

  if (response.statusCode != 200) {
    throw DioException(
      requestOptions: response.requestOptions,
      response: response,
      type: DioExceptionType.badResponse,
      message: 'Failed to fetch workout',
    );
  }

  final workoutResponse = GetWorkoutResponse.fromResponse(response);

  // Cache the response
  if (useCache) {
    _workoutCache[slug] = workoutResponse;
  }

  return workoutResponse;
}

/// Response containing workout details
class GetWorkoutResponse {
  GetWorkoutResponse({
    required this.id,
    required this.title,
    required this.duration,
    required this.plan,
    this.summary,
    this.tss,
    this.category,
  });

  factory GetWorkoutResponse.fromResponse(Response response) {
    final data = response.data as Map<String, dynamic>;
    return GetWorkoutResponse(
      id: data['id'] as String,
      title: data['title'] as String,
      duration: data['duration'] as int,
      plan: WorkoutPlan.fromJson({'plan': data['plan']}),
      summary: data['summary'] as String?,
      tss: data['tss'] as int?,
      category: data['category'] as String?,
    );
  }

  final String id;
  final String title;
  final int duration;
  final WorkoutPlan plan;
  final String? summary;
  final int? tss;
  final String? category;

  @override
  String toString() => 'GetWorkoutResponse(id: $id, title: $title)';
}
