# Workout Domain Models

Phase 1 implementation of the Workout Player architecture - domain models and utilities for structured workout plans.

## Files

### `workout_models.dart`
Core domain models for workout plans:

**Block Types:**
- `PowerBlock` - Constant power blocks with fixed target
- `RampBlock` - Ramping power blocks with gradual progression
- `WorkoutInterval` - Repeating sets of blocks

**Event Types:**
- `MessageEvent` - Text messages displayed during workout
- `EffectEvent` - Visual effects (fireworks, confetti, explosion)

**Main Model:**
- `WorkoutPlan` - Complete workout containing plan items and events

**Flattened Event Models (for playback):**
- `FlattenedMessageEvent` - Message with absolute time offset
- `FlattenedEffectEvent` - Effect with absolute time offset

All models support:
- JSON serialization/deserialization using `deep_pick`
- Immutable design with `copyWith()` methods
- Proper equality and hashCode implementations
- Type-safe enums

### `workout_utils.dart`
Utility functions for workout manipulation:

**Plan Manipulation:**
- `flattenWorkoutPlan()` - Expand intervals into flat block list
- `calculateTotalDuration()` - Sum all block durations
- `calculateBlockDuration()` - Duration of single block/interval

**Event Flattening:**
- `flattenWorkoutEvents()` - Convert block-relative to absolute time

**Navigation:**
- `mapAbsoluteTimeToBlockRelative()` - Find block at specific time
- `mapBlockRelativeToAbsoluteTime()` - Convert relative to absolute
- `getBlockIndexAtTime()` - Get block index at time
- `findBlockById()` - Locate block by ID

**Power Calculations:**
- `calculatePowerAtTime()` - Interpolate power in ramp blocks
- `calculateCadenceAtTime()` - Interpolate cadence in ramp blocks

**Statistics:**
- `calculatePowerStats()` - Min/max power values
- `calculateCadenceStats()` - Min/max cadence values

### `example_workout.dart`
Example workouts demonstrating usage:
- `createVo2maxIntervalWorkout()` - VO2max interval session
- `createSweetSpotWorkout()` - Sweet spot training
- `createFtpTestWorkout()` - FTP test protocol
- `demonstrateUsage()` - Complete usage examples
- `exampleWorkoutJson` - JSON structure reference

## Key Design Decisions

### 1. **No build_runner**
Per CLAUDE.md preferences, models use manual JSON parsing with `deep_pick` instead of code generation. This provides:
- Explicit, readable JSON handling
- No build step required
- Safe null handling with `asStringOrNull()`, etc.

### 2. **Millisecond Precision**
All durations are in milliseconds (not seconds) for consistency with Dart's `Timer` and better precision in UI.

### 3. **Power as Relative Value**
Power values are stored as multipliers of FTP (0.5-5.0 range):
- `1.0` = 100% FTP
- `0.85` = 85% FTP
- `1.2` = 120% FTP

This allows workouts to scale automatically with user's FTP setting.

### 4. **Dynamic Lists with Type Checking**
Used `List<dynamic>` for plan items and events instead of strict unions, with runtime type checking in `fromJson()`:
```dart
final List<dynamic> plan; // PowerBlock | RampBlock | WorkoutInterval
final List<dynamic> events; // MessageEvent | EffectEvent
```

This is more flexible than Dart's type system allows while maintaining type safety through validation.

### 5. **Block-Relative Event Positioning**
Events are stored with:
- `parentBlockId` - ID of the containing block/interval
- `relativeTimeOffset` - Time from block start

This makes events reusable when intervals repeat. The `flattenWorkoutEvents()` function converts these to absolute times for playback.

### 6. **Immutable Data Classes**
All models are immutable with:
- `const` constructors where possible
- `copyWith()` methods for modifications
- Proper equality and hashCode implementations

### 7. **Comprehensive Documentation**
Every class, field, and function includes detailed documentation comments explaining:
- Purpose and usage
- Parameter ranges and constraints
- Examples
- Related functions

## JSON Structure

Example workout JSON:
```json
{
  "plan": [
    {
      "id": "warmup01",
      "type": "ramp",
      "description": "Warm up",
      "duration": 600000,
      "powerStart": 0.5,
      "powerEnd": 0.75
    },
    {
      "id": "intervals",
      "type": "interval",
      "repeat": 3,
      "parts": [
        {
          "id": "work001",
          "type": "power",
          "duration": 180000,
          "power": 1.10,
          "cadence": 95
        },
        {
          "id": "rest001",
          "type": "power",
          "duration": 180000,
          "power": 0.5
        }
      ]
    }
  ],
  "events": [
    {
      "id": "msg001",
      "type": "message",
      "parentBlockId": "warmup01",
      "relativeTimeOffset": 300000,
      "text": "Get ready!"
    }
  ]
}
```

## Usage Examples

### Load workout from JSON
```dart
final json = jsonDecode(workoutJsonString);
final workout = WorkoutPlan.fromJson(json);
```

### Calculate duration
```dart
final duration = calculateTotalDuration(workout.plan);
print('Workout: ${duration ~/ 1000 ~/ 60} minutes');
```

### Flatten for playback
```dart
final blocks = flattenWorkoutPlan(workout.plan);
final events = flattenWorkoutEvents(workout.plan, workout.events);

// Play through blocks sequentially
for (final block in blocks) {
  if (block is PowerBlock) {
    print('Hold ${(block.power * 100).toInt()}% for ${block.duration ~/ 1000}s');
  }
}
```

### Apply power scale factor
```dart
// Make workout 10% easier
final easierBlocks = flattenWorkoutPlan(
  workout.plan,
  powerScaleFactor: 0.9,
);
```

### Find current block
```dart
final elapsedTime = 900000; // 15 minutes
final position = mapAbsoluteTimeToBlockRelative(workout.plan, elapsedTime);
if (position != null) {
  print('In block ${position.blockId}');
}
```

### Calculate current power target
```dart
final block = blocks[currentIndex];
final timeInBlock = elapsedTime - blockStartTime;
final power = calculatePowerAtTime(block, timeInBlock);
final watts = power * userFtp;
```

## Testing

All models and utilities are tested in `/test/workout_models_test.dart`:
- JSON roundtrip serialization
- Block flattening with intervals
- Power scale factor application
- Event time calculation
- Power interpolation in ramps
- Navigation utilities

Run tests:
```bash
puro flutter test test/workout_models_test.dart
```

## Next Steps (Phase 2)

With domain models complete, Phase 2 will implement:
- `WorkoutPlayerService` - Timer loop and state management
- Integration with `WorkoutSyncService` for ERG control
- Reactive streams with `state_beacon`
- Power target calculation and updates

## Related Files

Web implementation reference:
- Types: `/vekolo-web/shared/types/workout.ts`
- Utils: `/vekolo-web/shared/utils/workout.ts`

Architecture documentation:
- `/WORKOUT_PLAYER_ARCHITECTURE.md`
