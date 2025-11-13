import 'dart:async';
import 'package:clock/clock.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:state_beacon/state_beacon.dart';
import 'package:vekolo/ble/ble_permissions.dart';
import 'package:vekolo/ble/ble_platform.dart';
import 'package:chirp/chirp.dart';

/// Opaque token representing an active scan request.
///
/// Returned by [BleScanner.startScan] and must be passed to [BleScanner.stopScan]
/// to stop scanning. This allows multiple independent callers to start and stop
/// scanning without interfering with each other.
///
/// The scanner only stops when all outstanding tokens have been released.
class ScanToken {
  ScanToken._();
}

/// A discovered BLE device with timing information.
///
/// Wraps a [ScanResult] from flutter_blue_plus and tracks when the device
/// was first discovered and when it was last seen advertising.
class DiscoveredDevice {
  /// The raw scan result from flutter_blue_plus.
  final ScanResult scanResult;

  /// When this device was first discovered during the current scan session.
  final DateTime firstSeen;

  /// When this device was last seen advertising (most recent advertisement).
  final DateTime lastSeen;

  /// Current RSSI value (signal strength).
  ///
  /// Null if device hasn't been seen recently (>5 seconds).
  /// Updated periodically by the scanner to reflect current signal status.
  final int? rssi;

  DiscoveredDevice({required this.scanResult, required this.firstSeen, required this.lastSeen, required this.rssi});

  /// The device's Bluetooth identifier.
  String get deviceId => scanResult.device.remoteId.str;

  /// The device's advertised name, if available.
  String? get name => scanResult.advertisementData.advName;

  /// List of service UUIDs advertised by this device.
  List<Guid> get serviceUuids => scanResult.advertisementData.serviceUuids;

  /// Create a copy with updated scanResult and timestamps.
  ///
  /// Sets RSSI to the new scan result's value since device just advertised.
  DiscoveredDevice copyWithScanResult(ScanResult newScanResult, DateTime newLastSeen) {
    return DiscoveredDevice(
      scanResult: newScanResult,
      firstSeen: firstSeen,
      lastSeen: newLastSeen,
      rssi: newScanResult.rssi,
    );
  }

  /// Create a copy with updated RSSI value.
  DiscoveredDevice copyWithRssi(int? newRssi) {
    return DiscoveredDevice(scanResult: scanResult, firstSeen: firstSeen, lastSeen: lastSeen, rssi: newRssi);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DiscoveredDevice && runtimeType == other.runtimeType && deviceId == other.deviceId;

  @override
  int get hashCode => deviceId.hashCode;

  @override
  String toString() =>
      'DiscoveredDevice(id: $deviceId, name: $name, rssi: $rssi, firstSeen: $firstSeen, lastSeen: $lastSeen)';
}

/// Complete Bluetooth state including adapter, permissions, and location services.
///
/// Provides both raw state values and computed getters to determine what
/// actions are possible or needed.
class BluetoothState {
  /// Current Bluetooth adapter state (on, off, turning on/off, etc.).
  final BluetoothAdapterState adapterState;

  /// Whether all required BLE permissions are granted.
  final bool hasPermission;

  /// Whether BLE permissions have been permanently denied by the user.
  final bool isPermissionPermanentlyDenied;

  /// Whether location services are enabled (required on Android).
  final bool isLocationServiceEnabled;

  BluetoothState({
    required this.adapterState,
    required this.hasPermission,
    required this.isPermissionPermanentlyDenied,
    required this.isLocationServiceEnabled,
  });

  /// Whether Bluetooth adapter is powered on and ready.
  bool get isBluetoothOn => adapterState == BluetoothAdapterState.on;

  /// Whether Bluetooth adapter is unavailable (device doesn't support it).
  bool get isBluetoothUnavailable => adapterState == BluetoothAdapterState.unavailable;

  /// Whether the app can currently scan for BLE devices.
  ///
  /// Requires Bluetooth on + permissions granted + location services enabled.
  bool get canScan => isBluetoothOn && hasPermission && isLocationServiceEnabled;

  /// Whether the app needs to request permissions.
  bool get needsPermission => !hasPermission && !isPermissionPermanentlyDenied;

  /// Whether the app needs to prompt user to enable location services.
  bool get needsLocationService => !isLocationServiceEnabled;

