import 'package:vekolo/ble/ble_permissions.dart';

/// Fake implementation of [BlePermissions] for testing.
///
/// Uses the override pattern where each method can be customized via
/// nullable function fields. By default, provides sensible defaults
/// (permissions granted, location enabled).
///
/// Example usage:
/// ```dart
/// final permissions = FakeBlePermissions();
/// final scanner = BleScanner(permissions: permissions);
///
/// // Customize behavior for specific test
/// permissions.overrideCheck = () async => false;
/// expect(await permissions.check(), false);
///
/// // Simulate permission request that gets denied
/// permissions.overrideRequest = () async => false;
/// await permissions.request();
///
/// // Simulate permanently denied permission
/// permissions.overrideIsPermanentlyDenied = () async => true;
/// expect(await permissions.isPermanentlyDenied(), true);
/// ```
class FakeBlePermissions implements BlePermissions {
  // Internal state for default behavior
  bool _hasPermission = true;
  bool _isPermanentlyDenied = false;
  bool _isLocationServiceEnabled = true;

  /// Number of times [request] has been called.
  int requestCallCount = 0;

  /// Number of times [openSettings] has been called.
  int openSettingsCallCount = 0;

  Future<bool> Function()? overrideCheck;

  @override
  Future<bool> check() async {
    if (overrideCheck != null) {
      return overrideCheck!();
    }
    // Default: return internal state
    return _hasPermission;
  }

  Future<bool> Function()? overrideRequest;

  @override
  Future<bool> request() async {
    requestCallCount++;
    if (overrideRequest != null) {
      return overrideRequest!();
    }
    // Default: grant permission if not permanently denied
    if (_isPermanentlyDenied) {
      return false;
    }
    _hasPermission = true;
    return true;
  }

  Future<bool> Function()? overrideIsPermanentlyDenied;

  @override
  Future<bool> isPermanentlyDenied() async {
    if (overrideIsPermanentlyDenied != null) {
      return overrideIsPermanentlyDenied!();
    }
    // Default: return internal state
    return _isPermanentlyDenied;
  }

  Future<bool> Function()? overrideIsLocationServiceEnabled;

  @override
  Future<bool> isLocationServiceEnabled() async {
    if (overrideIsLocationServiceEnabled != null) {
      return overrideIsLocationServiceEnabled!();
    }
    // Default: return internal state
    return _isLocationServiceEnabled;
  }

  Future<void> Function()? overrideOpenSettings;

  @override
  Future<void> openSettings() async {
    openSettingsCallCount++;
    if (overrideOpenSettings != null) {
      return overrideOpenSettings!();
    }
    // Default: no-op
  }

  // Convenience methods for setting internal state
  // These are simpler than setting override functions for common cases

  // ignore: use_setters_to_change_properties
  void setHasPermission(bool value) {
    _hasPermission = value;
  }

  // ignore: use_setters_to_change_properties
  void setPermanentlyDenied(bool value) {
    _isPermanentlyDenied = value;
  }

  // ignore: use_setters_to_change_properties
  void setLocationServiceEnabled(bool value) {
    _isLocationServiceEnabled = value;
  }
}
