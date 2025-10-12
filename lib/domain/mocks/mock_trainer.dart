/// Mock smart trainer implementation for testing without Bluetooth hardware.
///
/// Provides a realistic simulation of a smart trainer that responds to ERG mode
/// commands with configurable latency and power ramp characteristics. Used for
/// testing workout scenarios and device management without actual hardware.
///
/// Example usage:
/// ```dart
/// final trainer = MockTrainer(
///   id: 'mock-001',
///   name: 'Virtual KICKR',
///   requiresContinuousRefresh: false,
/// );
/// await trainer.connect();
/// await trainer.setTargetPower(200);
/// trainer.powerStream?.listen((data) {
///   print('Power: ${data.watts}W');
/// });
/// ```
library;

import 'dart:async';
import 'dart:math';

import 'package:async/async.dart';
import 'package:vekolo/domain/devices/fitness_device.dart';
import 'package:vekolo/domain/models/device_info.dart';
import 'package:vekolo/domain/models/fitness_data.dart';

/// Realistic smart trainer mock for testing.
///
/// Simulates a controllable smart trainer with:
/// - Power and cadence data streams
/// - ERG mode control with realistic power ramp (3-5 seconds)
/// - Simulated BLE latency (100ms)
/// - Gradual power changes (±5W every 200ms)
/// - Configurable connection behavior
/// - Proper cleanup on disposal
class MockTrainer extends FitnessDevice {
  /// Creates a mock smart trainer.
  ///
  /// [id] - Unique device identifier
  /// [name] - Human-readable name displayed in UI
  /// [requiresContinuousRefresh] - Whether ERG commands need periodic resend
  /// [refreshInterval] - How often to refresh commands (default 2 seconds)
  /// [rampStepWatts] - Power change per step (default 5W)
  /// [rampStepIntervalMs] - Milliseconds between power steps (default 200ms)
  MockTrainer({
    required String id,
    required String name,
    bool requiresContinuousRefresh = false,
    Duration refreshInterval = const Duration(seconds: 2),
    int rampStepWatts = 5,
    int rampStepIntervalMs = 200,
  }) : _id = id,
       _name = name,
       _requiresContinuousRefresh = requiresContinuousRefresh,
       _refreshInterval = refreshInterval,
       _rampStepWatts = rampStepWatts,
       _rampStepIntervalMs = rampStepIntervalMs;

  final String _id;
  final String _name;
  final bool _requiresContinuousRefresh;
  final Duration _refreshInterval;
  final int _rampStepWatts;
  final int _rampStepIntervalMs;

  // Controllers for data streams
  final _powerController = StreamController<PowerData>.broadcast();
  final _cadenceController = StreamController<CadenceData>.broadcast();
  final _connectionController = StreamController<ConnectionState>.broadcast();

  // Current state
  int _currentPower = 0;
  int _targetPower = 0;
  int _currentCadence = 0;
  ConnectionState _state = ConnectionState.disconnected;
  ConnectionError? _lastConnectionError;
  Timer? _rampTimer;
  Timer? _cadenceTimer;
  final _random = Random();
  bool _disposed = false;

  // ============================================================================
  // FitnessDevice Interface Implementation
  // ============================================================================

  @override
  String get id => _id;

  @override
  String get name => _name;

  @override
  DeviceType get type => DeviceType.trainer;

  @override
  Set<DeviceDataType> get capabilities => {DeviceDataType.power, DeviceDataType.cadence};

  @override
  Stream<ConnectionState> get connectionState => _connectionController.stream;

  @override
  ConnectionError? get lastConnectionError => _lastConnectionError;

  @override
  CancelableOperation<void> connect() {
    return CancelableOperation.fromFuture(
      _connectImpl(),
      onCancel: () {
        _updateConnectionState(ConnectionState.disconnected);
      },
    );
  }

