# BLE Device Architecture

## Overview

A physical BLE device (e.g., KICKR CORE, Garmin HRM-Dual) is represented as a single `BleDevice` instance that **composes** multiple BLE transports. Each transport handles communication with a specific Bluetooth service and provides one or more data capabilities.

This architecture separates:
- **Physical device** (`BleDevice`) - represents the actual hardware
- **BLE services/sensors** (`BleTransport` implementations) - handle protocol-specific communication

## Core Concepts

### 1. BleDevice (Physical Device)

A single class representing any BLE fitness device, regardless of type.

**Responsibilities:**
- Aggregate multiple transports
- Expose unified connection state
- Provide data streams from all transports
- Manage device lifecycle (connect/disconnect/dispose)

**Does NOT:**
- Know about specific protocols (FTMS, Heart Rate, etc.)
- Implement protocol-specific logic
- Parse BLE characteristics

### 2. BleTransport (Service/Sensor)

Abstract interface implemented by protocol-specific transports.

**Responsibilities:**
- Describes possible capabilities based on advertising data / services
- Handle BLE communication for one service
- Parse protocol-specific data
- Expose typed data streams
- Manage service-level attachment state
- After attaching, provides the exact capabilities for that device based on e.g. firmware version

**Examples:**
- `FtmsBleTransport` - FTMS protocol (trainers)
- `HeartRateBleTransport` - Heart Rate Service
- `CyclingPowerBleTransport` - Cycling Power Service
- `WahooProprietaryTransport` - Wahoo-specific protocol

### 3. Transport Registry

Central registry of all available transport implementations.

**Responsibilities:**
- Maintain list of transport factories
- Test each transport's compatibility with a device
- Return all compatible transports for a device
- Allow runtime registration of new transports

## Transport Compatibility Detection

Transports implement two levels of compatibility checking:

### Level 1: Fast Compatibility Check (Instance Method)

**Used by:** BLE Scanner during device discovery
**When:** Before connecting to the device
**Connection required:** No - only uses advertising data

```dart
abstract class BleTransport {
  /// Quick compatibility check using only advertising data.
  ///
  /// Should check:
  /// - Service UUIDs in advertisement
  /// - Manufacturer ID and manufacturer data
  /// - Device name patterns
  /// - RSSI (if protocol requires minimum signal strength)
  ///
  /// Must be fast (< 1ms) as it runs for every discovered device.
  bool canSupport(DiscoveredDevice device);
}
```

**How it works:**
1. TransportRegistry creates lightweight transport instance (no BLE connection)
2. Calls `canSupport(discovered)` on the instance
3. If compatible, keeps instance; if not, disposes it
4. Transport constructors must NOT establish BLE connections

**Examples:**

```dart
// Simple: Just check service UUID
class FtmsBleTransport implements BleTransport {
  FtmsBleTransport({required this.deviceId});

  final String deviceId;
  static const _ftmsServiceUuid = Guid('00001826-0000-1000-8000-00805f9b34fb');

  @override
  bool canSupport(DiscoveredDevice device) {
    return device.serviceUuids.contains(_ftmsServiceUuid);
  }
}

// Complex: Check manufacturer data + service
class WahooProprietaryTransport implements BleTransport {
  WahooProprietaryTransport({required this.deviceId});

  final String deviceId;
  static const _wahooManufacturerId = 0x0100;
  static const _wahooServiceUuid = Guid('...');

  @override
  bool canSupport(DiscoveredDevice device) {
    final hasWahooId = device.manufacturerData.containsKey(_wahooManufacturerId);
    final hasService = device.serviceUuids.contains(_wahooServiceUuid);
    return hasWahooId && hasService;
  }
}

// Device name pattern
class StrydFootpodTransport implements BleTransport {
  StrydFootpodTransport({required this.deviceId});

  final String deviceId;

  @override
  bool canSupport(DiscoveredDevice device) {
    final name = device.name?.toLowerCase() ?? '';
    return name.startsWith('stryd') || name.contains('footpod');
  }
}
```

### Level 2: Deep Compatibility Check (Optional)

**Used by:** BleDevice during device connection (before attach)
**When:** After BLE connection is established and services are discovered, but BEFORE attach()
**Connection required:** Yes - can read characteristics

