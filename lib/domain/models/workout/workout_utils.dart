/// Utility functions for workout plan manipulation and calculations.
///
/// Based on the web implementation at `/vekolo-web/shared/utils/workout.ts`.
library;

import 'package:chirp/chirp.dart';
import 'package:vekolo/domain/models/workout/workout_models.dart';

// ============================================================================
// Workout Plan Flattening
// ============================================================================

/// Flattens a workout plan into a linear list of blocks.
///
/// Expands all intervals into their individual blocks based on repeat counts,
/// and optionally scales power values by a factor (for FTP adjustments).
///
/// Example:
/// ```dart
/// final plan = [
///   PowerBlock(duration: 300000, power: 0.5),
///   WorkoutInterval(
///     repeat: 3,
///     parts: [
///       PowerBlock(duration: 60000, power: 1.0),
///       PowerBlock(duration: 60000, power: 0.6),
///     ],
///   ),
/// ];
///
/// final flattened = flattenWorkoutPlan(plan);
/// // Returns: [warmup, work1, rest1, work2, rest2, work3, rest3]
/// ```
List<dynamic> flattenWorkoutPlan(List<dynamic> plan, {double powerScaleFactor = 1.0}) {
  final flattened = <dynamic>[];

  void processItem(dynamic item) {
    if (item is PowerBlock) {
      flattened.add(item.copyWith(power: item.power * powerScaleFactor));
    } else if (item is RampBlock) {
      flattened.add(
        item.copyWith(powerStart: item.powerStart * powerScaleFactor, powerEnd: item.powerEnd * powerScaleFactor),
      );
    } else if (item is WorkoutInterval) {
      for (var i = 0; i < item.repeat; i++) {
        for (final part in item.parts) {
          processItem(part);
        }
      }
    }
  }

  for (final item in plan) {
    processItem(item);
  }

  return flattened;
}

// ============================================================================
// Duration Calculations
// ============================================================================

/// Calculates the total duration of a workout plan in milliseconds.
///
/// Sums all block durations including expanded intervals.
///
/// Example:
/// ```dart
/// final duration = calculateTotalDuration(plan);
/// print('Workout is ${duration / 1000 / 60} minutes long');
/// ```
int calculateTotalDuration(List<dynamic> plan) {
  final flattened = flattenWorkoutPlan(plan);
  return flattened.fold<int>(0, (total, block) {
    if (block is PowerBlock) {
      return total + block.duration;
    } else if (block is RampBlock) {
      return total + block.duration;
    }
    return total;
  });
}

/// Calculates the duration of a single block or interval.
///
/// For intervals, calculates the total duration including all repetitions.
int calculateBlockDuration(dynamic item) {
  if (item is PowerBlock) {
    return item.duration;
  } else if (item is RampBlock) {
    return item.duration;
  } else if (item is WorkoutInterval) {
    final singleRepDuration = item.parts.fold<int>(0, (total, part) => total + calculateBlockDuration(part));
    return singleRepDuration * item.repeat;
  }
  return 0;
}

// ============================================================================
// Event Flattening
// ============================================================================

/// Flattens block-relative events into absolute time events for playback.
///
/// Converts events with parent block IDs and relative offsets into events
/// with absolute time offsets from the workout start.
///
/// Example:
/// ```dart
/// final events = [
///   MessageEvent(
///     parentBlockId: 'block123',
///     relativeTimeOffset: 30000, // 30s into the block
///     text: 'Push harder!',
///   ),
/// ];
///
/// final flattened = flattenWorkoutEvents(plan, events);
/// // Returns events with absolute timeOffset calculated from workout start
/// ```
List<dynamic> flattenWorkoutEvents(List<dynamic> plan, List<dynamic> events) {
  if (events.isEmpty) return [];

  // Build a map of block IDs to their start times in the workout
  final blockStartTimes = <String, int>{};
  var cumulativeTime = 0;

  for (final planItem in plan) {
    if (planItem is PowerBlock) {
      blockStartTimes[planItem.id] = cumulativeTime;
      cumulativeTime += planItem.duration;
    } else if (planItem is RampBlock) {
      blockStartTimes[planItem.id] = cumulativeTime;
      cumulativeTime += planItem.duration;
    } else if (planItem is WorkoutInterval) {
      blockStartTimes[planItem.id] = cumulativeTime;
      final intervalDuration = calculateBlockDuration(planItem);
      cumulativeTime += intervalDuration;
    }
  }

  // Flatten events by adding block start time to relative offset
  final flattenedEvents = events
      .where((event) {
        final parentBlockId = event is MessageEvent ? event.parentBlockId : (event as EffectEvent).parentBlockId;
        final startTime = blockStartTimes[parentBlockId];
        if (startTime == null) {
          Chirp.info('WARNING: Event ${(event as dynamic).id} references unknown block $parentBlockId');
          return false;
        }
        return true;
      })
      .map((event) {
        final parentBlockId = event is MessageEvent ? event.parentBlockId : (event as EffectEvent).parentBlockId;
        final startTime = blockStartTimes[parentBlockId]!;

        if (event is MessageEvent) {
          return FlattenedMessageEvent.fromMessageEvent(event, startTime + event.relativeTimeOffset);
        } else {
          final effectEvent = event as EffectEvent;
          return FlattenedEffectEvent.fromEffectEvent(effectEvent, startTime + effectEvent.relativeTimeOffset);
        }
      })
      .toList();

  // Sort by absolute time offset
  flattenedEvents.sort((a, b) {
    final aTime = a is FlattenedMessageEvent ? a.timeOffset : (a as FlattenedEffectEvent).timeOffset;
    final bTime = b is FlattenedMessageEvent ? b.timeOffset : (b as FlattenedEffectEvent).timeOffset;
    return aTime.compareTo(bTime);
  });

  return flattenedEvents;
}

