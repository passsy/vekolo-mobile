import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'package:chirp/chirp.dart';
import 'package:vekolo/ble/ble_permissions.dart';

/// Production implementation of [BlePermissions] for mobile and desktop platforms.
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
    Chirp.info('Requesting BLE permissions');

    if (!Platform.isAndroid) {
      Chirp.info('Non-Android platform, no permission request needed');
      return true;
    }

    final List<Permission> permissionsToRequest = [];

    // Determine permissions based on Android version with early return pattern
    final isAndroid12Plus = await _isAndroid12OrHigher();

    if (isAndroid12Plus) {
      // Android 12+ (API 31+) uses new Bluetooth permissions
      Chirp.info('Android 12+, requesting BLUETOOTH_SCAN and BLUETOOTH_CONNECT');
      permissionsToRequest.add(Permission.bluetoothScan);
      permissionsToRequest.add(Permission.bluetoothConnect);
    }

    if (!isAndroid12Plus) {
      // Android 11 and below requires location permission for BLE scanning
      Chirp.info('Android 11 or below, requesting LOCATION permissions');
      permissionsToRequest.add(Permission.locationWhenInUse);
    }

    // Request all permissions
    final statuses = await permissionsToRequest.request();

    // Check if all permissions granted
    bool allGranted = true;
    for (final entry in statuses.entries) {
      final permission = entry.key;
      final status = entry.value;
      Chirp.info('$permission: $status');

      if (!status.isGranted) {
        allGranted = false;
        if (status.isPermanentlyDenied) {
          Chirp.info('$permission is permanently denied');
        }
      }
    }

    if (allGranted) {
      Chirp.info('All permissions granted');
    } else {
      Chirp.info('Some permissions denied');
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
    Chirp.info('Opening app settings');
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
      Chirp.error('Not Android 12+', error: e, stackTrace: stackTrace);
      return false;
    }
  }
}