```dart
abstract class BleTransport {
  /// Optional deep compatibility check after connecting, before attaching.
  ///
  /// Called with the already-connected device and discovered services.
  /// Use these to perform deep compatibility checks before committing to attach().
  ///
  /// Should check:
  /// - Read firmware version characteristics
  /// - Check protocol version
  /// - Verify required characteristics exist
  /// - Test read/write permissions
  ///
  /// May take longer (100-500ms) as it involves BLE reads.
  /// Return false if device doesn't fully support this transport.
  Future<bool> verifyCompatibility({
    required BluetoothDevice device,
    required List<BluetoothService> services,
  }) async => true; // Default: no deep check
}
```

**Examples:**

```dart
class WahooProprietaryTransport {
  @override
  Future<bool> verifyCompatibility({
    required BluetoothDevice device,
    required List<BluetoothService> services,
  }) async {
    // Find firmware version characteristic from discovered services
    final fwChar = services
        .expand((s) => s.characteristics)
        .firstWhere((c) => c.uuid == firmwareVersionUuid);

    // Read firmware version to determine protocol variant
    final versionData = await fwChar.read();
    final version = parseFirmwareVersion(versionData);
    return version >= minimumSupportedVersion;
  }
}

class AdvancedFtmsTransport {
  @override
  Future<bool> verifyCompatibility({
    required BluetoothDevice device,
    required List<BluetoothService> services,
  }) async {
    // Find FTMS service from discovered services
    final ftmsService = services.firstWhere((s) => s.uuid == ftmsServiceUuid);

    // Find and read supported features characteristic
    final featuresChar = ftmsService.characteristics.firstWhere(
      (c) => c.uuid == ftmsFeaturesUuid,
    );
    final featuresData = await featuresChar.read();

    // Check if device supports advanced FTMS features
    final features = parseFtmsFeatures(featuresData);
    return features.supportsSimulationMode;
  }
}
```

## Transport Capabilities via Interfaces

Each transport implements only the capability interfaces it supports. The implemented interfaces determine the transport's possible capabilities.

### Capability Interfaces

```dart
/// Interface for transports that are a source of power data
abstract interface class PowerSource {
  ReadableBeacon<PowerData?> get powerStream;
}

/// Interface for transports that are a source of cadence data
abstract interface class CadenceSource {
  ReadableBeacon<CadenceData?> get cadenceStream;
}

/// Interface for transports that are a source of speed data
abstract interface class SpeedSource {
  ReadableBeacon<SpeedData?> get speedStream;
}

/// Interface for transports that are a source of heart rate data
abstract interface class HeartRateSource {
  ReadableBeacon<HeartRateData?> get heartRateStream;
}

/// Interface for transports that support ERG mode control
abstract interface class ErgModeControl {
  Future<void> setTargetPower(int watts);
}

/// Interface for transports that support simulation mode control
abstract interface class SimulationModeControl {
  Future<void> setSimulationParameters(SimulationParameters parameters);
}
```

**Examples:**

```dart
// FTMS transport implements all cycling capabilities + both control modes
class FtmsBleTransport implements
    BleTransport,
    PowerSource,
    CadenceSource,
    SpeedSource,
    ErgModeControl,
    SimulationModeControl {
  // Implements all methods from all interfaces
}

// Heart Rate transport implements only HR capability
class HeartRateBleTransport implements
    BleTransport,
    HeartRateSource {
  // Only implements heart rate stream
}

// Combined Speed/Cadence sensor implements two capabilities
class CscBleTransport implements
    BleTransport,
    SpeedSource,
    CadenceSource {
  // Implements speed and cadence streams only
}
```

Capabilities are detected at runtime via interface checks:

```dart
Set<DeviceDataType> getCapabilities(BleTransport transport) {
  final caps = <DeviceDataType>{};
  if (transport is PowerSource) caps.add(DeviceDataType.power);
  if (transport is CadenceSource) caps.add(DeviceDataType.cadence);
  if (transport is SpeedSource) caps.add(DeviceDataType.speed);
  if (transport is HeartRateSource) caps.add(DeviceDataType.heartRate);
  return caps;
}

bool supportsErgMode(BleTransport transport) {
  return transport is ErgModeControl;
}

bool supportsSimulationMode(BleTransport transport) {
  return transport is SimulationModeControl;
}
```

## Device Creation Flow

