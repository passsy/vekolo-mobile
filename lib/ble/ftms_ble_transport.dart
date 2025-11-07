import 'dart:async';
import 'package:vekolo/app/logger.dart';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;
import 'package:state_beacon/state_beacon.dart';
import 'package:vekolo/ble/ble_scanner.dart';
import 'package:vekolo/ble/ble_transport.dart';
import 'package:vekolo/ble/transport_capabilities.dart';
import 'package:vekolo/ble/transport_registry.dart';
import 'package:vekolo/domain/models/device_info.dart';
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
  String toString() =>
      'FtmsDeviceState('
      'power: $targetPower, '
      'resistance: $targetResistanceLevel, '
      'speed: $targetSpeed, '
      'incline: $targetInclination, '
      'hr: $targetHeartRate, '
      'cadence: $targetCadence, '
      'simulation: $simulationParams'
      ')';
}

/// Bluetooth transport layer for FTMS (Fitness Machine Service) protocol.
///
/// Handles low-level BLE communication with FTMS-compliant trainers and bikes.
/// Provides power, cadence, speed data streams and ERG mode control.
///
/// This is a pure transport layer - no domain logic, just BLE communication
/// and FTMS protocol parsing.
class FtmsBleTransport
    implements BleTransport, PowerSource, CadenceSource, SpeedSource, ErgModeControl, SimulationModeControl {
  /// Creates an FTMS BLE transport for the specified device.
  FtmsBleTransport({required this.deviceId});

  /// BLE device ID to connect to.
  final String deviceId;

  // FTMS service and characteristic UUIDs
  static final _ftmsServiceUuid = fbp.Guid('00001826-0000-1000-8000-00805f9b34fb');
  static final _indoorBikeDataUuid = fbp.Guid('00002AD2-0000-1000-8000-00805f9b34fb');
  static final _controlPointUuid = fbp.Guid('00002AD9-0000-1000-8000-00805f9b34fb');

  static const _bluetoothDebounce = Duration(milliseconds: 250);

  // Connection state
  StreamSubscription<fbp.BluetoothConnectionState>? _connectionSubscription;
  StreamSubscription<List<int>>? _indoorBikeDataSubscription;
  StreamSubscription<List<int>>? _controlPointSubscription;
  List<fbp.BluetoothService>? _services;
  ConnectionError? _lastAttachError;

  // Device state synchronization
  FtmsDeviceState _desiredState = const FtmsDeviceState.idle(); // What we want the device to be
  FtmsDeviceState _actualState = const FtmsDeviceState.idle(); // What the device actually is (last confirmed)
  bool _hasControl = false; // Whether we have control of the device
  bool _isSyncing = false; // Whether a sync operation is in progress
  Timer? _syncDebounceTimer; // Debounce timer for sync requests
  DateTime _lastSyncTime = clock.now();

  // Data beacons
  late final WritableBeacon<PowerData?> _powerBeacon = Beacon.writable(null);
  late final WritableBeacon<CadenceData?> _cadenceBeacon = Beacon.writable(null);
  late final WritableBeacon<SpeedData?> _speedBeacon = Beacon.writable(null);
  late final WritableBeacon<TransportState> _stateBeacon = Beacon.writable(TransportState.detached);

  // ============================================================================
  // BleTransport Interface Implementation
  // ============================================================================

  @override
  String get transportId => 'ftms';

  @override
  bool canSupport(DiscoveredDevice device) {
    // FTMS devices advertise the FTMS service UUID (0x1826)
    return device.serviceUuids.contains(_ftmsServiceUuid);
  }

  @override
  Future<bool> verifyCompatibility({
    required fbp.BluetoothDevice device,
    required List<fbp.BluetoothService> services,
  }) async {
    // FTMS has standard implementation, no deep check needed
    // All FTMS devices that advertise the service should work
    return true;
  }

  @override
  ReadableBeacon<TransportState> get state => _stateBeacon;

  @override
  ConnectionError? get lastAttachError => _lastAttachError;

  @override
  bool get isAttached => _stateBeacon.value == TransportState.attached;

  // ============================================================================
  // Capability Interface Implementations
  // ============================================================================

  // PowerSource
  @override
  ReadableBeacon<PowerData?> get powerStream => _powerBeacon;

  // CadenceSource
  @override
  ReadableBeacon<CadenceData?> get cadenceStream => _cadenceBeacon;

  // SpeedSource
  @override
  ReadableBeacon<SpeedData?> get speedStream => _speedBeacon;

  // ErgModeControl - setTargetPower is implemented below
  // SimulationModeControl - setSimulationParameters is implemented below

  /// Attaches to the FTMS service on an already-connected device.
  ///
  /// The [device] must already be connected and [services] must be discovered
  /// by BleDevice before calling this method.
  @override
  Future<void> attach({required fbp.BluetoothDevice device, required List<fbp.BluetoothService> services}) async {
    try {
      talker.info('[FtmsBleTransport] Attaching to FTMS service on device: $deviceId');
      _stateBeacon.value = TransportState.attaching;
      _lastAttachError = null; // Clear any previous error

      _services = services;
      await _setupCharacteristics(services: services);
      _stateBeacon.value = TransportState.attached;
      talker.info('[FtmsBleTransport] FTMS service attached successfully');
    } catch (e, stackTrace) {
      talker.error('[FtmsBleTransport] Failed to attach to FTMS service', e, stackTrace);
      _lastAttachError = ConnectionError(
        message: 'Failed to attach to FTMS service: $e',
        timestamp: clock.now(),
        error: e,
        stackTrace: stackTrace,
      );
      _handleDisconnection();
      rethrow;
    }
  }

  Future<void> _setupCharacteristics({required List<fbp.BluetoothService> services}) async {
    try {
      // Find FTMS service
      final ftmsService = services.firstWhere(
        (s) => s.uuid == _ftmsServiceUuid,
        orElse: () => throw Exception('FTMS service not found'),
      );

      // Find indoor bike data characteristic (optional)
      final indoorBikeDataChars = ftmsService.characteristics.where((c) => c.uuid == _indoorBikeDataUuid);
      final indoorBikeDataChar = indoorBikeDataChars.isNotEmpty ? indoorBikeDataChars.first : null;

      if (indoorBikeDataChar == null) {
        talker.info('[FtmsBleTransport] Indoor bike data characteristic not found - data reading will be unavailable');
      }

      // Find control point characteristic (optional)
      final controlPointChars = ftmsService.characteristics.where((c) => c.uuid == _controlPointUuid);
      final controlPointChar = controlPointChars.isNotEmpty ? controlPointChars.first : null;

      if (controlPointChar == null) {
        talker.info('[FtmsBleTransport] Control point characteristic not found - device control will be unavailable');
      }

      // Verify at least one characteristic exists
      if (indoorBikeDataChar == null && controlPointChar == null) {
        throw Exception(
          'FTMS service found but no required characteristics available. '
          'Expected at least one of: indoor bike data (${_indoorBikeDataUuid}) or control point (${_controlPointUuid})',
        );
      }

      // Subscribe to indoor bike data if available
      if (indoorBikeDataChar != null) {
        await indoorBikeDataChar.setNotifyValue(true);
        _indoorBikeDataSubscription = indoorBikeDataChar.lastValueStream.listen(
          (data) {
            _parseIndoorBikeData(Uint8List.fromList(data));
          },
          onError: (e, stackTrace) {
            talker.info('[FtmsBleTransport] Indoor bike data error: $e', e, stackTrace as StackTrace?);
          },
        );
      }

      // Subscribe to control point responses if available
      if (controlPointChar != null) {
        await controlPointChar.setNotifyValue(true);
        _controlPointSubscription = controlPointChar.lastValueStream.listen(
          (data) {
            _handleControlPointResponse(Uint8List.fromList(data));
          },
          onError: (e, stackTrace) {
            talker.info('[FtmsBleTransport] Control point error: $e', e, stackTrace as StackTrace?);
          },
        );
      }
    } catch (e, stackTrace) {
      talker.info('[FtmsBleTransport] Failed to setup characteristics: $e', e, stackTrace);
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
      final timestamp = clock.now();
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

      // Update beacons with parsed data
      if (power != null) {
        _powerBeacon.value = PowerData(watts: power, timestamp: timestamp);
      }
      if (cadence != null) {
        _cadenceBeacon.value = CadenceData(rpm: cadence, timestamp: timestamp);
      }
      if (speed != null) {
        _speedBeacon.value = SpeedData(kmh: speed, timestamp: timestamp);
      }
    } catch (e, stackTrace) {
      talker.error('[FtmsBleTransport] Error parsing indoor bike data', e, stackTrace);
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
        // Track actual device state based on successful commands
        if (requestOpCode == 0x00) {
          _hasControl = true;
        } else if (requestOpCode == 0x05) {
          // Set Target Power success - update actual state
          _actualState = FtmsDeviceState(targetPower: _desiredState.targetPower);
        } else if (requestOpCode == 0x04) {
          // Set Target Resistance Level success
          _actualState = FtmsDeviceState(targetResistanceLevel: _desiredState.targetResistanceLevel);
        } else if (requestOpCode == 0x11) {
          // Indoor Bike Simulation success
          _actualState = FtmsDeviceState(simulationParams: _desiredState.simulationParams);
        }
        // Add more op codes as needed
      } else {
        talker.warning(
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
    if (!isAttached || _isSyncing) return;

    // Rate limit sync operations
    final timeSinceLastSync = clock.now().difference(_lastSyncTime);
    if (timeSinceLastSync < _bluetoothDebounce) {
      return;
    }

    _isSyncing = true;
    _lastSyncTime = clock.now();

    // Find control point characteristic from stored services
    final controlPointChar = _getControlPointCharacteristic();
    if (controlPointChar == null) {
      talker.info('[FtmsBleTransport] Cannot sync device state - control point characteristic not available');
      return;
    }

    try {
      // Step 1: Request control if we don't have it and need it
      final needsControl = _desiredState.hasActiveControl;
      if (needsControl && !_hasControl) {
        await controlPointChar.write(Uint8List.fromList([0x00]));
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
          await controlPointChar.write(
            Uint8List.fromList([
              0x05,
              power & 0xFF, // Low byte
              (power >> 8) & 0xFF, // High byte
            ]),
          );
        }
        // Target Resistance Level (Op Code 0x04)
        else if (_desiredState.targetResistanceLevel != null) {
          final level = _desiredState.targetResistanceLevel!;
          await controlPointChar.write(
            Uint8List.fromList([
              0x04,
              level & 0xFF, // Low byte
              (level >> 8) & 0xFF, // High byte (signed int16, but resistance is positive)
            ]),
          );
        }
        // Indoor Bike Simulation (Op Code 0x11)
        else if (_desiredState.simulationParams != null) {
          final sim = _desiredState.simulationParams!;

          // FTMS spec: wind speed (sint16, 0.001 m/s), grade (sint16, 0.01%), crr (uint8, 0.0001), cw (uint8, 0.01)
          final windSpeedRaw = (sim.windSpeed * 1000).round().clamp(-32768, 32767);
          final gradeRaw = (sim.grade * 100).round().clamp(-32768, 32767);
          final crrRaw = (sim.rollingResistance * 10000).round().clamp(0, 255);
          final cwRaw = (sim.windResistanceCoefficient * 100).round().clamp(0, 255);

          await controlPointChar.write(
            Uint8List.fromList([
              0x11, // Op Code
              windSpeedRaw & 0xFF, // Wind speed low byte
              (windSpeedRaw >> 8) & 0xFF, // Wind speed high byte
              gradeRaw & 0xFF, // Grade low byte
              (gradeRaw >> 8) & 0xFF, // Grade high byte
              crrRaw, // Coefficient of rolling resistance
              cwRaw, // Wind resistance coefficient
            ]),
          );
        }
        // Add more modes here as needed (speed, inclination, HR, cadence, etc.)
      }
    } catch (e, stackTrace) {
      talker.error('[FtmsBleTransport] Error during state sync', e, stackTrace);
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
      talker.info('[FtmsBleTransport] Power clamped from ${state.targetPower}W to ${clampedState.targetPower}W');
    }

    // Update desired state
    _desiredState = clampedState;

    // Cancel any pending sync and schedule a new one (debouncing)
    _syncDebounceTimer?.cancel();
    _syncDebounceTimer = Timer(const Duration(milliseconds: 100), () {
      _syncState();
    });
  }

  void _handleDisconnection() {
    talker.info('[FtmsBleTransport] Device disconnected');
    _connectionSubscription?.cancel();
    _indoorBikeDataSubscription?.cancel();
    _controlPointSubscription?.cancel();
    _syncDebounceTimer?.cancel();
    _connectionSubscription = null;
    _indoorBikeDataSubscription = null;
    _controlPointSubscription = null;
    _syncDebounceTimer = null;
    _services = null;
    _desiredState = const FtmsDeviceState.idle();
    _actualState = const FtmsDeviceState.idle();
    _hasControl = false;
    _isSyncing = false;

    // Update transport state beacon
    _stateBeacon.value = TransportState.detached;
  }

  /// Gets the control point characteristic from stored services.
  fbp.BluetoothCharacteristic? _getControlPointCharacteristic() {
    if (_services == null) {
      return null;
    }

    final ftmsServices = _services!.where((s) => s.uuid == _ftmsServiceUuid);
    if (ftmsServices.isEmpty) {
      return null;
    }
    final ftmsService = ftmsServices.first;

    final controlPointChars = ftmsService.characteristics.where((c) => c.uuid == _controlPointUuid);
    return controlPointChars.isNotEmpty ? controlPointChars.first : null;
  }

  /// Detaches from the FTMS service.
  ///
  /// Cancels all subscriptions and resets transport state.
  /// Does not disconnect the physical device.
  @override
  Future<void> detach() async {
    _handleDisconnection();
  }

  /// Sets the target power for ERG mode.
  ///
  /// The transport handles continuous refresh internally as needed.
  @override
  Future<void> setTargetPower(int watts) async {
    syncState(FtmsDeviceState(targetPower: watts));
  }

  /// Sets simulation parameters for realistic road feel.
  ///
  /// The transport handles continuous refresh internally as needed.
  @override
  Future<void> setSimulationParameters(SimulationParameters parameters) async {
    syncState(FtmsDeviceState(simulationParams: parameters));
  }

  /// Disposes of all resources.
  ///
  /// Must be called when the transport is no longer needed.
  @override
  Future<void> dispose() async {
    await detach();
    _connectionSubscription?.cancel();
    _indoorBikeDataSubscription?.cancel();
    _controlPointSubscription?.cancel();
    _syncDebounceTimer?.cancel();
    _powerBeacon.dispose();
    _cadenceBeacon.dispose();
    _speedBeacon.dispose();
    _stateBeacon.dispose();
  }
}

/// Registration for FTMS transport.
///
/// Use this to register the FTMS transport with [TransportRegistry]:
/// ```dart
/// registry.register(ftmsTransportRegistration);
/// ```
final ftmsTransportRegistration = TransportRegistration(name: 'FTMS', factory: _createFtmsTransport);

/// Factory function for creating FTMS transport instances.
BleTransport _createFtmsTransport(String deviceId) {
  return FtmsBleTransport(deviceId: deviceId);
}
