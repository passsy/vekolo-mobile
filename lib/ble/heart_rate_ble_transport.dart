import 'dart:async';
import 'package:vekolo/app/logger.dart';

import 'package:clock/clock.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;
import 'package:state_beacon/state_beacon.dart';
import 'package:vekolo/ble/ble_scanner.dart';
import 'package:vekolo/ble/ble_transport.dart';
import 'package:vekolo/ble/transport_capabilities.dart';
import 'package:vekolo/ble/transport_registry.dart';
import 'package:vekolo/domain/models/device_info.dart';
import 'package:vekolo/domain/models/fitness_data.dart';

/// Bluetooth transport layer for Heart Rate Service protocol.
///
/// Handles low-level BLE communication with heart rate monitors using the
/// standard Bluetooth Heart Rate Service (0x180D). Exposes heart rate
/// measurements and provides connection management.
///
/// This is a pure transport layer - no domain logic, just BLE communication
/// and heart rate protocol parsing.
class HeartRateBleTransport implements BleTransport, HeartRateSource {
  /// Creates a heart rate BLE transport for the specified device.
  HeartRateBleTransport({required this.deviceId});

  /// BLE device ID to connect to.
  final String deviceId;

  // Heart Rate Service UUIDs (Bluetooth SIG standard)
  static final _heartRateServiceUuid = fbp.Guid('0000180d-0000-1000-8000-00805f9b34fb');
  static final _heartRateMeasurementCharUuid = fbp.Guid('00002a37-0000-1000-8000-00805f9b34fb');

  // Connection state
  StreamSubscription<List<int>>? _heartRateSubscription;
  ConnectionError? _lastAttachError;

  // Data beacons
  late final WritableBeacon<HeartRateData?> _heartRateBeacon = Beacon.writable(null);
  late final WritableBeacon<TransportState> _stateBeacon = Beacon.writable(TransportState.detached);

  // ============================================================================
  // BleTransport Interface Implementation
  // ============================================================================

  @override
  bool canSupport(DiscoveredDevice device) {
    // Heart rate monitors advertise the Heart Rate Service UUID (0x180D)
    return device.serviceUuids.contains(_heartRateServiceUuid);
  }

  @override
  Future<bool> verifyCompatibility({
    required fbp.BluetoothDevice device,
    required List<fbp.BluetoothService> services,
  }) async {
    // Heart Rate Service has standard implementation, no deep check needed
    return true;
  }

  // HeartRateSource implementation
  @override
  ReadableBeacon<HeartRateData?> get heartRateStream => _heartRateBeacon;

  @override
  ReadableBeacon<TransportState> get state => _stateBeacon;

  @override
  ConnectionError? get lastAttachError => _lastAttachError;

  @override
  bool get isAttached => _stateBeacon.value == TransportState.attached;

  /// Attaches to the Heart Rate service on an already-connected device.
  ///
  /// The [device] must already be connected and [services] must be discovered
  /// by BleDevice before calling this method.
  @override
  Future<void> attach({required fbp.BluetoothDevice device, required List<fbp.BluetoothService> services}) async {
    try {
      _stateBeacon.value = TransportState.attaching;
      _lastAttachError = null; // Clear any previous error
      talker.info(
        '[HeartRateBleTransport] Attaching to Heart Rate service on $deviceId',
      );

      // Find Heart Rate Service
      final hrService = services.firstWhere(
        (s) => s.uuid == _heartRateServiceUuid,
        orElse: () => throw Exception('Heart Rate Service not found'),
      );

      talker.info('[HeartRateBleTransport] Found Heart Rate Service');

      // Find Heart Rate Measurement characteristic
      final hrMeasurementChar = hrService.characteristics.firstWhere(
        (c) => c.uuid == _heartRateMeasurementCharUuid,
        orElse: () => throw Exception('Heart Rate Measurement characteristic not found'),
      );

      talker.info(
        '[HeartRateBleTransport] Found Heart Rate Measurement characteristic',
      );

      // Subscribe to heart rate notifications
      await hrMeasurementChar.setNotifyValue(true);
      _heartRateSubscription = hrMeasurementChar.onValueReceived.listen(_parseHeartRateMeasurement);

      talker.info('[HeartRateBleTransport] Subscribed to heart rate notifications');

      _stateBeacon.value = TransportState.attached;
    } catch (e, stackTrace) {
      talker.info(
        '[HeartRateBleTransport] Failed to attach to Heart Rate service: $e',
        e,
        stackTrace,
      );
      _lastAttachError = ConnectionError(
        message: 'Failed to attach to Heart Rate service: $e',
        timestamp: clock.now(),
        error: e,
        stackTrace: stackTrace,
      );
      _stateBeacon.value = TransportState.detached;
      rethrow;
    }
  }

  /// Detaches from the Heart Rate service.
  @override
  Future<void> detach() async {
    try {
      talker.info(
        '[HeartRateBleTransport] Detaching from Heart Rate service on $deviceId',
      );

      // Cancel subscriptions
      await _heartRateSubscription?.cancel();
      _heartRateSubscription = null;

      _stateBeacon.value = TransportState.detached;
    } catch (e, stackTrace) {
      talker.info(
        '[HeartRateBleTransport] Detach failed: $e',
        e,
        stackTrace,
      );
      _stateBeacon.value = TransportState.detached;
    }
  }

  /// Parses Heart Rate Measurement characteristic according to Bluetooth spec.
  ///
  /// Format:
  /// - Byte 0: Flags
  ///   - Bit 0: Heart Rate Value Format (0 = uint8, 1 = uint16)
  ///   - Bit 1-2: Sensor Contact Status
  ///   - Bit 3: Energy Expended Status
  ///   - Bit 4: RR-Interval
  /// - Byte 1-2: Heart Rate Measurement Value (uint8 or uint16)
  /// - Optional: Energy Expended (uint16)
  /// - Optional: RR-Interval values (uint16 list)
  void _parseHeartRateMeasurement(List<int> value) {
    if (value.isEmpty) return;

    try {
      final flags = value[0];
      final isUint16 = (flags & 0x01) != 0;

      int bpm;
      if (isUint16) {
        // uint16 format
        if (value.length < 3) return;
        bpm = value[1] | (value[2] << 8);
      } else {
        // uint8 format
        if (value.length < 2) return;
        bpm = value[1];
      }

      final data = HeartRateData(bpm: bpm, timestamp: clock.now());
      _heartRateBeacon.value = data;
    } catch (e, stackTrace) {
      talker.info(
        '[HeartRateBleTransport] Failed to parse heart rate: $e',
        e,
        stackTrace,
      );
    }
  }

  /// Disposes of resources.
  @override
  Future<void> dispose() async {
    await detach();
    _heartRateBeacon.dispose();
    _stateBeacon.dispose();
  }
}

/// Registration for Heart Rate transport.
///
/// Use this to register the Heart Rate transport with [TransportRegistry]:
/// ```dart
/// registry.register(heartRateTransportRegistration);
/// ```
final heartRateTransportRegistration = TransportRegistration(
  name: 'Heart Rate Service',
  factory: _createHeartRateTransport,
);

/// Factory function for creating Heart Rate transport instances.
BleTransport _createHeartRateTransport(String deviceId) {
  return HeartRateBleTransport(deviceId: deviceId);
}
