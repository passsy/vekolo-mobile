import 'package:device_info_plus/device_info_plus.dart';
import 'package:chirp/chirp.dart';

/// Utility for getting device information
class DeviceInfoUtil {
  // Logger instance for static methods
  /// Gets the device name/model
  ///
  /// Returns a string like "iPhone 15 Pro", "Pixel 8", etc.
  /// For web, returns browser name like "Chrome", "Firefox", etc.
  /// Falls back to "Flutter App" if unable to determine device info
  static Future<String> getDeviceName() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      final info = await deviceInfo.deviceInfo;

      if (info is WebBrowserInfo) {
        // Returns browser name like "Chrome", "Firefox", "Safari", etc.
        final browserName = info.browserName.name;
        // Capitalize first letter
        return browserName.substring(0, 1).toUpperCase() + browserName.substring(1);
      }
      if (info is AndroidDeviceInfo) {
        // Returns something like "Pixel 8" or "Samsung Galaxy S24"
        return info.model;
      }
      if (info is IosDeviceInfo) {
        // Returns something like "iPhone 15 Pro"
        return info.utsname.machine;
      }
      if (info is MacOsDeviceInfo) {
        return info.model;
      }
      if (info is WindowsDeviceInfo) {
        return info.computerName;
      }
      if (info is LinuxDeviceInfo) {
        return info.prettyName;
      }
    } catch (e, stackTrace) {
      Chirp.error('Error getting device info', error: e, stackTrace: stackTrace);
    }

    // Fallback
    return 'Flutter App';
  }
}
