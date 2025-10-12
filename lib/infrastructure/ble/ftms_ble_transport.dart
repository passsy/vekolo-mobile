import 'dart:async';
import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:async/async.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:vekolo/domain/models/fitness_data.dart';

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
  FtmsBleTransport({required this.deviceId, FlutterReactiveBle? ble}) : _ble = ble ?? FlutterReactiveBle();

  final FlutterReactiveBle _ble;

  /// BLE device ID to connect to.
  final String deviceId;

  // FTMS service and characteristic UUIDs
  static final _ftmsServiceUuid = Uuid.parse('00001826-0000-1000-8000-00805f9b34fb');
  static final _indoorBikeDataUuid = Uuid.parse('00002AD2-0000-1000-8000-00805f9b34fb');
  static final _controlPointUuid = Uuid.parse('00002AD9-0000-1000-8000-00805f9b34fb');

  static const _bluetoothTimeout = Duration(milliseconds: 5000);
  static const _bluetoothDebounce = Duration(milliseconds: 250);

  // Connection state
  StreamSubscription<ConnectionStateUpdate>? _connectionSubscription;
  StreamSubscription<List<int>>? _indoorBikeDataSubscription;
  StreamSubscription<List<int>>? _controlPointSubscription;
  Completer<void>? _connectionCompleter;

  // Command queue
  final List<Uint8List> _commandQueue = [];
  Uint8List? _sendingCommand;
  DateTime _lastSentCommandTime = DateTime.now();

  // Data stream controllers
  final _powerController = StreamController<PowerData>.broadcast();
  final _cadenceController = StreamController<CadenceData>.broadcast();
  final _connectionStateController = StreamController<ConnectionState>.broadcast();

  /// Stream of power data from the trainer.
  Stream<PowerData> get powerStream => _powerController.stream;

  /// Stream of cadence data from the trainer.
  Stream<CadenceData> get cadenceStream => _cadenceController.stream;

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
      _connectionCompleter = Completer<void>();

      // Listen to connection state changes
      _connectionSubscription = _ble
          .connectToDevice(id: deviceId, connectionTimeout: const Duration(seconds: 10))
          .listen(
            (update) async {
              developer.log('[FtmsBleTransport] Connection state: ${update.connectionState}');

              if (update.connectionState == DeviceConnectionState.connected) {
                _connectionStateController.add(ConnectionState.connected);
                try {
                  await _setupCharacteristics();
                  // Connection successful, complete the future
                  if (!_connectionCompleter!.isCompleted) {
                    developer.log('[FtmsBleTransport] Connection completed successfully');
                    _connectionCompleter!.complete();
                  }
                } catch (e, stackTrace) {
                  print('[FtmsBleTransport] Error setting up characteristics: $e');
                  print(stackTrace);
                  if (!_connectionCompleter!.isCompleted) {
                    _connectionCompleter!.completeError(e, stackTrace);
                  }
                  _handleDisconnection();
                }
              } else if (update.connectionState == DeviceConnectionState.disconnected) {
                if (!_connectionCompleter!.isCompleted) {
                  _connectionCompleter!.completeError('Device disconnected before connection completed');
                }
                _handleDisconnection();
              }
            },
            onError: (Object e, StackTrace stackTrace) {
              print('[FtmsBleTransport] Connection error: $e');
              print(stackTrace);
              if (!_connectionCompleter!.isCompleted) {
                _connectionCompleter!.completeError(e, stackTrace);
              }
              _handleDisconnection();
            },
          );

      // Wait for connection to complete with timeout
      await _connectionCompleter!.future.timeout(
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

      // Subscribe to indoor bike data
      final indoorBikeCharacteristic = QualifiedCharacteristic(
        serviceId: _ftmsServiceUuid,
        characteristicId: _indoorBikeDataUuid,
        deviceId: deviceId,
      );

      _indoorBikeDataSubscription = _ble
          .subscribeToCharacteristic(indoorBikeCharacteristic)
          .listen(
            (data) {
              _parseIndoorBikeData(Uint8List.fromList(data));
            },
            onError: (e, stackTrace) {
              print('[FtmsBleTransport] Indoor bike data error: $e');
              print(stackTrace);
            },
          );

      // Subscribe to control point responses
      final controlPointCharacteristic = QualifiedCharacteristic(
        serviceId: _ftmsServiceUuid,
        characteristicId: _controlPointUuid,
        deviceId: deviceId,
      );

      _controlPointSubscription = _ble
          .subscribeToCharacteristic(controlPointCharacteristic)
          .listen(
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

      // Parse speed if present (currently not used, but required for offset calculation)
      if (speedPresent && offset + 2 <= data.length) {
        // Skip speed value - resolution would be 0.01 km/h
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
        // Check if the command in the queue matches the response
        if (_sendingCommand != null && _sendingCommand![0] == requestOpCode) {
          _sendingCommand = null;
        }
      } else {
        print(
          '[FtmsBleTransport] FTMS operation 0x${requestOpCode.toRadixString(16)} failed with result: 0x${resultCode.toRadixString(16)}',
        );
        _sendingCommand = null;
      }

      // Send next command in queue
      _sendNextCommand();
    }
  }

  Future<void> _sendNextCommand() async {
    if (_commandQueue.isEmpty) return;
    if (_sendingCommand != null && DateTime.now().difference(_lastSentCommandTime) < _bluetoothTimeout) {
      return;
    }

    // Rate limiting
    if (DateTime.now().difference(_lastSentCommandTime) < _bluetoothDebounce) {
      return;
    }

    if (!isConnected) return;

    _sendingCommand = _commandQueue.removeAt(0);
    _lastSentCommandTime = DateTime.now();

    // Log the command being sent
    final opCode = _sendingCommand![0];
    if (opCode == 0x00) {
      developer.log('[FtmsBleTransport] 📤 Sending: Request Control (0x00)');
    } else if (opCode == 0x05 && _sendingCommand!.length >= 3) {
      final power = _sendingCommand![1] | (_sendingCommand![2] << 8);
      developer.log('[FtmsBleTransport] 📤 Sending: Set Target Power ${power}W (0x05)');
    } else {
      developer.log('[FtmsBleTransport] 📤 Sending: Command 0x${opCode.toRadixString(16)}');
    }

    final characteristic = QualifiedCharacteristic(
      serviceId: _ftmsServiceUuid,
      characteristicId: _controlPointUuid,
      deviceId: deviceId,
    );

    try {
      await _ble.writeCharacteristicWithResponse(characteristic, value: _sendingCommand!);
    } catch (e, stackTrace) {
      print('[FtmsBleTransport] Error sending command: $e');
      print(stackTrace);
      _sendingCommand = null;
    }
  }

  /// Sends target power command to the trainer in ERG mode.
  ///
  /// [watts] is clamped to 25-1500W range for safety.
  /// Commands are queued and sent with rate limiting to avoid overwhelming the device.
  Future<void> sendTargetPower(int watts) async {
    developer.log('[FtmsBleTransport] sendTargetPower called with ${watts}W');

    // Check if there's already a target power command in the queue
    final targetPowerInQueue = _commandQueue.any((cmd) => cmd[0] == 0x05);
    if (targetPowerInQueue) {
      developer.log('[FtmsBleTransport] Target power already in queue, skipping');
      _sendNextCommand();
      return;
    }

    // Limit power to 25-1500W
    final clampedPower = watts.clamp(25, 1500);
    if (clampedPower != watts) {
      developer.log('[FtmsBleTransport] Power clamped from ${watts}W to ${clampedPower}W');
    }

    developer.log(
      '[FtmsBleTransport] Queueing commands: Request Control (0x00) + Set Target Power ${clampedPower}W (0x05)',
    );

    // Request control (0x00)
    _commandQueue.add(Uint8List.fromList([0x00]));

    // Set target power (0x05) with little endian bytes
    _commandQueue.add(
      Uint8List.fromList([
        0x05,
        clampedPower & 0xFF, // Low byte
        (clampedPower >> 8) & 0xFF, // High byte
      ]),
    );

    _sendNextCommand();
  }

  void _handleDisconnection() {
    developer.log('[FtmsBleTransport] Device disconnected');
    _connectionSubscription?.cancel();
    _indoorBikeDataSubscription?.cancel();
    _controlPointSubscription?.cancel();
    _connectionSubscription = null;
    _indoorBikeDataSubscription = null;
    _controlPointSubscription = null;
    _commandQueue.clear();
    _sendingCommand = null;
    _connectionCompleter = null;
    _connectionStateController.add(ConnectionState.disconnected);
  }

  /// Disconnects from the FTMS device.
  ///
  /// Cancels all subscriptions and clears command queue.
  Future<void> disconnect() async {
    _handleDisconnection();
  }

  /// Disposes of all resources.
  ///
  /// Must be called when the transport is no longer needed.
  void dispose() {
    _connectionSubscription?.cancel();
    _indoorBikeDataSubscription?.cancel();
    _controlPointSubscription?.cancel();
    _powerController.close();
    _cadenceController.close();
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
