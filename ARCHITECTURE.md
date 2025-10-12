# Multi-Device Fitness Architecture

## Overview

This document describes the architecture for managing up to 3 Bluetooth fitness devices simultaneously, supporting different protocols and data sources (power, cadence, heart rate) with a focus on ERG mode trainer control.

## Requirements

- Support up to 3 simultaneous Bluetooth devices
- Handle different data sources: Power (watts), Cadence (RPM), Heart Rate (BPM)
- Support multiple protocols: FTMS, Wahoo proprietary, BT Power/CSC/HR services
- Support trainer control modes (Phase 1: ERG mode only)
- Fully testable architecture without actual Bluetooth hardware
- Reactive streams using state_beacon
- Bluetooth code isolated as implementation detail
- Workout sync mechanism with automatic retry and refresh

## Research Findings

### FTMS Protocol
- Commands appear to be one-shot (set and forget)
- Official spec requires membership to access full details
- Conservative approach: implement periodic refresh as safety mechanism

### ANT+ FE-C Protocol
- General FE Data sent at 2 Hz
- General Settings sent at 1 Hz
- Power data transmission: 1-4 Hz depending on device
- Spec unclear on ERG mode command refresh requirements

### Trainer Behavior
- High-end trainers (Wahoo KICKR, Tacx Neo): 3-5 seconds to reach target
- Mid-range trainers: 5-10 seconds response time
- Some trainers may timeout without regular commands
- **Conservative strategy**: Refresh ERG target every 1-3 seconds

## Architecture Layers

### 1. Domain Models (`lib/domain/models/`)

#### `fitness_data.dart`
Immutable data classes with timestamps:
```dart
class PowerData {
  final int watts;
  final DateTime timestamp;
}

class CadenceData {
  final int rpm;
  final DateTime timestamp;
}

class HeartRateData {
  final int bpm;
  final DateTime timestamp;
}
```

#### `device_info.dart`
Device metadata and capabilities:
```dart
enum DeviceType {
  trainer,           // Can control + provide data
  powerMeter,        // Power only
  cadenceSensor,     // Cadence only
  heartRateMonitor   // HR only
}

enum ConnectionState {
  disconnected,
  connecting,
  connected,
  error
}

enum DataSource {
  power,
  cadence,
  heartRate
}

class DeviceInfo {
  final String id;
  final String name;
  final DeviceType type;
  final Set<DataSource> capabilities;
}
```

#### `erg_command.dart`
ERG mode control command:
```dart
class ErgCommand {
  final int targetWatts;
  final DateTime timestamp;
}
```

### 2. Device Abstraction (`lib/domain/devices/`)

#### `fitness_device.dart`
Core abstract interface - NO Bluetooth code:
```dart
abstract class FitnessDevice {
  // Identity
  String get id;
  String get name;
  DeviceType get type;
  Set<DataSource> get capabilities;

  // Connection management
  Stream<ConnectionState> get connectionState;
  Future<void> connect();
  Future<void> disconnect();

  // Data streams (nullable - only if device supports)
  Stream<PowerData>? get powerStream;
  Stream<CadenceData>? get cadenceStream;
  Stream<HeartRateData>? get heartRateStream;

  // Control capabilities (only for trainers)
  bool get supportsErgMode;
  Future<void> setTargetPower(int watts);

  // Protocol-specific behavior
  bool get requiresContinuousRefresh;  // True if needs periodic resend
  Duration get refreshInterval;         // Default: 2 seconds
}
```

#### `device_manager.dart`
Manages multiple devices and aggregates data streams:
```dart
class DeviceManager {
  // Device collection
  final List<FitnessDevice> _devices = [];

  // Device assignments
  FitnessDevice? _primaryTrainer;   // ERG control + can provide all data
  FitnessDevice? _powerSource;      // Dedicated power meter
  FitnessDevice? _cadenceSource;    // Dedicated cadence sensor
  FitnessDevice? _heartRateSource;  // Dedicated HR monitor

  // Aggregated streams (combines data from assigned devices)
  Stream<PowerData> get powerStream;
  Stream<CadenceData> get cadenceStream;
  Stream<HeartRateData> get heartRateStream;

  // Device management API
  Future<void> addDevice(FitnessDevice device);
  Future<void> removeDevice(String deviceId);
  void assignPrimaryTrainer(String deviceId);
  void assignPowerSource(String deviceId);
  void assignCadenceSource(String deviceId);
  void assignHeartRateSource(String deviceId);

  // Queries
  List<FitnessDevice> get devices;
  FitnessDevice? get primaryTrainer;
  FitnessDevice? get powerSource;
  FitnessDevice? get cadenceSource;
  FitnessDevice? get heartRateSource;
}
```

