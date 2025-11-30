/// Models for workout session recording and crash recovery.
///
/// These models represent recorded workout sessions with metrics sampled at 1Hz.
/// Sessions are persisted to local storage with crash recovery support.
library;

import 'package:deep_pick/deep_pick.dart';
import 'package:vekolo/domain/models/workout/workout_models.dart';

// ============================================================================
// Session Status
// ============================================================================

/// Status of a workout session.
enum SessionStatus {
  /// Currently recording (workout in progress).
  active('active'),

  /// Workout finished normally.
  completed('completed'),

  /// User manually discarded the session.
  abandoned('abandoned'),

  /// App closed unexpectedly during workout (detected on restart).
  crashed('crashed');

  const SessionStatus(this.value);

  final String value;

  /// Parse from string value.
  static SessionStatus fromString(String value) {
    return SessionStatus.values.firstWhere(
      (status) => status.value == value,
      orElse: () => throw ArgumentError('Unknown session status: $value'),
    );
  }
}

// ============================================================================
// Workout Session Metadata
// ============================================================================

/// Complete metadata for a workout session stored in `workouts/{id}/metadata.json`.
///
/// Contains ALL workout information - nothing stored in SharedPreferences except
/// the active session ID for crash detection.
class WorkoutSessionMetadata {
  /// Creates workout session metadata.
  const WorkoutSessionMetadata({
    required this.sessionId,
    required this.workoutName,
    required this.workoutPlan,
    required this.startTime,
    required this.status,
    required this.ftp,
    required this.totalSamples,
    required this.currentBlockIndex,
    required this.elapsedMs,
    required this.lastUpdated,
    required this.sourceWorkoutId,
    this.endTime,
    this.userId,
  });

  /// Creates from JSON using deep_pick.
  factory WorkoutSessionMetadata.fromJson(Map<String, dynamic> json) {
    return WorkoutSessionMetadata(
      // JSON key remains 'workoutId' for backwards compatibility with persisted data
      sessionId: pick(json, 'workoutId').asStringOrThrow(),
      workoutName: pick(json, 'workoutName').asStringOrThrow(),
      workoutPlan: WorkoutPlan.fromJson(pick(json, 'workoutPlanJson').asMapOrThrow<String, dynamic>()),
      startTime: DateTime.parse(pick(json, 'startTime').asStringOrThrow()),
      endTime: pick(json, 'endTime').letOrNull((p) => DateTime.parse(p.asStringOrThrow())),
      status: SessionStatus.fromString(pick(json, 'status').asStringOrThrow()),
      userId: pick(json, 'userId').asStringOrNull(),
      ftp: pick(json, 'ftp').asIntOrThrow(),
      totalSamples: pick(json, 'totalSamples').asIntOrThrow(),
      currentBlockIndex: pick(json, 'currentBlockIndex').asIntOrThrow(),
      elapsedMs: pick(json, 'elapsedMs').asIntOrThrow(),
      lastUpdated: DateTime.parse(pick(json, 'lastUpdated').asStringOrThrow()),
      sourceWorkoutId: pick(json, 'sourceWorkoutId').asStringOrThrow(),
    );
  }

  /// Unique session ID (nanoid, e.g., "V1StGXR8_Z5jdHi6B-myT").
  /// This identifies this specific workout session/recording.
  final String sessionId;

  /// Workout name (e.g., "Sweet Spot Intervals").
  final String workoutName;

  /// Complete workout plan for resume capability.
  final WorkoutPlan workoutPlan;

  /// When the session started.
  final DateTime startTime;

  /// When the session ended (null if active or crashed).
  final DateTime? endTime;

  /// Current session status.
  final SessionStatus status;

  /// User ID (null if not logged in).
  final String? userId;

  /// Source workout ID from library/API (for re-riding the same workout).
  final String sourceWorkoutId;

  /// FTP at time of workout (for historical comparison).
  final int ftp;

  /// Number of samples recorded so far.
  final int totalSamples;

  /// Current block index in workout plan (for resume).
  final int currentBlockIndex;

  /// Elapsed time in milliseconds (for resume).
  final int elapsedMs;

  /// Last time metadata was updated.
  final DateTime lastUpdated;

  /// Converts to JSON.
  Map<String, dynamic> toJson() {
    return {
      // JSON key remains 'workoutId' for backwards compatibility with persisted data
      'workoutId': sessionId,
      'workoutName': workoutName,
      'workoutPlanJson': workoutPlan.toJson(),
      'startTime': startTime.toIso8601String(),
      if (endTime != null) 'endTime': endTime!.toIso8601String(),
      'status': status.value,
      if (userId != null) 'userId': userId,
      'sourceWorkoutId': sourceWorkoutId,
      'ftp': ftp,
      'totalSamples': totalSamples,
      'currentBlockIndex': currentBlockIndex,
      'elapsedMs': elapsedMs,
      'lastUpdated': lastUpdated.toIso8601String(),
    };
  }

