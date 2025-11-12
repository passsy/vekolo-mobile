import 'dart:async';
import 'package:chirp/chirp.dart';

import 'package:async/async.dart';
import 'package:clock/clock.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;
import 'package:state_beacon/state_beacon.dart';
import 'package:vekolo/ble/ble_platform.dart' hide LogLevel;
import 'package:vekolo/ble/ble_scanner.dart';
import 'package:vekolo/ble/ble_transport.dart';
import 'package:vekolo/ble/transport_capabilities.dart';
import 'package:vekolo/domain/devices/fitness_device.dart';
import 'package:vekolo/domain/models/device_info.dart';
import 'package:vekolo/domain/models/fitness_data.dart';

/// Single device class representing any BLE fitness device.
///
/// A physical BLE device (e.g., KICKR CORE, Garmin HRM-Dual) is represented as
/// a single BleDevice instance that composes multiple BLE transports. Each
/// transport handles communication with a specific Bluetooth service.
///
/// This architecture separates:
/// - Physical device (BleDevice) - represents the actual hardware
/// - BLE services/sensors (BleTransport implementations) - handle protocol-specific communication
///
/// See docs/BLE_DEVICE_ARCHITECTURE.md for detailed architecture documentation.
class BleDevice extends FitnessDevice {
  /// Creates a BLE device with the specified transports.
  ///
  /// [id] - BLE device identifier
  /// [name] - Human-readable device name
  /// [transports] - List of compatible transports for this device
  /// [platform] - BLE platform abstraction for connecting/disconnecting
  /// [discoveredDevice] - Optional original discovered device for Phase 1 compatibility checks
  BleDevice({
    required String id,
    required String name,
    required List<BleTransport> transports,
    required BlePlatform platform,
    DiscoveredDevice? discoveredDevice,
  }) : _id = id,
       _name = name,
       _transports = transports,
       _platform = platform,
       _discoveredDevice = discoveredDevice {
    // Set up aggregated connection state
    _setupConnectionStateAggregation();
  }

  final String _id;
  final String _name;
  final List<BleTransport> _transports;
  final BlePlatform _platform;
  final DiscoveredDevice? _discoveredDevice;

  // Aggregated state
  late final WritableBeacon<ConnectionState> _connectionStateBeacon = Beacon.writable(ConnectionState.disconnected);
  ConnectionError? _lastConnectionError;

  // Transport state subscriptions (unsubscribe callbacks)
  final List<void Function()> _transportStateUnsubscribers = [];

  // ============================================================================
  // Identity Properties
  // ============================================================================

  @override
  String get id => _id;

  @override
  String get name => _name;

  @override
  List<String> get transportIds {
    // Return all transport IDs from attached transports
    final attachedTransports = _transports.where((t) => t.isAttached).toList();
    if (attachedTransports.isNotEmpty) {
      return attachedTransports.map((t) => t.transportId).toList();
    }
    // Fallback to all transport IDs if none attached yet
    return _transports.map((t) => t.transportId).toList();
  }

  @override
  DeviceType get type {
    // Determine device type based on capabilities
    // If device supports ERG mode, it's a trainer
    if (supportsErgMode) {
      return DeviceType.trainer;
    }
    // If device only provides heart rate, it's a heart rate monitor
    if (capabilities.length == 1 && capabilities.contains(DeviceDataType.heartRate)) {
      return DeviceType.heartRateMonitor;
    }
    // Default to unknown for other combinations
    return DeviceType.trainer; // Conservative default
  }

  @override
  Set<DeviceDataType> get capabilities {
    // Detect capabilities by checking which interfaces each ATTACHED transport implements
    final caps = <DeviceDataType>{};
    for (final transport in _transports.where((t) => t.isAttached)) {
      if (transport is PowerSource) caps.add(DeviceDataType.power);
      if (transport is CadenceSource) caps.add(DeviceDataType.cadence);
      if (transport is SpeedSource) caps.add(DeviceDataType.speed);
      if (transport is HeartRateSource) caps.add(DeviceDataType.heartRate);
    }
    return caps;
  }

  @override
  bool get supportsErgMode {
    // Device supports ERG mode if any ATTACHED transport implements ErgModeControl
    return _transports.any((t) => t.isAttached && t is ErgModeControl);
  }

  // ============================================================================
  // Connection Management
  // ============================================================================

  @override
  ReadableBeacon<ConnectionState> get connectionState => _connectionStateBeacon;

  @override
  ConnectionError? get lastConnectionError => _lastConnectionError;

  void _setupConnectionStateAggregation() {
    // Monitor all transport attachment states
    for (final transport in _transports) {
      final unsubscribe = transport.state.subscribe((state) {
        _updateAggregatedConnectionState();
      });
      _transportStateUnsubscribers.add(unsubscribe);
    }
  }