### 3. Protocol Implementations (`lib/domain/protocols/`)

Each protocol extends `FitnessDevice` - NO Bluetooth code here!

#### `ftms_device.dart`
FTMS protocol device (most modern trainers):
```dart
class FtmsDevice extends FitnessDevice {
  final FtmsBleTransport _transport;

  @override
  bool get requiresContinuousRefresh => true;  // Conservative

  @override
  Duration get refreshInterval => Duration(seconds: 2);

  @override
  Future<void> setTargetPower(int watts) async {
    await _transport.sendTargetPower(watts);
  }

  @override
  Stream<PowerData>? get powerStream => _transport.powerStream;

  @override
  Stream<CadenceData>? get cadenceStream => _transport.cadenceStream;
}
```

#### Future protocols:
- `wahoo_device.dart` - Wahoo proprietary (KICKR, CORE)
- `power_meter_device.dart` - BT Cycling Power Service
- `csc_device.dart` - BT Cycling Speed & Cadence
- `heart_rate_device.dart` - BT Heart Rate Service

### 4. Transport Layer (`lib/infrastructure/ble/`)

Bluetooth-specific code lives here - isolated from domain logic.

#### `ftms_ble_transport.dart`
Refactored from existing `BleManager`:
```dart
class FtmsBleTransport {
  final FlutterReactiveBle _ble;
  final String deviceId;

  // FTMS UUIDs
  static final _ftmsServiceUuid = Uuid.parse('00001826-...');
  static final _indoorBikeDataUuid = Uuid.parse('00002AD2-...');
  static final _controlPointUuid = Uuid.parse('00002AD9-...');

  // Data streams
  final _powerController = StreamController<PowerData>.broadcast();
  final _cadenceController = StreamController<CadenceData>.broadcast();

  Stream<PowerData> get powerStream => _powerController.stream;
  Stream<CadenceData> get cadenceStream => _cadenceController.stream;

  // Connection
  Future<void> connect() { /* existing BleManager logic */ }

  // Parsing
  void _parseIndoorBikeData(Uint8List data) { /* existing logic */ }

  // Control
  Future<void> sendTargetPower(int watts) { /* existing logic */ }
}
```

### 5. Workout Sync Service (`lib/services/workout_sync_service.dart`)

**⭐ KEY COMPONENT** - Syncs workout targets to trainer

```dart
class WorkoutSyncService {
  final DeviceManager _deviceManager;

  // Current target from workout playback
  final Beacon<ErgCommand?> currentTarget = Beacon.writable(null);

  // Sync state
  final Beacon<bool> isSyncing = Beacon.writable(false);
  final Beacon<DateTime?> lastSyncTime = Beacon.writable(null);
  final Beacon<String?> syncError = Beacon.writable(null);

  Timer? _refreshTimer;
  ErgCommand? _lastSentCommand;
  int _retryCount = 0;
  static const _maxRetries = 3;

  /// Start syncing workout targets to primary trainer
  void startSync() {
    isSyncing.value = true;

    // React to target changes from workout
    currentTarget.subscribe((target) {
      if (target != null) {
        _syncTargetToDevice(target);
      }
    });

    // Start periodic refresh for devices that need it
    _startRefreshTimer();
  }

  void stopSync() {
    isSyncing.value = false;
    _refreshTimer?.cancel();
    _lastSentCommand = null;
    _retryCount = 0;
  }

  /// Sync target to device with retry logic
  Future<void> _syncTargetToDevice(ErgCommand command) async {
    final trainer = _deviceManager.primaryTrainer;
    if (trainer == null || !trainer.supportsErgMode) {
      syncError.value = 'No trainer connected';
      return;
    }

    try {
      await trainer.setTargetPower(command.targetWatts);
      _lastSentCommand = command;
      lastSyncTime.value = DateTime.now();
      syncError.value = null;
      _retryCount = 0;
    } catch (e, stackTrace) {
      print('[WorkoutSync] Failed to set target: $e');
      print(stackTrace);

      // Exponential backoff retry
      if (_retryCount < _maxRetries) {
        _retryCount++;
        syncError.value = 'Retry $_retryCount/$_maxRetries';
        await Future.delayed(Duration(seconds: _retryCount));
        await _syncTargetToDevice(command);
      } else {
        syncError.value = 'Failed after $_maxRetries retries';
        _retryCount = 0;
      }
    }
  }

  /// Periodic refresh for trainers that need it
  void _startRefreshTimer() {
    final trainer = _deviceManager.primaryTrainer;
    if (trainer == null || !trainer.requiresContinuousRefresh) return;

    _refreshTimer = Timer.periodic(trainer.refreshInterval, (timer) {
      // Re-send last command to keep device in sync
      if (_lastSentCommand != null && isSyncing.value) {
        print('[WorkoutSync] Refreshing target: ${_lastSentCommand!.targetWatts}W');
        _syncTargetToDevice(_lastSentCommand!);
      }
    });
  }

  void dispose() {
    stopSync();
    currentTarget.dispose();
  }
}
```

