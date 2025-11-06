# Workout Recording Implementation Plan

## Overview

Implement persistent workout session recording with 1Hz metric sampling, stale data detection, and crash recovery. Local-first storage with future cloud sync capability.

## Requirements

### Functional Requirements

1. **Continuous Recording**
   - Record metrics every 1 second during active workout
   - Capture: power (actual + target), HR, cadence, speed, power scale factor
   - Save to persistent storage incrementally (survive app kill)

2. **Stale Data Detection**
   - Detect when BLE sensors stop sending data
   - Timeout: 5 seconds without updates
   - Behavior: Return `null` instead of stale value
   - Apply to: power, cadence, speed, heart rate

3. **Crash Recovery**
   - Detect incomplete sessions on app restart
   - Show resume dialog with session info
   - Options: Resume, Discard, Start Fresh
   - Restore exact workout state (elapsed time, current block)

4. **Session States**
   - `active` - currently recording
   - `completed` - workout finished normally
   - `abandoned` - user manually discarded
   - `crashed` - app closed unexpectedly during workout

5. **Storage Strategy**
   - Local-first: SharedPreferences + JSON files
   - One file per session (samples)
   - Metadata in SharedPreferences
   - Future: Cloud sync to backend API

### Non-Functional Requirements

- **Performance**: Recording must not impact UI (background thread if needed)
- **Memory**: Don't hold all samples in RAM - flush to disk periodically
- **Reliability**: No data loss even with force quit
- **Code Style**: Follow state_beacon patterns, no manual subscriptions
- **Testing**: TDD approach - robot test first, then implementation


## Workout Session Files

### Storage Location

All workout data is stored locally on your device:

- Organized in individual folders (one per workout)
- Each workout gets a unique ID (like `V1StGXR8_Z5jdHi6B-myT`)
- Stored in your app's private documents directory
- Easy to manage - delete a workout by removing its folder

**Directory Structure:**
```
Workouts/
├── V1StGXR8_Z5jdHi6B-myT/     (Sweet Spot Intervals)
│   ├── metadata.json
│   └── samples.jsonl
├── A2bK9xF3_P8qR4mN6-vWz/     (FTP Test)
│   ├── metadata.json
│   └── samples.jsonl
└── ...
```

### File Contents

Each workout folder contains two files:

**Metadata File** (`metadata.json`):
- Unique workout ID
- Workout name (e.g., "Sweet Spot Intervals")
- Complete workout plan (allows resuming exactly where you left off)
- Start and end times
- Completion status (completed, abandoned, crashed)
- User ID (if logged in)
- Your FTP at time of workout (for historical comparison)
- Total sample count

**Samples File** (`samples.jsonl`):
- One line per second of data (JSONL format)
- Each line is a complete JSON object
- Efficient append-only format
- Standard format supported by data analysis tools (Python, R, jq, etc.)

**Example sample line:**
```json
{"timestamp":"2025-01-15T10:15:23Z","elapsedMs":123000,"powerActual":195,"powerTarget":200,"cadence":88,"speed":35.2,"heartRate":145,"powerScaleFactor":1.0}
```

## Architecture

### Data Flow

```
BLE Notifications → Transport Layer → DeviceManager (with staleness check)
                                              ↓
                                    WorkoutRecordingService (1Hz sampling)
                                              ↓
                                    WorkoutSessionPersistence
                                              ↓
                              SharedPreferences + JSON Files
                                              ↓
                                    (Future) Backend API Sync
```

### Component Responsibilities

#### 1. **Stale Data Detection (DeviceManager Layer)**

**Why here?** Centralized location - all consumers benefit from clean data.

**Approach:** Modify derived beacons to check timestamp age.

```dart
late final ReadableBeacon<PowerData?> _powerBeacon = Beacon.derived(() {
  final device = /* ... get device ... */;
  final data = device?.powerStream?.value;
  if (data == null) return null;

  // Staleness check
  final age = clock.now().difference(data.timestamp);
  if (age > Duration(seconds: 5)) return null;

  return data;
});
```

