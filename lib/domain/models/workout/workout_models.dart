/// Workout domain models for structured training.
///
/// These models represent workout plans consisting of power blocks, ramp blocks,
/// and intervals with events. Based on the web implementation at
/// `/vekolo-web/shared/types/workout.ts`.
library;

import 'package:deep_pick/deep_pick.dart';

// ============================================================================
// Block Models
// ============================================================================

/// A constant power block with fixed target power and duration.
///
/// Used for steady-state training at a specific power level relative to FTP.
/// Example: 5 minutes at 85% FTP (power: 0.85)
class PowerBlock {
  /// Creates a power block.
  const PowerBlock({
    required this.id,
    required this.duration,
    required this.power,
    this.description,
    this.cadence,
    this.cadenceHigh,
    this.cadenceLow,
  });

  /// Creates a power block from JSON.
  ///
  /// Uses deep_pick for safe JSON parsing as per CLAUDE.md preferences.
  factory PowerBlock.fromJson(Map<String, dynamic> json) {
    return PowerBlock(
      id: pick(json, 'id').asStringOrThrow(),
      duration: pick(json, 'duration').asIntOrThrow(),
      power: pick(json, 'power').asDoubleOrThrow(),
      description: pick(json, 'description').asStringOrNull(),
      cadence: pick(json, 'cadence').asIntOrNull(),
      cadenceHigh: pick(json, 'cadenceHigh').asIntOrNull(),
      cadenceLow: pick(json, 'cadenceLow').asIntOrNull(),
    );
  }

  /// Unique identifier for this block.
  final String id;

  /// Block type identifier (always 'power').
  String get type => 'power';

  /// Short description (max 32 characters).
  ///
  /// Optional, used for display purposes. Examples: "Maximum effort", "Cadence drills".
  final String? description;

  /// Duration in milliseconds.
  final int duration;

  /// Relative power as a multiplier of FTP.
  ///
  /// Range: 0.5-5.0, where 1.0 = 100% FTP.
  /// Example: 0.85 = 85% FTP, 1.2 = 120% FTP.
  final double power;

  /// Optional target cadence in RPM.
  ///
  /// If set, rider should maintain this cadence during the block.
  final int? cadence;

  /// Optional maximum cadence in RPM.
  ///
  /// Prevents rider from spinning too fast.
  final int? cadenceHigh;

  /// Optional minimum cadence in RPM.
  ///
  /// Prevents rider from dropping too low.
  final int? cadenceLow;

  /// Converts to JSON.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      if (description != null) 'description': description,
      'duration': duration,
      'power': power,
      if (cadence != null) 'cadence': cadence,
      if (cadenceHigh != null) 'cadenceHigh': cadenceHigh,
      if (cadenceLow != null) 'cadenceLow': cadenceLow,
    };
  }

  /// Creates a copy with optional field replacements.
  PowerBlock copyWith({
    String? id,
    String? description,
    int? duration,
    double? power,
    int? cadence,
    int? cadenceHigh,
    int? cadenceLow,
  }) {
    return PowerBlock(
      id: id ?? this.id,
      description: description ?? this.description,
      duration: duration ?? this.duration,
      power: power ?? this.power,
      cadence: cadence ?? this.cadence,
      cadenceHigh: cadenceHigh ?? this.cadenceHigh,
      cadenceLow: cadenceLow ?? this.cadenceLow,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is PowerBlock &&
        other.id == id &&
        other.description == description &&
        other.duration == duration &&
        other.power == power &&
        other.cadence == cadence &&
        other.cadenceHigh == cadenceHigh &&
        other.cadenceLow == cadenceLow;
  }

  @override
  int get hashCode => Object.hash(
        id,
        description,
        duration,
        power,
        cadence,
        cadenceHigh,
        cadenceLow,
      );

  @override
  String toString() {
    return 'PowerBlock(id: $id, duration: ${duration}ms, power: ${(power * 100).toStringAsFixed(0)}%, '
        'cadence: $cadence, description: $description)';
  }
}

/// A ramping power block with gradually changing power target.
///
/// Used for warm-ups, cool-downs, or progressive intervals where power
/// transitions smoothly from start to end over the duration.
/// Example: 10 minutes ramping from 60% to 90% FTP
class RampBlock {
  /// Creates a ramp block.
  const RampBlock({
    required this.id,
    required this.duration,
    required this.powerStart,
    required this.powerEnd,
    this.description,
    this.cadenceStart,
    this.cadenceEnd,
    this.cadenceHigh,
    this.cadenceLow,
  });

