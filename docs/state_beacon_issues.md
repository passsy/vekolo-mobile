# State Beacon Usage Issues

This document identifies places where `state_beacon` is used incorrectly according to best practices outlined in [state_beacon_overview.md](./state_beacon_overview.md) and [AGENTS.md](../AGENTS.md).

## Critical Issues: Manual Subscription + Mutation Pattern

### 1. `lib/state/device_state_manager.dart` - Multiple violations

**Problem:** Uses `.subscribe()` to manually mutate other beacons, violating the transform chain pattern.

**Lines 60-107:** All subscriptions manually update beacons:
```dart
deviceManager.powerStream.subscribe((PowerData? data) {
  telemetry.power.value = data;  // ❌ Manual mutation
});
```

**Recommendation:** Use transform chains or direct assignment. Since these are 1:1 mappings, they could be direct assignments or derived beacons:

```dart
// Option 1: Direct assignment if streams are beacons
telemetry.power = deviceManager.powerStream;

// Option 2: Use Beacon.derived if streams need transformation
final power = Beacon.derived(() => deviceManager.powerStream.value);
```

**Impact:** Risk of memory leaks, double notifications, harder to test, not declarative.

---

### 2. `lib/domain/devices/device_manager.dart` - Stream aggregation pattern

**Problem:** Subscribes to device beacons and manually updates aggregated beacons.

**Lines 444-519:** Multiple subscriptions in `_updatePowerStream()`, `_updateCadenceStream()`, `_updateSpeedStream()`, `_updateHeartRateStream()`:

```dart
beacon.subscribe((PowerData? data) {
  _powerBeacon.value = data;  // ❌ Manual mutation
});
```

**Recommendation:** This is trickier because the source beacon changes dynamically. Consider:
- Using `Beacon.derived` that checks the current source
- Or use a transform chain that switches sources dynamically

**Impact:** Similar to above - risk of leaks, harder to reason about.

---

### 3. `lib/pages/trainer_page.dart` - Mixing reactive state with setState

**Problem:** Uses `.subscribe()` with `setState()`, mixing reactive patterns with Flutter's imperative state.

**Lines 138-169:** Multiple subscriptions that call `setState()`:

```dart
device.connectionState.subscribe((state) {
  if (!mounted) return;
  if (state == device_info.ConnectionState.disconnected && !_isDisposing) {
    context.go('/');
  }
});

device.powerStream?.subscribe((PowerData? data) {
  if (!mounted) return;
  setState(() {  // ❌ Mixing reactive state with setState
    _currentPower = data?.watts;
  });
});
```

**Recommendation:** Convert to StatelessWidget or use `.watch()` in build method:

```dart
// In build method:
final power = device.powerStream?.watch(context);
final currentPower = power?.watts;
```

**Impact:** Unnecessary rebuilds, harder to maintain, mixing patterns.

---

### 4. `lib/pages/devices_page.dart` - Same pattern

**Problem:** Uses `.subscribe()` with `setState()` for scanner state.

**Lines 1012-1039:** Multiple subscriptions:

```dart
_scanner!.devices.subscribe((devices) {
  if (mounted) {
    setState(() {  // ❌ Should use .watch() instead
      _devices = devices;
    });
  }
});
```

**Recommendation:** Use `.watch()` in build method or convert to StatelessWidget.

**Impact:** Same as above.

---

### 5. `lib/pages/scanner_page.dart` - Same pattern

**Problem:** Uses `.subscribe()` with `setState()`.

**Lines 52-74:** Similar pattern to devices_page.

**Recommendation:** Use `.watch()` in build method.

---

## Questionable Patterns: Side Effects

### 6. `lib/services/workout_sync_service.dart` - Subscription for side effects

**Problem:** Uses `.subscribe()` to trigger side effects (syncing to device).

**Line 162:**
```dart
_targetUnsubscribe = currentTarget.subscribe((target) {
  if (target != null && isSyncing.value) {
    _syncTargetToDevice(target);  // Side effect
  }
});
```

**Analysis:** This might be acceptable since it's a true side effect (sending commands to hardware), not just mutating another beacon. However, consider using `Beacon.effect()` instead for clarity:

```dart
Beacon.effect(() {
  final target = currentTarget.value;
  if (target != null && isSyncing.value) {
    _syncTargetToDevice(target);
  }
});
```

**Impact:** Lower priority, but `Beacon.effect()` is more explicit about side effects.

---

## Summary

### Priority 1 (Critical): Manual Subscription + Mutation
- `lib/state/device_state_manager.dart` - 8 subscriptions manually mutating beacons
- `lib/domain/devices/device_manager.dart` - 4 subscriptions manually mutating beacons

### Priority 2 (High): Mixing Reactive State with setState
- `lib/pages/trainer_page.dart` - 4 subscriptions using setState
- `lib/pages/devices_page.dart` - 3 subscriptions using setState
- `lib/pages/scanner_page.dart` - 3 subscriptions using setState

### Priority 3 (Medium): Side Effects
- `lib/services/workout_sync_service.dart` - Consider using `Beacon.effect()` instead

## Good Patterns Found ✅

- `lib/state/device_state.dart` - Beacons properly encapsulated in classes, not top-level
- `lib/services/auth_service.dart` - Uses `Beacon.streamRaw()` correctly
- `lib/ble/ble_platform.dart` - Uses `Beacon.streamRaw()` correctly
- All beacons are instance members, not top-level singletons ✅

## Recommendations

1. **Refactor `DeviceStateManager`**: Remove all `.subscribe()` calls and use direct beacon assignment or derived beacons.

2. **Convert pages to use `.watch()`**: TrainerPage, DevicesPage, and ScannerPage should use `.watch()` in their build methods instead of `.subscribe()` + `setState()`.

3. **Consider `Beacon.effect()`**: For true side effects like `workout_sync_service.dart`, use `Beacon.effect()` for clarity.

4. **Test after refactoring**: Ensure all reactive updates still work correctly after removing manual subscriptions.

