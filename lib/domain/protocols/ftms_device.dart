import 'dart:async';

import 'package:async/async.dart';
import 'package:clock/clock.dart';
import 'package:state_beacon/state_beacon.dart';
import 'package:vekolo/domain/devices/fitness_device.dart';
import 'package:vekolo/domain/models/device_info.dart';
import 'package:vekolo/domain/models/fitness_data.dart';
import 'package:vekolo/infrastructure/ble/ftms_ble_transport.dart' as transport;

/// FTMS (Fitness Machine Service) protocol implementation.
///
/// Wraps [transport.FtmsBleTransport] to implement the [FitnessDevice] interface
/// for FTMS-compliant smart trainers and bikes. FTMS is the standard Bluetooth
/// protocol for modern fitness equipment.
///
/// FTMS devices provide power and cadence data and support ERG mode control
/// where the trainer adjusts resistance to maintain a target power output.
///
/// This class bridges the domain layer (protocol-agnostic) with the infrastructure
/// layer (BLE-specific transport). It maps transport connection states to domain
/// connection states and exposes data streams in domain model types.
///
/// Used by [DeviceManager] to manage FTMS trainers alongside other device types.
class FtmsDevice extends FitnessDevice {
  /// Creates an FTMS device wrapper.
  ///
  /// [deviceId] must be a valid Bluetooth device identifier.
  /// [name] is displayed in the UI to identify this specific device.
  ///
  /// The transport is initialized internally and will be disposed when
  /// [dispose] is called.
  FtmsDevice({required String deviceId, required String name})
    : _id = deviceId,
      _name = name,
      _transport = transport.FtmsBleTransport(deviceId: deviceId);

  /// Creates an FTMS device with a custom transport for testing.
  ///
  /// Allows injection of mock/fake transports in unit tests.
  FtmsDevice.withTransport({
    required String deviceId,
    required String name,
    required transport.FtmsBleTransport transport,
  }) : _id = deviceId,
       _name = name,
       _transport = transport;

  final String _id;
  final String _name;
  final transport.FtmsBleTransport _transport;

  // Connection state beacon for mapping transport states to domain states
  late final WritableBeacon<ConnectionState> _connectionStateBeacon = Beacon.writable(ConnectionState.disconnected);
  StreamSubscription<transport.ConnectionState>? _connectionStateSubscription;
  ConnectionError? _lastConnectionError;

  // Data stream beacons
  late final WritableBeacon<PowerData?> _powerBeacon = Beacon.writable(null);
  late final WritableBeacon<CadenceData?> _cadenceBeacon = Beacon.writable(null);
  late final WritableBeacon<SpeedData?> _speedBeacon = Beacon.writable(null);
  StreamSubscription<PowerData>? _powerSubscription;
  StreamSubscription<CadenceData>? _cadenceSubscription;
  StreamSubscription<SpeedData>? _speedSubscription;

  // ============================================================================
  // Identity Properties
  // ============================================================================

  @override
  String get id => _id;

  @override
  String get name => _name;

  @override
  DeviceType get type => DeviceType.trainer;

  @override
  Set<DeviceDataType> get capabilities => {DeviceDataType.power, DeviceDataType.cadence, DeviceDataType.speed};

  // ============================================================================
  // Connection Management
  // ============================================================================

  @override
  ReadableBeacon<ConnectionState> get connectionState {
    // Set up connection state subscription on first access
    if (_connectionStateSubscription == null) {
      _setupConnectionStateMapping();
    }
    return _connectionStateBeacon;
  }

  @override
  ConnectionError? get lastConnectionError => _lastConnectionError;

  void _setupConnectionStateMapping() {
    // Update current state from transport's actual state
    _connectionStateBeacon.value = _transport.isConnected ? ConnectionState.connected : ConnectionState.disconnected;

    _connectionStateSubscription = _transport.connectionStateStream.listen((state) {
      final domainState = _mapConnectionState(state);
      _connectionStateBeacon.value = domainState;
    });

    // Set up data stream subscriptions
    _powerSubscription = _transport.powerStream.listen((data) {
      _powerBeacon.value = data;
    });

    _cadenceSubscription = _transport.cadenceStream.listen((data) {
      _cadenceBeacon.value = data;
    });

    _speedSubscription = _transport.speedStream.listen((data) {
      _speedBeacon.value = data;
    });
  }

  /// Maps transport connection state to domain connection state.
  ConnectionState _mapConnectionState(transport.ConnectionState state) {
    switch (state) {
      case transport.ConnectionState.disconnected:
        return ConnectionState.disconnected;
      case transport.ConnectionState.connecting:
        return ConnectionState.connecting;
      case transport.ConnectionState.connected:
        return ConnectionState.connected;
    }
  }

  @override
  CancelableOperation<void> connect() {
    return CancelableOperation.fromFuture(
      _connectImpl(),
      onCancel: () async {
        await _transport.disconnect();
      },
    );
  }

  Future<void> _connectImpl() async {
    try {
      await _transport.connect();
      _lastConnectionError = null;
    } catch (e, stackTrace) {
      _lastConnectionError = ConnectionError(
        message: 'Failed to connect to FTMS device: $e',
        timestamp: clock.now(),
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    await _transport.disconnect();
  }

  // ============================================================================
  // Data Streams
  // ============================================================================

  @override
  ReadableBeacon<PowerData?>? get powerStream {
    // Set up subscriptions on first access
    if (_powerSubscription == null && _connectionStateSubscription == null) {
      _setupConnectionStateMapping();
    }
    return _powerBeacon;
  }

  @override
  ReadableBeacon<CadenceData?>? get cadenceStream {
    // Set up subscriptions on first access
    if (_cadenceSubscription == null && _connectionStateSubscription == null) {
      _setupConnectionStateMapping();
    }
    return _cadenceBeacon;
  }

  @override
  ReadableBeacon<SpeedData?>? get speedStream {
    // Set up subscriptions on first access
    if (_speedSubscription == null && _connectionStateSubscription == null) {
      _setupConnectionStateMapping();
    }
    return _speedBeacon;
  }

  @override
  ReadableBeacon<HeartRateData?>? get heartRateStream => null;

  // ============================================================================
  // Control Capabilities (Trainers Only)
  // ============================================================================

  @override
  bool get supportsErgMode => true;

  @override
  Future<void> setTargetPower(int watts) async {
    if (!supportsErgMode) {
      throw UnsupportedError('This device does not support ERG mode');
    }
    _transport.syncState(transport.FtmsDeviceState(targetPower: watts));
  }

  // ============================================================================
  // Protocol-Specific Behavior
  // ============================================================================

  @override
  bool get requiresContinuousRefresh => true;

  @override
  Duration get refreshInterval => const Duration(seconds: 2);

  // ============================================================================
  // Resource Management
  // ============================================================================

  /// Disposes of all resources including the transport and beacons.
  ///
  /// Must be called when this device is no longer needed to prevent memory leaks.
  /// After calling dispose, this device instance should not be used anymore.
  void dispose() {
    _connectionStateSubscription?.cancel();
    _powerSubscription?.cancel();
    _cadenceSubscription?.cancel();
    _speedSubscription?.cancel();
    _connectionStateBeacon.dispose();
    _powerBeacon.dispose();
    _cadenceBeacon.dispose();
    _speedBeacon.dispose();
    _transport.dispose();
  }
}