  /// Creates a ramp block from JSON.
  factory RampBlock.fromJson(Map<String, dynamic> json) {
    return RampBlock(
      id: pick(json, 'id').asStringOrThrow(),
      duration: pick(json, 'duration').asIntOrThrow(),
      powerStart: pick(json, 'powerStart').asDoubleOrThrow(),
      powerEnd: pick(json, 'powerEnd').asDoubleOrThrow(),
      description: pick(json, 'description').asStringOrNull(),
      cadenceStart: pick(json, 'cadenceStart').asIntOrNull(),
      cadenceEnd: pick(json, 'cadenceEnd').asIntOrNull(),
      cadenceHigh: pick(json, 'cadenceHigh').asIntOrNull(),
      cadenceLow: pick(json, 'cadenceLow').asIntOrNull(),
    );
  }

  /// Unique identifier for this block.
  final String id;

  /// Block type identifier (always 'ramp').
  String get type => 'ramp';

  /// Short description (max 32 characters).
  ///
  /// Optional. Examples: "Warm up", "Cool down", "Shark tooth up".
  final String? description;

  /// Duration in milliseconds.
  final int duration;

  /// Relative power at the beginning of the ramp.
  ///
  /// Range: 0.5-5.0, where 1.0 = 100% FTP.
  final double powerStart;

  /// Relative power at the end of the ramp.
  ///
  /// Range: 0.5-5.0, where 1.0 = 100% FTP.
  final double powerEnd;

  /// Optional target cadence in RPM at the beginning.
  final int? cadenceStart;

  /// Optional target cadence in RPM at the end.
  ///
  /// If cadenceStart is set, this should also be set.
  final int? cadenceEnd;

  /// Optional maximum cadence in RPM.
  final int? cadenceHigh;

  /// Optional minimum cadence in RPM.
  final int? cadenceLow;

  /// Converts to JSON.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      if (description != null) 'description': description,
      'duration': duration,
      'powerStart': powerStart,
      'powerEnd': powerEnd,
      if (cadenceStart != null) 'cadenceStart': cadenceStart,
      if (cadenceEnd != null) 'cadenceEnd': cadenceEnd,
      if (cadenceHigh != null) 'cadenceHigh': cadenceHigh,
      if (cadenceLow != null) 'cadenceLow': cadenceLow,
    };
  }

  /// Creates a copy with optional field replacements.
  RampBlock copyWith({
    String? id,
    String? description,
    int? duration,
    double? powerStart,
    double? powerEnd,
    int? cadenceStart,
    int? cadenceEnd,
    int? cadenceHigh,
    int? cadenceLow,
  }) {
    return RampBlock(
      id: id ?? this.id,
      description: description ?? this.description,
      duration: duration ?? this.duration,
      powerStart: powerStart ?? this.powerStart,
      powerEnd: powerEnd ?? this.powerEnd,
      cadenceStart: cadenceStart ?? this.cadenceStart,
      cadenceEnd: cadenceEnd ?? this.cadenceEnd,
      cadenceHigh: cadenceHigh ?? this.cadenceHigh,
      cadenceLow: cadenceLow ?? this.cadenceLow,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is RampBlock &&
        other.id == id &&
        other.description == description &&
        other.duration == duration &&
        other.powerStart == powerStart &&
        other.powerEnd == powerEnd &&
        other.cadenceStart == cadenceStart &&
        other.cadenceEnd == cadenceEnd &&
        other.cadenceHigh == cadenceHigh &&
        other.cadenceLow == cadenceLow;
  }

  @override
  int get hashCode => Object.hash(
        id,
        description,
        duration,
        powerStart,
        powerEnd,
        cadenceStart,
        cadenceEnd,
        cadenceHigh,
        cadenceLow,
      );

  @override
  String toString() {
    return 'RampBlock(id: $id, duration: ${duration}ms, '
        'power: ${(powerStart * 100).toStringAsFixed(0)}% → ${(powerEnd * 100).toStringAsFixed(0)}%, '
        'description: $description)';
  }
}

/// A repeating interval containing multiple blocks.
///
/// Used for structured interval training where a sequence of blocks
/// (work/recovery) is repeated multiple times.
/// Example: 3x (3min @ 105% FTP, 2min @ 60% FTP)
class WorkoutInterval {
  /// Creates an interval.
  const WorkoutInterval({
    required this.id,
    required this.parts,
    required this.repeat,
    this.description,
  });

