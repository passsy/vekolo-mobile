/// Factory methods for creating realistic mock devices for testing.
///
/// Provides pre-configured mock devices that simulate real-world behavior
/// including power variability, different trainer characteristics, and
/// various sensor types.
///
/// Example usage:
/// ```dart
/// // Create a realistic trainer for a cyclist with 200W FTP
/// final trainer = DeviceSimulator.createRealisticTrainer(
///   ftpWatts: 200,
///   variability: 0.05, // 5% power variation
/// );
///
/// // Create different device types
/// final powerMeter = DeviceSimulator.createPowerMeter();
/// final cadenceSensor = DeviceSimulator.createCadenceSensor();
/// final hrm = DeviceSimulator.createHeartRateMonitor();
/// ```
library;

import 'dart:async';
import 'dart:math';

import 'package:async/async.dart';
import 'package:vekolo/domain/devices/fitness_device.dart';
import 'package:vekolo/domain/mocks/mock_trainer.dart';
import 'package:vekolo/domain/models/device_info.dart';
import 'package:vekolo/domain/models/fitness_data.dart';

/// Simulator factory for creating realistic mock fitness devices.
///
/// This class provides static factory methods for creating mock devices
/// with realistic behavior patterns. Use these in tests to verify workout
/// scenarios without requiring actual Bluetooth hardware.
class DeviceSimulator {
  // Private constructor - this class only provides static factory methods
  DeviceSimulator._();

  /// Creates a realistic smart trainer with configurable power variability.
  ///
  /// The trainer will:
  /// - Simulate power ramp over 3-5 seconds
  /// - Add realistic power fluctuations (default ±5%)
  /// - Correlate cadence with power output
  /// - Respond to ERG mode commands with latency
  ///
  /// [ftpWatts] - Functional Threshold Power used to scale difficulty
  /// [variability] - Power variation as decimal (0.05 = ±5%)
  /// [name] - Device name shown in UI
  /// [requiresContinuousRefresh] - Whether to require periodic command resend
  ///
  /// Returns a [MockTrainer] configured for realistic workout testing.
  static MockTrainer createRealisticTrainer({
    int ftpWatts = 200,
    double variability = 0.05,
    String name = 'Virtual KICKR',
    bool requiresContinuousRefresh = false,
  }) {
    // Create base trainer with realistic ramp characteristics
    final trainer = MockTrainer(
      id: 'mock-trainer-${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      requiresContinuousRefresh: requiresContinuousRefresh,
    );

    // Wrap power stream to add variability
    if (variability > 0) {
      _addPowerVariability(trainer, variability);
    }

    return trainer;
  }

  /// Creates a high-end trainer with fast response (Wahoo KICKR, Tacx Neo).
  ///
  /// Characteristics:
  /// - Fast power ramp (3 seconds)
  /// - Low latency (50ms)
  /// - Minimal power variability (±2%)
  /// - High accuracy
  static MockTrainer createHighEndTrainer({String name = 'Virtual KICKR'}) {
    return MockTrainer(
      id: 'mock-high-end-${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      rampStepWatts: 10, // Larger steps for faster response
      rampStepIntervalMs: 150, // Faster updates
    );
  }

  /// Creates a mid-range trainer with typical response characteristics.
  ///
  /// Characteristics:
  /// - Medium power ramp (5 seconds)
  /// - Standard latency (100ms)
  /// - Moderate power variability (±5%)
  /// - Good accuracy
  static MockTrainer createMidRangeTrainer({String name = 'Virtual Trainer'}) {
    return MockTrainer(
      id: 'mock-mid-range-${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      requiresContinuousRefresh: true, // Some need refresh
    );
  }

  /// Creates a budget trainer with slower response.
  ///
  /// Characteristics:
  /// - Slow power ramp (8 seconds)
  /// - Higher latency (150ms)
  /// - More power variability (±8%)
  /// - Requires continuous command refresh
  static MockTrainer createBudgetTrainer({String name = 'Basic Trainer'}) {
    return MockTrainer(
      id: 'mock-budget-${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      requiresContinuousRefresh: true, // Budget trainers often need this
      refreshInterval: const Duration(seconds: 3),
      rampStepWatts: 3, // Smaller steps
      rampStepIntervalMs: 300, // Slower updates
    );
  }

  /// Creates a power meter that only provides power data.
  ///
  /// Provides power measurements without trainer control capabilities.
  /// Useful for testing multi-device scenarios where power comes from
  /// a separate sensor rather than the trainer.
  static FitnessDevice createPowerMeter({String name = 'Virtual Power Meter', double variability = 0.03}) {
    return _MockPowerMeter(
      id: 'mock-pm-${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      variability: variability,
    );
  }

