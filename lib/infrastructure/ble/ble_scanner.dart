import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:vekolo/utils/ble_permissions.dart';

/// Service for scanning and discovering FTMS-compatible BLE devices.
///
/// This service wraps flutter_reactive_ble to provide a clean API for
/// scanning for fitness devices that support the FTMS (Fitness Machine Service)
/// protocol. It handles permission checks, Bluetooth status monitoring, and
/// device discovery.
///
/// Example usage:
/// ```dart
/// final scanner = BleScanner();
///
/// // Listen to scan results
/// scanner.discoveredDevices.listen((devices) {
///   print('Found ${devices.length} devices');
/// });
///
/// // Start scanning
/// await scanner.startScan();
///
/// // Stop scanning when done
/// scanner.stopScan();
/// ```
class BleScanner {
  BleScanner({FlutterReactiveBle? ble}) : _ble = ble ?? FlutterReactiveBle();

  final FlutterReactiveBle _ble;

  /// FTMS service UUID (Fitness Machine Service)
  static final ftmsServiceUuid = Uuid.parse('00001826-0000-1000-8000-00805f9b34fb');

  // Scan state
  StreamSubscription<DiscoveredDevice>? _scanSubscription;
  StreamSubscription<BleStatus>? _bleStatusSubscription;
  bool _isScanning = false;
  BleStatus _bleStatus = BleStatus.unknown;
  bool _permissionsGranted = false;

  // Discovered devices map (deviceId -> DiscoveredDevice)
  final Map<String, DiscoveredDevice> _discoveredDevices = {};

  // Stream controllers
  final _devicesController = StreamController<List<DiscoveredDevice>>.broadcast();
  final _scanStateController = StreamController<ScanState>.broadcast();

  /// Stream of discovered devices.
  ///
  /// Emits a new list whenever a device is discovered or updated during scanning.
  /// The list is sorted by signal strength (RSSI, strongest first).
  Stream<List<DiscoveredDevice>> get discoveredDevices => _devicesController.stream;

  /// Stream of scan state changes.
  ///
  /// Emits current scan state including scanning status, permissions, and BLE status.
  Stream<ScanState> get scanState => _scanStateController.stream;

  /// Current BLE status.
  BleStatus get bleStatus => _bleStatus;

  /// Whether a scan is currently active.
  bool get isScanning => _isScanning;

  /// Whether Bluetooth permissions are granted.
  bool get permissionsGranted => _permissionsGranted;

  /// List of currently discovered devices.
  List<DiscoveredDevice> get devices =>
      _discoveredDevices.values.toList()..sort((a, b) => b.rssi.compareTo(a.rssi)); // Sort by signal strength

  /// Initializes the scanner and starts monitoring BLE status.
  ///
  /// Should be called before starting a scan. Automatically checks permissions
  /// when BLE becomes ready.
  Future<void> initialize() async {
    developer.log('[BleScanner] Initializing scanner');

    // Listen to BLE status changes
    _bleStatusSubscription = _ble.statusStream.listen((status) async {
      developer.log('[BleScanner] BLE status changed to: $status');
      _bleStatus = status;
      _emitScanState();

      // Check and request permissions when BLE becomes ready
      if (status == BleStatus.ready || status == BleStatus.unauthorized) {
        await checkAndRequestPermissions();
      }
    });
  }

  /// Checks if permissions are granted and requests them if needed.
  ///
  /// Returns true if permissions are granted after this call.
  Future<bool> checkAndRequestPermissions() async {
    developer.log('[BleScanner] Checking permissions...');

    // Check if permissions already granted
    final granted = await BlePermissions.arePermissionsGranted();

    _permissionsGranted = granted;
    _emitScanState();

    if (!granted) {
      // Check if permanently denied
      final permanentlyDenied = await BlePermissions.isAnyPermissionPermanentlyDenied();

      if (!permanentlyDenied) {
        // Request permissions
        developer.log('[BleScanner] Requesting permissions...');
        final requestGranted = await BlePermissions.requestPermissions();
        _permissionsGranted = requestGranted;
        _emitScanState();
        return requestGranted;
      }
      return false;
    }

    return true;
  }

  /// Opens app settings for manual permission grant.
  ///
  /// Useful when permissions are permanently denied.
  Future<void> openSettings() async {
    await BlePermissions.openSettings();
  }

