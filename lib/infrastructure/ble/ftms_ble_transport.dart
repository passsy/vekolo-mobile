import 'dart:async';
import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:async/async.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;
import 'package:vekolo/domain/models/fitness_data.dart';

/// Shadow state representing the desired configuration of an FTMS device.
///
/// Similar to virtual DOM in React, this represents what we want the device
/// to be, not what it currently is. The transport layer diffs this against
/// the actual device state and syncs necessary changes.
///
/// Based on FTMS v1.0 specification section 4.16.1 - Fitness Machine Control Point.
///
/// Only one control mode can be active at a time. Setting a new mode
/// automatically clears the previous one.
class FtmsDeviceState {
  /// Creates a device state with a specific control mode.
  ///
  /// Only one of the target parameters should be set at a time:
  /// - [targetPower] - ERG mode (Op Code 0x05)
  /// - [targetResistanceLevel] - Resistance mode (Op Code 0x04)
  /// - [targetSpeed] - Speed mode (Op Code 0x02)
  /// - [targetInclination] - Inclination/grade mode (Op Code 0x03)
  /// - [targetHeartRate] - HR-based mode (Op Code 0x06)
  /// - [targetCadence] - Cadence-based mode (Op Code 0x14)
  /// - [simulationParams] - Simulation mode with wind/grade (Op Code 0x11)
  const FtmsDeviceState({
    this.targetPower,
    this.targetResistanceLevel,
    this.targetSpeed,
    this.targetInclination,
    this.targetHeartRate,
    this.targetCadence,
    this.simulationParams,
  });

  /// Target power in watts for ERG mode (Op Code 0x05).
  /// Range: typically 0-4000W depending on trainer.
  final int? targetPower;

  /// Target resistance level (Op Code 0x04).
  /// Range: device-specific, typically 0-100.
  final int? targetResistanceLevel;

  /// Target speed in km/h (Op Code 0x02).
  /// Resolution: 0.01 km/h.
  final double? targetSpeed;

  /// Target inclination percentage (Op Code 0x03).
  /// Range: typically -100% to +100% (negative = downhill).
  /// Resolution: 0.1%.
  final double? targetInclination;

  /// Target heart rate in BPM (Op Code 0x06).
  /// Range: typically 0-220 BPM.
  final int? targetHeartRate;

  /// Target cadence in RPM (Op Code 0x14).
  /// Resolution: 0.5 RPM.
  final double? targetCadence;

  /// Indoor bike simulation parameters (Op Code 0x11).
  /// Combines wind speed, grade, rolling resistance, and wind resistance.
  final SimulationParameters? simulationParams;

  /// Creates an idle state (device not under control).
  const FtmsDeviceState.idle()
      : targetPower = null,
        targetResistanceLevel = null,
        targetSpeed = null,
        targetInclination = null,
        targetHeartRate = null,
        targetCadence = null,
        simulationParams = null;

  /// Returns true if any control mode is active.
  bool get hasActiveControl =>
      targetPower != null ||
      targetResistanceLevel != null ||
      targetSpeed != null ||
      targetInclination != null ||
      targetHeartRate != null ||
      targetCadence != null ||
      simulationParams != null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FtmsDeviceState &&
          runtimeType == other.runtimeType &&
          targetPower == other.targetPower &&
          targetResistanceLevel == other.targetResistanceLevel &&
          targetSpeed == other.targetSpeed &&
          targetInclination == other.targetInclination &&
          targetHeartRate == other.targetHeartRate &&
          targetCadence == other.targetCadence &&
          simulationParams == other.simulationParams;

  @override
  int get hashCode =>
      targetPower.hashCode ^
      targetResistanceLevel.hashCode ^
      targetSpeed.hashCode ^
      targetInclination.hashCode ^
      targetHeartRate.hashCode ^
      targetCadence.hashCode ^
      simulationParams.hashCode;

