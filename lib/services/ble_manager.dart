import 'dart:async';
import 'dart:developer' as developer;
import 'dart:typed_data';
import 'package:async/async.dart';
import 'package:context_plus/context_plus.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

class BleManager {
  final FlutterReactiveBle _ble = FlutterReactiveBle();

  // FTMS service and characteristic UUIDs
  static final _ftmsServiceUuid = Uuid.parse('00001826-0000-1000-8000-00805f9b34fb');
  static final _indoorBikeDataUuid = Uuid.parse('00002AD2-0000-1000-8000-00805f9b34fb');
  static final _controlPointUuid = Uuid.parse('00002AD9-0000-1000-8000-00805f9b34fb');

  static const _bluetoothTimeout = Duration(milliseconds: 5000);
  static const _bluetoothDebounce = Duration(milliseconds: 250);

  // Connection state
  String? _connectedDeviceId;
  StreamSubscription<ConnectionStateUpdate>? _connectionSubscription;
  StreamSubscription<List<int>>? _indoorBikeDataSubscription;
  StreamSubscription<List<int>>? _controlPointSubscription;
  Completer<void>? _connectionCompleter;

  // Command queue
  final List<Uint8List> _commandQueue = [];
  Uint8List? _sendingCommand;
  DateTime _lastSentCommandTime = DateTime.now();

  // Trainer data
  int? currentPower;
  int? currentCadence;
  double? currentSpeed;

  // Connection status
  bool get isConnected => _connectedDeviceId != null;
  String? get connectedDeviceId => _connectedDeviceId;

  // Callbacks
  Function(int power, int cadence, double speed)? onTrainerDataUpdate;
  Function(String error)? onError;
  Function()? onDisconnected;

  CancelableOperation<void> connectToDevice(String deviceId) {
    return CancelableOperation.fromFuture(
      _connectToDeviceInternal(deviceId),
      onCancel: () {
        developer.log('[BleManager] Connection cancelled, cleaning up');
        _connectionSubscription?.cancel();
        _connectionCompleter?.completeError(Exception('Connection cancelled'));
        _handleDisconnection();
      },
    );
  }