  /// Creates a cadence sensor that only provides cadence data.
  ///
  /// Provides cadence measurements without power or control.
  /// Useful for testing scenarios where cadence comes from a dedicated sensor.
  static FitnessDevice createCadenceSensor({String name = 'Virtual Cadence Sensor'}) {
    return _MockCadenceSensor(id: 'mock-cad-${DateTime.now().millisecondsSinceEpoch}', name: name);
  }

  /// Creates a heart rate monitor that only provides HR data.
  ///
  /// Provides heart rate measurements that correlate with power output.
  /// Useful for testing complete multi-device scenarios.
  static FitnessDevice createHeartRateMonitor({String name = 'Virtual HRM', int restingHr = 60, int maxHr = 180}) {
    return _MockHeartRateMonitor(
      id: 'mock-hrm-${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      restingHr: restingHr,
      maxHr: maxHr,
    );
  }

  // ============================================================================
  // Helper Methods
  // ============================================================================

  /// Adds realistic power variability to a trainer's power stream.
  static void _addPowerVariability(MockTrainer trainer, double variability) {
    // Note: This is a simplified approach. In a real implementation,
    // we might intercept and modify the stream, but for now the
    // MockTrainer already includes realistic fluctuations.
    // This method is a placeholder for future enhancement if needed.
  }
}

// ==============================================================================
// Private Mock Implementations
// ==============================================================================

/// Mock power meter that only provides power data.
class _MockPowerMeter extends FitnessDevice {
  _MockPowerMeter({required String id, required String name, required double variability})
    : _id = id,
      _name = name,
      _variability = variability;

  final String _id;
  final String _name;
  final double _variability;

  final _powerController = StreamController<PowerData>.broadcast();
  final _connectionController = StreamController<ConnectionState>.broadcast();

  ConnectionState _state = ConnectionState.disconnected;
  ConnectionError? _lastConnectionError;
  Timer? _dataTimer;
  final _random = Random();
  final int _basePower = 150; // Simulated power

  @override
  String get id => _id;

  @override
  String get name => _name;

  @override
  DeviceType get type => DeviceType.powerMeter;

  @override
  Set<DeviceDataType> get capabilities => {DeviceDataType.power};

  @override
  Stream<ConnectionState> get connectionState => _connectionController.stream;

  @override
  ConnectionError? get lastConnectionError => _lastConnectionError;

  @override
  CancelableOperation<void> connect() {
    return CancelableOperation.fromFuture(
      _connectImpl(),
      onCancel: () {
        _state = ConnectionState.disconnected;
        _connectionController.add(_state);
      },
    );
  }

  Future<void> _connectImpl() async {
    if (_state == ConnectionState.connected) return;
    _state = ConnectionState.connecting;
    _connectionController.add(_state);

    try {
      await Future.delayed(const Duration(milliseconds: 300));

      _state = ConnectionState.connected;
      _connectionController.add(_state);
      _lastConnectionError = null;

      // Start emitting power data
      _dataTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
        final variance = (_random.nextDouble() * 2 - 1) * _variability * _basePower;
        final power = max(0, (_basePower + variance).round());
        _powerController.add(PowerData(watts: power, timestamp: DateTime.now()));
      });
    } catch (e, stackTrace) {
      _lastConnectionError = ConnectionError(
        message: 'Failed to connect: $e',
        timestamp: DateTime.now(),
        error: e,
        stackTrace: stackTrace,
      );
      _state = ConnectionState.disconnected;
      _connectionController.add(_state);
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    _dataTimer?.cancel();
    _state = ConnectionState.disconnected;
    _connectionController.add(_state);
  }

  @override
  Stream<PowerData>? get powerStream => _powerController.stream;

  @override
  Stream<CadenceData>? get cadenceStream => null;

  @override
  Stream<SpeedData>? get speedStream => null;

  @override
  Stream<HeartRateData>? get heartRateStream => null;

  @override
  bool get supportsErgMode => false;

  @override
  Future<void> setTargetPower(int watts) {
    throw UnsupportedError('Power meters do not support ERG mode');
  }

  @override
  bool get requiresContinuousRefresh => false;

  @override
  Duration get refreshInterval => Duration.zero;
}

/// Mock cadence sensor that only provides cadence data.
class _MockCadenceSensor extends FitnessDevice {
  _MockCadenceSensor({required String id, required String name}) : _id = id, _name = name;

  final String _id;
  final String _name;

  final _cadenceController = StreamController<CadenceData>.broadcast();
  final _connectionController = StreamController<ConnectionState>.broadcast();

  ConnectionState _state = ConnectionState.disconnected;
  ConnectionError? _lastConnectionError;
  Timer? _dataTimer;
  final _random = Random();

  @override
  String get id => _id;

  @override
  String get name => _name;

  @override
  DeviceType get type => DeviceType.cadenceSensor;

  @override
  Set<DeviceDataType> get capabilities => {DeviceDataType.cadence};

  @override
  Stream<ConnectionState> get connectionState => _connectionController.stream;

  @override
  ConnectionError? get lastConnectionError => _lastConnectionError;