  /// Whether user must manually grant permissions in system settings.
  bool get mustOpenSettings => isPermissionPermanentlyDenied;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BluetoothState &&
          runtimeType == other.runtimeType &&
          adapterState == other.adapterState &&
          hasPermission == other.hasPermission &&
          isPermissionPermanentlyDenied == other.isPermissionPermanentlyDenied &&
          isLocationServiceEnabled == other.isLocationServiceEnabled;

  @override
  int get hashCode =>
      adapterState.hashCode ^
      hasPermission.hashCode ^
      isPermissionPermanentlyDenied.hashCode ^
      isLocationServiceEnabled.hashCode;

  @override
  String toString() =>
      'BluetoothState(adapter: ${adapterState.name}, hasPermission: $hasPermission, '
      'isPermanentlyDenied: $isPermissionPermanentlyDenied, '
      'isLocationServiceEnabled: $isLocationServiceEnabled, canScan: $canScan)';
}

/// BLE device scanner with automatic state management and lifecycle awareness.
///
/// Key features:
/// - **Token-based scanning**: Multiple callers can independently start/stop scanning
/// - **Auto device expiry**: Devices not seen in 5 seconds are automatically removed
/// - **Discovery-time sorting**: Devices maintain their discovery order
/// - **Auto-restart**: Resumes scanning when Bluetooth becomes available
/// - **Lifecycle awareness**: Stops scanning when app backgrounds, resumes on foreground
/// - **Reactive state**: All state exposed via state_beacon signals
/// - **Fully testable**: All dependencies injected (BlePlatform, BlePermissions, Clock)
///
/// Usage:
/// ```dart
/// final scanner = BleScanner();
///
/// // Start scanning
/// final token = scanner.startScan();
///
/// // Listen to devices
/// scanner.devices.observe((devices) {
///   print('Found ${devices.length} devices');
/// });
///
/// // Stop scanning
/// scanner.stopScan(token);
/// ```
class BleScanner with WidgetsBindingObserver {
  /// Platform abstraction for BLE operations.
  final BlePlatform _platform;

  /// Permissions abstraction for checking/requesting permissions.
  final BlePermissions _permissions;

  /// Active scan tokens. Scanning continues as long as this is non-empty.
  final Set<ScanToken> _activeTokens = {};

  /// Map of device ID to discovered device (preserves discovery order via insertion order).
  final Map<String, DiscoveredDevice> _discoveredDevices = {};

  /// Writable beacon for discovered devices list.
  late final WritableBeacon<List<DiscoveredDevice>> _devicesBeacon;

  /// Writable beacon for scanning state.
  late final WritableBeacon<bool> _isScanningBeacon;

  /// Writable beacon for Bluetooth state.
  late final WritableBeacon<BluetoothState> _bluetoothStateBeacon;

  /// Unsubscribe function for adapter state beacon.
  VoidCallback? _adapterStateUnsubscribe;

  /// Unsubscribe function for scan results beacon.
  VoidCallback? _scanResultsUnsubscribe;

  /// Timer for periodically checking device expiry and permissions.
  Timer? _periodicCheckTimer;

  /// Whether dispose has been called.
  bool _disposed = false;

  /// Whether we're currently in the process of starting a scan.
  bool _isStartingScan = false;

  /// Public read-only view of discovered devices, sorted by discovery time.
  ReadableBeacon<List<DiscoveredDevice>> get devices => _devicesBeacon;

  /// Public read-only view of scanning state.
  ReadableBeacon<bool> get isScanning => _isScanningBeacon;

  /// Public read-only view of Bluetooth state.
  ReadableBeacon<BluetoothState> get bluetoothState => _bluetoothStateBeacon;

  /// Create a BLE scanner with optional dependency injection.
  ///
  /// All parameters are optional for easy testing:
  /// - [platform]: BLE platform abstraction (defaults to production impl)
  /// - [permissions]: Permissions abstraction (defaults to production impl)
  ///
  /// IMPORTANT: You must call [initialize] after construction to start monitoring
  /// Bluetooth state and app lifecycle.
  BleScanner({required BlePlatform platform, required BlePermissions permissions})
    : _platform = platform,
      _permissions = permissions {
    // Initialize beacons with default values
    _devicesBeacon = Beacon.writable(<DiscoveredDevice>[]);
    _isScanningBeacon = Beacon.writable(false);
    _bluetoothStateBeacon = Beacon.writable(
      BluetoothState(
        adapterState: BluetoothAdapterState.unknown,
        hasPermission: false,
        isPermissionPermanentlyDenied: false,
        isLocationServiceEnabled: false,
      ),
    );
  }