**Benefits:**
- ✅ Follows state_beacon transform chain pattern
- ✅ No subscriptions needed
- ✅ UI automatically shows "--" for stale data
- ✅ Recording service gets clean data

#### 2. **WorkoutRecordingService**

**Responsibilities:**
- Create session on workout start
- Sample metrics every 1 second
- Write samples to persistence layer
- Handle pause/resume (pause sampling, not recording)
- Complete session on workout end
- Proper cleanup on dispose

**Key Design:**
```dart
class WorkoutRecordingService {
  final WorkoutPlayerService _playerService;
  final DeviceManager _deviceManager;
  final WorkoutSessionPersistence _persistence;
  final Clock _clock;

  Timer? _recordingTimer;
  String? _sessionId;

  void startRecording(String workoutName) {
    _sessionId = _persistence.createSession(workoutName);
    _startSampling();
  }

  void _startSampling() {
    _recordingTimer = Timer.periodic(Duration(seconds: 1), (_) {
      final sample = _collectSample();
      _persistence.saveSample(_sessionId!, sample);
    });
  }

  WorkoutSample _collectSample() {
    // Read current values from beacons (no subscriptions!)
    return WorkoutSample(
      timestamp: _clock.now(),
      elapsedMs: _playerService.elapsedTime$.value,
      powerActual: _deviceManager.powerStream.value?.watts,
      powerTarget: _playerService.powerTarget$.value,
      cadence: _deviceManager.cadenceStream.value?.rpm,
      speed: _deviceManager.speedStream.value?.kmh,
      heartRate: _deviceManager.heartRateStream.value?.bpm,
      powerScaleFactor: _playerService.powerScaleFactor.value,
    );
  }

  void stopRecording({required bool completed}) {
    _recordingTimer?.cancel();
    if (_sessionId != null) {
      _persistence.updateSessionStatus(
        _sessionId!,
        completed ? SessionStatus.completed : SessionStatus.abandoned,
      );
    }
  }

  void dispose() {
    _recordingTimer?.cancel();
  }
}
```

**State Management:**
- No beacons needed (this is a background service)
- Just reads from other beacons
- Timer handles periodic sampling

#### 3. **WorkoutSessionPersistence**

**Responsibilities:**
- Create/load/update sessions
- Save samples to disk (batched writes for performance)
- Detect active session (crash recovery)
- Cleanup old sessions (future)

**Storage Structure:**

**Storage Layers (Clear Separation):**
```
┌─────────────────────────────────────────────────────────────────┐
│ SharedPreferences (App State - Crash Detection Only)           │
├─────────────────────────────────────────────────────────────────┤
│ "vekolo.workout_sessions.active" = "V1StGXR8_Z5jdHi6B-myT"     │
│                                                                  │
│ ✅ ONLY stores which workout is currently active                │
│ ❌ NO workout data, NO metadata, NO lists                       │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ File System (All Workout Data)                                  │
├─────────────────────────────────────────────────────────────────┤
│ workouts/                                                        │
│ ├── V1StGXR8_Z5jdHi6B-myT/                                      │
│ │   ├── metadata.json      ← ALL workout info (name, status,   │
│ │   │                          plan, timestamps, resume state)  │
│ │   └── samples.jsonl      ← Recorded data (1 line/second)     │
│ ├── A2bK9xF3_P8qR4mN6-vWz/                                      │
│ │   ├── metadata.json                                           │
│ │   └── samples.jsonl                                           │
│ └── ...                                                          │
│                                                                  │
│ ✅ Complete, self-contained workout data                        │
│ ✅ Portable (can copy/delete folders independently)             │
│ ✅ Future-proof (add more files per workout as needed)          │
└─────────────────────────────────────────────────────────────────┘
```

**Workout ID Generation:**
- Use `nanoid2` package (already available as transitive dependency)
- Example ID: `V1StGXR8_Z5jdHi6B-myT` (21 characters, URL-safe)
- Shorter and more readable than UUIDs
- Cryptographically random, collision-resistant