  void _updateAggregatedConnectionState() {
    // Aggregate connection state from all transports:
    // - If any transport is attaching -> connecting
    // - If all transports are attached -> connected
    // - Otherwise -> disconnected

    final states = _transports.map((t) => t.state.value).toList();

    if (states.any((s) => s == TransportState.attaching)) {
      _connectionStateBeacon.value = ConnectionState.connecting;
    } else if (states.every((s) => s == TransportState.attached)) {
      _connectionStateBeacon.value = ConnectionState.connected;
    } else {
      _connectionStateBeacon.value = ConnectionState.disconnected;
    }
  }

  @override
  CancelableOperation<void> connect() {
    return CancelableOperation.fromFuture(
      _connectImpl(),
      onCancel: () async {
        Chirp.info('Connection cancelled for $name');
        // Detach all transports on cancel
        await Future.wait(_transports.map((t) => t.detach()));
      },
    );
  }

  Future<void> _connectImpl() async {
    try {
      Chirp.info('Connecting device: $name');

      // Connect via BlePlatform abstraction (works with FakeBlePlatform in tests)
      Chirp.info('Connecting to physical device');
      await _platform.connect(_id, timeout: const Duration(seconds: 15));
      Chirp.info('Connected');

      // Get the device object via platform abstraction
      final device = _platform.getDevice(_id);

      // Request larger MTU for better performance (optional, non-fatal if it fails)
      try {
        final mtu = await _platform.requestMtu(_id);
        Chirp.info('MTU negotiated: $mtu bytes');
      } catch (e) {
        // MTU negotiation can fail on some devices or platforms (iOS handles automatically)
        // This is non-fatal, continue with default MTU
        Chirp.info('MTU negotiation failed, using default: $e');
      }

      // Discover services once via platform abstraction
      Chirp.info('Discovering services');
      final services = await _platform.discoverServices(_id);
      Chirp.info('Discovered ${services.length} services');

      // Create DiscoveredDevice for Phase 1 checks if not provided
      final discoveredDevice = _discoveredDevice ?? _createDiscoveredDeviceFromServices(device, services);

      // Phase 1: Verify canSupport for all transports (fast compatibility check)
      // This uses advertising data to verify transports can potentially work with the device
      Chirp.info('Verifying Phase 1 transport compatibility (canSupport)');
      final phase1VerifiedTransports = <BleTransport>[];
      for (final transport in _transports) {
        try {
          final canSupport = transport.canSupport(discoveredDevice);
          if (canSupport) {
            phase1VerifiedTransports.add(transport);
            Chirp.info('Transport ${transport.runtimeType} passed Phase 1 (canSupport)');
          } else {
            Chirp.info('Transport ${transport.runtimeType} failed Phase 1 (canSupport)');
          }
        } catch (e, stackTrace) {
          Chirp.error('Phase 1 verification failed for ${transport.runtimeType}', error: e, stackTrace: stackTrace);
        }
      }

      // Phase 2: Verify verifyCompatibility for Phase 1 verified transports (deep compatibility check)
      // This allows transports to perform deep checks on the connected device
      // Process serially to avoid overwhelming the BLE stack
      Chirp.info('Verifying Phase 2 transport compatibility (verifyCompatibility)');
      final verifiedTransports = <BleTransport>[];
      for (final transport in phase1VerifiedTransports) {
        try {
          final isCompatible = await transport.verifyCompatibility(device: device, services: services);
          if (isCompatible) {
            verifiedTransports.add(transport);
            Chirp.info('Transport ${transport.runtimeType} passed Phase 2 (verifyCompatibility)');
          } else {
            Chirp.info('Transport ${transport.runtimeType} failed Phase 2 (verifyCompatibility)');
          }
        } catch (e, stackTrace) {
          Chirp.error('Phase 2 verification failed for ${transport.runtimeType}', error: e, stackTrace: stackTrace);
        }
      }

      // Fail if no compatible transports found
      if (verifiedTransports.isEmpty) {
        throw Exception('No compatible transports found for device $name');
      }

      Chirp.info('${verifiedTransports.length}/${_transports.length} transport(s) verified, now attaching');

      // Try to attach only verified transports with the connected device and discovered services
      // Each transport finds its service and subscribes to characteristics
      // Process serially to avoid overwhelming the BLE stack
      var attachedCount = 0;
      for (final transport in verifiedTransports) {
        try {
          await transport.attach(device: device, services: services);
          attachedCount++;
          Chirp.info('Successfully attached ${transport.runtimeType}');
        } catch (e, stackTrace) {
          Chirp.error('Transport attachment failed for ${transport.runtimeType}', error: e, stackTrace: stackTrace);
          // Don't remove - just let it stay detached
          // Error is stored in transport.lastAttachError
        }
      }

      // Fail if no transports successfully attached
      if (attachedCount == 0) {
        throw Exception('All transports failed to attach for device $name');
      }

      Chirp.info('Device connected successfully with $attachedCount/${_transports.length} transport(s) attached');

      _lastConnectionError = null;
    } catch (e, stackTrace) {
      _lastConnectionError = ConnectionError(
        message: 'Failed to connect to device $name: $e',
        timestamp: clock.now(),
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    Chirp.info('Disconnecting device: $name');

    // Detach all transports in parallel
    await Future.wait(_transports.map((t) => t.detach()));

    // Disconnect via BlePlatform abstraction
    await _platform.disconnect(_id);
  }

  // ============================================================================
  // Data Streams
  // ============================================================================

  @override
  ReadableBeacon<PowerData?>? get powerStream {
    // Find first ATTACHED transport that implements PowerSource
    for (final transport in _transports.where((t) => t.isAttached)) {
      if (transport is PowerSource) {
        return (transport as PowerSource).powerStream;
      }
    }
    return null;
  }

  @override
  ReadableBeacon<CadenceData?>? get cadenceStream {
    // Find first ATTACHED transport that implements CadenceSource
    for (final transport in _transports.where((t) => t.isAttached)) {
      if (transport is CadenceSource) {
        return (transport as CadenceSource).cadenceStream;
      }
    }
    return null;
  }

  @override
  ReadableBeacon<SpeedData?>? get speedStream {
    // Find first ATTACHED transport that implements SpeedSource
    for (final transport in _transports.where((t) => t.isAttached)) {
      if (transport is SpeedSource) {
        return (transport as SpeedSource).speedStream;
      }
    }
    return null;
  }

  @override
  ReadableBeacon<HeartRateData?>? get heartRateStream {
    // Find first ATTACHED transport that implements HeartRateSource
    for (final transport in _transports.where((t) => t.isAttached)) {
      if (transport is HeartRateSource) {
        return (transport as HeartRateSource).heartRateStream;
      }
    }
    return null;
  }

  // ============================================================================
  // Control Capabilities
  // ============================================================================

  @override
  Future<void> setTargetPower(int watts) async {
    // Find first ATTACHED transport that implements ErgModeControl
    BleTransport? transport;
    for (final t in _transports.where((t) => t.isAttached)) {
      if (t is ErgModeControl) {
        transport = t;
        break;
      }
    }

    if (transport == null) {
      throw UnsupportedError('No attached transport supports ERG mode for device $name');
    }

    await (transport as ErgModeControl).setTargetPower(watts);
  }

  @override
  bool get supportsSimulationMode {
    // Device supports simulation mode if any ATTACHED transport implements SimulationModeControl
    return _transports.any((t) => t.isAttached && t is SimulationModeControl);
  }

  @override
  Future<void> setSimulationParameters(SimulationParameters parameters) async {
    // Find first ATTACHED transport that implements SimulationModeControl
    BleTransport? transport;
    for (final t in _transports.where((t) => t.isAttached)) {
      if (t is SimulationModeControl) {
        transport = t;
        break;
      }
    }

    if (transport == null) {
      throw UnsupportedError('No attached transport supports simulation mode for device $name');
    }

    await (transport as SimulationModeControl).setSimulationParameters(parameters);
  }

  // ============================================================================
  // Protocol-Specific Behavior
  // ============================================================================

  @override
  bool get requiresContinuousRefresh {
    // Conservative approach: require refresh if ANY transport needs it
    // In practice, FTMS trainers need continuous refresh
    return supportsErgMode; // Trainers typically need refresh
  }

  @override
  Duration get refreshInterval => const Duration(seconds: 2);

  // ============================================================================
  // Resource Management
  // ============================================================================

  /// Disposes of all resources including transports and subscriptions.
  ///
  /// Must be called when this device is no longer needed to prevent memory leaks.
  Future<void> dispose() async {
    Chirp.info('Disposing device: $name');

    // Unsubscribe from all beacon subscriptions
    for (final unsubscribe in _transportStateUnsubscribers) {
      unsubscribe();
    }
    _transportStateUnsubscribers.clear();

    // Dispose all transports
    await Future.wait(_transports.map((t) => t.dispose()));

    // Dispose beacons
    _connectionStateBeacon.dispose();
  }

  // ============================================================================
  // Helper Methods
  // ============================================================================

  /// Creates a synthetic DiscoveredDevice from discovered services.
  ///
  /// Used when the original DiscoveredDevice is not available, allowing
  /// Phase 1 compatibility checks (canSupport) to still be performed.
  DiscoveredDevice _createDiscoveredDeviceFromServices(
    fbp.BluetoothDevice device,
    List<fbp.BluetoothService> services,
  ) {
    final serviceUuids = services.map((s) => s.uuid).toList();
    final now = clock.now();

    final advertisementData = fbp.AdvertisementData(
      advName: _name,
      txPowerLevel: null,
      appearance: null,
      connectable: true,
      manufacturerData: {},
      serviceUuids: serviceUuids,
      serviceData: {},
    );

    final scanResult = fbp.ScanResult(device: device, advertisementData: advertisementData, rssi: 0, timeStamp: now);

    return DiscoveredDevice(scanResult: scanResult, firstSeen: now, lastSeen: now, rssi: null);
  }
}
