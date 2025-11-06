// ignore_for_file: use_setters_to_change_properties

import 'package:async/async.dart';
import 'package:state_beacon/state_beacon.dart';
import 'package:vekolo/ble/transport_capabilities.dart';
import 'package:vekolo/domain/devices/fitness_device.dart';
import 'package:vekolo/domain/models/device_info.dart';
import 'package:vekolo/domain/models/fitness_data.dart';

/// Fake implementation of FitnessDevice for testing.
///
/// Allows manual control over data streams for testing device manager logic.
class FakeFitnessDevice implements FitnessDevice {
  FakeFitnessDevice({
    required String id,
    required String name,
    this.type = DeviceType.trainer,
    Set<DeviceDataType>? capabilities,
  }) : _id = id,
       _name = name,
       _capabilities =
           capabilities ??
           {DeviceDataType.power, DeviceDataType.cadence, DeviceDataType.speed, DeviceDataType.heartRate};

  final String _id;
  final String _name;
  final Set<DeviceDataType> _capabilities;

  @override
  String get id => _id;

  @override
  String get name => _name;

  @override
  final DeviceType type;

  @override
  Set<DeviceDataType> get capabilities => _capabilities;

  @override
  List<String> get transportIds => ['FakeTrans port'];

  // Connection state
  final WritableBeacon<ConnectionState> _connectionStateBeacon = Beacon.writable(ConnectionState.disconnected);

  @override
  ReadableBeacon<ConnectionState> get connectionState => _connectionStateBeacon;

  @override
  ConnectionError? lastConnectionError;

  @override
  CancelableOperation<void> connect() {
    _connectionStateBeacon.value = ConnectionState.connected;
    return CancelableOperation.fromFuture(Future.value());
  }

  @override
  Future<void> disconnect() async {
    _connectionStateBeacon.value = ConnectionState.disconnected;
  }

  // Data streams
  final WritableBeacon<PowerData?> _powerBeacon = Beacon.writable(null);
  final WritableBeacon<CadenceData?> _cadenceBeacon = Beacon.writable(null);
  final WritableBeacon<SpeedData?> _speedBeacon = Beacon.writable(null);
  final WritableBeacon<HeartRateData?> _heartRateBeacon = Beacon.writable(null);

  @override
  ReadableBeacon<PowerData?>? get powerStream => _capabilities.contains(DeviceDataType.power) ? _powerBeacon : null;

  @override
  ReadableBeacon<CadenceData?>? get cadenceStream =>
      _capabilities.contains(DeviceDataType.cadence) ? _cadenceBeacon : null;

  @override
  ReadableBeacon<SpeedData?>? get speedStream => _capabilities.contains(DeviceDataType.speed) ? _speedBeacon : null;

  @override
  ReadableBeacon<HeartRateData?>? get heartRateStream =>
      _capabilities.contains(DeviceDataType.heartRate) ? _heartRateBeacon : null;

  // Test control methods

  /// Emit power data for testing.
  void emitPower(PowerData data) {
    _powerBeacon.value = data;
  }

  /// Emit cadence data for testing.
  void emitCadence(CadenceData data) {
    _cadenceBeacon.value = data;
  }

  /// Emit speed data for testing.
  void emitSpeed(SpeedData data) {
    _speedBeacon.value = data;
  }

  /// Emit heart rate data for testing.
  void emitHeartRate(HeartRateData data) {
    _heartRateBeacon.value = data;
  }

  // Control capabilities
  @override
  bool get supportsErgMode => true;

  @override
  bool get supportsSimulationMode => false;

  @override
  Duration get refreshInterval => const Duration(seconds: 10);

  @override
  bool get requiresContinuousRefresh => false;

  int? _targetPower;

  @override
  Future<void> setTargetPower(int watts) async {
    if (!supportsErgMode) {
      throw StateError('Device does not support ERG mode');
    }
    if (connectionState.value != ConnectionState.connected) {
      throw StateError('Device not connected');
    }
    _targetPower = watts;
  }

  /// Get the last target power set (for testing).
  int? get targetPower => _targetPower;

  @override
  Future<void> setSimulationParameters(SimulationParameters parameters) {
    throw UnimplementedError('Simulation mode not supported');
  }

  void dispose() {
    _connectionStateBeacon.dispose();
    _powerBeacon.dispose();
    _cadenceBeacon.dispose();
    _speedBeacon.dispose();
    _heartRateBeacon.dispose();
  }
}