**Directory Structure:**
```
<app_documents>/workouts/
├── V1StGXR8_Z5jdHi6B-myT/          # Workout folder (nanoid)
│   ├── metadata.json                # Workout metadata
│   └── samples.jsonl                # Recorded samples (append-only)
├── A2bK9xF3_P8qR4mN6-vWz/          # Another workout
│   ├── metadata.json
│   └── samples.jsonl
└── ...
```

**Benefits of One Folder Per Workout:**
- ✅ Clean organization - all workout data grouped together
- ✅ Easy to delete entire workout (just delete folder)
- ✅ Future extensibility:
  - Add `chart.png` for power profile visualization
  - Add `export.fit` or `export.tcx` for third-party apps
  - Add `summary.json` for post-workout analysis
  - Add `notes.txt` for user notes
- ✅ Simple to list workouts (just list directories)
- ✅ Web-compatible (future requirement)

**SharedPreferences (Crash Detection):**
```json
{
  "vekolo.workout_sessions.active": "V1StGXR8_Z5jdHi6B-myT"
}
```

**How Crash Detection Works:**
1. **Workout starts**: Set `active` key to workout ID in SharedPreferences
2. **Workout completes/abandoned**: Clear `active` key (set to `null`)
3. **App startup**: Check if `active` key exists and is non-null
4. **If exists**: Load that specific workout's metadata from `workouts/{id}/metadata.json`
5. **Show resume dialog** with workout info from metadata

**Benefits:**
- ✅ **O(1) crash detection** - just check one SharedPreferences key
- ✅ **No folder scanning** - instant app startup
- ✅ **Works even if metadata corrupted** - can fall back to cleanup
- ✅ **Simple and fast** - single string read

**Implementation:**
```dart
class WorkoutSessionPersistence {
  static const _activeWorkoutKey = 'vekolo.workout_sessions.active';

  Future<String?> getActiveWorkoutId() async {
    return await _prefs.getString(_activeWorkoutKey);
  }

  Future<void> setActiveWorkout(String workoutId) async {
    await _prefs.setString(_activeWorkoutKey, workoutId);
  }

  Future<void> clearActiveWorkout() async {
    await _prefs.remove(_activeWorkoutKey);
  }

  Future<WorkoutSession?> getActiveSession() async {
    final workoutId = await getActiveWorkoutId();
    if (workoutId == null) return null;

    // Load metadata from file
    final metadata = await loadSessionMetadata(workoutId);
    if (metadata == null) {
      // Metadata file missing - cleanup orphaned active flag
      await clearActiveWorkout();
      return null;
    }

    return WorkoutSession(
      id: workoutId,
      workoutName: metadata.workoutName,
      startTime: metadata.startTime,
      status: metadata.status,
      // ... other fields from metadata
    );
  }
}
```

---

### Storage Responsibilities Summary

**SharedPreferences (ONLY crash detection marker):**
- ✅ Active workout ID: `vekolo.workout_sessions.active` = `"V1StGXR8_Z5jdHi6B-myT"`
- ❌ NO workout metadata (name, status, timestamps, etc.)
- ❌ NO workout index/list

**Workout Metadata Files (ALL workout data):**
- ✅ Workout name, status, timestamps
- ✅ Complete workout plan (for resume)
- ✅ User ID, FTP, sample counts
- ✅ Everything needed to display workout info

**Listing Workouts (future feature):**
- Option 1: List directories in `workouts/` folder (simple, no index needed)
- Option 2: Maintain separate index file `workouts/index.json` (faster for large lists)
- For Phase 1: Not needed, only crash recovery matters

**Why this separation?**
- SharedPreferences is for app-level state (which workout is active)
- Files are for data persistence (actual workout content)
- Keeps concerns separated and data portable

**Metadata File** (`workouts/V1StGXR8_Z5jdHi6B-myT/metadata.json`):
```json
{
  "workoutId": "V1StGXR8_Z5jdHi6B-myT",
  "workoutName": "Sweet Spot Intervals",
  "workoutPlanJson": {
    "plan": [...],
    "events": [...]
  },
  "startTime": "2025-01-15T10:00:00.000Z",
  "endTime": null,
  "status": "active",
  "userId": "user-456",
  "ftp": 200,
  "totalSamples": 123,
  "currentBlockIndex": 2,
  "elapsedMs": 123000,
  "lastUpdated": "2025-01-15T10:02:03.000Z"
}
```

