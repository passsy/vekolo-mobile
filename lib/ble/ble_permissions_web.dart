import 'package:chirp/chirp.dart';
import 'package:vekolo/ble/ble_permissions.dart';

/// Web implementation of [BlePermissions].
///
/// On web, Bluetooth permissions are handled automatically by the browser's
/// Web Bluetooth API. The browser prompts the user when attempting to scan
/// or connect to devices, so no manual permission requests are needed.
class BlePermissionsImpl implements BlePermissions {
  @override
  Future<bool> check() async {
    // Web handles permissions automatically via Web Bluetooth API
    return true;
  }

  @override
  Future<bool> request() async {
    Chirp.info('Web platform, permissions handled by browser');
    return true;
  }

  @override
  Future<bool> isPermanentlyDenied() async {
    return false;
  }

  @override
  Future<bool> isLocationServiceEnabled() async {
    // Web doesn't require location services for BLE
    return true;
  }

  @override
  Future<void> openSettings() async {
    Chirp.info('Opening settings not supported on web');
    // No-op on web - browser handles settings
  }
}