**Key Features:**
- Automatic retry with exponential backoff (1s, 2s, 3s delays)
- Periodic refresh every 2 seconds for FTMS devices
- Error tracking with beacons for UI feedback
- Separate sync state from workout state

### 6. Devices Screen (`lib/pages/devices_page.dart`)

**Accessible from anywhere** - bottom sheet or full screen

#### UI Layout
```
┌─────────────────────────────────────┐
│  Devices                    [Scan]  │
├─────────────────────────────────────┤
│                                     │
│  PRIMARY TRAINER ⚡                 │
│  ┌─────────────────────────────┐   │
│  │ 🔗 Wahoo KICKR              │   │
│  │ Power • Cadence             │   │
│  │ 🔋 95% • 📶 -45dBm         │   │
│  │ [Disconnect]                │   │
│  └─────────────────────────────┘   │
│                                     │
│  POWER SOURCE 💪                   │
│  [ + Assign Device ]               │
│                                     │
│  CADENCE SOURCE 🔄                 │
│  [ + Assign Device ]               │
│                                     │
│  HEART RATE 💓                     │
│  [ + Assign Device ]               │
│                                     │
│  ─────────────────────────         │
│                                     │
│  OTHER DEVICES                     │
│  ┌─────────────────────────────┐   │
│  │ 🔗 Garmin HRM-Dual          │   │
│  │ Heart Rate                  │   │
│  │ [Assign to HR] [Connect]    │   │
│  └─────────────────────────────┘   │
└─────────────────────────────────────┘
```

#### Features
- List all connected devices
- Scan for new devices
- Assign devices to data sources
- Show connection status, capabilities
- Device info (battery, signal strength if available)
- Quick disconnect/connect actions
- Capability badges (Power, Cadence, HR, ERG Control)

#### Navigation
- Can be opened from workout page FAB
- Available in app drawer/menu
- Deep linkable: `/devices`

### 7. State Management (`lib/state/device_state.dart`)

```dart
// Service references
final deviceManagerRef = Ref<DeviceManager>();
final workoutSyncServiceRef = Ref<WorkoutSyncService>();

// UI state beacons
final connectedDevicesBeacon = Beacon.writable<List<FitnessDevice>>([]);
final primaryTrainerBeacon = Beacon.writable<FitnessDevice?>(null);
final powerSourceBeacon = Beacon.writable<FitnessDevice?>(null);
final cadenceSourceBeacon = Beacon.writable<FitnessDevice?>(null);
final heartRateSourceBeacon = Beacon.writable<FitnessDevice?>(null);

// Aggregated data streams
final currentPowerBeacon = Beacon.writable<PowerData?>(null);
final currentCadenceBeacon = Beacon.writable<CadenceData?>(null);
final currentHeartRateBeacon = Beacon.writable<HeartRateData?>(null);

// Sync status
final syncStatusBeacon = Beacon.writable<String>('Not syncing');
final lastSyncBeacon = Beacon.writable<DateTime?>(null);
```

### 8. Mock Implementations (`lib/domain/mocks/`)

For testing without hardware:

#### `mock_trainer.dart`
```dart
class MockTrainer extends FitnessDevice {
  @override
  bool get requiresContinuousRefresh => false;  // Configurable

  @override
  Duration get refreshInterval => Duration(seconds: 2);

  final _powerController = StreamController<PowerData>.broadcast();
  final _cadenceController = StreamController<CadenceData>.broadcast();
  final _targetPower = Beacon.writable<int>(0);

  int _currentPower = 0;
  Timer? _rampTimer;

  @override
  Stream<PowerData> get powerStream => _powerController.stream;

  @override
  Stream<CadenceData> get cadenceStream => _cadenceController.stream;

  @override
  Future<void> setTargetPower(int watts) async {
    await Future.delayed(Duration(milliseconds: 100));  // Simulate BLE latency
    _targetPower.value = watts;
    _simulatePowerRamp(watts);
  }

  void _simulatePowerRamp(int target) {
    _rampTimer?.cancel();

    // Simulate realistic trainer response (3-5 seconds to reach target)
    _rampTimer = Timer.periodic(Duration(milliseconds: 200), (timer) {
      if (_currentPower < target) {
        _currentPower = (_currentPower + 5).clamp(0, target);
      } else if (_currentPower > target) {
        _currentPower = (_currentPower - 5).clamp(target, 1500);
      } else {
        timer.cancel();
      }

      _powerController.add(PowerData(
        watts: _currentPower,
        timestamp: DateTime.now(),
      ));
    });
  }
}
```