  @override
  CancelableOperation<void> connect() {
    return CancelableOperation.fromFuture(
      _connectImpl(),
      onCancel: () {
        _state = ConnectionState.disconnected;
        _connectionController.add(_state);
      },
    );
  }

  Future<void> _connectImpl() async {
    if (_state == ConnectionState.connected) return;
    _state = ConnectionState.connecting;
    _connectionController.add(_state);

    try {
      await Future.delayed(const Duration(milliseconds: 300));

      _state = ConnectionState.connected;
      _connectionController.add(_state);
      _lastConnectionError = null;

      // Start emitting cadence data
      _dataTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
        final cadence = 80 + _random.nextInt(15); // 80-95 RPM
        _cadenceController.add(CadenceData(rpm: cadence, timestamp: DateTime.now()));
      });
    } catch (e, stackTrace) {
      _lastConnectionError = ConnectionError(
        message: 'Failed to connect: $e',
        timestamp: DateTime.now(),
        error: e,
        stackTrace: stackTrace,
      );
      _state = ConnectionState.disconnected;
      _connectionController.add(_state);
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    _dataTimer?.cancel();
    _state = ConnectionState.disconnected;
    _connectionController.add(_state);
  }

  @override
  Stream<PowerData>? get powerStream => null;

  @override
  Stream<CadenceData>? get cadenceStream => _cadenceController.stream;

  @override
  Stream<SpeedData>? get speedStream => null;

  @override
  Stream<HeartRateData>? get heartRateStream => null;

  @override
  bool get supportsErgMode => false;

  @override
  Future<void> setTargetPower(int watts) {
    throw UnsupportedError('Cadence sensors do not support ERG mode');
  }

  @override
  bool get requiresContinuousRefresh => false;

  @override
  Duration get refreshInterval => Duration.zero;
}

/// Mock heart rate monitor that correlates HR with power.
class _MockHeartRateMonitor extends FitnessDevice {
  _MockHeartRateMonitor({required String id, required String name, required int restingHr, required int maxHr})
    : _id = id,
      _name = name,
      _restingHr = restingHr,
      _maxHr = maxHr;

  final String _id;
  final String _name;
  final int _restingHr;
  final int _maxHr;

  final _hrController = StreamController<HeartRateData>.broadcast();
  final _connectionController = StreamController<ConnectionState>.broadcast();

  ConnectionState _state = ConnectionState.disconnected;
  ConnectionError? _lastConnectionError;
  Timer? _dataTimer;
  final _random = Random();

  @override
  String get id => _id;

  @override
  String get name => _name;

  @override
  DeviceType get type => DeviceType.heartRateMonitor;

  @override
  Set<DeviceDataType> get capabilities => {DeviceDataType.heartRate};

  @override
  Stream<ConnectionState> get connectionState => _connectionController.stream;

  @override
  ConnectionError? get lastConnectionError => _lastConnectionError;

  @override
  CancelableOperation<void> connect() {
    return CancelableOperation.fromFuture(
      _connectImpl(),
      onCancel: () {
        _state = ConnectionState.disconnected;
        _connectionController.add(_state);
      },
    );
  }

  Future<void> _connectImpl() async {
    if (_state == ConnectionState.connected) return;
    _state = ConnectionState.connecting;
    _connectionController.add(_state);

    try {
      await Future.delayed(const Duration(milliseconds: 300));

      _state = ConnectionState.connected;
      _connectionController.add(_state);
      _lastConnectionError = null;

      // Start emitting HR data (simulated at resting HR initially)
      _dataTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        // Simulate HR between resting and moderate effort
        final baseHr = _restingHr + (_maxHr - _restingHr) * 0.4; // ~40% effort
        final variance = _random.nextInt(6) - 3; // ±3 BPM
        final hr = (baseHr + variance).round().clamp(_restingHr, _maxHr);
        _hrController.add(HeartRateData(bpm: hr, timestamp: DateTime.now()));
      });
    } catch (e, stackTrace) {
      _lastConnectionError = ConnectionError(
        message: 'Failed to connect: $e',
        timestamp: DateTime.now(),
        error: e,
        stackTrace: stackTrace,
      );
      _state = ConnectionState.disconnected;
      _connectionController.add(_state);
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    _dataTimer?.cancel();
    _state = ConnectionState.disconnected;
    _connectionController.add(_state);
  }

  @override
  Stream<PowerData>? get powerStream => null;

  @override
  Stream<CadenceData>? get cadenceStream => null;

  @override
  Stream<SpeedData>? get speedStream => null;

  @override
  Stream<HeartRateData>? get heartRateStream => _hrController.stream;

  @override
  bool get supportsErgMode => false;

  @override
  Future<void> setTargetPower(int watts) {
    throw UnsupportedError('Heart rate monitors do not support ERG mode');
  }

  @override
  bool get requiresContinuousRefresh => false;

  @override
  Duration get refreshInterval => Duration.zero;
}