  @override
  String toString() => 'FtmsDeviceState('
      'power: $targetPower, '
      'resistance: $targetResistanceLevel, '
      'speed: $targetSpeed, '
      'incline: $targetInclination, '
      'hr: $targetHeartRate, '
      'cadence: $targetCadence, '
      'simulation: $simulationParams'
      ')';
}

/// Indoor bike simulation parameters (FTMS Op Code 0x11).
///
/// Used for realistic outdoor ride simulation, combining environmental
/// factors like wind, grade, and rolling resistance.
class SimulationParameters {
  /// Creates simulation parameters.
  ///
  /// [windSpeed] - Wind speed in m/s (positive = headwind, negative = tailwind)
  /// [grade] - Grade percentage (positive = uphill, negative = downhill)
  /// [crr] - Coefficient of rolling resistance (default: 0.004 for asphalt)
  /// [cw] - Wind resistance coefficient (default: 0.51 for upright position)
  const SimulationParameters({
    required this.windSpeed,
    required this.grade,
    this.crr = 0.004,
    this.cw = 0.51,
  });

  /// Wind speed in meters/second.
  /// Range: -127.99 to +127.99 m/s
  /// Resolution: 0.001 m/s
  /// Positive = headwind, Negative = tailwind
  final double windSpeed;

  /// Grade (slope) in percentage.
  /// Range: -200.00% to +200.00%
  /// Resolution: 0.01%
  /// Positive = uphill, Negative = downhill
  final double grade;

  /// Coefficient of Rolling Resistance (Crr).
  /// Range: 0 to 1
  /// Resolution: 0.0001
  /// Examples: 0.004 (asphalt), 0.008 (rough road), 0.012 (gravel)
  final double crr;

  /// Wind Resistance Coefficient (Cw).
  /// Range: 0 to 1
  /// Resolution: 0.01
  /// Examples: 0.51 (upright), 0.38 (hoods), 0.32 (drops), 0.25 (aero)
  final double cw;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SimulationParameters &&
          runtimeType == other.runtimeType &&
          windSpeed == other.windSpeed &&
          grade == other.grade &&
          crr == other.crr &&
          cw == other.cw;

  @override
  int get hashCode => windSpeed.hashCode ^ grade.hashCode ^ crr.hashCode ^ cw.hashCode;

  @override
  String toString() => 'SimulationParameters(wind: ${windSpeed}m/s, grade: $grade%, crr: $crr, cw: $cw)';
}

/// Bluetooth transport layer for FTMS (Fitness Machine Service) protocol.
///
/// Handles low-level BLE communication with FTMS-compliant trainers and bikes.
/// Exposes data streams for power and cadence, and provides methods for
/// connection management and ERG mode control.
///
/// This is a pure transport layer - no domain logic, just BLE communication
/// and FTMS protocol parsing. Used by [FtmsDevice] for protocol implementation.
class FtmsBleTransport {
  /// Creates an FTMS BLE transport for the specified device.
  FtmsBleTransport({required this.deviceId});

  /// BLE device ID to connect to.
  final String deviceId;

  // FTMS service and characteristic UUIDs
  static final _ftmsServiceUuid = fbp.Guid('00001826-0000-1000-8000-00805f9b34fb');
  static final _indoorBikeDataUuid = fbp.Guid('00002AD2-0000-1000-8000-00805f9b34fb');
  static final _controlPointUuid = fbp.Guid('00002AD9-0000-1000-8000-00805f9b34fb');

  // BLE device reference
  fbp.BluetoothDevice? _device;

  static const _bluetoothDebounce = Duration(milliseconds: 250);

  // Connection state
  StreamSubscription<fbp.BluetoothConnectionState>? _connectionSubscription;
  StreamSubscription<List<int>>? _indoorBikeDataSubscription;
  StreamSubscription<List<int>>? _controlPointSubscription;
  Completer<void>? _connectionCompleter;
  fbp.BluetoothCharacteristic? _indoorBikeDataChar;
  fbp.BluetoothCharacteristic? _controlPointChar;

