## Signals: state_beacon Overview

A reactive state management library using the signal pattern. Beacons automatically track dependencies and only recompute what changed.

### Quick Start

```dart
import 'package:state_beacon/state_beacon.dart';

// Create mutable state
final counter = Beacon.writable(0);

// Read value
print(counter.value); // 0

// Update value
counter.value = 5;

// In widgets, watch for changes
class CounterWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Widget rebuilds automatically when counter changes
    return Text('${counter.watch(context)}');
  }
}
```

### Core Concepts

#### Beacon Types

**`Beacon.writable<T>`** - Mutable state you can read and write:
```dart
final name = Beacon.writable('Alice');
name.value = 'Bob'; // Update
print(name.value); // Read
```

**`Beacon.derived<T>`** - Computed from other beacons:
```dart
final count = Beacon.writable(5);
final doubled = Beacon.derived(() => count.value * 2);
// doubled automatically updates when count changes
```

**`Beacon.readable<T>`** - Read-only wrapper (rarely needed):
```dart
final public = Beacon.readable(privateBeacon);
// Can read but not write
```

#### Widget Integration

Use `.watch(context)` in `build()` to rebuild on changes:

```dart
class ProfileCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final name = nameBeacon.watch(context);
    return Text(name);
  }
}
```

For multiple beacons, watch them separately:
```dart
Widget build(BuildContext context) {
  final count = counter.watch(context);
  final name = nameBeacon.watch(context);
  return Text('$name: $count');
}
```

### Common Patterns

#### State Container Class

Group related beacons in a class with manual disposal:

```dart
class DeviceState {
  final devices = Beacon.writable<List<Device>>([]);
  final selectedDevice = Beacon.writable<Device?>(null);
  
  void dispose() {
    devices.dispose();
    selectedDevice.dispose();
  }
}
```

#### Exposing Read-Only Views

Provide public read-only access while keeping writable private:

```dart
class BleScanner {
  late final _isScanningBeacon = Beacon.writable(false);
  
  // Public read-only view
  ReadableBeacon<bool> get isScanning => _isScanningBeacon;
  
  void startScan() {
    _isScanningBeacon.value = true;
  }
}
```

#### Derived State

Compute values automatically from sources:

```dart
final items = Beacon.writable<List<Item>>([]);
final itemCount = Beacon.derived(() => items.value.length);
final hasItems = Beacon.derived(() => items.value.isNotEmpty);
```

#### Side Effects

Use `.subscribe()` for imperative reactions (logging, analytics):

```dart
counter.subscribe((value) {
  print('Counter changed to: $value');
  analytics.track('counter_update', value);
});
```

**Important:** Store unsubscribe callbacks and call them on disposal:

```dart
class MyService {
  VoidCallback? _unsubscribe;
  
  void initialize() {
    _unsubscribe = someBeacon.subscribe((value) {
      // react to changes
    });
  }
  
  void dispose() {
    _unsubscribe?.call();
  }
}
```

### Async State

#### Future Beacons

`Beacon.future` wraps async operations in `AsyncValue`:

```dart
final userId = Beacon.writable('user-123');
final userData = Beacon.future(() async {
  final id = userId.value; // Read before await!
  return await fetchUser(id);
});

// In widget:
Widget build(BuildContext context) {
  return switch (userData.watch(context)) {
    AsyncData<User>(value: final user) => UserWidget(user),
    AsyncError(error: final e) => ErrorWidget(e),
    _ => CircularProgressIndicator(),
  };
}
```

**Critical:** Only beacons read **before** the first `await` are tracked as dependencies. To depend on multiple async beacons:

```dart
// ❌ BAD - lastNameBeacon won't be tracked
final fullName = Beacon.future(() async {
  final first = await firstNameBeacon.toFuture();
  final last = await lastNameBeacon.toFuture(); // Not tracked!
  return '$first $last';
});

// ✅ GOOD - Capture futures before await
final fullName = Beacon.future(() async {
  final firstFuture = firstNameBeacon.toFuture();
  final lastFuture = lastNameBeacon.toFuture();
  final (first, last) = await (firstFuture, lastFuture).wait;
  return '$first $last';
});
```

#### Stream Beacons

Convert Dart streams to beacons:

```dart
final streamBeacon = Beacon.stream(deviceDataStream);
// Returns AsyncValue<T>, same pattern matching as future
```

### Transform Chains (Preferred Pattern)

**Always prefer chaining transformations** over manual subscriptions:

```dart
// ✅ GOOD - Declarative chain
final activeCount = source
    .filter((prev, next) => next > 0)
    .debounce(duration: Duration(milliseconds: 300))
    .map((value) => value * 2);

// ❌ BAD - Manual bridging
final activeCount = Beacon.writable(0);
source.subscribe((value) {
  if (value > 0) {
    activeCount.value = value * 2; // Risk of leaks, double notifications
  }
});
```

**Benefits of chaining:**
- Automatic lifecycle management
- No memory leaks
- Single reactive path (no redundant updates)
- Easier to test
- Declarative and readable

### Controllers & Lifecycle

#### BeaconControllerMixin (for StatefulWidget)

Auto-disposes beacons when widget unmounts:

```dart
class _MyWidgetState extends State<MyWidget> with BeaconControllerMixin {
  // Use B.* shorthand - auto-disposed
  late final count = B.writable(0);
  late final doubled = B.derived(() => count.value * 2);
  
  @override
  Widget build(BuildContext context) {
    return Text('${doubled.watch(context)}');
  }
  // No dispose() needed!
}
```

#### BeaconController (for plain classes)

Extend instead of mixin for non-widget classes:

```dart
class MyController extends BeaconController {
  late final count = B.writable(0);
  late final doubled = B.derived(() => count.value * 2);
}

// Usage
final controller = MyController();
// ... use controller ...
controller.dispose(); // Disposes all beacons
```

### Collections

Use `Beacon.list`, `Beacon.set` for reactive collections:

```dart
final items = Beacon.list<int>([1, 2, 3]);

items.add(4); // Triggers updates
items.remove(2); // Triggers updates

// Watch in widgets
Widget build(BuildContext context) {
  final list = items.watch(context);
  return ListView.builder(
    itemCount: list.length,
    itemBuilder: (context, i) => Text('${list[i]}'),
  );
}
```

### Families (Parameterized Beacons)

Create beacons keyed by a parameter:

```dart
final postFamily = Beacon.family((String id) {
  return Beacon.future(() => fetchPost(id));
});

// Usage
final post1 = postFamily('post-123');
final post2 = postFamily('post-456');
// Same ID returns same beacon instance (memoized)
```

### When to Use What

- **`Beacon.writable`** - Mutable state (user input, selections, flags)
- **`Beacon.derived`** - Computed values (filtered lists, counts, formatted strings)
- **`Beacon.future`** - Async data fetching (API calls, file reads)
- **`Beacon.stream`** - Converting Dart streams (BLE data, sensor streams)
- **`.subscribe()`** - Side effects only (logging, analytics, navigation)
- **Transform chains** - Always prefer over manual `.subscribe()` + mutation

### Testing

Convert beacons to streams for testing:

```dart
final count = Beacon.writable(0);
final stream = count.toStream();

count.value = 10;
count.value = 20;

expect(stream, emitsInOrder([0, 10, 20]));
```

Use `.next()` to wait for next value:

```dart
final count = Beacon.writable(0);
expectLater(count.next(), completion(10));
count.value = 10;
```