  /// Starts scanning for FTMS-compatible devices.
  ///
  /// Returns a [ScanResult] indicating success or the reason for failure.
  /// Automatically handles permission requests if needed.
  ///
  /// The scan will continue until [stopScan] is called or an error occurs.
  /// Discovered devices are emitted through [discoveredDevices] stream.
  Future<ScanResult> startScan() async {
    developer.log('[BleScanner] Start scan requested');

    // Check BLE status
    if (_bleStatus != BleStatus.ready) {
      developer.log('[BleScanner] Cannot start scan, BLE status is: $_bleStatus');
      return ScanResult.bleNotReady(_bleStatus);
    }

    // Check permissions
    if (!_permissionsGranted) {
      developer.log('[BleScanner] Permissions not granted, requesting...');
      final granted = await checkAndRequestPermissions();
      if (!granted) {
        developer.log('[BleScanner] Cannot start scan, permissions not granted');
        final permanentlyDenied = await BlePermissions.isAnyPermissionPermanentlyDenied();
        return ScanResult.permissionDenied(permanentlyDenied: permanentlyDenied);
      }
    }

    // Already scanning
    if (_isScanning) {
      developer.log('[BleScanner] Already scanning');
      return ScanResult.success();
    }

    developer.log('[BleScanner] Starting BLE scan for FTMS devices');
    _isScanning = true;
    _discoveredDevices.clear();
    _emitScanState();
    _emitDevices();

    _scanSubscription = _ble
        .scanForDevices(withServices: [ftmsServiceUuid], scanMode: ScanMode.lowLatency)
        .listen(
          (device) {
            final isNew = !_discoveredDevices.containsKey(device.id);
            _discoveredDevices[device.id] = device;

            if (isNew) {
              developer.log(
                '[BleScanner] Discovered new device: ${device.name.isEmpty ? device.id : device.name} '
                '(RSSI: ${device.rssi})',
              );
            }

            _emitDevices();
          },
          onError: (Object e, StackTrace stackTrace) {
            developer.log('[BleScanner] Scan error: $e', error: e, stackTrace: stackTrace);
            stopScan();
          },
        );

    return ScanResult.success();
  }

  /// Stops the current scan.
  ///
  /// Does nothing if no scan is active.
  void stopScan() {
    if (!_isScanning) return;

    developer.log('[BleScanner] Stopping BLE scan (found ${_discoveredDevices.length} device(s))');
    _scanSubscription?.cancel();
    _scanSubscription = null;
    _isScanning = false;
    _emitScanState();
  }

  /// Clears the list of discovered devices.
  void clearDevices() {
    _discoveredDevices.clear();
    _emitDevices();
  }

  void _emitScanState() {
    final state = ScanState(isScanning: _isScanning, bleStatus: _bleStatus, permissionsGranted: _permissionsGranted);
    _scanStateController.add(state);
  }

  void _emitDevices() {
    _devicesController.add(devices);
  }

  /// Disposes of all resources.
  ///
  /// Must be called when the scanner is no longer needed to prevent memory leaks.
  void dispose() {
    developer.log('[BleScanner] Disposing scanner');
    _scanSubscription?.cancel();
    _bleStatusSubscription?.cancel();
    _devicesController.close();
    _scanStateController.close();
  }
}

/// Represents the state of the BLE scanner.
class ScanState {
  const ScanState({required this.isScanning, required this.bleStatus, required this.permissionsGranted});

  final bool isScanning;
  final BleStatus bleStatus;
  final bool permissionsGranted;

  /// Whether the scanner is ready to scan.
  bool get canScan => bleStatus == BleStatus.ready && permissionsGranted;

  /// Human-readable status message.
  String get statusMessage {
    if (bleStatus != BleStatus.ready) {
      return switch (bleStatus) {
        BleStatus.unknown => 'Initializing Bluetooth...',
        BleStatus.unsupported => 'Bluetooth is not supported on this device',
        BleStatus.unauthorized => 'Bluetooth permission required',
        BleStatus.poweredOff => 'Bluetooth is turned off',
        BleStatus.locationServicesDisabled => 'Location services required',
        BleStatus.ready => 'Ready',
      };
    }

    if (!permissionsGranted) {
      return 'Bluetooth permissions required';
    }

    return isScanning ? 'Scanning for devices...' : 'Ready to scan';
  }
}

/// Result of a scan operation.
class ScanResult {
  const ScanResult._({required this.success, this.errorMessage, this.bleStatus, this.permanentlyDenied = false});

  factory ScanResult.success() => const ScanResult._(success: true);

  factory ScanResult.bleNotReady(BleStatus status) {
    final message = switch (status) {
      BleStatus.unknown => 'Bluetooth is initializing',
      BleStatus.unsupported => 'Bluetooth is not supported on this device',
      BleStatus.unauthorized => 'Bluetooth permission is required',
      BleStatus.poweredOff => 'Please turn on Bluetooth',
      BleStatus.locationServicesDisabled => 'Please enable location services',
      BleStatus.ready => 'Ready',
    };
    return ScanResult._(success: false, errorMessage: message, bleStatus: status);
  }

  factory ScanResult.permissionDenied({bool permanentlyDenied = false}) {
    return ScanResult._(
      success: false,
      errorMessage: permanentlyDenied
          ? 'Permissions permanently denied. Please enable them in app settings.'
          : 'Bluetooth permissions are required to scan for devices',
      permanentlyDenied: permanentlyDenied,
    );
  }

  final bool success;
  final String? errorMessage;
  final BleStatus? bleStatus;
  final bool permanentlyDenied;
}
