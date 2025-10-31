import 'dart:async';
import 'dart:developer' as developer;
import 'package:async/async.dart';
import 'package:context_plus/context_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:vekolo/ble/ble_device.dart';
import 'package:vekolo/ble/ftms_ble_transport.dart';
import 'package:vekolo/domain/devices/fitness_device.dart';

/// Service layer wrapper for BleDevice with FTMS transport.
///
/// Provides a simple callback-based API for testing and debugging trainer connections.
/// This is a thin wrapper that delegates to BleDevice (which uses BLE transports).
///
/// Architecture flow:
/// - BleManager (service layer, callback API)
///   → BleDevice (domain layer, stream API)
///     → FtmsBleTransport (BLE communication layer)
///
/// Used by TrainerPage for simple testing UI. For production multi-device
/// management, use DeviceManager instead.
class BleManager {
  FitnessDevice? _device;
  VoidCallback? _powerSubscription;
  VoidCallback? _cadenceSubscription;

  // Cached trainer data (for backward compatibility with old API)
  int? currentPower;
  int? currentCadence;
  double? currentSpeed;

  // Connection status
  bool get isConnected => _device != null;
  String? get connectedDeviceId => _device?.id;

  // Callbacks
  Function(int power, int cadence, double speed)? onTrainerDataUpdate;
  Function(String error)? onError;
  Function()? onDisconnected;

  /// Connects to an FTMS device.
  ///
  /// Creates a BleDevice with FTMS transport and delegates connection to it.
  /// Returns a CancelableOperation for backward compatibility.
  CancelableOperation<void> connectToDevice(String deviceId) {
    developer.log('[BleManager] Connecting to device: $deviceId');

    // Create BleDevice with FTMS transport
    final ftmsTransport = FtmsBleTransport(deviceId: deviceId);
    _device = BleDevice(
      id: deviceId,
      name: 'Trainer',
      transports: [ftmsTransport],
    );

    // Subscribe to data streams and convert to callbacks
    _setupDataStreamSubscriptions();

    // Delegate connection to BleDevice
    final connectOperation = _device!.connect();

    // Wrap in CancelableOperation with custom cancel logic
    return CancelableOperation.fromFuture(
      _connectWithErrorHandling(connectOperation),
      onCancel: () {
        developer.log('[BleManager] Connection cancelled, cleaning up');
        connectOperation.cancel();
        _cleanup();
      },
    );
  }

  Future<void> _connectWithErrorHandling(CancelableOperation<void> operation) async {
    try {
      await operation.value;
      developer.log('[BleManager] Connection completed successfully');
    } catch (e, stackTrace) {
      print('[BleManager] Failed to connect: $e');
      print(stackTrace);
      onError?.call('Failed to connect: $e');
      _cleanup();
      rethrow;
    }
  }

  /// Subscribe to BleDevice data streams and convert to callbacks.
  void _setupDataStreamSubscriptions() {
    // Subscribe to power beacon
    _powerSubscription = _device?.powerStream?.subscribe((data) {
      if (data != null) {
        currentPower = data.watts;
        _notifyDataUpdate();
      }
    });

    // Subscribe to cadence beacon
    _cadenceSubscription = _device?.cadenceStream?.subscribe((data) {
      if (data != null) {
        currentCadence = data.rpm;
        _notifyDataUpdate();
      }
    });

    // Note: Speed is provided by FTMS Indoor Bike Data characteristic
    // but BleDevice doesn't expose it yet. For now we'll simulate it
    // based on power and cadence (rough approximation).
    // TODO: Add speed support to BleDevice/FtmsBleTransport
  }

  /// Notify callbacks when we have updated data.
  void _notifyDataUpdate() {
    if (currentPower != null && currentCadence != null) {
      // Rough speed approximation: assuming ~80 RPM at 25 km/h
      currentSpeed ??= currentCadence! * 0.3125;

      onTrainerDataUpdate?.call(currentPower!, currentCadence!, currentSpeed!);
    }
  }

  /// Sets target power for ERG mode.
  ///
  /// Delegates to BleDevice.setTargetPower().
  void setTargetPower(int powerInWatts) {
    developer.log('[BleManager] setTargetPower called with ${powerInWatts}W');

    if (_device == null) {
      developer.log('[BleManager] Cannot set target power: device not connected');
      return;
    }

    // Delegate to BleDevice (which handles clamping and FTMS commands)
    _device!.setTargetPower(powerInWatts).catchError((e, stackTrace) {
      print('[BleManager] Failed to set target power: $e');
      print(stackTrace);
      onError?.call('Failed to set target power: $e');
    });
  }

  /// Disconnects from the device.
  void disconnect() {
    developer.log('[BleManager] Disconnecting');
    _cleanup();
  }

  void _cleanup() {
    _powerSubscription?.call();
    _cadenceSubscription?.call();
    _powerSubscription = null;
    _cadenceSubscription = null;

    final device = _device;
    if (device != null) {
      device.disconnect();
      if (device is BleDevice) {
        device.dispose();
      }
    }
    _device = null;

    currentPower = null;
    currentCadence = null;
    currentSpeed = null;

    onDisconnected?.call();
  }

  /// Disposes all resources.
  void dispose() {
    disconnect();
  }
}

final bleManagerRef = Ref<BleManager>();