  /// Creates an interval from JSON.
  factory WorkoutInterval.fromJson(Map<String, dynamic> json) {
    final partsList = pick(json, 'parts').asListOrThrow<Map<String, dynamic>>((p) => p.asMapOrThrow<String, dynamic>());

    return WorkoutInterval(
      id: pick(json, 'id').asStringOrThrow(),
      repeat: pick(json, 'repeat').asIntOrThrow(),
      description: pick(json, 'description').asStringOrNull(),
      parts: partsList.map((partJson) {
        final type = pick(partJson, 'type').asStringOrThrow();
        if (type == 'power') {
          return PowerBlock.fromJson(partJson);
        } else if (type == 'ramp') {
          return RampBlock.fromJson(partJson);
        } else {
          throw ArgumentError('Invalid block type in interval parts: $type');
        }
      }).toList(),
    );
  }

  /// Unique identifier for this interval.
  final String id;

  /// Type identifier (always 'interval').
  String get type => 'interval';

  /// Medium description (max 64 characters).
  ///
  /// Optional. Examples: "VO2max intervals", "Sweet spot training".
  final String? description;

  /// List of blocks to repeat.
  ///
  /// Can contain PowerBlock or RampBlock, but not nested intervals.
  final List<dynamic> parts; // List of PowerBlock or RampBlock

  /// Number of times to repeat the interval.
  ///
  /// Repeat count of 1 means the interval is done once.
  final int repeat;

  /// Converts to JSON.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      if (description != null) 'description': description,
      'parts': parts.map((block) {
        if (block is PowerBlock) {
          return block.toJson();
        } else if (block is RampBlock) {
          return block.toJson();
        } else {
          throw ArgumentError('Invalid block type in interval parts: ${block.runtimeType}');
        }
      }).toList(),
      'repeat': repeat,
    };
  }

  /// Creates a copy with optional field replacements.
  WorkoutInterval copyWith({
    String? id,
    String? description,
    List<dynamic>? parts,
    int? repeat,
  }) {
    return WorkoutInterval(
      id: id ?? this.id,
      description: description ?? this.description,
      parts: parts ?? this.parts,
      repeat: repeat ?? this.repeat,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is WorkoutInterval &&
        other.id == id &&
        other.description == description &&
        other.repeat == repeat &&
        _listEquals(other.parts, parts);
  }

  @override
  int get hashCode => Object.hash(
        id,
        description,
        Object.hashAll(parts),
        repeat,
      );

  @override
  String toString() {
    return 'WorkoutInterval(id: $id, repeat: ${repeat}x, parts: ${parts.length} blocks, '
        'description: $description)';
  }
}

// ============================================================================
// Event Models
// ============================================================================

/// A message event to display during workout execution.
///
/// Messages are attached to blocks/intervals with a relative time offset
/// and shown to the user during workout playback.
class MessageEvent {
  /// Creates a message event.
  const MessageEvent({
    required this.id,
    required this.parentBlockId,
    required this.relativeTimeOffset,
    required this.text,
    this.duration,
  });

  /// Creates a message event from JSON.
  factory MessageEvent.fromJson(Map<String, dynamic> json) {
    return MessageEvent(
      id: pick(json, 'id').asStringOrThrow(),
      parentBlockId: pick(json, 'parentBlockId').asStringOrThrow(),
      relativeTimeOffset: pick(json, 'relativeTimeOffset').asIntOrThrow(),
      text: pick(json, 'text').asStringOrThrow(),
      duration: pick(json, 'duration').asIntOrNull(),
    );
  }

  /// Unique identifier for this event.
  final String id;

  /// Event type identifier (always 'message').
  String get type => 'message';

  /// ID of the parent block/interval this event is attached to.
  final String parentBlockId;

  /// Time offset in milliseconds relative to the parent block's start.
  final int relativeTimeOffset;

  /// Message text to display (max 128 characters).
  ///
  /// Keep messages simple, fun, and motivating. Longer messages should be
  /// split into multiple events.
  final String text;

  /// Duration in milliseconds to display the message.
  ///
  /// If not set, defaults to 10 seconds.
  final int? duration;