  // Device state synchronization
  FtmsDeviceState _desiredState = const FtmsDeviceState.idle(); // What we want the device to be
  FtmsDeviceState _actualState = const FtmsDeviceState.idle(); // What the device actually is (last confirmed)
  bool _hasControl = false; // Whether we have control of the device
  bool _isSyncing = false; // Whether a sync operation is in progress
  Timer? _syncDebounceTimer; // Debounce timer for sync requests
  DateTime _lastSyncTime = DateTime.now();

  // Data stream controllers
  final _powerController = StreamController<PowerData>.broadcast();
  final _cadenceController = StreamController<CadenceData>.broadcast();
  final _speedController = StreamController<SpeedData>.broadcast();
  final _connectionStateController = StreamController<ConnectionState>.broadcast();

  /// Stream of power data from the trainer.
  Stream<PowerData> get powerStream => _powerController.stream;

  /// Stream of cadence data from the trainer.
  Stream<CadenceData> get cadenceStream => _cadenceController.stream;

  /// Stream of speed data from the trainer.
  Stream<SpeedData> get speedStream => _speedController.stream;

  /// Stream of connection state changes.
  Stream<ConnectionState> get connectionStateStream => _connectionStateController.stream;

  /// Whether the transport is currently connected.
  bool get isConnected => _connectionSubscription != null;

  /// Connects to the FTMS device with cancellable operation support.
  ///
  /// Returns a [CancelableOperation] that can be cancelled during connection.
  /// Throws [TimeoutException] if connection takes longer than 15 seconds.
  CancelableOperation<void> connectCancelable() {
    return CancelableOperation.fromFuture(
      connect(),
      onCancel: () {
        developer.log('[FtmsBleTransport] Connection cancelled, cleaning up');
        _connectionSubscription?.cancel();
        _connectionCompleter?.completeError(Exception('Connection cancelled'));
        _handleDisconnection();
      },
    );
  }