**Note:** ALL workout data lives in this file. SharedPreferences only contains the workout ID for crash detection.

**Samples File - JSONL** (`workouts/V1StGXR8_Z5jdHi6B-myT/samples.jsonl`):
```jsonl
{"timestamp":"2025-01-15T10:00:01.000Z","elapsedMs":1000,"powerActual":195,"powerTarget":200,"cadence":88,"speed":35.2,"heartRate":145,"powerScaleFactor":1.0}
{"timestamp":"2025-01-15T10:00:02.000Z","elapsedMs":2000,"powerActual":198,"powerTarget":200,"cadence":90,"speed":35.5,"heartRate":146,"powerScaleFactor":1.0}
{"timestamp":"2025-01-15T10:00:03.000Z","elapsedMs":3000,"powerActual":null,"powerTarget":200,"cadence":null,"speed":null,"heartRate":147,"powerScaleFactor":1.0}
```

**Why JSONL (JSON Lines)?**
- ✅ Append-only: Add new sample without reading entire file
- ✅ Efficient: Write single line, no JSON array manipulation
- ✅ Crash-safe: Each line is valid JSON, partial files still readable
- ✅ Streaming: Can process line-by-line without loading all into memory
- ✅ Standard format: Many tools support JSONL (jq, data analysis tools)

**API:**
```dart
class WorkoutSessionPersistence {
  final SharedPreferencesAsync _prefs;
  final Clock _clock;
  final String _workoutsBasePath; // <app_documents>/workouts/

  // Session lifecycle
  Future<String> createSession(String workoutName, WorkoutPlan plan, {String? userId, int? ftp});
  Future<WorkoutSession?> getActiveSession();
  Future<WorkoutSessionMetadata?> loadSessionMetadata(String workoutId);
  Future<void> updateSessionStatus(String workoutId, SessionStatus status);
  Future<void> updateSessionMetadata(String workoutId, WorkoutSessionMetadata metadata);

  // Sample storage (JSONL append-only)
  Future<void> appendSample(String workoutId, WorkoutSample sample);
  Future<void> appendSamples(String workoutId, List<WorkoutSample> samples); // Batch
  Stream<WorkoutSample> loadSamples(String workoutId); // Streaming read
  Future<List<WorkoutSample>> loadAllSamples(String workoutId); // Full read

  // Directory management
  Future<Directory> getWorkoutDirectory(String workoutId); // workouts/{id}/
  Future<File> getMetadataFile(String workoutId); // workouts/{id}/metadata.json
  Future<File> getSamplesFile(String workoutId); // workouts/{id}/samples.jsonl
  Future<List<String>> listWorkoutIds(); // List all workout folder names

  // Cleanup
  Future<void> clearActiveSession();
  Future<void> deleteSession(String workoutId); // Deletes entire folder
}
```

**Performance Optimization:**
- Batch writes: Buffer 5 samples, write together (5 lines appended at once)
- Avoid blocking UI thread
- Use `SharedPreferencesAsync` (non-blocking)
- JSONL append mode: Open file in append mode, write new line, close
- No need to read entire file to add samples
- Metadata file updated periodically (every N samples, on status change)
- Lazy directory creation: Only create workout folder when first sample recorded

#### 4. **WorkoutResumeDialog**

**Responsibilities:**
- Display session info (workout name, elapsed time, last sample)
- Provide action buttons
- Return user choice to caller

**Widget:**
```dart
class WorkoutResumeDialog extends StatelessWidget {
  final WorkoutSession session;
  final VoidCallback onResume;
  final VoidCallback onDiscard;
  final VoidCallback onStartFresh;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Resume Workout?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Workout: ${session.workoutName}'),
          Text('Elapsed: ${_formatDuration(session.elapsedMs)}'),
          Text('Last recorded: ${_formatTimestamp(session.lastSampleTime)}'),
        ],
      ),
      actions: [
        TextButton(onPressed: onDiscard, child: Text('Discard')),
        TextButton(onPressed: onStartFresh, child: Text('Start Fresh')),
        ElevatedButton(onPressed: onResume, child: Text('Resume')),
      ],
    );
  }
}
```

