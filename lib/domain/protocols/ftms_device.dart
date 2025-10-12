import 'dart:async';

import 'package:async/async.dart';
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

  // Connection state stream controller for mapping transport states to domain states
  StreamController<ConnectionState>? _connectionStateController;
  StreamSubscription<transport.ConnectionState>? _connectionStateSubscription;
  ConnectionError? _lastConnectionError;

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
  Set<DeviceDataType> get capabilities => {DeviceDataType.power, DeviceDataType.cadence};

  // ============================================================================
  // Connection Management
  // ============================================================================

  @override
  Stream<ConnectionState> get connectionState {
    // Lazy initialization of connection state stream
    _connectionStateController ??= StreamController<ConnectionState>.broadcast(
      onListen: _setupConnectionStateMapping,
      onCancel: () {
        _connectionStateSubscription?.cancel();
        _connectionStateSubscription = null;
      },
    );
    return _connectionStateController!.stream;
  }

  @override
  ConnectionError? get lastConnectionError => _lastConnectionError;

  void _setupConnectionStateMapping() {
    _connectionStateSubscription?.cancel();
    _connectionStateSubscription = _transport.connectionStateStream.listen((state) {
      final domainState = _mapConnectionState(state);
      _connectionStateController?.add(domainState);
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
        timestamp: DateTime.now(),
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
  Stream<PowerData> get powerStream => _transport.powerStream;

  @override
  Stream<CadenceData> get cadenceStream => _transport.cadenceStream;

  @override
  Stream<HeartRateData>? get heartRateStream => null;

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
    await _transport.sendTargetPower(watts);
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

  /// Disposes of all resources including the transport and stream controllers.
  ///
  /// Must be called when this device is no longer needed to prevent memory leaks.
  /// After calling dispose, this device instance should not be used anymore.
  void dispose() {
    _connectionStateSubscription?.cancel();
    _connectionStateController?.close();
    _transport.dispose();
  }
}