  Future<void> _connectImpl() async {
    if (_disposed) throw StateError('Device has been disposed');
    if (_state == ConnectionState.connected) return;

    _updateConnectionState(ConnectionState.connecting);

    try {
      // Simulate connection delay (realistic BLE discovery and pairing)
      await Future.delayed(const Duration(milliseconds: 500));

      _updateConnectionState(ConnectionState.connected);
      _lastConnectionError = null; // Clear any previous error

      // Start simulating cadence updates (realistic pedaling)
      _startCadenceSimulation();
    } catch (e, stackTrace) {
      _lastConnectionError = ConnectionError(
        message: 'Failed to connect: $e',
        timestamp: DateTime.now(),
        error: e,
        stackTrace: stackTrace,
      );
      _updateConnectionState(ConnectionState.disconnected);
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    if (_state == ConnectionState.disconnected) return;

    _stopAllSimulations();
    _updateConnectionState(ConnectionState.disconnected);
    _currentPower = 0;
    _targetPower = 0;
    _currentCadence = 0;
  }

  @override
  Stream<PowerData>? get powerStream => _powerController.stream;

  @override
  Stream<CadenceData>? get cadenceStream => _cadenceController.stream;

  @override
  Stream<HeartRateData>? get heartRateStream => null;

  @override
  bool get supportsErgMode => true;

  @override
  Future<void> setTargetPower(int watts) async {
    if (_disposed) throw StateError('Device has been disposed');
    if (_state != ConnectionState.connected) {
      throw StateError('Device not connected');
    }
    if (watts < 0) throw ArgumentError('Power cannot be negative: $watts');
    if (watts > 1500) throw ArgumentError('Power exceeds maximum: $watts');

    // Simulate BLE command latency
    await Future.delayed(const Duration(milliseconds: 100));

    _targetPower = watts;
    _simulatePowerRamp(watts);
  }

  @override
  bool get requiresContinuousRefresh => _requiresContinuousRefresh;

  @override
  Duration get refreshInterval => _refreshInterval;

  // ============================================================================
  // Simulation Logic
  // ============================================================================

  /// Simulates realistic power ramp to target.
  ///
  /// Gradually adjusts [_currentPower] toward [target] in steps of [_rampStepWatts]
  /// every [_rampStepIntervalMs] milliseconds. Emits power updates on each step.
  void _simulatePowerRamp(int target) {
    _rampTimer?.cancel();

    _rampTimer = Timer.periodic(Duration(milliseconds: _rampStepIntervalMs), (timer) {
      if (_disposed) {
        timer.cancel();
        return;
      }

      if (_currentPower < target) {
        // Ramp up to target
        _currentPower = min(_currentPower + _rampStepWatts, target);
      } else if (_currentPower > target) {
        // Ramp down to target
        _currentPower = max(_currentPower - _rampStepWatts, target);
      } else {
        // Reached target - add small realistic fluctuations (±2W)
        final fluctuation = _random.nextInt(5) - 2; // -2 to +2
        _currentPower = max(0, target + fluctuation);
      }

      // Emit power update with slight random variation for realism
      final variance = _random.nextDouble() * 2 - 1; // -1 to +1
      final actualPower = max(0, (_currentPower + variance).round());

      _powerController.add(PowerData(watts: actualPower, timestamp: DateTime.now()));

      // Cancel timer if we've been at target for a while and target hasn't changed
      if (_currentPower == target && _targetPower == target) {
        // Keep emitting with fluctuations - don't cancel
      }
    });
  }

  /// Simulates realistic cadence based on current power.
  ///
  /// Cadence typically correlates with power:
  /// - 0W: 0 RPM (not pedaling)
  /// - Low power (< 100W): 70-80 RPM
  /// - Medium power (100-200W): 80-90 RPM
  /// - High power (> 200W): 85-95 RPM
  ///
  /// Adds realistic variation (±3 RPM) to simulate natural pedaling rhythm.
  void _startCadenceSimulation() {
    _cadenceTimer?.cancel();

    _cadenceTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (_disposed) {
        timer.cancel();
        return;
      }

      if (_state != ConnectionState.connected) {
        timer.cancel();
        return;
      }

      // Calculate base cadence from current power
      int baseCadence;
      if (_currentPower == 0) {
        baseCadence = 0;
      } else if (_currentPower < 100) {
        baseCadence = 75;
      } else if (_currentPower < 200) {
        baseCadence = 85;
      } else {
        baseCadence = 90;
      }

      // Add realistic variation (±3 RPM) when pedaling
      if (baseCadence > 0) {
        final variation = _random.nextInt(7) - 3; // -3 to +3
        _currentCadence = max(0, baseCadence + variation);
      } else {
        _currentCadence = 0;
      }

      _cadenceController.add(CadenceData(rpm: _currentCadence, timestamp: DateTime.now()));
    });
  }

  /// Updates connection state and notifies listeners.
  void _updateConnectionState(ConnectionState newState) {
    _state = newState;
    _connectionController.add(newState);
  }

  /// Stops all active simulations.
  void _stopAllSimulations() {
    _rampTimer?.cancel();
    _rampTimer = null;
    _cadenceTimer?.cancel();
    _cadenceTimer = null;
  }

  // ============================================================================
  // Lifecycle Management
  // ============================================================================

  /// Disposes of all resources.
  ///
  /// Cancels all timers and closes all stream controllers. After calling dispose,
  /// this device cannot be used anymore.
  void dispose() {
    if (_disposed) return;
    _disposed = true;

    _stopAllSimulations();
    _powerController.close();
    _cadenceController.close();
    _connectionController.close();
  }
}