  /// Initialize the scanner by starting state monitoring and lifecycle observation.
  ///
  /// Must be called after construction before using the scanner. This is separate
  /// from the constructor to avoid doing work during construction, which makes
  /// testing more predictable.
  void initialize() {
    if (_disposed) {
      chirp.info('Cannot initialize after disposal');
      return;
    }

    // Register for app lifecycle events
    WidgetsBinding.instance.addObserver(this);

    // Start monitoring adapter state
    _startMonitoring();
  }

  /// Start monitoring Bluetooth adapter state and permissions.
  void _startMonitoring() {
    // Subscribe to adapter state changes
    _adapterStateUnsubscribe = _platform.adapterState.subscribe((state) {
      chirp.info('Adapter state changed to: $state');
      _updateBluetoothState();
    });

    // Subscribe to scan results
    _scanResultsUnsubscribe = _platform.scanResults.subscribe((results) {
      _handleScanResults(results);
    });

    // Start periodic checks for device expiry and permissions
    _periodicCheckTimer = Timer.periodic(const Duration(seconds: 1), (_) => _performPeriodicChecks());

    // Initial state update
    _updateBluetoothState();
  }

  /// Update Bluetooth state by checking all required conditions.
  Future<void> _updateBluetoothState() async {
    if (_disposed) return;

    try {
      final adapterState = _platform.adapterState.value;
      final hasPermission = await _permissions.check();
      final isPermanentlyDenied = await _permissions.isPermanentlyDenied();
      final isLocationEnabled = await _permissions.isLocationServiceEnabled();

      // Check disposed again after async operations
      if (_disposed) return;

      final newState = BluetoothState(
        adapterState: adapterState,
        hasPermission: hasPermission,
        isPermissionPermanentlyDenied: isPermanentlyDenied,
        isLocationServiceEnabled: isLocationEnabled,
      );

      // Only update if state actually changed
      if (newState != _bluetoothStateBeacon.value) {
        _bluetoothStateBeacon.value = newState;

        chirp.info('Bluetooth state updated: $newState');

        // Clear devices and stop scanning when Bluetooth turns off or becomes unavailable
        if (!newState.isBluetoothOn) {
          if (_discoveredDevices.isNotEmpty) {
            chirp.info('Bluetooth turned off, clearing ${_discoveredDevices.length} devices');
            _discoveredDevices.clear();
            _updateDevicesBeacon();
          }
          // Stop platform scanning if it's active
          if (_isScanningBeacon.value) {
            chirp.info('Bluetooth turned off, stopping scan');
            _stopPlatformScan();
          }
        }

        // Auto-restart scanning if conditions became favorable
        _maybeAutoRestartScanning();
      }
    } catch (e, stack) {
      chirp.error('Error updating Bluetooth state', error: e, stackTrace: stack);
    }
  }

  /// Perform periodic maintenance checks.
  Future<void> _performPeriodicChecks() async {
    if (_disposed) return;

    // Update signal status for all devices
    _updateDeviceSignalStatus();

    // Remove expired devices
    _removeExpiredDevices();

    // Update permissions state (might have changed in system settings)
    await _updateBluetoothState();
  }

