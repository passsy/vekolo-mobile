// Export the platform-specific implementation
export 'ble_permissions_io.dart'
    if (dart.library.html) 'ble_permissions_web.dart';

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
/// **Web**:
/// - Permissions handled automatically by the browser's Web Bluetooth API
/// - User is prompted when attempting to scan or connect to devices
///
/// This abstraction allows for easy testing with fake implementations.
abstract class BlePermissions {
  /// Check if all required BLE permissions are currently granted.
  ///
  /// Returns true if all permissions needed for BLE operations are granted,
  /// false otherwise.
  ///
  /// On iOS and Web, this always returns true since permissions are handled
  /// by the system/browser.
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
  /// On iOS and Web, this always returns true since location is not needed for BLE.
  Future<bool> isLocationServiceEnabled();

  /// Open the app's settings page where the user can manually grant permissions.
  ///
  /// Use this when [isPermanentlyDenied] returns true.
  Future<void> openSettings();
}