  /// Converts to JSON.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'parentBlockId': parentBlockId,
      'relativeTimeOffset': relativeTimeOffset,
      'text': text,
      if (duration != null) 'duration': duration,
    };
  }

  /// Creates a copy with optional field replacements.
  MessageEvent copyWith({
    String? id,
    String? parentBlockId,
    int? relativeTimeOffset,
    String? text,
    int? duration,
  }) {
    return MessageEvent(
      id: id ?? this.id,
      parentBlockId: parentBlockId ?? this.parentBlockId,
      relativeTimeOffset: relativeTimeOffset ?? this.relativeTimeOffset,
      text: text ?? this.text,
      duration: duration ?? this.duration,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is MessageEvent &&
        other.id == id &&
        other.parentBlockId == parentBlockId &&
        other.relativeTimeOffset == relativeTimeOffset &&
        other.text == text &&
        other.duration == duration;
  }

  @override
  int get hashCode => Object.hash(
        id,
        parentBlockId,
        relativeTimeOffset,
        text,
        duration,
      );

  @override
  String toString() {
    return 'MessageEvent(id: $id, offset: ${relativeTimeOffset}ms, text: "$text")';
  }
}

/// A visual effect event to trigger during workout execution.
///
/// Effects provide visual feedback and celebration during workouts.
class EffectEvent {
  /// Creates an effect event.
  const EffectEvent({
    required this.id,
    required this.parentBlockId,
    required this.relativeTimeOffset,
    required this.effect,
  });

  /// Creates an effect event from JSON.
  factory EffectEvent.fromJson(Map<String, dynamic> json) {
    return EffectEvent(
      id: pick(json, 'id').asStringOrThrow(),
      parentBlockId: pick(json, 'parentBlockId').asStringOrThrow(),
      relativeTimeOffset: pick(json, 'relativeTimeOffset').asIntOrThrow(),
      effect: _parseEffect(pick(json, 'effect').asStringOrThrow()),
    );
  }

  /// Unique identifier for this event.
  final String id;

  /// Event type identifier (always 'effect').
  String get type => 'effect';

  /// ID of the parent block/interval this event is attached to.
  final String parentBlockId;

  /// Time offset in milliseconds relative to the parent block's start.
  final int relativeTimeOffset;

  /// Type of visual effect to trigger.
  final EffectType effect;

  /// Converts to JSON.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'parentBlockId': parentBlockId,
      'relativeTimeOffset': relativeTimeOffset,
      'effect': effect.name,
    };
  }

  /// Creates a copy with optional field replacements.
  EffectEvent copyWith({
    String? id,
    String? parentBlockId,
    int? relativeTimeOffset,
    EffectType? effect,
  }) {
    return EffectEvent(
      id: id ?? this.id,
      parentBlockId: parentBlockId ?? this.parentBlockId,
      relativeTimeOffset: relativeTimeOffset ?? this.relativeTimeOffset,
      effect: effect ?? this.effect,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is EffectEvent &&
        other.id == id &&
        other.parentBlockId == parentBlockId &&
        other.relativeTimeOffset == relativeTimeOffset &&
        other.effect == effect;
  }

  @override
  int get hashCode => Object.hash(
        id,
        parentBlockId,
        relativeTimeOffset,
        effect,
      );

  @override
  String toString() {
    return 'EffectEvent(id: $id, offset: ${relativeTimeOffset}ms, effect: ${effect.name})';
  }
}

/// Type of visual effect.
enum EffectType {
  /// Fireworks celebration effect.
  fireworks,

  /// Confetti celebration effect.
  confetti,

  /// Explosion celebration effect.
  explosion,
}

/// Parses effect type from string.
EffectType _parseEffect(String value) {
  return EffectType.values.firstWhere(
    (e) => e.name == value,
    orElse: () => throw ArgumentError('Invalid effect type: $value'),
  );
}

// ============================================================================
// Flattened Event Models (for playback)
// ============================================================================

/// A message event with absolute time offset for playback.
///
/// Flattened version that includes the calculated absolute time offset
/// while preserving the original block-relative information for debugging.
class FlattenedMessageEvent {
  /// Creates a flattened message event.
  const FlattenedMessageEvent({
    required this.id,
    required this.timeOffset,
    required this.text,
    required this.parentBlockId,
    required this.relativeTimeOffset,
    this.duration,
  });

  /// Creates from a MessageEvent with calculated absolute time.
  factory FlattenedMessageEvent.fromMessageEvent(
    MessageEvent event,
    int absoluteTimeOffset,
  ) {
    return FlattenedMessageEvent(
      id: event.id,
      timeOffset: absoluteTimeOffset,
      text: event.text,
      parentBlockId: event.parentBlockId,
      relativeTimeOffset: event.relativeTimeOffset,
      duration: event.duration,
    );
  }

  /// Unique identifier for this event.
  final String id;

  /// Event type identifier (always 'message').
  String get type => 'message';

  /// Calculated absolute time offset in milliseconds for playback.
  final int timeOffset;

  /// Message text to display.
  final String text;

  /// Duration in milliseconds to display the message.
  final int? duration;