```
1. BLE Scanner discovers device
   ↓
2. TransportRegistry.detectCompatibleTransports(discovered)
   ↓
3. For each registered transport:
   - Call Transport.canSupport(discovered)
   - If true, add to compatible list
   ↓
4. Create BleDevice with compatible transports
   ↓
5. User initiates connection
   ↓
6. BleDevice.connect():
   - Connect to physical device ONCE
   - Discover services ONCE
   - Each transport calls verifyCompatibility(device, services) (BEFORE attach)
   - Remove incompatible transports
   - Try to attach remaining transports with device and services (partial success allowed)
   - Each transport finds its service and subscribes to characteristics
   - Remove transports that failed to attach
   - If no transports remain, fail connection
   ↓
7. Device ready with aggregated capabilities from successfully attached transports
```

## Multi-Transport Example: KICKR CORE with HR

**Advertised Services:**
- FTMS Service (0x1826)
- Heart Rate Service (0x180D)

**Compatibility Detection:**
```dart
// TransportRegistry creates instances and tests compatibility
final ftmsTransport = FtmsBleTransport(deviceId: kickr.deviceId);
ftmsTransport.canSupport(kickr) // true

final hrTransport = HeartRateBleTransport(deviceId: kickr.deviceId);
hrTransport.canSupport(kickr) // true

final cpTransport = CyclingPowerBleTransport(deviceId: kickr.deviceId);
cpTransport.canSupport(kickr) // false (disposed by registry)
```

**Resulting BleDevice:**
```dart
BleDevice(
  id: "DFFE6EF8-640E-AFDB-A557-C3D891F37A55",
  name: "KICKR CORE 6D9A",
  transports: [
    FtmsBleTransport(...),      // provides power, cadence, speed + ERG control
    HeartRateBleTransport(...), // provides heartRate
  ],
  capabilities: {power, cadence, speed, heartRate},
  supportsErgMode: true,
)
```

## Transport Selection and Conflicts

When multiple transports provide the same capability, the first matching transport is used.

**Example Conflict:**

Device advertises both:
- FTMS (provides power)
- Cycling Power Service (provides power)

Both transports are compatible. The first registered transport's data stream is exposed:

```dart
// If transports list is: [FtmsBleTransport, CyclingPowerBleTransport]
// Result: FtmsBleTransport's power stream is used

// If transports list is: [CyclingPowerBleTransport, FtmsBleTransport]
// Result: CyclingPowerBleTransport's power stream is used
```

**Future Enhancement:** Priority-based selection or user preference could be added to allow explicit control over which transport is preferred when conflicts exist.

## Transport Lifecycle

Each transport manages its own lifecycle:

```dart
abstract class BleTransport {
  /// Attach to the BLE service on an already-connected device.
  ///
  /// The [device] must already be connected and [services] must be discovered
  /// by BleDevice before calling this method. BleDevice handles the physical
  /// connection and service discovery once, then passes them to all transports.
  ///
  /// The transport finds its specific service, locates characteristics, and subscribes.
  Future<void> attach({
    required BluetoothDevice device,
    required List<BluetoothService> services,
  });

  /// Detach from the BLE service.
  ///
  /// Unsubscribes from characteristics and cleans up service resources.
  /// Does not disconnect the physical device.
  Future<void> detach();

  /// Clean up resources
  Future<void> dispose();

  /// Reactive beacon of transport attachment state
  ReadableBeacon<TransportState> get state;

  /// Current attachment state (convenience getter)
  bool get isAttached;
}
```

**BleDevice orchestrates all transports:**