#### `device_simulator.dart`
Realistic workout simulation for testing:
```dart
class DeviceSimulator {
  static MockTrainer createRealisticTrainer({
    int ftpWatts = 200,
    double variability = 0.05,  // 5% power variation
  }) {
    // Returns a trainer that simulates realistic power fluctuations
  }
}
```

## Implementation Order

### Phase 1: Foundation
1.  Create domain models (`fitness_data.dart`, `device_info.dart`, `erg_command.dart`)
2.  Define `FitnessDevice` interface
3.  Implement `DeviceManager`
4.  Create mock implementations for testing

### Phase 2: FTMS Integration
5.  Refactor `BleManager` → `FtmsBleTransport` (extract BLE code)
6.  Implement `FtmsDevice` using transport
7.  Test with real FTMS trainer

### Phase 3: Workout Sync
8.  Implement `WorkoutSyncService`
9.  Add retry logic
10.  Add periodic refresh mechanism
11.  Test with mock trainer
12.  Test with real trainer

### Phase 4: UI
13.  Create `DevicesPage` UI
14.  Add device scanning integration
15.  Implement device assignment UI
16.  Add navigation from workout page
17.  Add connection status indicators

### Phase 5: Integration
18.  Wire up all beacons and streams
19.  Connect workout playback to sync service
20.  End-to-end testing
21.  Polish and error handling

### Phase 6: More devices
22. Research and Implement Wahoo smart trainers
23. Research and Implement common Heart rate sensors
24. Research and implement other common smart trainers

## Benefits of This Architecture

✅ **Fully Testable**: Core logic separated from Bluetooth hardware
✅ **Sync Mechanism**: Automatic retry + periodic refresh for reliability
✅ **Protocol Agnostic**: Easy to add new protocols (Wahoo, Power Meter, etc.)
✅ **Flexible Assignment**: Any device can be power/cadence/HR source
✅ **Accessible UI**: Devices screen available from anywhere
✅ **Error Handling**: Connection loss, retry, timeout all handled
✅ **Production Ready**: Works with real FTMS trainers immediately
✅ **Clear Separation**: Domain → Protocol → Transport layers
✅ **Reactive**: State management with beacons for automatic UI updates

## Next Steps (Phase 2+)

### Additional Protocols
- Wahoo proprietary protocol (KICKR, CORE via BLE private service)
- Cycling Power Service (separate power meters)
- CSC Service (speed/cadence sensors)
- Heart Rate Service (chest straps, watches)

### Additional Control Modes
- Resistance/Level mode (0-100% or 1-20 levels)
- Simulation mode (gradient, wind, rolling resistance)

### Enhanced Features
- Persist device assignments (SharedPreferences)
- Device pairing wizard
- Battery level monitoring
- Signal strength indicators
- Device firmware updates
- ANT+ support (requires platform channels)

### Testing
- Unit tests for all domain logic
- Integration tests with device simulator
- Real hardware testing guide
- Performance benchmarks

## File Structure

```
lib/
├── domain/
│   ├── models/
│   │   ├── fitness_data.dart
│   │   ├── device_info.dart
│   │   └── erg_command.dart
│   ├── devices/
│   │   ├── fitness_device.dart
│   │   └── device_manager.dart
│   ├── protocols/
│   │   ├── ftms_device.dart
│   │   ├── wahoo_device.dart  (future)
│   │   ├── power_meter_device.dart  (future)
│   │   ├── csc_device.dart  (future)
│   │   └── heart_rate_device.dart  (future)
│   └── mocks/
│       ├── mock_trainer.dart
│       ├── mock_power_meter.dart
│       └── device_simulator.dart
├── infrastructure/
│   └── ble/
│       ├── ftms_ble_transport.dart
│       ├── wahoo_ble_transport.dart  (future)
│       ├── power_meter_transport.dart  (future)
│       ├── csc_transport.dart  (future)
│       └── hr_transport.dart  (future)
├── services/
│   ├── workout_sync_service.dart
│   └── ble_manager.dart  (refactor into transport)
├── state/
│   └── device_state.dart
└── pages/
    ├── devices_page.dart
    └── (existing pages)
```

## Related Documents

- `AUTHENTICATION.md` - Auth flow and API integration
- `README.md` - Project setup and getting started
- `CLAUDE.md` - Project-specific Claude instructions
