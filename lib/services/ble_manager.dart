import 'dart:async';
import 'dart:developer' as developer;
import 'package:async/async.dart';
import 'package:context_plus/context_plus.dart';
import 'package:vekolo/domain/models/fitness_data.dart';
import 'package:vekolo/domain/protocols/ftms_device.dart';

/// Service layer wrapper for FtmsDevice.
///
/// Provides a simple callback-based API for testing and debugging trainer connections.
/// This is a thin wrapper that delegates to FtmsDevice (which uses FtmsBleTransport).
///
/// Architecture flow:
/// - BleManager (service layer, callback API)
///   → FtmsDevice (protocol layer, stream API)
///     → FtmsBleTransport (infrastructure layer, BLE communication)
///
/// Used by TrainerPage for simple testing UI. For production multi-device
/// management, use DeviceManager instead.
class BleManager {
  FtmsDevice? _device;
  StreamSubscription<PowerData>? _powerSubscription;
  StreamSubscription<CadenceData>? _cadenceSubscription;

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
  /// Creates an FtmsDevice internally and delegates connection to it.
  /// Returns a CancelableOperation for backward compatibility.
  CancelableOperation<void> connectToDevice(String deviceId) {
    developer.log('[BleManager] Connecting to device: $deviceId');

    // Create FtmsDevice (which uses FtmsBleTransport internally)
    _device = FtmsDevice(deviceId: deviceId, name: 'Trainer');

    // Subscribe to data streams and convert to callbacks
    _setupDataStreamSubscriptions();

    // Delegate connection to FtmsDevice
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

  /// Subscribe to FtmsDevice data streams and convert to callbacks.
  void _setupDataStreamSubscriptions() {
    // Subscribe to power stream
    _powerSubscription = _device?.powerStream.listen(
      (data) {
        currentPower = data.watts;
        _notifyDataUpdate();
      },
      onError: (e, stackTrace) {
        print('[BleManager] Power stream error: $e');
        print(stackTrace);
        onError?.call('Power stream error: $e');
      },
    );

    // Subscribe to cadence stream
    _cadenceSubscription = _device?.cadenceStream.listen(
      (data) {
        currentCadence = data.rpm;
        _notifyDataUpdate();
      },
      onError: (e, stackTrace) {
        print('[BleManager] Cadence stream error: $e');
        print(stackTrace);
        onError?.call('Cadence stream error: $e');
      },
    );

    // Note: Speed is provided by FTMS Indoor Bike Data characteristic
    // but FtmsDevice doesn't expose it yet. For now we'll simulate it
    // based on power and cadence (rough approximation).
    // TODO: Add speed support to FtmsDevice/FtmsBleTransport
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
  /// Delegates to FtmsDevice.setTargetPower().
  void setTargetPower(int powerInWatts) {
    developer.log('[BleManager] setTargetPower called with ${powerInWatts}W');

    if (_device == null) {
      developer.log('[BleManager] Cannot set target power: device not connected');
      return;
    }

    // Delegate to FtmsDevice (which handles clamping and FTMS commands)
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
    _powerSubscription?.cancel();
    _cadenceSubscription?.cancel();
    _powerSubscription = null;
    _cadenceSubscription = null;

    _device?.disconnect();
    _device?.dispose();
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
