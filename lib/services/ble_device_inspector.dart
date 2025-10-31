import 'dart:async';
import 'dart:developer' as developer;

import 'package:clock/clock.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;

/// Service for inspecting unknown BLE devices and collecting comprehensive GATT data.
///
/// This service connects to a BLE device, discovers all services, characteristics,
/// and descriptors, reads available data, captures advertisement information,
/// and generates a human-readable TXT report for debugging and device identification.
///
/// Example usage:
/// ```dart
/// final inspector = BleDeviceInspector();
/// final report = await inspector.inspectDevice(
///   deviceId: 'XX:XX:XX:XX:XX:XX',
///   deviceName: 'Unknown Device',
///   advertisementData: scanResult.advertisementData.serviceData,
/// );
/// print(report);
/// ```
class BleDeviceInspector {
  BleDeviceInspector();

  /// Timeout for BLE connection attempts.
  static const _connectionTimeout = Duration(seconds: 30);

  /// Timeout for reading individual characteristics.
  static const _characteristicReadTimeout = Duration(seconds: 10);

  // Connection state
  StreamSubscription<fbp.BluetoothConnectionState>? _connectionSubscription;
  fbp.BluetoothDevice? _device;

  /// Data collected during inspection.
  final List<_ServiceInfo> _services = [];
  String? _deviceName;
  String? _deviceId;
  Map<fbp.Guid, List<int>>? _advertisementData;
  int? _rssi;
  DateTime? _inspectionStartTime;
  DateTime? _inspectionEndTime;

  /// Inspects a BLE device and returns a comprehensive TXT report.
  ///
  /// [deviceId] - The BLE device ID to connect to.
  /// [deviceName] - Optional device name from scan results.
  /// [advertisementData] - Optional advertisement service data from scan results.
  /// [rssi] - Optional signal strength from scan results.
  ///
  /// Returns a formatted text report containing all collected device information.
  /// Throws [TimeoutException] if connection takes longer than 30 seconds.
  /// Continues collection even if some characteristic reads fail.
  Future<String> inspectDevice({
    required String deviceId,
    String? deviceName,
    Map<fbp.Guid, List<int>>? advertisementData,
    int? rssi,
  }) async {
    _inspectionStartTime = clock.now();
    _deviceId = deviceId;
    _deviceName = deviceName;
    _advertisementData = advertisementData;
    _rssi = rssi;
    _services.clear();

    developer.log('[BleDeviceInspector] Starting inspection of device: $deviceId');

    try {
      // Step 1: Connect to device
      await _connectToDevice(deviceId);

      // Step 2: Discover GATT services
      await _discoverServices(deviceId);

      // Step 3: Disconnect
      await _disconnect();

      _inspectionEndTime = clock.now();

      // Step 4: Generate report
      return _generateReport();
    } catch (e, stackTrace) {
      developer.log('[BleDeviceInspector] Inspection failed: $e', error: e, stackTrace: stackTrace);
      await _disconnect();
      _inspectionEndTime = clock.now();
      return _generateReport(error: e.toString());
    }
  }

  /// Connects to the BLE device with timeout.
  Future<void> _connectToDevice(String deviceId) async {
    developer.log('[BleDeviceInspector] Connecting to device: $deviceId');

    final completer = Completer<void>();

    // Get or create device
    final devices = fbp.FlutterBluePlus.connectedDevices;
    _device = devices.firstWhere((d) => d.remoteId.str == deviceId, orElse: () => fbp.BluetoothDevice.fromId(deviceId));

    _connectionSubscription = _device!.connectionState.listen(
      (state) {
        developer.log('[BleDeviceInspector] Connection state: $state');

        if (state == fbp.BluetoothConnectionState.connected) {
          if (!completer.isCompleted) {
            developer.log('[BleDeviceInspector] Connected successfully');
            completer.complete();
          }
        } else if (state == fbp.BluetoothConnectionState.disconnected) {
          if (!completer.isCompleted) {
            completer.completeError('Device disconnected before connection completed');
          }
        }
      },
      onError: (Object e, StackTrace stackTrace) {
        developer.log('[BleDeviceInspector] Connection error: $e', error: e, stackTrace: stackTrace);
        if (!completer.isCompleted) {
          completer.completeError(e, stackTrace);
        }
      },
    );

    // Connect to device
    await _device!.connect(timeout: _connectionTimeout);

    await completer.future.timeout(
      _connectionTimeout,
      onTimeout: () {
        throw TimeoutException('Connection timed out after ${_connectionTimeout.inSeconds}s');
      },
    );
  }