  /// Update the RSSI values for all discovered devices.
  ///
  /// This is called periodically to ensure devices that lose signal
  /// have their RSSI set to null, which triggers UI updates to show "No signal".
  void _updateDeviceSignalStatus() {
    final now = clock.now();
    final recentSignalThreshold = const Duration(seconds: 5);
    bool updated = false;
    int signalLostCount = 0;
    int signalRestoredCount = 0;

    for (final entry in _discoveredDevices.entries) {
      final device = entry.value;
      final timeSinceLastSeen = now.difference(device.lastSeen);
      final hasRecentSignal = timeSinceLastSeen < recentSignalThreshold;
      final newRssi = hasRecentSignal ? device.scanResult.rssi : null;

      // Only update if RSSI changed
      if (device.rssi == newRssi) continue;

      if (newRssi == null) {
        signalLostCount++;
        chirp.info(
          'Device lost signal: ${device.name ?? device.deviceId} '
          '(last seen ${timeSinceLastSeen.inSeconds}s ago, was ${device.rssi} dBm)',
        );
      }

      if (newRssi != null) {
        signalRestoredCount++;
        chirp.info(
          'Device signal restored: ${device.name ?? device.deviceId} '
          '(RSSI: $newRssi dBm)',
        );
      }

      _discoveredDevices[entry.key] = device.copyWithRssi(newRssi);
      updated = true;
    }

    if (updated) {
      chirp.info(
        'Signal status updated: $signalLostCount lost, $signalRestoredCount restored '
        '(${_discoveredDevices.length} total devices)',
      );
      _updateDevicesBeacon();
    }
  }

  /// Remove devices that haven't been seen in 30 seconds.
  ///
  /// Devices remain visible in the UI but show "no signal" status
  /// until they are completely removed after 30 seconds of inactivity.
  void _removeExpiredDevices() {
    final now = clock.now();
    final expiryThreshold = const Duration(seconds: 30);

    final expiredIds = _discoveredDevices.entries
        .where((entry) => now.difference(entry.value.lastSeen) > expiryThreshold)
        .map((entry) => entry.key)
        .toList();

    if (expiredIds.isNotEmpty) {
      for (final id in expiredIds) {
        _discoveredDevices.remove(id);
      }
      chirp.info('Removed ${expiredIds.length} expired devices');
      _updateDevicesBeacon();
    }
  }

  /// Handle new scan results from the platform.
  void _handleScanResults(List<ScanResult> results) {
    if (_disposed) return;

    // Ignore scan results if Bluetooth is not on
    if (!_bluetoothStateBeacon.value.isBluetoothOn) {
      return;
    }

    final now = clock.now();
    bool updated = false;

    for (final result in results) {
      final deviceId = result.device.remoteId.str;
      final existing = _discoveredDevices[deviceId];

      // Early return pattern for new device
      if (existing == null) {
        _discoveredDevices[deviceId] = DiscoveredDevice(
          scanResult: result,
          firstSeen: now,
          lastSeen: now,
          rssi: result.rssi,
        );
        updated = true;
        chirp.info('New device discovered: $deviceId (${result.advertisementData.advName})');
        continue;
      }

      // Update existing device with new scan result and last seen time
      _discoveredDevices[deviceId] = existing.copyWithScanResult(result, now);
      updated = true;
    }

    if (updated) {
      _updateDevicesBeacon();
    }
  }

  /// Update the devices beacon with current list (maintains discovery order).
  void _updateDevicesBeacon() {
    if (_disposed) return;
    _devicesBeacon.value = _discoveredDevices.values.toList();
  }

  /// Maybe auto-restart scanning if conditions are now favorable.
  void _maybeAutoRestartScanning() {
    // Only auto-restart if we have active tokens but aren't currently scanning
    if (_activeTokens.isNotEmpty &&
        !_isScanningBeacon.value &&
        !_isStartingScan &&
        _bluetoothStateBeacon.value.canScan) {
      chirp.info('Auto-restarting scan (conditions now favorable)');
      _startPlatformScan();
    }
  }

  /// Start scanning for BLE devices.
  ///
  /// Returns a [ScanToken] that must be passed to [stopScan] to stop scanning.
  /// Multiple callers can start scanning independently - scanning continues
  /// as long as at least one token is active.
  ///
  /// Scanning automatically stops when the app goes to background and resumes
  /// when the app returns to foreground (if tokens are still active).
  ///
  /// If Bluetooth is off, permissions are missing, or location services are
  /// disabled, scanning will automatically start once conditions become favorable.
  ScanToken startScan() {
    if (_disposed) {
      throw StateError('Cannot start scan: BleScanner has been disposed');
    }

    final token = ScanToken._();
    _activeTokens.add(token);

    chirp.info('Start scan requested (${_activeTokens.length} active tokens)');

    // Start platform scan if not already scanning and conditions are met
    if (!_isScanningBeacon.value && !_isStartingScan) {
      _startPlatformScan();
    }

    return token;
  }