```dart
class BleDevice {
  Future<void> connect() async {
    // Connect to physical device ONCE
    final device = BluetoothDevice.fromId(_id);
    await device.connect();

    // Discover services ONCE
    final services = await device.discoverServices();

    // Phase 1: Verify compatibility (BEFORE attaching)
    final verificationResults = await Future.wait(
      _transports.indexed.map((indexed) async {
        try {
          final isCompatible = await indexed.$2.verifyCompatibility(
            device: device,
            services: services,
          );
          return (indexed.$1, isCompatible);
        } catch (e) {
          return (indexed.$1, false); // Verification failed
        }
      }),
      eagerError: false,
    );

    // Remove incompatible transports
    final incompatibleIndices = verificationResults
        .where((result) => !result.$2)
        .map((result) => result.$1)
        .toList()
      ..sort((a, b) => b.compareTo(a));

    for (final index in incompatibleIndices) {
      await _transports[index].dispose();
      _transports.removeAt(index);
    }

    if (_transports.isEmpty) {
      throw Exception('No compatible transports found');
    }

    // Phase 2: Attach verified transports
    // Each transport just finds its service and subscribes to characteristics
    // No redundant connect() or discoverServices() calls!
    final attachResults = await Future.wait(
      _transports.indexed.map((indexed) async {
        try {
          await indexed.$2.attach(device: device, services: services);
          return (indexed.$1, null); // Success
        } catch (e) {
          return (indexed.$1, e); // Failed - error stored in transport.lastAttachError
        }
      }),
      eagerError: false, // Don't fail fast
    );

    // Remove failed transports, continue with successful ones
    // Fails only if ALL transports fail
  }

  Future<void> disconnect() async {
    // Detach all transports
    await Future.wait(
      _transports.map((t) => t.detach()),
    );
  }
}
```

## Data Stream Aggregation

BleDevice aggregates data streams from all transports:

```dart
class BleDevice extends FitnessDevice {
  @override
  ReadableBeacon<PowerData?>? get powerStream {
    // Find first transport that implements PowerSource
    for (final transport in _transports) {
      if (transport is PowerSource) {
        return (transport as PowerSource).powerStream;
      }
    }
    return null;
  }

  @override
  Set<DeviceDataType> get capabilities {
    // Detect capabilities by checking which interfaces each transport implements
    final caps = <DeviceDataType>{};
    for (final transport in _transports) {
      if (transport is PowerSource) caps.add(DeviceDataType.power);
      if (transport is CadenceSource) caps.add(DeviceDataType.cadence);
      if (transport is SpeedSource) caps.add(DeviceDataType.speed);
      if (transport is HeartRateSource) caps.add(DeviceDataType.heartRate);
    }
    return caps;
  }

  @override
  bool get supportsErgMode {
    // Device supports ERG mode if any transport implements ErgModeControl
    return _transports.any((t) => t is ErgModeControl);
  }
}
```

## Extensibility

### Adding New Transports

1. Implement `BleTransport` interface
2. Implement `canSupport()` instance method
3. Create a `TransportRegistration` with a factory function
4. Register with `TransportRegistry`

```dart
class NewProtocolTransport implements BleTransport {
  NewProtocolTransport({required this.deviceId});

  final String deviceId;
  static const _newProtocolUuid = Guid('...');

  @override
  bool canSupport(DiscoveredDevice device) {
    // Check compatibility using advertising data
    return device.serviceUuids.contains(_newProtocolUuid);
  }

  @override
  Future<void> attach({
    required BluetoothDevice device,
    required List<BluetoothService> services,
  }) async {
    // Find our service from the already-discovered services
    final myService = services.firstWhere((s) => s.uuid == _myServiceUuid);

    // Find characteristics and subscribe
    final myChar = myService.characteristics.firstWhere((c) => c.uuid == _myCharUuid);
    await myChar.setNotifyValue(true);
    myChar.onValueReceived.listen(_parseData);
  }

  @override
  Future<void> detach() async {
    // Unsubscribe and clean up
  }

  // ... implement other BleTransport methods
}

// Create registration
final newProtocolRegistration = TransportRegistration(
  name: 'New Protocol',
  factory: (deviceId) => NewProtocolTransport(deviceId: deviceId),
);

// Register with registry
final registry = TransportRegistry();
registry.register(newProtocolRegistration);
```

### Custom/Proprietary Protocols

The architecture supports vendor-specific protocols:

