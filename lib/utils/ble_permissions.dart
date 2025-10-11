import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'dart:developer' as developer;

class BlePermissions {
  /// Request all necessary BLE permissions based on Android version
  static Future<bool> requestPermissions() async {
    developer.log('[BlePermissions] Requesting BLE permissions');

    if (!Platform.isAndroid) {
      developer.log('[BlePermissions] Not Android, no permission request needed');
      return true;
    }

    // Get Android version info
    // Android 12+ (API 31+) uses new Bluetooth permissions
    // Android 11 and below uses location permissions for BLE scanning

    final List<Permission> permissionsToRequest = [];

    // For Android 12+ (API 31+)
    if (await _isAndroid12OrHigher()) {
      developer.log('[BlePermissions] Android 12+, requesting BLUETOOTH_SCAN and BLUETOOTH_CONNECT');
      permissionsToRequest.add(Permission.bluetoothScan);
      permissionsToRequest.add(Permission.bluetoothConnect);
    } else {
      // For Android 11 and below
      developer.log('[BlePermissions] Android 11 or below, requesting LOCATION permissions');
      permissionsToRequest.add(Permission.locationWhenInUse);
    }

    // Request all permissions
    final statuses = await permissionsToRequest.request();

    // Check if all permissions granted
    bool allGranted = true;
    for (final entry in statuses.entries) {
      final permission = entry.key;
      final status = entry.value;
      developer.log('[BlePermissions] $permission: $status');

      if (!status.isGranted) {
        allGranted = false;
        if (status.isPermanentlyDenied) {
          developer.log('[BlePermissions] $permission is permanently denied');
        }
      }
    }

    if (allGranted) {
      developer.log('[BlePermissions] All permissions granted ✅');
    } else {
      developer.log('[BlePermissions] Some permissions denied ❌');
    }

    return allGranted;
  }

  /// Check if any required BLE permission is permanently denied
  static Future<bool> isAnyPermissionPermanentlyDenied() async {
    if (!Platform.isAndroid) return false;

    if (await _isAndroid12OrHigher()) {
      final scanStatus = await Permission.bluetoothScan.status;
      final connectStatus = await Permission.bluetoothConnect.status;
      return scanStatus.isPermanentlyDenied || connectStatus.isPermanentlyDenied;
    } else {
      final locationStatus = await Permission.locationWhenInUse.status;
      return locationStatus.isPermanentlyDenied;
    }
  }

  /// Check if all required permissions are granted
  static Future<bool> arePermissionsGranted() async {
    if (!Platform.isAndroid) return true;

    if (await _isAndroid12OrHigher()) {
      final scanStatus = await Permission.bluetoothScan.status;
      final connectStatus = await Permission.bluetoothConnect.status;
      return scanStatus.isGranted && connectStatus.isGranted;
    } else {
      final locationStatus = await Permission.locationWhenInUse.status;
      return locationStatus.isGranted;
    }
  }

  /// Helper to determine if running Android 12 or higher
  static Future<bool> _isAndroid12OrHigher() async {
    // The permission_handler package will automatically handle version checks
    // We check if bluetoothScan permission exists (only on Android 12+)
    try {
      await Permission.bluetoothScan.status;
      // If we can check the status without error, we're on Android 12+
      return true;
    } catch (e) {
      // If checking bluetoothScan throws error, we're on older Android
      return false;
    }
  }

  /// Open app settings for manual permission grant
  static Future<void> openSettings() async {
    developer.log('[BlePermissions] Opening app settings');
    await openAppSettings();
  }
}