  /// Actually start the platform scan if conditions allow.
  Future<void> _startPlatformScan() async {
    if (_disposed || _isScanningBeacon.value || _isStartingScan) {
      return;
    }

    final state = _bluetoothStateBeacon.value;

    if (!state.canScan) {
      chirp.info('Cannot start scan: canScan=false (${state})');
      return;
    }

    _isStartingScan = true;

    try {
      await _platform.startScan();
      // Check disposed again after async operation
      if (!_disposed) {
        _isScanningBeacon.value = true;
        chirp.info('Platform scan started successfully');
      }
    } catch (e, stack) {
      chirp.error('Failed to start platform scan', error: e, stackTrace: stack);
    } finally {
      _isStartingScan = false;
    }
  }

  /// Stop scanning for BLE devices.
  ///
  /// The provided [token] must match one returned by [startScan].
  /// Scanning only stops when all active tokens have been released.
  ///
  /// It's safe to call this multiple times with the same token - only the
  /// first call has any effect.
  ///
  /// Note: The device list is cleared immediately when scanning stops.
  /// UI layers should maintain their own local state if they want to keep
  /// displaying devices after scanning stops.
  void stopScan(ScanToken token) {
    if (_disposed) {
      return;
    }

    final wasRemoved = _activeTokens.remove(token);

    if (wasRemoved) {
      chirp.info('Stop scan requested (${_activeTokens.length} active tokens remaining)');

      // Stop platform scan if no tokens remain
      if (_activeTokens.isEmpty && _isScanningBeacon.value) {
        // Clear devices immediately when stopping scan
        _discoveredDevices.clear();
        _updateDevicesBeacon();

        _stopPlatformScan();
      }
    }
  }

  /// Actually stop the platform scan.
  Future<void> _stopPlatformScan() async {
    if (_disposed || !_isScanningBeacon.value) {
      return;
    }

    try {
      await _platform.stopScan();
      // Check disposed again after async operation
      if (!_disposed) {
        _isScanningBeacon.value = false;
        chirp.info('Platform scan stopped');
      }
    } catch (e, stack) {
      chirp.error('Failed to stop platform scan', error: e, stackTrace: stack);
    }
  }

  /// Handle app lifecycle state changes.
  ///
  /// Stops scanning when app goes to background (inactive/paused) and resumes
  /// when app comes to foreground (resumed) if tokens are still active.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed) return;

    chirp.info('App lifecycle changed to: $state');

    switch (state) {
      case AppLifecycleState.resumed:
        // App came to foreground - resume scanning if we have active tokens
        if (_activeTokens.isNotEmpty && !_isScanningBeacon.value) {
          chirp.info('App resumed, restarting scan');
          _startPlatformScan();
        }

      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
        // App going to background - stop scanning to save battery
        if (_isScanningBeacon.value) {
          chirp.info('App backgrounded, stopping scan');
          _stopPlatformScan();
        }

      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        // App is detaching or hidden - ensure scan is stopped
        if (_isScanningBeacon.value) {
          chirp.info('App detached/hidden, stopping scan');
          _stopPlatformScan();
        }
    }
  }

  /// Dispose of all resources.
  ///
  /// Stops scanning, cancels all subscriptions, and releases all resources.
  /// After calling dispose, this scanner instance cannot be used anymore.
  void dispose() {
    if (_disposed) return;

    chirp.info('Disposing scanner');

    _disposed = true;

    // Unregister lifecycle observer
    WidgetsBinding.instance.removeObserver(this);

    // Stop scanning
    if (_isScanningBeacon.value) {
      _stopPlatformScan();
    }

    // Clear tokens
    _activeTokens.clear();

    // Unsubscribe from beacons
    _adapterStateUnsubscribe?.call();
    _scanResultsUnsubscribe?.call();

    // Cancel timers
    _periodicCheckTimer?.cancel();

    // Clear devices
    _discoveredDevices.clear();

    // Dispose beacons
    _devicesBeacon.dispose();
    _isScanningBeacon.dispose();
    _bluetoothStateBeacon.dispose();

    chirp.info('Scanner disposed');
  }
}