```dart
class PelotonBikeTransport implements BleTransport {
  PelotonBikeTransport({required this.deviceId});

  final String deviceId;

  @override
  bool canSupport(DiscoveredDevice device) {
    // Check for Peloton-specific manufacturer data
    return device.name?.startsWith('Peloton') ?? false;
  }

  @override
  Future<bool> verifyCompatibility({
    required BluetoothDevice device,
    required List<BluetoothService> services,
  }) async {
    // Find proprietary service from discovered services
    final proprietaryService = services.firstWhere(
      (s) => s.uuid == _proprietaryUuid,
    );

    // Find and read version characteristic
    final versionChar = proprietaryService.characteristics.firstWhere(
      (c) => c.uuid == _versionCharUuid,
    );
    final versionData = await versionChar.read();

    // Verify protocol version
    final version = parseProprietaryVersion(versionData);
    return version.isSupported;
  }

  @override
  Future<void> attach({
    required BluetoothDevice device,
    required List<BluetoothService> services,
  }) async {
    // Find proprietary service from already-discovered services
    final proprietaryService = services.firstWhere((s) => s.uuid == _proprietaryUuid);

    // Set up proprietary protocol communication
  }

  @override
  Future<void> detach() async {
    // Detach from service
  }

  // ... implement other BleTransport methods
}

// Register the proprietary transport
final pelotonRegistration = TransportRegistration(
  name: 'Peloton Bike',
  factory: (deviceId) => PelotonBikeTransport(deviceId: deviceId),
);
registry.register(pelotonRegistration);
```

## Testing Strategy

### Unit Tests

Each transport can be tested independently:

```dart
test('FtmsBleTransport detects FTMS service', () {
  final transport = FtmsBleTransport(deviceId: 'test-device-id');
  final device = DiscoveredDevice(
    deviceId: 'test-device-id',
    serviceUuids: [ftmsServiceUuid],
    name: 'Test Device',
  );

  expect(transport.canSupport(device), isTrue);
});

test('FtmsBleTransport parses power data', () async {
  final transport = FakeFtmsBleTransport();
  await transport.attach();

  transport.simulatePowerData([0x00, 0x64, 0x00]); // 100 watts

  expect(transport.powerStream.value?.watts, equals(100));
});
```

### Integration Tests

Test multi-transport devices:

```dart
test('KICKR with HR provides all capabilities', () async {
  final discovered = DiscoveredDevice(
    deviceId: 'test-kickr-id',
    name: 'KICKR CORE',
    serviceUuids: [ftmsServiceUuid, heartRateServiceUuid],
  );

  // Detect compatible transports
  final registry = TransportRegistry();
  registry.register(ftmsTransportRegistration);
  registry.register(heartRateTransportRegistration);

  final transports = registry.detectCompatibleTransports(
    discovered,
    deviceId: discovered.deviceId,
  );

  // Create device with transports
  final device = BleDevice(
    id: discovered.deviceId,
    name: discovered.name,
    transports: transports,
  );

  expect(device.capabilities, containsAll([
    DeviceDataType.power,
    DeviceDataType.cadence,
    DeviceDataType.speed,
    DeviceDataType.heartRate,
  ]));
});
```

## Migration Notes

### From Current Architecture

**Before:**
```dart
// Separate device classes
final trainer = FtmsDevice(...);
final hrMonitor = HeartRateDevice(...);
```

**After:**
```dart
// Single device with multiple transports
// 1. Detect compatible transports
final transports = registry.detectCompatibleTransports(
  discovered,
  deviceId: discovered.deviceId,
);

// 2. Create device with transports
final device = BleDevice(
  id: discovered.deviceId,
  name: discovered.name,
  transports: transports,
);

// Device automatically provides all capabilities from all transports
```

### Backward Compatibility

Existing code using `FitnessDevice` interface continues to work:

```dart
// Still works - BleDevice implements FitnessDevice
FitnessDevice device = BleDevice(
  id: deviceId,
  name: deviceName,
  transports: transports,
);
device.powerStream?.subscribe((data) {
  // Handle power data
});
device.connect();
```

## Future Enhancements

### 1. Transport Plugins

Allow runtime loading of transport implementations:

```dart
TransportRegistry.registerPlugin('wahoo_transport.dart');
```

### 2. User Preferences

Let users choose which transport to use when conflicts exist:

```dart
device.setPreferredTransportForDataType(
  DeviceDataType.power,
  CyclingPowerBleTransport,
);
```

### 3. Transport Fallback

Automatic fallback if primary transport fails:

```dart
// If FTMS power fails, fall back to Cycling Power Service
device.enableFallback(DeviceDataType.power);
```

### 4. Multi-Device Aggregation

Future support for virtual devices combining multiple physical devices:

```dart
final virtualDevice = AggregateDevice([
  trainerDevice,  // provides power, speed
  hrMonitor,      // provides heart rate
  cadenceSensor,  // provides cadence
]);
```