#### 5. **WorkoutPlayerPage Integration**

**Modified Flow:**

```dart
class _WorkoutPlayerPageState extends State<WorkoutPlayerPage> {
  WorkoutRecordingService? _recordingService;

  @override
  void initState() {
    super.initState();
    _checkForActiveSession(); // NEW: Check for crash recovery
  }

  Future<void> _checkForActiveSession() async {
    final persistence = Refs.workoutSessionPersistence.of(context);
    final activeSession = await persistence.getActiveSession();

    if (activeSession != null && mounted) {
      final choice = await showDialog<ResumeChoice>(
        context: context,
        builder: (ctx) => WorkoutResumeDialog(
          session: activeSession,
          onResume: () => Navigator.pop(ctx, ResumeChoice.resume),
          onDiscard: () => Navigator.pop(ctx, ResumeChoice.discard),
          onStartFresh: () => Navigator.pop(ctx, ResumeChoice.startFresh),
        ),
      );

      if (choice == ResumeChoice.resume) {
        await _resumeWorkout(activeSession);
      } else if (choice == ResumeChoice.discard) {
        await persistence.updateSessionStatus(
          activeSession.id,
          SessionStatus.abandoned,
        );
      } else {
        await persistence.deleteSession(activeSession.id);
      }
    }

    if (mounted) {
      _loadWorkout();
    }
  }

  Future<void> _resumeWorkout(WorkoutSession session) async {
    // Load workout normally
    await _loadWorkout();

    // Restore player state
    _playerService?.restoreState(
      elapsedMs: session.elapsedMs,
      currentBlockIndex: session.currentBlockIndex,
    );

    // Resume recording
    _recordingService = WorkoutRecordingService(
      playerService: _playerService!,
      deviceManager: Refs.deviceManager.of(context),
      persistence: Refs.workoutSessionPersistence.of(context),
      sessionId: session.id, // Existing session
    );
    _recordingService!.resumeRecording();
  }

  void _setupPowerMonitoring(...) {
    // ... existing auto-start logic ...

    if (!_hasStarted && currentPower >= startResumeThreshold) {
      playerService.start();

      // NEW: Start recording
      _recordingService = WorkoutRecordingService(
        playerService: playerService,
        deviceManager: deviceManager,
        persistence: Refs.workoutSessionPersistence.of(context),
      );
      _recordingService!.startRecording(_playerService!.workoutPlan.name);

      setState(() => _hasStarted = true);
    }
  }

  @override
  void dispose() {
    _recordingService?.dispose();
    // ... existing dispose ...
  }
}
```

#### 6. **WorkoutPlayerService State Restoration**

**New Methods:**

```dart
class WorkoutPlayerService {
  String? sessionId; // NEW: Track recording session

  // NEW: Restore from saved state
  void restoreState({
    required int elapsedMs,
    required int currentBlockIndex,
  }) {
    _elapsedTime.value = elapsedMs;
    _currentBlockIndex = currentBlockIndex;
    _updateCurrentBlock();
    // Don't start timer - that happens when user resumes
  }
}
```

## Implementation Phases

### Phase 1: Robot Test (TDD) 🤖

**File:** `test/scenarios/workout_session_crash_recovery.dart`

**Test Flow:**
1. Create fake DeviceManager with controllable power/HR/cadence streams
2. Load workout player page
3. Simulate pedaling (power = 50W) → auto-start
4. Wait 10 seconds, verify samples recorded
5. **Simulate crash:** Dispose page but keep persistence
6. Verify active session exists in storage
7. **Restart app:** Create new page instance
8. Verify resume dialog appears
9. User clicks "Resume"
10. Verify state restored (elapsed time, current block)
11. Continue workout for 5 more seconds
12. Verify continuous sample recording
13. Complete workout
14. Verify session marked as completed
15. Verify all 15 samples saved

**Also test:**
- Discard flow
- Start fresh flow
- Stale metric handling (stop power for 6s → null recorded)

