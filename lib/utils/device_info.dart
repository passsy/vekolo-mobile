import 'package:vekolo/app/logger.dart';
import 'dart:io' if (dart.library.html) 'dart:html';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Utility for getting device information
class DeviceInfoUtil {
  /// Gets the device name/model
  ///
  /// Returns a string like "iPhone 15 Pro", "Pixel 8", etc.
  /// For web, returns browser name like "Chrome", "Firefox", etc.
  /// Falls back to "Flutter App" if unable to determine device info
  static Future<String> getDeviceName() async {
    try {
      final _deviceInfo = DeviceInfoPlugin();
      if (kIsWeb) {
        final webInfo = await _deviceInfo.webBrowserInfo;
        // Returns browser name like "Chrome", "Firefox", "Safari", etc.
        final browserName = webInfo.browserName.name;
        // Capitalize first letter
        return browserName.substring(0, 1).toUpperCase() + browserName.substring(1);
      } else if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        // Returns something like "Pixel 8" or "Samsung Galaxy S24"
        return androidInfo.model;
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        // Returns something like "iPhone 15 Pro"
        return iosInfo.utsname.machine;
      } else if (Platform.isMacOS) {
        final macOsInfo = await _deviceInfo.macOsInfo;
        return macOsInfo.model;
      } else if (Platform.isWindows) {
        final windowsInfo = await _deviceInfo.windowsInfo;
        return windowsInfo.computerName;
      } else if (Platform.isLinux) {
        final linuxInfo = await _deviceInfo.linuxInfo;
        return linuxInfo.prettyName;
      }
    } catch (e, stackTrace) {
      talker.error(
        'Error getting device info: $e',
        e,
        stackTrace,
      );
    }

    // Fallback
    return 'Flutter App';
  }
}
