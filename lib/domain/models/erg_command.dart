/// ERG mode control command for smart trainers.
///
/// This command sets a target power level on trainers that support ERG mode.
/// Used by [WorkoutSyncService] to sync workout targets to the primary trainer.
library;

/// Command to set target power in ERG mode.
///
/// ERG mode automatically adjusts trainer resistance to maintain the specified
/// power output regardless of cadence or speed.
class ErgCommand {
  /// Creates an ERG mode command.
  const ErgCommand({required this.targetWatts, required this.timestamp});

  /// Target power output in watts.
  ///
  /// Trainer will adjust resistance to maintain this power level.
  /// Typical range: 0-1500W depending on trainer capabilities.
  final int targetWatts;

  /// Time when this command was created.
  ///
  /// Used for tracking command freshness and implementing periodic refresh
  /// for trainers that require continuous command updates.
  final DateTime timestamp;

  /// Creates a copy with optional field replacements.
  ErgCommand copyWith({int? targetWatts, DateTime? timestamp}) {
    return ErgCommand(targetWatts: targetWatts ?? this.targetWatts, timestamp: timestamp ?? this.timestamp);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is ErgCommand && other.targetWatts == targetWatts && other.timestamp == timestamp;
  }

  @override
  int get hashCode => Object.hash(targetWatts, timestamp);

  @override
  String toString() {
    return 'ErgCommand(targetWatts: $targetWatts, timestamp: $timestamp)';
  }
}