  /// Discovers all GATT services and collects data.
  Future<void> _discoverServices(String deviceId) async {
    developer.log('[BleDeviceInspector] Discovering services...');

    try {
      final services = await _device!.discoverServices();
      developer.log('[BleDeviceInspector] Found ${services.length} service(s)');

      for (final service in services) {
        developer.log('[BleDeviceInspector] Processing service: ${service.uuid}');

        final characteristics = <_CharacteristicInfo>[];

        // Process each characteristic
        for (final characteristic in service.characteristics) {
          developer.log('[BleDeviceInspector] Processing characteristic: ${characteristic.uuid}');

          // Try to read characteristic value if readable
          List<int>? charValue;
          String? charReadError;
          if (characteristic.properties.read) {
            final readResult = await _readCharacteristic(characteristic);
            charValue = readResult.value;
            charReadError = readResult.error;
          } else {
            developer.log('[BleDeviceInspector] Characteristic ${characteristic.uuid} is not readable');
          }

          // Process descriptors
          final descriptors = <_DescriptorInfo>[];
          for (final descriptor in characteristic.descriptors) {
            developer.log('[BleDeviceInspector] Processing descriptor: ${descriptor.uuid}');

            List<int>? descriptorValue;
            String? descriptorReadError;

            try {
              final value = await descriptor.read().timeout(
                _characteristicReadTimeout,
                onTimeout: () {
                  developer.log('[BleDeviceInspector] Read timeout for descriptor ${descriptor.uuid}');
                  return <int>[];
                },
              );

              if (value.isNotEmpty) {
                descriptorValue = value;
                developer.log('[BleDeviceInspector] Read ${value.length} byte(s) from descriptor ${descriptor.uuid}');
              }
            } catch (e, stackTrace) {
              developer.log(
                '[BleDeviceInspector] Failed to read descriptor ${descriptor.uuid}: $e',
                error: e,
                stackTrace: stackTrace,
              );
              descriptorReadError = e.toString();
            }

            descriptors.add(
              _DescriptorInfo(uuid: descriptor.uuid, value: descriptorValue, readError: descriptorReadError),
            );
          }

          characteristics.add(
            _CharacteristicInfo(
              uuid: characteristic.uuid,
              isReadable: characteristic.properties.read,
              isWritableWithResponse: characteristic.properties.write,
              isWritableWithoutResponse: characteristic.properties.writeWithoutResponse,
              isNotifiable: characteristic.properties.notify,
              isIndicatable: characteristic.properties.indicate,
              value: charValue,
              readError: charReadError,
              descriptors: descriptors,
            ),
          );
        }

        _services.add(_ServiceInfo(uuid: service.uuid, isPrimary: service.isPrimary, characteristics: characteristics));
      }

      developer.log('[BleDeviceInspector] Service discovery completed');
    } catch (e, stackTrace) {
      developer.log('[BleDeviceInspector] Error during service discovery: $e', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Reads a characteristic value with timeout and error handling.
  Future<({List<int>? value, String? error})> _readCharacteristic(fbp.BluetoothCharacteristic characteristic) async {
    try {
      final value = await characteristic.read().timeout(
        _characteristicReadTimeout,
        onTimeout: () {
          developer.log('[BleDeviceInspector] Read timeout for characteristic ${characteristic.uuid}');
          return <int>[];
        },
      );

      if (value.isNotEmpty) {
        developer.log('[BleDeviceInspector] Read ${value.length} byte(s) from ${characteristic.uuid}');
        return (value: value, error: null);
      }
      return (value: null, error: null);
    } catch (e, stackTrace) {
      developer.log(
        '[BleDeviceInspector] Failed to read characteristic ${characteristic.uuid}: $e',
        error: e,
        stackTrace: stackTrace,
      );
      return (value: null, error: e.toString());
    }
  }

  /// Disconnects from the device.
  Future<void> _disconnect() async {
    developer.log('[BleDeviceInspector] Disconnecting');
    await _connectionSubscription?.cancel();
    _connectionSubscription = null;
    if (_device != null) {
      await _device!.disconnect();
    }
  }

  /// Generates a human-readable TXT report from collected data.
  String _generateReport({String? error}) {
    final buffer = StringBuffer();

    // Header
    buffer.writeln('═══════════════════════════════════════════════════════════════════');
    buffer.writeln('                    BLE DEVICE INSPECTION REPORT');
    buffer.writeln('═══════════════════════════════════════════════════════════════════');
    buffer.writeln();

    // Device information
    buffer.writeln('DEVICE INFORMATION');
    buffer.writeln('─────────────────────────────────────────────────────────────────');
    buffer.writeln('Device ID:      $_deviceId');
    buffer.writeln('Device Name:    ${_deviceName ?? "N/A"}');
    buffer.writeln('RSSI:           ${_rssi != null ? "$_rssi dBm" : "N/A"}');
    buffer.writeln(
      'Inspection:     ${_formatTimestamp(_inspectionStartTime)} - ${_formatTimestamp(_inspectionEndTime)}',
    );
    if (_inspectionStartTime != null && _inspectionEndTime != null) {
      final duration = _inspectionEndTime!.difference(_inspectionStartTime!);
      buffer.writeln('Duration:       ${duration.inSeconds}s');
    }
    if (error != null) {
      buffer.writeln('ERROR:          $error');
    }
    buffer.writeln();

    // Advertisement data
    if (_advertisementData != null && _advertisementData!.isNotEmpty) {
      buffer.writeln('ADVERTISEMENT DATA');
      buffer.writeln('─────────────────────────────────────────────────────────────────');
      for (final entry in _advertisementData!.entries) {
        buffer.writeln('Service UUID:   ${entry.key}');
        buffer.writeln('Data:           ${_formatBytes(entry.value)}');
        buffer.writeln('ASCII:          ${_formatAscii(entry.value)}');
        buffer.writeln();
      }
    }

    // GATT services
    if (_services.isNotEmpty) {
      buffer.writeln('GATT SERVICES (${_services.length} found)');
      buffer.writeln('═══════════════════════════════════════════════════════════════════');
      buffer.writeln();

      for (var i = 0; i < _services.length; i++) {
        final service = _services[i];
        buffer.writeln('Service ${i + 1}: ${service.uuid}');
        buffer.writeln('  Type:         ${service.isPrimary ? "Primary" : "Secondary"}');
        buffer.writeln('  Known Name:   ${_getKnownServiceName(service.uuid)}');
        buffer.writeln();

        if (service.characteristics.isEmpty) {
          buffer.writeln('  No characteristics found');
          buffer.writeln();
        } else {
          for (var j = 0; j < service.characteristics.length; j++) {
            final char = service.characteristics[j];
            buffer.writeln('  Characteristic ${j + 1}: ${char.uuid}');
            buffer.writeln('    Known Name: ${_getKnownCharacteristicName(char.uuid)}');
            buffer.writeln('    Properties: ${_formatProperties(char)}');

            if (char.value != null) {
              buffer.writeln('    Value:      ${_formatBytes(char.value!)}');
              buffer.writeln('    ASCII:      ${_formatAscii(char.value!)}');
            } else if (char.readError != null) {
              buffer.writeln('    Read Error: ${char.readError}');
            } else {
              buffer.writeln('    Value:      Not readable');
            }

            if (char.descriptors.isNotEmpty) {
              buffer.writeln('    Descriptors (${char.descriptors.length}):');
              for (final descriptor in char.descriptors) {
                buffer.writeln('      - ${descriptor.uuid}');
                if (descriptor.value != null) {
                  buffer.writeln('        Value: ${_formatBytes(descriptor.value!)}');
                } else if (descriptor.readError != null) {
                  buffer.writeln('        Error: ${descriptor.readError}');
                }
              }
            }
            buffer.writeln();
          }
        }

        buffer.writeln('─────────────────────────────────────────────────────────────────');
        buffer.writeln();
      }
    } else {
      buffer.writeln('No GATT services discovered');
      buffer.writeln();
    }

    // Footer
    buffer.writeln('═══════════════════════════════════════════════════════════════════');
    buffer.writeln('                          END OF REPORT');
    buffer.writeln('═══════════════════════════════════════════════════════════════════');

    return buffer.toString();
  }

  /// Formats a list of bytes as hex string.
  String _formatBytes(List<int> bytes) {
    if (bytes.isEmpty) return '(empty)';
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
  }

  /// Formats bytes as ASCII string (printable characters only).
  String _formatAscii(List<int> bytes) {
    if (bytes.isEmpty) return '(empty)';
    return bytes.map((b) => (b >= 32 && b <= 126) ? String.fromCharCode(b) : '.').join();
  }

  /// Formats characteristic properties.
  String _formatProperties(_CharacteristicInfo char) {
    final props = <String>[];
    if (char.isReadable) props.add('Read');
    if (char.isWritableWithResponse) props.add('Write');
    if (char.isWritableWithoutResponse) props.add('WriteNoResp');
    if (char.isNotifiable) props.add('Notify');
    if (char.isIndicatable) props.add('Indicate');
    return props.isEmpty ? 'None' : props.join(', ');
  }

  /// Formats timestamp for display.
  String _formatTimestamp(DateTime? timestamp) {
    if (timestamp == null) return 'N/A';
    return timestamp.toIso8601String().replaceAll('T', ' ').split('.')[0];
  }

  /// Returns known service name for common UUIDs.
  String _getKnownServiceName(fbp.Guid uuid) {
    final knownServices = {
      '00001800-0000-1000-8000-00805f9b34fb': 'Generic Access',
      '00001801-0000-1000-8000-00805f9b34fb': 'Generic Attribute',
      '0000180a-0000-1000-8000-00805f9b34fb': 'Device Information',
      '0000180d-0000-1000-8000-00805f9b34fb': 'Heart Rate',
      '0000180f-0000-1000-8000-00805f9b34fb': 'Battery Service',
      '00001816-0000-1000-8000-00805f9b34fb': 'Cycling Speed and Cadence',
      '00001818-0000-1000-8000-00805f9b34fb': 'Cycling Power',
      '00001826-0000-1000-8000-00805f9b34fb': 'Fitness Machine Service (FTMS)',
    };
    return knownServices[uuid.toString().toLowerCase()] ?? 'Unknown';
  }

  /// Returns known characteristic name for common UUIDs.
  String _getKnownCharacteristicName(fbp.Guid uuid) {
    final knownChars = {
      '00002a00-0000-1000-8000-00805f9b34fb': 'Device Name',
      '00002a01-0000-1000-8000-00805f9b34fb': 'Appearance',
      '00002a19-0000-1000-8000-00805f9b34fb': 'Battery Level',
      '00002a23-0000-1000-8000-00805f9b34fb': 'System ID',
      '00002a24-0000-1000-8000-00805f9b34fb': 'Model Number',
      '00002a25-0000-1000-8000-00805f9b34fb': 'Serial Number',
      '00002a26-0000-1000-8000-00805f9b34fb': 'Firmware Revision',
      '00002a27-0000-1000-8000-00805f9b34fb': 'Hardware Revision',
      '00002a28-0000-1000-8000-00805f9b34fb': 'Software Revision',
      '00002a29-0000-1000-8000-00805f9b34fb': 'Manufacturer Name',
      '00002a37-0000-1000-8000-00805f9b34fb': 'Heart Rate Measurement',
      '00002a63-0000-1000-8000-00805f9b34fb': 'Cycling Power Measurement',
      '00002a5b-0000-1000-8000-00805f9b34fb': 'CSC Measurement',
      '00002ad2-0000-1000-8000-00805f9b34fb': 'Indoor Bike Data',
      '00002ad9-0000-1000-8000-00805f9b34fb': 'Fitness Machine Control Point',
    };
    return knownChars[uuid.toString().toLowerCase()] ?? 'Unknown';
  }

  /// Disposes resources.
  void dispose() {
    _connectionSubscription?.cancel();
  }
}

/// Internal class to store service information.
class _ServiceInfo {
  _ServiceInfo({required this.uuid, required this.isPrimary, required this.characteristics});

  final fbp.Guid uuid;
  final bool isPrimary;
  final List<_CharacteristicInfo> characteristics;
}

/// Internal class to store characteristic information.
class _CharacteristicInfo {
  _CharacteristicInfo({
    required this.uuid,
    required this.isReadable,
    required this.isWritableWithResponse,
    required this.isWritableWithoutResponse,
    required this.isNotifiable,
    required this.isIndicatable,
    required this.value,
    required this.readError,
    required this.descriptors,
  });

  final fbp.Guid uuid;
  final bool isReadable;
  final bool isWritableWithResponse;
  final bool isWritableWithoutResponse;
  final bool isNotifiable;
  final bool isIndicatable;
  final List<int>? value;
  final String? readError;
  final List<_DescriptorInfo> descriptors;
}

/// Internal class to store descriptor information.
class _DescriptorInfo {
  _DescriptorInfo({required this.uuid, required this.value, required this.readError});

  final fbp.Guid uuid;
  final List<int>? value;
  final String? readError;
}