// ============================================================================
// Block Navigation
// ============================================================================

/// Maps absolute workout time to block-relative positioning.
///
/// Returns the parent block ID and relative time offset for a given
/// absolute time in the workout. Returns null if the time is beyond
/// the workout duration.
///
/// Example:
/// ```dart
/// final position = mapAbsoluteTimeToBlockRelative(plan, 90000); // 90 seconds
/// if (position != null) {
///   print('At block ${position.blockId}, ${position.offset}ms into it');
/// }
/// ```
({String blockId, int offset})? mapAbsoluteTimeToBlockRelative(List<dynamic> plan, int absoluteTime) {
  var cumulativeTime = 0;

  for (final planItem in plan) {
    final duration = calculateBlockDuration(planItem);

    if (absoluteTime >= cumulativeTime && absoluteTime <= cumulativeTime + duration) {
      final relativeTime = absoluteTime - cumulativeTime;

      final blockId = planItem is PowerBlock
          ? planItem.id
          : planItem is RampBlock
          ? planItem.id
          : planItem is WorkoutInterval
          ? planItem.id
          : null;

      if (blockId == null) {
        cumulativeTime += duration;
        continue;
      }

      return (blockId: blockId, offset: _roundToNearest100ms(relativeTime));
    }

    cumulativeTime += duration;
  }

  return null;
}

/// Maps block-relative time to absolute workout time.
///
/// Returns the absolute time offset from workout start for a given
/// block ID and relative offset within that block. Returns null if
/// the block is not found.
int? mapBlockRelativeToAbsoluteTime(List<dynamic> plan, String parentBlockId, int relativeTimeOffset) {
  var cumulativeTime = 0;

  for (final planItem in plan) {
    final blockId = planItem is PowerBlock
        ? planItem.id
        : planItem is RampBlock
        ? planItem.id
        : planItem is WorkoutInterval
        ? planItem.id
        : null;

    if (blockId == parentBlockId) {
      return cumulativeTime + relativeTimeOffset;
    }

    cumulativeTime += calculateBlockDuration(planItem);
  }

  return null;
}

// ============================================================================
// Power Calculations
// ============================================================================

/// Calculates the current power target at a specific time in a block.
///
/// For power blocks, returns the constant power value.
/// For ramp blocks, interpolates between start and end power based on
/// the elapsed time within the block.
///
/// Example:
/// ```dart
/// final ramp = RampBlock(
///   duration: 60000,
///   powerStart: 0.6,
///   powerEnd: 1.0,
/// );
/// final power = calculatePowerAtTime(ramp, 30000); // Halfway through
/// // Returns 0.8 (midpoint between 0.6 and 1.0)
/// ```
double calculatePowerAtTime(dynamic block, int elapsedTime) {
  if (block is PowerBlock) {
    return block.power;
  } else if (block is RampBlock) {
    // Interpolate power based on elapsed time
    final progress = elapsedTime / block.duration;
    final clampedProgress = progress.clamp(0.0, 1.0);
    return block.powerStart + (block.powerEnd - block.powerStart) * clampedProgress;
  }
  return 0.0;
}

/// Calculates the current cadence target at a specific time in a block.
///
/// For power blocks, returns the constant cadence value (if set).
/// For ramp blocks, interpolates between start and end cadence based on
/// the elapsed time within the block.
int? calculateCadenceAtTime(dynamic block, int elapsedTime) {
  if (block is PowerBlock) {
    return block.cadence;
  } else if (block is RampBlock) {
    if (block.cadenceStart == null || block.cadenceEnd == null) {
      return null;
    }
    // Interpolate cadence based on elapsed time
    final progress = elapsedTime / block.duration;
    final clampedProgress = progress.clamp(0.0, 1.0);
    final interpolated = block.cadenceStart! + (block.cadenceEnd! - block.cadenceStart!) * clampedProgress;
    return interpolated.round();
  }
  return null;
}

// ============================================================================
// Statistics
// ============================================================================

