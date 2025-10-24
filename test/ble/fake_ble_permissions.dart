import 'package:vekolo/ble/ble_permissions.dart';

/// Fake implementation of [BlePermissions] for testing.
///
/// Provides complete control over permission states and tracks all permission-
/// related method calls for verification in tests.
///
/// By default, [request] automatically grants permission (sets [_hasPermission]
/// to true), but this can be customized by calling [setAutoGrantOnRequest].
///
/// Example usage:
/// ```dart
/// final permissions = FakeBlePermissions();
/// final scanner = BleScanner(permissions: permissions);
///
/// // Simulate permission denied
/// permissions.setHasPermission(false);
/// expect(await permissions.check(), false);
///
/// // Simulate user granting permission
/// await permissions.request();
/// expect(permissions.requestCallCount, 1);
/// expect(await permissions.check(), true);
///
/// // Simulate permanently denied permission
/// permissions.setPermanentlyDenied(true);
/// permissions.setAutoGrantOnRequest(false);
/// await permissions.request();
/// expect(await permissions.check(), false);
/// ```
class FakeBlePermissions implements BlePermissions {
  bool _hasPermission = false;
  bool _isPermanentlyDenied = false;
  bool _isLocationServiceEnabled = true;
  bool _autoGrantOnRequest = true;

  /// Number of times [request] has been called.
  ///
  /// Useful for verifying that permission requests happen at the right time
  /// in tests.
  int requestCallCount = 0;

  /// Number of times [openSettings] has been called.
  ///
  /// Useful for verifying that the app correctly guides users to settings
  /// when permissions are permanently denied.
  int openSettingsCallCount = 0;

  @override
  Future<bool> check() async {
    return _hasPermission;
  }

  @override
  Future<bool> request() async {
    requestCallCount++;

    // If permanently denied, request does nothing
    if (_isPermanentlyDenied) {
      return false;
    }

    // Auto-grant by default (can be disabled for testing denials)
    if (_autoGrantOnRequest) {
      _hasPermission = true;
    }

    return _hasPermission;
  }

  @override
  Future<bool> isPermanentlyDenied() async {
    return _isPermanentlyDenied;
  }

  @override
  Future<bool> isLocationServiceEnabled() async {
    return _isLocationServiceEnabled;
  }

  @override
  Future<void> openSettings() async {
    openSettingsCallCount++;
  }

  // Test control methods

  /// Set whether the app has BLE permissions.
  ///
  /// When true, [check] returns true. When false, [check] returns false.
  // ignore: use_setters_to_change_properties
  void setHasPermission(bool value) {
    _hasPermission = value;
  }

  /// Set whether permissions are permanently denied.
  ///
  /// When true:
  /// - [isPermanentlyDenied] returns true
  /// - [request] returns false and doesn't grant permission
  /// - User must call [openSettings] to manually grant permissions
  // ignore: use_setters_to_change_properties
  void setPermanentlyDenied(bool value) {
    _isPermanentlyDenied = value;
  }

  /// Set whether location services are enabled.
  ///
  /// On Android, location services must be enabled for BLE scanning to work,
  /// even when using Android 12+ Bluetooth permissions.
  // ignore: use_setters_to_change_properties
  void setLocationServiceEnabled(bool value) {
    _isLocationServiceEnabled = value;
  }

  /// Control whether [request] automatically grants permission.
  ///
  /// When true (default), calling [request] sets [_hasPermission] to true,
  /// simulating the user granting permission.
  ///
  /// When false, [request] doesn't change permission state, allowing tests
  /// to verify behavior when users deny permission.
  // ignore: use_setters_to_change_properties
  void setAutoGrantOnRequest(bool value) {
    _autoGrantOnRequest = value;
  }
}