### Phase 2: Stale Metrics Fix ⏱️

**Files:**
- Modify: `lib/domain/devices/device_manager.dart`
- Test: `test/domain/devices/device_manager_staleness_test.dart`

**Changes:**
```dart
// Before
late final ReadableBeacon<PowerData?> _powerBeacon = Beacon.derived(() {
  final device = _getPowerDevice();
  return device?.powerStream?.value;
});

// After
late final ReadableBeacon<PowerData?> _powerBeacon = Beacon.derived(() {
  final device = _getPowerDevice();
  final data = device?.powerStream?.value;
  if (data == null) return null;

  final age = clock.now().difference(data.timestamp);
  if (age > Duration(seconds: 5)) return null;

  return data;
});
```

**Repeat for:** `_cadenceBeacon`, `_speedBeacon`, `_heartRateBeacon`

**Inject Clock:** Add `Clock` parameter to DeviceManager constructor for testing.

### Phase 3: Data Models 📊

**Files:**
- Create: `lib/domain/models/workout_session.dart`
- Test: `test/domain/models/workout_session_test.dart`

**Models:**
```dart
enum SessionStatus { active, completed, abandoned, crashed }

/// Workout metadata stored in `workouts/{id}/metadata.json`
/// Contains ALL workout information - nothing stored in SharedPreferences
class WorkoutSessionMetadata {
  final String workoutId; // Generated using nanoid2.nanoid()
  final String workoutName;
  final WorkoutPlan workoutPlan; // Full plan for resume
  final DateTime startTime;
  final DateTime? endTime;
  final SessionStatus status;
  final String? userId;
  final int ftp;
  final int totalSamples;
  final int currentBlockIndex; // Which block user was on (for resume)
  final int elapsedMs; // How much time had elapsed (for resume)
  final DateTime lastUpdated;

  // JSON serialization using deep_pick
  Map<String, dynamic> toJson();
  factory WorkoutSessionMetadata.fromJson(Map<String, dynamic> json);
}

/// Lightweight session info for resume dialog
/// Created by reading WorkoutSessionMetadata from file
/// NOT stored anywhere - just used for UI
class WorkoutSession {
  final String id; // nanoid (e.g., "V1StGXR8_Z5jdHi6B-myT")
  final String workoutName;
  final DateTime startTime;
  final SessionStatus status;
  final int elapsedMs; // For resume
  final int currentBlockIndex; // For resume
  final DateTime? lastSampleTime;

  // Created from WorkoutSessionMetadata:
  factory WorkoutSession.fromMetadata(WorkoutSessionMetadata metadata) {
    return WorkoutSession(
      id: metadata.workoutId,
      workoutName: metadata.workoutName,
      startTime: metadata.startTime,
      status: metadata.status,
      elapsedMs: metadata.elapsedMs,
      currentBlockIndex: metadata.currentBlockIndex,
      lastSampleTime: metadata.lastUpdated,
    );
  }
}

class WorkoutSample {
  final DateTime timestamp;
  final int elapsedMs;
  final int? powerActual;
  final int powerTarget;
  final int? cadence;
  final double? speed;
  final int? heartRate;
  final double powerScaleFactor;

  // Compact JSON for JSONL (no pretty printing)
  Map<String, dynamic> toJson();
  factory WorkoutSample.fromJson(Map<String, dynamic> json);
}
```

### Phase 4: Persistence Layer 💾

**Files:**
- Create: `lib/services/workout_session_persistence.dart`
- Test: `test/services/workout_session_persistence_test.dart`

**Implementation notes:**
- Follow `DeviceAssignmentPersistence` pattern
- Use `SharedPreferencesAsync` from existing dependency
- Use `nanoid2` package for workout ID generation (already available)
- One directory per workout in `<app_documents>/workouts/`
- Two files per workout:
  - `metadata.json` - Workout info (updated on status changes)
  - `samples.jsonl` - Samples (append-only, one JSON per line)
- Batch JSONL writes (buffer 5 samples, write 5 lines at once)
- Version metadata for future schema migrations

