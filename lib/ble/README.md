# BLE Scanner Reimplementation

## Primary Goal
**100% testable BleScanner** - All logic, state transitions, timers, lifecycle handling, and edge cases must be testable without real Bluetooth hardware.

## Architecture Decision: Separate Permissions Layer
Create dedicated permissions abstraction because:
- FlutterBluePlus doesn't provide permission APIs
- Complex Android version-specific permission logic
- Location services checking is separate concern
- Better testability with isolated dependencies

## Key Features
1. **Token-based scanning** - Multiple callers can start/stop scanning independently
2. **Auto device expiry** - Remove devices not seen in 5 seconds
3. **Discovery-time sorting** - Maintain device order by first appearance
4. **Auto-restart** - Resume scanning when Bluetooth becomes available again
5. **Lifecycle awareness** - Stop scanning when app backgrounds, resume when foregrounded
6. **Reactive state** - All state exposed via `state_beacon` signals
7. **No service filtering** - Scan for all BLE devices
8. **Full ScanResult access** - Expose complete flutter_blue_plus ScanResult data
9. **Detailed state tracking** - Explicit states for all conditions
10. **Fully testable** - All external dependencies injected

## File Structure
```
lib/ble/
├── ble_scanner.dart              # Main BleScanner + data classes
├── ble_platform.dart             # Abstract BlePlatform + impl (wraps FlutterBluePlus)
└── ble_permissions.dart          # Abstract BlePermissions + impl (wraps permission_handler)

test/ble/
├── fake_ble_platform.dart        # Fake with device simulation
├── fake_ble_permissions.dart     # Fake for permission states
└── ble_scanner_test.dart         # Comprehensive tests
```

## Public API (ble_scanner.dart)

```dart
class BleScanner {
  BleScanner({
    BlePlatform? platform,
    BlePermissions? permissions,
    Clock? clock,
  });

  ReadableBeacon<List<DiscoveredDevice>> get devices;
  ReadableBeacon<bool> get isScanning;
  ReadableBeacon<BluetoothState> get bluetoothState;

  ScanToken startScan();
  void stopScan(ScanToken token);
  void dispose();
}

class DiscoveredDevice {
  final ScanResult scanResult;
  final DateTime firstSeen;
  final DateTime lastSeen;
  // Convenience getters...
}

class BluetoothState {
  final BluetoothAdapterState adapterState;
  final bool hasPermission;
  final bool isPermissionPermanentlyDenied;
  final bool isLocationServiceEnabled;
  // Computed getters...
}
```

## BlePlatform (ble_platform.dart)

```dart
abstract class BlePlatform {
  Stream<BluetoothAdapterState> get adapterStateStream;
  Stream<List<ScanResult>> get scanResultsStream;
  Future<void> startScan();
  Future<void> stopScan();
}

class BlePlatformImpl implements BlePlatform {
  // Wraps FlutterBluePlus only (no permissions)
}
```

## BlePermissions (ble_permissions.dart)

```dart
abstract class BlePermissions {
  Future<bool> check();
  Future<bool> request();
  Future<bool> isPermanentlyDenied();
  Future<bool> isLocationServiceEnabled();
  Future<void> openSettings();
}

class BlePermissionsImpl implements BlePermissions {
  // Wraps permission_handler + location services check
  // Reuses existing lib/utils/ble_permissions.dart logic
}
```

## Fake APIs for Testing

### FakeBlePlatform (fake_ble_platform.dart)
```dart
class FakeBlePlatform implements BlePlatform {
  void setAdapterState(BluetoothAdapterState state);

  // Device simulation - devices advertise until turned off
  FakeDevice addDevice(String id, String name, {int rssi, List<Guid>? services});
  void removeDevice(String id);
}

class FakeDevice {
  void turnOn();      // Start advertising
  void turnOff();     // Stop advertising
  void updateRssi(int rssi);
}
```

### FakeBlePermissions (fake_ble_permissions.dart)
```dart
class FakeBlePermissions implements BlePermissions {
  void setHasPermission(bool value);
  void setPermanentlyDenied(bool value);
  void setLocationServiceEnabled(bool value);

  // Track calls for verification
  int requestCallCount;
  int openSettingsCallCount;
}
```

## Implementation Steps
1. ✅ Write this plan to `lib/ble/README.md`
2. ✅ Create ble_permissions.dart (abstract + impl wrapping existing utils/ble_permissions.dart)
3. ✅ Create ble_platform.dart (abstract + impl wrapping FlutterBluePlus)
4. ✅ Create ble_scanner.dart with dependency injection
5. ✅ Implement token management
6. ✅ Implement device expiry using Clock
7. ✅ Implement state monitoring and auto-restart
8. ✅ Implement lifecycle monitoring (WidgetsBindingObserver)
9. ✅ Create FakeBlePlatform and FakeBlePermissions
10. ✅ Write comprehensive unit tests
11. ✅ Add inline documentation

## Test Coverage Areas
- Token management: Multiple start/stop operations
- Device expiry: Devices removed after 5s using injected Clock
- State transitions: All BluetoothState combinations
- Auto-restart: When Bluetooth/permissions/location become available
- Lifecycle handling: Background/foreground transitions
- Edge cases: Rapid start/stop, state changes during scan
- Device sorting: Discovery time order maintained
- Error handling: Platform errors, permission denials

## Benefits of This Design
- **Testability**: All external dependencies injected and fakeable
- **Separation of concerns**: BLE ops, permissions, and scanning logic isolated
- **Realistic fakes**: Device simulation matches real BLE behavior
- **Maintainability**: Clear interfaces, easy to extend
- **Reusability**: Permission abstraction usable elsewhere