  /// Connects to the FTMS device.
  ///
  /// Establishes BLE connection and subscribes to FTMS characteristics.
  /// Throws [TimeoutException] if connection takes longer than 15 seconds.
  Future<void> connect() async {
    try {
      developer.log('[FtmsBleTransport] Connecting to device: $deviceId');
      _connectionStateController.add(ConnectionState.connecting);

      // Create a completer to track connection completion
      final completer = Completer<void>();
      _connectionCompleter = completer;

      // Get the device from system devices or connected devices
      final devices = fbp.FlutterBluePlus.connectedDevices;
      _device = devices.firstWhere(
        (d) => d.remoteId.str == deviceId,
        orElse: () => fbp.BluetoothDevice.fromId(deviceId),
      );

      // Track if we've ever connected to distinguish initial state from disconnection
      var hasConnected = false;

      // Listen to connection state changes
      _connectionSubscription = _device!.connectionState.listen(
        (state) async {
          developer.log('[FtmsBleTransport] Connection state: $state');

          if (state == fbp.BluetoothConnectionState.connected) {
            hasConnected = true;
            _connectionStateController.add(ConnectionState.connected);
            try {
              await _setupCharacteristics();
              // Connection successful, complete the future
              if (!completer.isCompleted) {
                developer.log('[FtmsBleTransport] Connection completed successfully');
                completer.complete();
              }
            } catch (e, stackTrace) {
              print('[FtmsBleTransport] Error setting up characteristics: $e');
              print(stackTrace);
              if (!completer.isCompleted) {
                completer.completeError(e, stackTrace);
              }
              _handleDisconnection();
            }
          } else if (state == fbp.BluetoothConnectionState.disconnected) {
            // Only handle disconnection if we had successfully connected before
            // This prevents initial "disconnected" state from canceling the connection
            if (hasConnected) {
              if (!completer.isCompleted) {
                completer.completeError('Device disconnected unexpectedly');
              }
              _handleDisconnection();
            }
          }
        },
        onError: (Object e, StackTrace stackTrace) {
          print('[FtmsBleTransport] Connection error: $e');
          print(stackTrace);
          if (!completer.isCompleted) {
            completer.completeError(e, stackTrace);
          }
          _handleDisconnection();
        },
      );

      // Connect to the device
      await _device!.connect(timeout: const Duration(seconds: 10));

      // Wait for connection to complete with timeout
      await completer.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw TimeoutException('Connection timed out after 15 seconds');
        },
      );
    } catch (e, stackTrace) {
      print('[FtmsBleTransport] Failed to connect: $e');
      print(stackTrace);
      _handleDisconnection();
      rethrow;
    }
  }

  Future<void> _setupCharacteristics() async {
    try {
      developer.log('[FtmsBleTransport] Setting up characteristics');

      // Discover services
      final services = await _device!.discoverServices();
      developer.log('[FtmsBleTransport] Discovered ${services.length} services');

      // Find FTMS service
      final ftmsService = services.firstWhere(
        (s) => s.uuid == _ftmsServiceUuid,
        orElse: () => throw Exception('FTMS service not found'),
      );

      developer.log('[FtmsBleTransport] Found FTMS service with ${ftmsService.characteristics.length} characteristics');

      // Find indoor bike data characteristic
      _indoorBikeDataChar = ftmsService.characteristics.firstWhere(
        (c) => c.uuid == _indoorBikeDataUuid,
        orElse: () => throw Exception('Indoor bike data characteristic not found'),
      );

      // Find control point characteristic
      _controlPointChar = ftmsService.characteristics.firstWhere(
        (c) => c.uuid == _controlPointUuid,
        orElse: () => throw Exception('Control point characteristic not found'),
      );

      developer.log('[FtmsBleTransport] Found required characteristics');

      // Subscribe to indoor bike data
      await _indoorBikeDataChar!.setNotifyValue(true);
      _indoorBikeDataSubscription = _indoorBikeDataChar!.lastValueStream.listen(
        (data) {
          _parseIndoorBikeData(Uint8List.fromList(data));
        },
        onError: (e, stackTrace) {
          print('[FtmsBleTransport] Indoor bike data error: $e');
          print(stackTrace);
        },
      );

      // Subscribe to control point responses
      await _controlPointChar!.setNotifyValue(true);
      _controlPointSubscription = _controlPointChar!.lastValueStream.listen(
        (data) {
          _handleControlPointResponse(Uint8List.fromList(data));
        },
        onError: (e, stackTrace) {
          print('[FtmsBleTransport] Control point error: $e');
          print(stackTrace);
        },
      );

      developer.log('[FtmsBleTransport] Characteristics setup complete');
    } catch (e, stackTrace) {
      print('[FtmsBleTransport] Failed to setup characteristics: $e');
      print(stackTrace);
      rethrow;
    }
  }

  void _parseIndoorBikeData(Uint8List data) {
    if (data.length < 2) return;

    final buffer = data.buffer.asByteData();
    int offset = 0;

    // Parse flags (2 bytes, little endian)
    final flags = buffer.getUint16(offset, Endian.little);
    offset += 2;

    // FTMS Indoor Bike Data characteristic flags
    // Bit 0: More Data (0=speed present, 1=speed not present)
    // Bit 1: Average Speed Present
    // Bit 2: Instantaneous Cadence Present
    // Bit 3: Average Cadence Present
    // Bit 4: Total Distance Present
    // Bit 5: Resistance Level Present
    // Bit 6: Instantaneous Power Present
    // Bit 7: Average Power Present
    // Bit 8: Expended Energy Present
    // Bit 9: Heart Rate Present
    // Bit 10: Metabolic Equivalent Present
    // Bit 11: Elapsed Time Present
    // Bit 12: Remaining Time Present

    final speedPresent = (flags & 0x01) == 0;
    final cadencePresent = (flags & 0x04) != 0;
    final powerPresent = (flags & 0x40) != 0;

    try {
      final timestamp = DateTime.now();
      int? power;
      int? cadence;
      double? speed;

      // Parse speed if present
      if (speedPresent && offset + 2 <= data.length) {
        final rawSpeed = buffer.getUint16(offset, Endian.little);
        speed = rawSpeed * 0.01; // Resolution: 0.01 km/h
        offset += 2;
      }

      // Skip average speed if present
      if ((flags & 0x02) != 0 && offset + 2 <= data.length) {
        offset += 2;
      }

      // Parse cadence if present
      if (cadencePresent && offset + 2 <= data.length) {
        final rawCadence = buffer.getUint16(offset, Endian.little);
        cadence = (rawCadence / 2).round(); // Resolution: 0.5 rpm
        offset += 2;
      }

      // Skip average cadence if present
      if ((flags & 0x08) != 0 && offset + 2 <= data.length) {
        offset += 2;
      }

      // Skip distance if present (3 bytes)
      if ((flags & 0x10) != 0 && offset + 3 <= data.length) {
        offset += 3;
      }

      // Skip resistance if present
      if ((flags & 0x20) != 0 && offset + 2 <= data.length) {
        offset += 2;
      }

      // Parse power if present
      if (powerPresent && offset + 2 <= data.length) {
        power = buffer.getInt16(offset, Endian.little);
        offset += 2;
      }

      // Skip average power if present
      if ((flags & 0x80) != 0 && offset + 2 <= data.length) {
        offset += 2;
      }

      // Emit data to streams
      if (power != null) {
        _powerController.add(PowerData(watts: power, timestamp: timestamp));
      }
      if (cadence != null) {
        _cadenceController.add(CadenceData(rpm: cadence, timestamp: timestamp));
      }
      if (speed != null) {
        _speedController.add(SpeedData(kmh: speed, timestamp: timestamp));
      }
    } catch (e, stackTrace) {
      print('[FtmsBleTransport] Error parsing indoor bike data: $e');
      print(stackTrace);
    }
  }

  void _handleControlPointResponse(Uint8List data) {
    if (data.isEmpty) return;

    final responseCode = data[0];

    // 0x80 indicates a general response from the FTMS
    if (responseCode == 0x80) {
      if (data.length < 3) return;

      final requestOpCode = data[1];
      final resultCode = data[2];

      // FTMS Result Codes:
      // 0x01 - SUCCESS
      // 0x02 - NOT_SUPPORTED
      // 0x03 - INVALID_PARAMETER
      // 0x04 - OPERATION_FAILED
      // 0x05 - CONTROL_NOT_PERMITTED

      if (resultCode == 0x01) {
        developer.log('[FtmsBleTransport] Command 0x${requestOpCode.toRadixString(16)} succeeded');

        // Track actual device state based on successful commands
        if (requestOpCode == 0x00) {
          _hasControl = true;
        } else if (requestOpCode == 0x05) {
          // Set Target Power success - update actual state
          _actualState = FtmsDeviceState(targetPower: _desiredState.targetPower);
          developer.log('[FtmsBleTransport] Power target ${_actualState.targetPower}W applied successfully');
        } else if (requestOpCode == 0x04) {
          // Set Target Resistance Level success
          _actualState = FtmsDeviceState(targetResistanceLevel: _desiredState.targetResistanceLevel);
          developer.log('[FtmsBleTransport] Resistance level ${_actualState.targetResistanceLevel} applied');
        } else if (requestOpCode == 0x11) {
          // Indoor Bike Simulation success
          _actualState = FtmsDeviceState(simulationParams: _desiredState.simulationParams);
          developer.log('[FtmsBleTransport] Simulation parameters applied: ${_actualState.simulationParams}');
        }
        // Add more op codes as needed
      } else {
        print(
          '[FtmsBleTransport] FTMS operation 0x${requestOpCode.toRadixString(16)} failed with result: 0x${resultCode.toRadixString(16)}',
        );

        // Lost control or failed to apply state
        if (requestOpCode == 0x00) {
          _hasControl = false;
        }
      }
    }
  }

  /// Internal method to synchronize actual device state with desired state.
  ///
  /// Compares current device state with [_desiredState] and sends only the
  /// necessary BLE commands to reconcile the difference.
  ///
  /// Implements FTMS Control Point operations (section 4.16.1 of spec).
  Future<void> _syncState() async {
    if (!isConnected || _isSyncing) return;

    // Rate limit sync operations
    final timeSinceLastSync = DateTime.now().difference(_lastSyncTime);
    if (timeSinceLastSync < _bluetoothDebounce) {
      return;
    }

    _isSyncing = true;
    _lastSyncTime = DateTime.now();

    try {
      // Step 1: Request control if we don't have it and need it
      final needsControl = _desiredState.hasActiveControl;
      if (needsControl && !_hasControl) {
        developer.log('[FtmsBleTransport] 📤 Sending: Request Control (0x00)');
        await _controlPointChar!.write(Uint8List.fromList([0x00]));
        await Future.delayed(const Duration(milliseconds: 100)); // Wait for response
      }

      if (!_hasControl) {
        return; // Can't set any targets without control
      }

      // Step 2: Determine if state changed and send appropriate command
      // Only one mode can be active at a time, so we check each in priority order

      if (_desiredState != _actualState) {
        // Target Power mode (Op Code 0x05) - ERG mode
        if (_desiredState.targetPower != null) {
          final power = _desiredState.targetPower!;
          developer.log('[FtmsBleTransport] 📤 Sending: Set Target Power ${power}W (0x05)');
          await _controlPointChar!.write(Uint8List.fromList([
            0x05,
            power & 0xFF, // Low byte
            (power >> 8) & 0xFF, // High byte
          ]));
        }
        // Target Resistance Level (Op Code 0x04)
        else if (_desiredState.targetResistanceLevel != null) {
          final level = _desiredState.targetResistanceLevel!;
          developer.log('[FtmsBleTransport] 📤 Sending: Set Target Resistance Level $level (0x04)');
          await _controlPointChar!.write(Uint8List.fromList([
            0x04,
            level & 0xFF, // Low byte
            (level >> 8) & 0xFF, // High byte (signed int16, but resistance is positive)
          ]));
        }
        // Indoor Bike Simulation (Op Code 0x11)
        else if (_desiredState.simulationParams != null) {
          final sim = _desiredState.simulationParams!;
          developer.log(
            '[FtmsBleTransport] 📤 Sending: Set Indoor Bike Simulation (0x11) - Grade: ${sim.grade}%, Wind: ${sim.windSpeed}m/s',
          );

          // FTMS spec: wind speed (sint16, 0.001 m/s), grade (sint16, 0.01%), crr (uint8, 0.0001), cw (uint8, 0.01)
          final windSpeedRaw = (sim.windSpeed * 1000).round().clamp(-32768, 32767);
          final gradeRaw = (sim.grade * 100).round().clamp(-32768, 32767);
          final crrRaw = (sim.crr * 10000).round().clamp(0, 255);
          final cwRaw = (sim.cw * 100).round().clamp(0, 255);

          await _controlPointChar!.write(Uint8List.fromList([
            0x11, // Op Code
            windSpeedRaw & 0xFF, // Wind speed low byte
            (windSpeedRaw >> 8) & 0xFF, // Wind speed high byte
            gradeRaw & 0xFF, // Grade low byte
            (gradeRaw >> 8) & 0xFF, // Grade high byte
            crrRaw, // Coefficient of rolling resistance
            cwRaw, // Wind resistance coefficient
          ]));
        }
        // Add more modes here as needed (speed, inclination, HR, cadence, etc.)
        else {
          // Idle state - no command needed (or could send Reset if desired)
          developer.log('[FtmsBleTransport] Desired state is idle, no sync needed');
        }
      }
    } catch (e, stackTrace) {
      print('[FtmsBleTransport] Error during state sync: $e');
      print(stackTrace);
      _hasControl = false; // Assume we lost control on error
    } finally {
      // Always reset syncing flag so subsequent syncs can proceed
      _isSyncing = false;
    }
  }

  /// Synchronizes the device to match the desired state.
  ///
  /// This is the only public method for controlling device state. Pass a
  /// [FtmsDeviceState] representing what you want the device to be, and the
  /// transport will figure out what commands to send.
  ///
  /// The sync is debounced to avoid overwhelming the device when called rapidly.
  /// Power values are automatically clamped to 25-1500W for safety.
  ///
  /// Example:
  /// ```dart
  /// // Set to 200W ERG mode
  /// transport.syncState(FtmsDeviceState(targetPower: 200));
  ///
  /// // Set to 250W
  /// transport.syncState(FtmsDeviceState(targetPower: 250));
  ///
  /// // Release control
  /// transport.syncState(FtmsDeviceState.idle());
  /// ```
  void syncState(FtmsDeviceState state) {
    // Clamp power to safe range
    final clampedState = state.targetPower != null
        ? FtmsDeviceState(targetPower: state.targetPower!.clamp(25, 1500))
        : state;

    if (clampedState.targetPower != state.targetPower) {
      developer.log(
        '[FtmsBleTransport] Power clamped from ${state.targetPower}W to ${clampedState.targetPower}W',
      );
    }

    // Update desired state
    final stateChanged = _desiredState != clampedState;
    _desiredState = clampedState;

    if (stateChanged) {
      developer.log('[FtmsBleTransport] Desired state updated: $clampedState');
    }

    // Cancel any pending sync and schedule a new one (debouncing)
    _syncDebounceTimer?.cancel();
    _syncDebounceTimer = Timer(const Duration(milliseconds: 100), () {
      _syncState();
    });
  }

  void _handleDisconnection() {
    developer.log('[FtmsBleTransport] Device disconnected');
    _connectionSubscription?.cancel();
    _indoorBikeDataSubscription?.cancel();
    _controlPointSubscription?.cancel();
    _syncDebounceTimer?.cancel();
    _connectionSubscription = null;
    _indoorBikeDataSubscription = null;
    _controlPointSubscription = null;
    _syncDebounceTimer = null;
    _desiredState = const FtmsDeviceState.idle();
    _actualState = const FtmsDeviceState.idle();
    _hasControl = false;
    _isSyncing = false;
    _connectionCompleter = null;

    // Only add event if stream controller is not closed
    if (!_connectionStateController.isClosed) {
      _connectionStateController.add(ConnectionState.disconnected);
    }
  }

  /// Disconnects from the FTMS device.
  ///
  /// Cancels all subscriptions and resets device state.
  Future<void> disconnect() async {
    try {
      if (_device != null) {
        await _device!.disconnect();
      }
    } finally {
      _handleDisconnection();
    }
  }

  /// Disposes of all resources.
  ///
  /// Must be called when the transport is no longer needed.
  void dispose() {
    _connectionSubscription?.cancel();
    _indoorBikeDataSubscription?.cancel();
    _controlPointSubscription?.cancel();
    _syncDebounceTimer?.cancel();
    _powerController.close();
    _cadenceController.close();
    _speedController.close();
    _connectionStateController.close();
  }
}

/// Connection state for BLE transport.
enum ConnectionState {
  /// Device is disconnected.
  disconnected,

  /// Device is connecting.
  connecting,

  /// Device is connected and ready.
  connected,
}