**Directory Setup:**
```dart
import 'package:nanoid2/nanoid2.dart';
import 'package:path_provider/path_provider.dart';

Future<String> createWorkout(String workoutName, WorkoutPlan plan) async {
  // Generate unique ID
  final workoutId = nanoid(); // e.g., "V1StGXR8_Z5jdHi6B-myT"

  // Create workout directory
  final appDir = await getApplicationDocumentsDirectory();
  final workoutDir = Directory('${appDir.path}/workouts/$workoutId');
  await workoutDir.create(recursive: true);

  // Create metadata file
  final metadata = WorkoutSessionMetadata(
    workoutId: workoutId,
    workoutName: workoutName,
    workoutPlan: plan,
    // ...
  );
  final metadataFile = File('${workoutDir.path}/metadata.json');
  await metadataFile.writeAsString(jsonEncode(metadata.toJson()));

  return workoutId;
}
```

**JSONL Write Implementation:**
```dart
Future<void> appendSamples(String workoutId, List<WorkoutSample> samples) async {
  final file = await getSamplesFile(workoutId); // workouts/{id}/samples.jsonl
  final sink = file.openWrite(mode: FileMode.append);

  for (final sample in samples) {
    final json = jsonEncode(sample.toJson());
    sink.writeln(json); // Each sample = one line
  }

  await sink.flush();
  await sink.close();

  // Update metadata file (total samples count)
  await _updateMetadataSampleCount(workoutId, samples.length);
}
```

**JSONL Read Implementation:**
```dart
Stream<WorkoutSample> loadSamples(String workoutId) async* {
  final file = await getSamplesFile(workoutId); // workouts/{id}/samples.jsonl
  if (!await file.exists()) return;

  final lines = file.openRead().transform(utf8.decoder).transform(LineSplitter());

  await for (final line in lines) {
    if (line.trim().isEmpty) continue;
    final json = jsonDecode(line) as Map<String, dynamic>;
    yield WorkoutSample.fromJson(json);
  }
}
```

**Directory Cleanup:**
```dart
Future<void> deleteWorkout(String workoutId) async {
  final workoutDir = await getWorkoutDirectory(workoutId);
  if (await workoutDir.exists()) {
    await workoutDir.delete(recursive: true); // Deletes entire folder
  }
}
```

### Phase 5: Recording Service 🎙️

**Files:**
- Create: `lib/services/workout_recording_service.dart`
- Test: `test/services/workout_recording_service_test.dart`
- Modify: `lib/services/workout_player_service.dart` (add state restoration)

**Implementation notes:**
- 1-second timer
- Read beacon values synchronously (no subscriptions)
- Handle pause/resume (pause timer, not recording)
- Flush samples on dispose
- Inject Clock for testing

### Phase 6: Resume Dialog & UI 🖥️

**Files:**
- Create: `lib/widgets/workout_resume_dialog.dart`
- Test: `test/widgets/workout_resume_dialog_test.dart`
- Modify: `lib/pages/workout_player_page.dart`
- Modify: `lib/app/refs.dart`

**Integration flow:**
1. Check for active session in `initState()`
2. Show dialog if found
3. Handle resume/discard/fresh choices
4. Initialize recording service on workout start

### Phase 7: App Lifecycle (Optional Polish) 🔄

**Files:**
- Modify: `lib/app/app.dart` or create `lib/services/app_lifecycle_service.dart`

**Implementation:**
- Add `WidgetsBindingObserver`
- Flush pending samples on app pause
- No-op on resume (WorkoutPlayerPage handles)

## Testing Strategy

### 1. Robot Test (Integration)
- Full crash recovery flow
- Resume, discard, start fresh paths
- Stale metric handling
- File: `test/scenarios/workout_session_crash_recovery.dart`

### 2. Unit Tests
- Staleness detection (each metric)
- Session persistence (save/load/crash detection)
- Recording service (sampling, pause/resume)
- Data models (JSON serialization)

### 3. Fake Implementations
- `FakeClock` for time control
- `FakeSharedPreferences` for persistence testing
- `FakeDeviceManager` with controllable streams

