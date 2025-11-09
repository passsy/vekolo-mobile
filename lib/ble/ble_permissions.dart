import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'package:vekolo/app/logger.dart';

/// Abstract interface for checking and requesting BLE permissions.
///
/// BLE permissions vary by platform and Android version:
///
/// **Android 12+ (API 31+)**:
/// - Requires BLUETOOTH_SCAN for discovering nearby devices
/// - Requires BLUETOOTH_CONNECT for connecting to devices
/// - Location services must be enabled for BLE scanning
///
/// **Android 11 and below**:
/// - Requires ACCESS_FINE_LOCATION for BLE scanning
/// - Requires BLUETOOTH and BLUETOOTH_ADMIN (granted automatically via manifest)
/// - Location services must be enabled for BLE scanning
///
/// **iOS**:
/// - Bluetooth permission requested automatically when accessing CoreBluetooth
/// - No location permission needed for BLE
///
/// This abstraction allows for easy testing with fake implementations.
abstract class BlePermissions {
  /// Check if all required BLE permissions are currently granted.
  ///
  /// Returns true if all permissions needed for BLE operations are granted,
  /// false otherwise.
  ///
  /// On iOS, this always returns true since permissions are handled by the system.
  Future<bool> check();

  /// Request all necessary BLE permissions from the user.
  ///
  /// Returns true if all permissions were granted, false if any were denied.
  ///
  /// If permissions are permanently denied, this will return false and
  /// [isPermanentlyDenied] will return true. In that case, the user must
  /// grant permissions via [openSettings].
  Future<bool> request();

  /// Check if any required BLE permission has been permanently denied.
  ///
  /// When true, calling [request] will not show a permission dialog.
  /// The user must manually grant permissions via [openSettings].
  Future<bool> isPermanentlyDenied();

  /// Check if location services are enabled on the device.
  ///
  /// On Android, location services must be enabled for BLE scanning to work,
  /// even when using the new Android 12+ Bluetooth permissions.
  ///
  /// Returns true if location services are enabled, false otherwise.
  /// On iOS, this always returns true since location is not needed for BLE.
  Future<bool> isLocationServiceEnabled();

  /// Open the app's settings page where the user can manually grant permissions.
  ///
  /// Use this when [isPermanentlyDenied] returns true.
  Future<void> openSettings();
}

/// Production implementation of [BlePermissions] that wraps permission_handler.
///
/// Handles all the complexity of Android version-specific permission logic
/// and provides a simple API for checking and requesting BLE permissions.
class BlePermissionsImpl implements BlePermissions {
  @override
  Future<bool> check() async {
    if (!Platform.isAndroid) {
      // iOS handles permissions automatically
      return true;
    }

    // Early return for Android 11 and below
    if (!await _isAndroid12OrHigher()) {
      final locationStatus = await Permission.locationWhenInUse.status;
      return locationStatus.isGranted;
    }

    // Android 12+
    final scanStatus = await Permission.bluetoothScan.status;
    final connectStatus = await Permission.bluetoothConnect.status;
    return scanStatus.isGranted && connectStatus.isGranted;
  }

  @override
  Future<bool> request() async {
    logClass('Requesting BLE permissions');

    if (!Platform.isAndroid) {
      logClass('Not Android, no permission request needed');
      return true;
    }

    final List<Permission> permissionsToRequest = [];

    // Determine permissions based on Android version with early return pattern
    final isAndroid12Plus = await _isAndroid12OrHigher();

    if (isAndroid12Plus) {
      // Android 12+ (API 31+) uses new Bluetooth permissions
      logClass('Android 12+, requesting BLUETOOTH_SCAN and BLUETOOTH_CONNECT');
      permissionsToRequest.add(Permission.bluetoothScan);
      permissionsToRequest.add(Permission.bluetoothConnect);
    }

    if (!isAndroid12Plus) {
      // Android 11 and below requires location permission for BLE scanning
      logClass('Android 11 or below, requesting LOCATION permissions');
      permissionsToRequest.add(Permission.locationWhenInUse);
    }

    // Request all permissions
    final statuses = await permissionsToRequest.request();

    // Check if all permissions granted
    bool allGranted = true;
    for (final entry in statuses.entries) {
      final permission = entry.key;
      final status = entry.value;
      logClass('$permission: $status');

      if (!status.isGranted) {
        allGranted = false;
        if (status.isPermanentlyDenied) {
          logClass('$permission is permanently denied');
        }
      }
    }

    if (allGranted) {
      logClass('All permissions granted');
    } else {
      logClass('Some permissions denied');
    }

    return allGranted;
  }

  @override
  Future<bool> isPermanentlyDenied() async {
    if (!Platform.isAndroid) {
      return false;
    }

    // Early return for Android 11 and below
    if (!await _isAndroid12OrHigher()) {
      final locationStatus = await Permission.locationWhenInUse.status;
      return locationStatus.isPermanentlyDenied;
    }

    // Android 12+
    final scanStatus = await Permission.bluetoothScan.status;
    final connectStatus = await Permission.bluetoothConnect.status;
    return scanStatus.isPermanentlyDenied || connectStatus.isPermanentlyDenied;
  }

  @override
  Future<bool> isLocationServiceEnabled() async {
    if (!Platform.isAndroid) {
      // iOS doesn't require location services for BLE
      return true;
    }

    // On Android, check if location services are enabled
    // This is required even with Android 12+ Bluetooth permissions
    final serviceStatus = await Permission.location.serviceStatus;
    return serviceStatus.isEnabled;
  }

  @override
  Future<void> openSettings() async {
    logClass('Opening app settings');
    await openAppSettings();
  }

  /// Determine if running Android 12 (API 31) or higher.
  ///
  /// Android 12 introduced new runtime Bluetooth permissions that replace
  /// the need for location permissions when scanning for BLE devices.
  ///
  /// We detect this by checking if the bluetoothScan permission is available,
  /// which only exists on Android 12+.
  Future<bool> _isAndroid12OrHigher() async {
    try {
      // The bluetoothScan permission only exists on Android 12+
      await Permission.bluetoothScan.status;
      return true;
    } catch (e, stackTrace) {
      // If checking bluetoothScan throws an error, we're on older Android
      logClass('Not Android 12+: $e', e: e, stack: stackTrace);
      return false;
    }
  }
}