/// Calculates power statistics for a workout plan.
///
/// Returns the minimum and maximum power values in the plan.
({double minPower, double maxPower}) calculatePowerStats(List<dynamic> plan) {
  var minPower = double.infinity;
  var maxPower = double.negativeInfinity;

  void processItem(dynamic item) {
    if (item is PowerBlock) {
      minPower = minPower < item.power ? minPower : item.power;
      maxPower = maxPower > item.power ? maxPower : item.power;
    } else if (item is RampBlock) {
      minPower = minPower < item.powerStart ? minPower : item.powerStart;
      minPower = minPower < item.powerEnd ? minPower : item.powerEnd;
      maxPower = maxPower > item.powerStart ? maxPower : item.powerStart;
      maxPower = maxPower > item.powerEnd ? maxPower : item.powerEnd;
    } else if (item is WorkoutInterval) {
      for (final part in item.parts) {
        processItem(part);
      }
    }
  }

  for (final item in plan) {
    processItem(item);
  }

  return (minPower: minPower.isInfinite ? 0.0 : minPower, maxPower: maxPower.isInfinite ? 0.0 : maxPower);
}

/// Calculates cadence statistics for a workout plan.
///
/// Returns the minimum and maximum cadence values in the plan.
/// Only considers blocks with explicit cadence targets.
({int minCadence, int maxCadence}) calculateCadenceStats(List<dynamic> plan) {
  var minCadence = double.infinity;
  var maxCadence = double.negativeInfinity;

  void processItem(dynamic item) {
    if (item is PowerBlock) {
      if (item.cadence != null) {
        minCadence = minCadence < item.cadence! ? minCadence : item.cadence!.toDouble();
        maxCadence = maxCadence > item.cadence! ? maxCadence : item.cadence!.toDouble();
      }
      if (item.cadenceLow != null) {
        minCadence = minCadence < item.cadenceLow! ? minCadence : item.cadenceLow!.toDouble();
      }
      if (item.cadenceHigh != null) {
        maxCadence = maxCadence > item.cadenceHigh! ? maxCadence : item.cadenceHigh!.toDouble();
      }
    } else if (item is RampBlock) {
      if (item.cadenceStart != null) {
        minCadence = minCadence < item.cadenceStart! ? minCadence : item.cadenceStart!.toDouble();
        maxCadence = maxCadence > item.cadenceStart! ? maxCadence : item.cadenceStart!.toDouble();
      }
      if (item.cadenceEnd != null) {
        minCadence = minCadence < item.cadenceEnd! ? minCadence : item.cadenceEnd!.toDouble();
        maxCadence = maxCadence > item.cadenceEnd! ? maxCadence : item.cadenceEnd!.toDouble();
      }
      if (item.cadenceLow != null) {
        minCadence = minCadence < item.cadenceLow! ? minCadence : item.cadenceLow!.toDouble();
      }
      if (item.cadenceHigh != null) {
        maxCadence = maxCadence > item.cadenceHigh! ? maxCadence : item.cadenceHigh!.toDouble();
      }
    } else if (item is WorkoutInterval) {
      for (final part in item.parts) {
        processItem(part);
      }
    }
  }

  for (final item in plan) {
    processItem(item);
  }

  return (
    minCadence: minCadence.isInfinite ? 0 : minCadence.round(),
    maxCadence: maxCadence.isInfinite ? 0 : maxCadence.round(),
  );
}

// ============================================================================
// Helpers
// ============================================================================

/// Rounds time to the nearest 100ms for consistency.
int _roundToNearest100ms(int timeMs) {
  return (timeMs / 100).round() * 100;
}

/// Finds a block by ID in the workout plan.
///
/// Searches both top-level blocks and blocks within intervals.
/// Returns null if the block is not found.
dynamic findBlockById(List<dynamic> plan, String blockId) {
  for (final item in plan) {
    if (item is PowerBlock && item.id == blockId) {
      return item;
    } else if (item is RampBlock && item.id == blockId) {
      return item;
    } else if (item is WorkoutInterval) {
      if (item.id == blockId) {
        return item;
      }
      // Check inside interval parts
      final foundPart = item.parts.firstWhere(
        (part) => (part is PowerBlock && part.id == blockId) || (part is RampBlock && part.id == blockId),
        orElse: () => null,
      );
      if (foundPart != null) {
        return foundPart;
      }
    }
  }
  return null;
}

/// Gets the index of the block containing the specified absolute time.
///
/// Returns -1 if the time is beyond the workout duration.
int getBlockIndexAtTime(List<dynamic> plan, int absoluteTime) {
  var cumulativeTime = 0;

  for (var i = 0; i < plan.length; i++) {
    final duration = calculateBlockDuration(plan[i]);

    if (absoluteTime >= cumulativeTime && absoluteTime < cumulativeTime + duration) {
      return i;
    }

    cumulativeTime += duration;
  }

  return -1;
}
