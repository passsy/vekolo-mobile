import 'dart:async';
import 'package:clock/clock.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:state_beacon/state_beacon.dart';
import 'package:vekolo/ble/ble_permissions.dart';
import 'package:vekolo/ble/ble_platform.dart';
import 'dart:developer' as developer;

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

  DiscoveredDevice({
    required this.scanResult,
    required this.firstSeen,
    required this.lastSeen,
  });

  /// The device's Bluetooth identifier.
  String get deviceId => scanResult.device.remoteId.str;

  /// The device's advertised name, if available.
  String? get name => scanResult.advertisementData.advName;

  /// Signal strength indicator (more negative = weaker signal).
  int get rssi => scanResult.rssi;

  /// List of service UUIDs advertised by this device.
  List<Guid> get serviceUuids => scanResult.advertisementData.serviceUuids;

  /// Create a copy with updated lastSeen timestamp.
  DiscoveredDevice copyWithLastSeen(DateTime newLastSeen) {
    return DiscoveredDevice(
      scanResult: scanResult,
      firstSeen: firstSeen,
      lastSeen: newLastSeen,
    );
  }

  /// Create a copy with updated scanResult (preserving discovery times).
  DiscoveredDevice copyWithScanResult(ScanResult newScanResult, DateTime newLastSeen) {
    return DiscoveredDevice(
      scanResult: newScanResult,
      firstSeen: firstSeen,
      lastSeen: newLastSeen,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DiscoveredDevice &&
          runtimeType == other.runtimeType &&
          deviceId == other.deviceId;

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
  bool get isBluetoothUnavailable =>
      adapterState == BluetoothAdapterState.unavailable;

  /// Whether the app can currently scan for BLE devices.
  ///
  /// Requires Bluetooth on + permissions granted + location services enabled.
  bool get canScan =>
      isBluetoothOn && hasPermission && isLocationServiceEnabled;

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
      'BluetoothState(adapter: $adapterState, hasPermission: $hasPermission, '
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

  /// Clock for testable time operations.
  final Clock _clock;

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

  /// Subscription to adapter state changes.
  StreamSubscription<BluetoothAdapterState>? _adapterStateSubscription;

  /// Subscription to scan results.
  StreamSubscription<List<ScanResult>>? _scanResultsSubscription;

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
  /// - [clock]: Clock for time operations (defaults to system clock)
  BleScanner({
    BlePlatform? platform,
    BlePermissions? permissions,
    Clock? clock,
  })  : _platform = platform ?? BlePlatformImpl(),
        _permissions = permissions ?? BlePermissionsImpl(),
        _clock = clock ?? const Clock() {
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

    // Register for app lifecycle events
    WidgetsBinding.instance.addObserver(this);

    // Start monitoring adapter state
    _startMonitoring();
  }

  /// Start monitoring Bluetooth adapter state and permissions.
  void _startMonitoring() {
    // Listen to adapter state changes
    _adapterStateSubscription = _platform.adapterStateStream.listen(
      (state) {
        developer.log('[BleScanner] Adapter state changed to: $state');
        _updateBluetoothState(adapterState: state);
      },
      onError: (e, stackTrace) {
        developer.log('[BleScanner] Error in adapter state stream: $e');
        developer.log('$stackTrace');
      },
    );

    // Listen to scan results
    _scanResultsSubscription = _platform.scanResultsStream.listen(
      (results) {
        _handleScanResults(results);
      },
      onError: (e, stackTrace) {
        developer.log('[BleScanner] Error in scan results stream: $e');
        developer.log('$stackTrace');
      },
    );

    // Start periodic checks for device expiry and permissions
    _periodicCheckTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _performPeriodicChecks(),
    );

    // Initial state update
    _updateBluetoothState();
  }

  /// Update Bluetooth state by checking all required conditions.
  Future<void> _updateBluetoothState({BluetoothAdapterState? adapterState}) async {
    if (_disposed) return;

    try {
      final hasPermission = await _permissions.check();
      final isPermanentlyDenied = await _permissions.isPermanentlyDenied();
      final isLocationEnabled = await _permissions.isLocationServiceEnabled();

      final newState = BluetoothState(
        adapterState: adapterState ?? _bluetoothStateBeacon.value.adapterState,
        hasPermission: hasPermission,
        isPermissionPermanentlyDenied: isPermanentlyDenied,
        isLocationServiceEnabled: isLocationEnabled,
      );

      // Only update if state actually changed
      if (newState != _bluetoothStateBeacon.value) {
        _bluetoothStateBeacon.value = newState;

        developer.log('[BleScanner] Bluetooth state updated: $newState');

        // Auto-restart scanning if conditions became favorable
        _maybeAutoRestartScanning();
      }
    } catch (e, stackTrace) {
      developer.log('[BleScanner] Error updating Bluetooth state: $e');
      developer.log('$stackTrace');
    }
  }

  /// Perform periodic maintenance checks.
  Future<void> _performPeriodicChecks() async {
    if (_disposed) return;

    // Remove expired devices
    _removeExpiredDevices();

    // Update permissions state (might have changed in system settings)
    await _updateBluetoothState();
  }

  /// Remove devices that haven't been seen in 5 seconds.
  void _removeExpiredDevices() {
    final now = _clock.now();
    final expiryThreshold = const Duration(seconds: 5);

    final expiredIds = _discoveredDevices.entries
        .where((entry) => now.difference(entry.value.lastSeen) > expiryThreshold)
        .map((entry) => entry.key)
        .toList();

    if (expiredIds.isNotEmpty) {
      for (final id in expiredIds) {
        _discoveredDevices.remove(id);
      }
      developer.log('[BleScanner] Removed ${expiredIds.length} expired devices');
      _updateDevicesBeacon();
    }
  }

  /// Handle new scan results from the platform.
  void _handleScanResults(List<ScanResult> results) {
    if (_disposed) return;

    final now = _clock.now();
    bool updated = false;

    for (final result in results) {
      final deviceId = result.device.remoteId.str;
      final existing = _discoveredDevices[deviceId];

      if (existing == null) {
        // New device discovered
        _discoveredDevices[deviceId] = DiscoveredDevice(
          scanResult: result,
          firstSeen: now,
          lastSeen: now,
        );
        updated = true;
        developer.log('[BleScanner] New device discovered: $deviceId (${result.advertisementData.advName})');
      } else {
        // Update existing device with new scan result and last seen time
        _discoveredDevices[deviceId] = existing.copyWithScanResult(result, now);
        updated = true;
      }
    }

    if (updated) {
      _updateDevicesBeacon();
    }
  }

  /// Update the devices beacon with current list (maintains discovery order).
  void _updateDevicesBeacon() {
    _devicesBeacon.value = _discoveredDevices.values.toList();
  }

  /// Maybe auto-restart scanning if conditions are now favorable.
  void _maybeAutoRestartScanning() {
    // Only auto-restart if we have active tokens but aren't currently scanning
    if (_activeTokens.isNotEmpty &&
        !_isScanningBeacon.value &&
        !_isStartingScan &&
        _bluetoothStateBeacon.value.canScan) {
      developer.log('[BleScanner] Auto-restarting scan (conditions now favorable)');
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

    developer.log('[BleScanner] Start scan requested (${_activeTokens.length} active tokens)');

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
      developer.log('[BleScanner] Cannot start scan: canScan=false (${state})');
      return;
    }

    _isStartingScan = true;

    try {
      await _platform.startScan();
      _isScanningBeacon.value = true;
      developer.log('[BleScanner] Platform scan started successfully');
    } catch (e, stackTrace) {
      developer.log('[BleScanner] Failed to start platform scan: $e');
      developer.log('$stackTrace');
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
  void stopScan(ScanToken token) {
    if (_disposed) {
      return;
    }

    final wasRemoved = _activeTokens.remove(token);

    if (wasRemoved) {
      developer.log('[BleScanner] Stop scan requested (${_activeTokens.length} active tokens remaining)');

      // Stop platform scan if no tokens remain
      if (_activeTokens.isEmpty && _isScanningBeacon.value) {
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
      _isScanningBeacon.value = false;
      developer.log('[BleScanner] Platform scan stopped');
    } catch (e, stackTrace) {
      developer.log('[BleScanner] Failed to stop platform scan: $e');
      developer.log('$stackTrace');
    }
  }

  /// Handle app lifecycle state changes.
  ///
  /// Stops scanning when app goes to background (inactive/paused) and resumes
  /// when app comes to foreground (resumed) if tokens are still active.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed) return;

    developer.log('[BleScanner] App lifecycle changed to: $state');

    switch (state) {
      case AppLifecycleState.resumed:
        // App came to foreground - resume scanning if we have active tokens
        if (_activeTokens.isNotEmpty && !_isScanningBeacon.value) {
          developer.log('[BleScanner] App resumed, restarting scan');
          _startPlatformScan();
        }

      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
        // App going to background - stop scanning to save battery
        if (_isScanningBeacon.value) {
          developer.log('[BleScanner] App backgrounded, stopping scan');
          _stopPlatformScan();
        }

      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        // App is detaching or hidden - ensure scan is stopped
        if (_isScanningBeacon.value) {
          developer.log('[BleScanner] App detached/hidden, stopping scan');
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

    developer.log('[BleScanner] Disposing scanner');

    _disposed = true;

    // Unregister lifecycle observer
    WidgetsBinding.instance.removeObserver(this);

    // Stop scanning
    if (_isScanningBeacon.value) {
      _stopPlatformScan();
    }

    // Clear tokens
    _activeTokens.clear();

    // Cancel subscriptions
    _adapterStateSubscription?.cancel();
    _scanResultsSubscription?.cancel();

    // Cancel timers
    _periodicCheckTimer?.cancel();

    // Clear devices
    _discoveredDevices.clear();

    // Dispose beacons
    _devicesBeacon.dispose();
    _isScanningBeacon.dispose();
    _bluetoothStateBeacon.dispose();

    developer.log('[BleScanner] Scanner disposed');
  }
}