### 4. Manual Testing Checklist
- [ ] Record workout with real trainer
- [ ] Force quit app mid-workout (iOS: swipe up, Android: force stop)
- [ ] Restart app, verify resume dialog
- [ ] Resume workout, verify time continues
- [ ] Disconnect HR monitor, verify null after 5s
- [ ] Complete workout, verify file saved
- [ ] Discard session, verify marked abandoned
- [ ] Start fresh, verify old session deleted

## Migration & Rollout

### Breaking Changes
None - this is a new feature.

### Database Migrations
Not applicable (no database, using SharedPreferences + files).

### Versioning
Add version field to session metadata:
```json
{"version": 1, "sessionId": "..."}
```

Future schema changes can be detected and migrated.

### Rollback Plan
If issues arise:
1. Recording service is opt-in (only active during workout)
2. Can disable by not initializing `WorkoutRecordingService`
3. Existing workout playback unaffected
4. Persisted data remains on device (not deleted)

## Performance Considerations

### Memory
- Don't hold all samples in RAM
- Batch writes every 5 samples (~1 KB per batch)
- Flush on dispose

### CPU
- 1Hz timer is very low frequency
- Reading beacon values is O(1)
- JSON serialization per sample: <1ms

### Storage
- 60 min workout: ~720 KB
- 100 workouts: ~72 MB (negligible)

### Battery
- Timer overhead: minimal (1Hz is very low frequency)
- File writes: batched, not per-sample

### Network
Not applicable (local-only, no sync yet).

## Future Enhancements

### Cloud Sync
- Add API endpoints: `POST /api/workouts/sessions`, `POST /api/workouts/sessions/:id/samples`
- Implement sync service with retry logic
- Handle conflicts (local vs cloud state)
- Background sync on workout complete

### Workout History
- List all completed workouts
- Show stats (avg power, duration, TSS)
- Delete old sessions

### Export Formats
- FIT file export (Garmin)
- TCX file export (TrainingPeaks)
- CSV export (spreadsheet analysis)

### Analytics
- Power curve (best 1s, 5s, 1min, 5min, 20min)
- Training Stress Score (TSS)
- Intensity Factor (IF)
- Variability Index (VI)

### Automatic FTP Detection
- Analyze workout data
- Suggest FTP updates based on performance

## Success Criteria

- ✅ Robot test passes (full crash recovery flow)
- ✅ All unit tests pass
- ✅ No memory leaks (verified with devtools)
- ✅ Recording doesn't impact UI performance
- ✅ Data survives force quit on iOS/Android
- ✅ Stale metrics return null after 5 seconds
- ✅ Manual testing checklist complete
- ✅ Code review approved
- ✅ Documentation complete (this doc + user-facing feature doc)

## Estimated Effort

| Phase | Task | Hours |
|-------|------|-------|
| 1 | Robot test | 2-3 |
| 2 | Stale metrics fix | 1-2 |
| 3 | Data models | 1-2 |
| 4 | Persistence layer | 2-3 |
| 5 | Recording service | 2-3 |
| 6 | Resume dialog & UI | 2-3 |
| 7 | App lifecycle | 1 |
| - | Unit tests | 2-3 |
| - | Manual testing | 1-2 |
| - | Documentation | 1 |
| **Total** | | **15-22 hours** |

## Dependencies

### Existing Packages (No New Dependencies)
- ✅ `state_beacon` - reactive state management
- ✅ `shared_preferences` - session metadata storage
- ✅ `path_provider` - get documents directory for sample files
- ✅ `clock` - time abstraction for testing
- ✅ `nanoid2` - workout ID generation (already available as transitive dependency)

### New Packages Needed
- ❌ None (per CLAUDE.md: "Ask before adding any new package!")

## References

- [WORKOUT_PLAYER_ARCHITECTURE.md](./WORKOUT_PLAYER_ARCHITECTURE.md)
- [state_beacon_overview.md](./state_beacon_overview.md)
- [ARCHITECTURE.md](./ARCHITECTURE.md)
- Existing implementation: `lib/services/device_assignment_persistence.dart`
- Robot test example: `test/scenarios/workout_player_auto_pause.dart`
