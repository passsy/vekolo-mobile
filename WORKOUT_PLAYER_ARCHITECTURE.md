# Workout Player Architecture

## Overview
Implement a workout player that allows users to execute structured workouts with real-time power control of their trainer. Based on the web implementation at `/vekolo-web/app/models/WorkoutPlayer.ts`.

## Requirements
- Load workout from JSON (structure from save.json)
- Real-time playback with timer
- Automatic power updates to trainer via WorkoutSyncService
- Display current/next blocks, progress, elapsed time
- Pause/resume/skip functionality
- Event notifications (messages during workout)
- Power scale factor adjustment (FTP calibration)

## Architecture Layers

### 1. Domain Models (`lib/domain/models/workout/`)
**workout_models.dart**
- `WorkoutPlan` (list of WorkoutPlanItem)
- `WorkoutPlanItem` (union: WorkoutBlock | WorkoutInterval)
- `WorkoutBlock` (union: PowerBlock | RampBlock)
- `PowerBlock` (duration, power %, cadence targets)
- `RampBlock` (duration, power start/end %, cadence)
- `WorkoutInterval` (parts list, repeat count)
- `WorkoutEvent` (union: MessageEvent | EffectEvent)
- `MessageEvent` (parentBlockId, relativeTimeOffset, text)
- JSON serialization/deserialization

**workout_utils.dart**
- `flattenWorkoutPlan()` - expand intervals into flat list
- `calculateTotalDuration()` - sum all block durations
- `flattenWorkoutEvents()` - convert relative to absolute time

### 2. Service Layer (`lib/services/`)
**workout_player_service.dart**
- Manages workout execution state
- Timer loop (100ms intervals)
- Tracks: currentIndex, elapsedTime, isPaused, isComplete
- Reactive streams:
  - `currentBlock$` - current block being executed
  - `nextBlock$` - upcoming block
  - `powerTarget$` - current power target (W)
  - `progress$` - workout progress (0.0-1.0)
  - `remainingTime$` - time remaining (ms)
  - `events$` - stream of triggered events
- Methods:
  - `start()` - start/resume workout
  - `pause()` - pause workout
  - `skip()` - skip current block
  - `setPowerScaleFactor()` - adjust intensity
  - `complete()` - end workout early
- Integration: Updates WorkoutSyncService.currentTarget beacon with ERG commands

### 3. UI Layer (`lib/pages/`)
**workout_player_page.dart**
- Display workout progress chart
- Show current block info (power, duration, description)
- Display next block preview
- Timer display (elapsed / remaining / total)
- Progress bar
- Controls: Play/Pause, Skip, End Workout
- Power scale factor adjustment (+/- 1%)
- Event notifications (SnackBar or overlay)
- Real-time metrics (power, cadence, HR) from beacons

**workout_list_page.dart** (optional, later)
- Browse available workouts
- Select workout to execute

## Data Flow

```
User taps "Start Workout"
  ↓
Load workout JSON → Parse to WorkoutPlan model
  ↓
Create WorkoutPlayerService(plan, deviceManager, syncService)
  ↓
Navigate to WorkoutPlayerPage
  ↓
Player starts timer loop (100ms)
  ↓
Every tick:
  - Update elapsed time
  - Check if current block is complete → advance to next
  - Calculate current power target (with scale factor)
  - Update WorkoutSyncService.currentTarget beacon
  - Check for events to trigger
  - Update UI via streams
  ↓
WorkoutSyncService (existing)
  - Listens to currentTarget beacon
  - Sends ERG command to trainer
  ↓
Trainer adjusts resistance in ERG mode
```

## Integration Points

### Existing Services
- **DeviceManager**: Provide power/cadence/HR streams for display
- **WorkoutSyncService**: Receive power targets, handle ERG updates
- **DeviceStateManager**: Current metrics via beacons

### New Dependencies
- No new packages needed (use existing: state_beacon, async)

## Implementation Phases

### Phase 1: Domain Models
- Create workout data models
- JSON parsing (from save.json structure)
- Flatten utilities

### Phase 2: Player Service
- WorkoutPlayerService with timer loop
- State management with beacons
- Power target calculation (power block, ramp block)
- Event triggering system

### Phase 3: Player UI
- WorkoutPlayerPage layout
- Progress visualization
- Playback controls
- Integration with existing metric beacons

### Phase 4: Testing & Polish
- Unit tests for player logic
- Integration test with mock workout
- Edge cases (pause/resume, skip, complete early)
- Error handling

## Key Differences from Web

1. **State Management**: Use state_beacon instead of Vue refs
2. **Timer**: Use Dart Timer.periodic instead of setTimeout
3. **UI**: Flutter widgets instead of Vue components
4. **FTP**: Will initially use hardcoded 200W, later integrate with user profile

## Success Criteria
- ✅ Load workout from JSON file
- ✅ Display workout plan and progress
- ✅ Execute workout with timer
- ✅ Update trainer power in real-time
- ✅ Show current/next blocks
- ✅ Pause/resume/skip controls work
- ✅ Events trigger at correct times
- ✅ Power scale factor adjustable
- ✅ Complete workout flow (start → play → finish)