  /// Creates a copy with optional field replacements.
  WorkoutSessionMetadata copyWith({
    String? sessionId,
    String? workoutName,
    WorkoutPlan? workoutPlan,
    DateTime? startTime,
    DateTime? endTime,
    SessionStatus? status,
    String? userId,
    String? sourceWorkoutId,
    int? ftp,
    int? totalSamples,
    int? currentBlockIndex,
    int? elapsedMs,
    DateTime? lastUpdated,
  }) {
    return WorkoutSessionMetadata(
      sessionId: sessionId ?? this.sessionId,
      workoutName: workoutName ?? this.workoutName,
      workoutPlan: workoutPlan ?? this.workoutPlan,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      status: status ?? this.status,
      userId: userId ?? this.userId,
      sourceWorkoutId: sourceWorkoutId ?? this.sourceWorkoutId,
      ftp: ftp ?? this.ftp,
      totalSamples: totalSamples ?? this.totalSamples,
      currentBlockIndex: currentBlockIndex ?? this.currentBlockIndex,
      elapsedMs: elapsedMs ?? this.elapsedMs,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }
}

// ============================================================================
// Workout Session (UI Model)
// ============================================================================

/// Lightweight session info for resume dialog and UI display.
///
/// Created from WorkoutSessionMetadata - not stored independently.
class WorkoutSession {
  /// Creates a workout session.
  const WorkoutSession({
    required this.id,
    required this.workoutName,
    required this.workoutPlan,
    required this.startTime,
    required this.status,
    required this.elapsedMs,
    required this.currentBlockIndex,
    required this.sourceWorkoutId,
    this.lastSampleTime,
  });

  /// Creates from metadata.
  factory WorkoutSession.fromMetadata(WorkoutSessionMetadata metadata) {
    return WorkoutSession(
      id: metadata.sessionId,
      workoutName: metadata.workoutName,
      workoutPlan: metadata.workoutPlan,
      startTime: metadata.startTime,
      status: metadata.status,
      elapsedMs: metadata.elapsedMs,
      currentBlockIndex: metadata.currentBlockIndex,
      sourceWorkoutId: metadata.sourceWorkoutId,
      lastSampleTime: metadata.lastUpdated,
    );
  }

  /// Workout session ID (nanoid).
  final String id;

  /// Workout name.
  final String workoutName;

  /// Complete workout plan (needed for resume).
  final WorkoutPlan workoutPlan;

  /// When the session started.
  final DateTime startTime;

  /// Current session status.
  final SessionStatus status;

  /// Elapsed time in milliseconds (for resume).
  final int elapsedMs;

  /// Current block index (for resume).
  final int currentBlockIndex;

  /// Source workout ID from library/API (for re-riding the same workout).
  final String sourceWorkoutId;

  /// Last time a sample was recorded (for display).
  final DateTime? lastSampleTime;
}

// ============================================================================
// Workout Sample
// ============================================================================

/// A single data sample recorded at 1Hz during a workout.
///
/// Stored in JSONL format (one JSON object per line) in `workouts/{id}/samples.jsonl`.
class WorkoutSample {
  /// Creates a workout sample.
  const WorkoutSample({
    required this.timestamp,
    required this.elapsedMs,
    required this.powerTarget,
    required this.powerScaleFactor,
    this.powerActual,
    this.cadence,
    this.speed,
    this.heartRate,
  });

  /// Creates from JSON using deep_pick.
  factory WorkoutSample.fromJson(Map<String, dynamic> json) {
    return WorkoutSample(
      timestamp: DateTime.parse(pick(json, 'timestamp').asStringOrThrow()),
      elapsedMs: pick(json, 'elapsedMs').asIntOrThrow(),
      powerActual: pick(json, 'powerActual').asIntOrNull(),
      powerTarget: pick(json, 'powerTarget').asIntOrThrow(),
      cadence: pick(json, 'cadence').asIntOrNull(),
      speed: pick(json, 'speed').asDoubleOrNull(),
      heartRate: pick(json, 'heartRate').asIntOrNull(),
      powerScaleFactor: pick(json, 'powerScaleFactor').asDoubleOrThrow(),
    );
  }

  /// Precise timestamp of this sample.
  final DateTime timestamp;

  /// Elapsed time since workout start in milliseconds.
  final int elapsedMs;

  /// Actual power output in watts (null if stale/unavailable).
  final int? powerActual;

  /// Target power in watts from workout plan.
  final int powerTarget;

  /// Current cadence in RPM (null if stale/unavailable).
  final int? cadence;

  /// Current speed in km/h (null if stale/unavailable).
  final double? speed;

  /// Current heart rate in BPM (null if stale/unavailable).
  final int? heartRate;

  /// Power scale factor adjustment (1.0 = 100%, 1.1 = 110%, etc.).
  final double powerScaleFactor;

  /// Converts to compact JSON for JSONL storage.
  ///
  /// No pretty printing - single line for append-only JSONL format.
  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'elapsedMs': elapsedMs,
      'powerActual': powerActual,
      'powerTarget': powerTarget,
      'cadence': cadence,
      'speed': speed,
      'heartRate': heartRate,
      'powerScaleFactor': powerScaleFactor,
    };
  }
}