  /// Original parent block ID (preserved for debugging/context).
  final String parentBlockId;

  /// Original relative time offset (preserved for debugging/context).
  final int relativeTimeOffset;

  @override
  String toString() {
    return 'FlattenedMessageEvent(id: $id, timeOffset: ${timeOffset}ms, text: "$text")';
  }
}

/// An effect event with absolute time offset for playback.
///
/// Flattened version that includes the calculated absolute time offset
/// while preserving the original block-relative information for debugging.
class FlattenedEffectEvent {
  /// Creates a flattened effect event.
  const FlattenedEffectEvent({
    required this.id,
    required this.timeOffset,
    required this.effect,
    required this.parentBlockId,
    required this.relativeTimeOffset,
  });

  /// Creates from an EffectEvent with calculated absolute time.
  factory FlattenedEffectEvent.fromEffectEvent(
    EffectEvent event,
    int absoluteTimeOffset,
  ) {
    return FlattenedEffectEvent(
      id: event.id,
      timeOffset: absoluteTimeOffset,
      effect: event.effect,
      parentBlockId: event.parentBlockId,
      relativeTimeOffset: event.relativeTimeOffset,
    );
  }

  /// Unique identifier for this event.
  final String id;

  /// Event type identifier (always 'effect').
  String get type => 'effect';

  /// Calculated absolute time offset in milliseconds for playback.
  final int timeOffset;

  /// Type of visual effect to trigger.
  final EffectType effect;

  /// Original parent block ID (preserved for debugging/context).
  final String parentBlockId;

  /// Original relative time offset (preserved for debugging/context).
  final int relativeTimeOffset;

  @override
  String toString() {
    return 'FlattenedEffectEvent(id: $id, timeOffset: ${timeOffset}ms, effect: ${effect.name})';
  }
}

// ============================================================================
// Workout Plan Model
// ============================================================================

/// Complete workout plan containing all blocks and events.
///
/// This is the top-level model loaded from JSON representing a full workout.
class WorkoutPlan {
  /// Creates a workout plan.
  const WorkoutPlan({
    required this.plan,
    this.events = const [],
  });

  /// Creates a workout plan from JSON.
  factory WorkoutPlan.fromJson(Map<String, dynamic> json) {
    final planList = pick(json, 'plan').asListOrThrow<Map<String, dynamic>>((p) => p.asMapOrThrow<String, dynamic>());
    final eventsList = pick(json, 'events').asListOrEmpty<Map<String, dynamic>>((p) => p.asMapOrThrow<String, dynamic>());

    return WorkoutPlan(
      plan: planList.map((itemJson) {
        final type = pick(itemJson, 'type').asStringOrThrow();
        if (type == 'power') {
          return PowerBlock.fromJson(itemJson);
        } else if (type == 'ramp') {
          return RampBlock.fromJson(itemJson);
        } else if (type == 'interval') {
          return WorkoutInterval.fromJson(itemJson);
        } else {
          throw ArgumentError('Invalid plan item type: $type');
        }
      }).toList(),
      events: eventsList.map((eventJson) {
        final type = pick(eventJson, 'type').asStringOrThrow();
        if (type == 'message') {
          return MessageEvent.fromJson(eventJson);
        } else if (type == 'effect') {
          return EffectEvent.fromJson(eventJson);
        } else {
          throw ArgumentError('Invalid event type: $type');
        }
      }).toList(),
    );
  }

  /// List of workout plan items (blocks and intervals).
  final List<dynamic> plan; // List of PowerBlock, RampBlock, or WorkoutInterval

  /// List of events (messages and effects).
  final List<dynamic> events; // List of MessageEvent or EffectEvent

  /// Converts to JSON.
  Map<String, dynamic> toJson() {
    return {
      'plan': plan.map((item) {
        if (item is PowerBlock) {
          return item.toJson();
        } else if (item is RampBlock) {
          return item.toJson();
        } else if (item is WorkoutInterval) {
          return item.toJson();
        } else {
          throw ArgumentError('Invalid plan item type: ${item.runtimeType}');
        }
      }).toList(),
      'events': events.map((event) {
        if (event is MessageEvent) {
          return event.toJson();
        } else if (event is EffectEvent) {
          return event.toJson();
        } else {
          throw ArgumentError('Invalid event type: ${event.runtimeType}');
        }
      }).toList(),
    };
  }

  @override
  String toString() {
    return 'WorkoutPlan(plan: ${plan.length} items, events: ${events.length})';
  }
}

// ============================================================================
// Helpers
// ============================================================================

/// Helper for list equality comparison.
bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