  Future<void> _connectToDeviceInternal(String deviceId) async {
    try {
      developer.log('[BleManager] Connecting to device: $deviceId');

      // Create a completer to track connection completion
      _connectionCompleter = Completer<void>();

      // Listen to connection state changes
      _connectionSubscription = _ble
          .connectToDevice(id: deviceId, connectionTimeout: const Duration(seconds: 10))
          .listen(
            (update) async {
              developer.log('[BleManager] Connection state: ${update.connectionState}');

              if (update.connectionState == DeviceConnectionState.connected) {
                _connectedDeviceId = deviceId;
                try {
                  await _setupCharacteristics(deviceId);
                  // Connection successful, complete the future
                  if (!_connectionCompleter!.isCompleted) {
                    developer.log('[BleManager] Connection completed successfully');
                    _connectionCompleter!.complete();
                  }
                } catch (e, stackTrace) {
                  print('[BleManager] Error setting up characteristics: $e');
                  print(stackTrace);
                  if (!_connectionCompleter!.isCompleted) {
                    _connectionCompleter!.completeError(e, stackTrace);
                  }
                  onError?.call('Failed to setup characteristics: $e');
                }
              } else if (update.connectionState == DeviceConnectionState.disconnected) {
                if (!_connectionCompleter!.isCompleted) {
                  _connectionCompleter!.completeError('Device disconnected before connection completed');
                }
                _handleDisconnection();
              }
            },
            onError: (Object e, StackTrace stackTrace) {
              print('[BleManager] Connection error: $e');
              print(stackTrace);
              if (!_connectionCompleter!.isCompleted) {
                _connectionCompleter!.completeError(e, stackTrace);
              }
              onError?.call('Connection failed: $e');
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
      print('[BleManager] Failed to connect: $e');
      print(stackTrace);
      onError?.call('Failed to connect: $e');
      rethrow;
    }
  }

  Future<void> _setupCharacteristics(String deviceId) async {
    try {
      developer.log('[BleManager] Setting up characteristics');

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
              print('[BleManager] Indoor bike data error: $e');
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
              print('[BleManager] Control point error: $e');
              print(stackTrace);
            },
          );

      developer.log('[BleManager] Characteristics setup complete');
    } catch (e, stackTrace) {
      print('[BleManager] Failed to setup characteristics: $e');
      print(stackTrace);
      onError?.call('Failed to setup characteristics: $e');
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
      // Parse speed if present
      if (speedPresent && offset + 2 <= data.length) {
        final rawSpeed = buffer.getUint16(offset, Endian.little);
        currentSpeed = rawSpeed / 100.0; // Resolution: 0.01 km/h
        offset += 2;
      }

      // Skip average speed if present
      if ((flags & 0x02) != 0 && offset + 2 <= data.length) {
        offset += 2;
      }

      // Parse cadence if present
      if (cadencePresent && offset + 2 <= data.length) {
        final rawCadence = buffer.getUint16(offset, Endian.little);
        currentCadence = (rawCadence / 2).round(); // Resolution: 0.5 rpm
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
        currentPower = buffer.getInt16(offset, Endian.little);
        offset += 2;
      }

      // Skip average power if present
      if ((flags & 0x80) != 0 && offset + 2 <= data.length) {
        offset += 2;
      }

      // Notify listeners
      if (currentPower != null && currentCadence != null && currentSpeed != null) {
        onTrainerDataUpdate?.call(currentPower!, currentCadence!, currentSpeed!);
      }
    } catch (e, stackTrace) {
      print('[BleManager] Error parsing indoor bike data: $e');
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
        developer.log('[BleManager] Command 0x${requestOpCode.toRadixString(16)} succeeded');
        // Check if the command in the queue matches the response
        if (_sendingCommand != null && _sendingCommand![0] == requestOpCode) {
          _sendingCommand = null;
        }
      } else {
        print(
          '[BleManager] FTMS operation 0x${requestOpCode.toRadixString(16)} failed with result: 0x${resultCode.toRadixString(16)}',
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

    if (_connectedDeviceId == null) return;

    _sendingCommand = _commandQueue.removeAt(0);
    _lastSentCommandTime = DateTime.now();

    // Log the command being sent
    final opCode = _sendingCommand![0];
    if (opCode == 0x00) {
      developer.log('[BleManager] 📤 Sending: Request Control (0x00)');
    } else if (opCode == 0x05 && _sendingCommand!.length >= 3) {
      final power = _sendingCommand![1] | (_sendingCommand![2] << 8);
      developer.log('[BleManager] 📤 Sending: Set Target Power ${power}W (0x05)');
    } else {
      developer.log('[BleManager] 📤 Sending: Command 0x${opCode.toRadixString(16)}');
    }

    final characteristic = QualifiedCharacteristic(
      serviceId: _ftmsServiceUuid,
      characteristicId: _controlPointUuid,
      deviceId: _connectedDeviceId!,
    );

    try {
      await _ble.writeCharacteristicWithResponse(characteristic, value: _sendingCommand!);
    } catch (e, stackTrace) {
      print('[BleManager] Error sending command: $e');
      print(stackTrace);
      _sendingCommand = null;
    }
  }

  void setTargetPower(int powerInWatts) {
    developer.log('[BleManager] setTargetPower called with ${powerInWatts}W');

    // Check if there's already a target power command in the queue
    final targetPowerInQueue = _commandQueue.any((cmd) => cmd[0] == 0x05);
    if (targetPowerInQueue) {
      developer.log('[BleManager] Target power already in queue, skipping');
      _sendNextCommand();
      return;
    }

    // Limit power to 25-1500W
    final clampedPower = powerInWatts.clamp(25, 1500);
    if (clampedPower != powerInWatts) {
      developer.log('[BleManager] Power clamped from ${powerInWatts}W to ${clampedPower}W');
    }

    developer.log('[BleManager] Queueing commands: Request Control (0x00) + Set Target Power ${clampedPower}W (0x05)');

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
    developer.log('[BleManager] Device disconnected');
    _connectedDeviceId = null;
    _commandQueue.clear();
    _sendingCommand = null;
    _connectionCompleter = null;
    currentPower = null;
    currentCadence = null;
    currentSpeed = null;
    onDisconnected?.call();
  }

  void disconnect() {
    _connectionSubscription?.cancel();
    _indoorBikeDataSubscription?.cancel();
    _controlPointSubscription?.cancel();
    _connectionSubscription = null;
    _indoorBikeDataSubscription = null;
    _controlPointSubscription = null;
    _handleDisconnection();
  }

  void dispose() {
    disconnect();
  }
}

final bleManagerRef = Ref<BleManager>();
