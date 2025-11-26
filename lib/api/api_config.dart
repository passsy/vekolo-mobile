import 'package:flutter/foundation.dart';

/// API configuration for different environments
class ApiConfig {
  static const String devBaseUrl = 'https://vekolo-development.up.railway.app';
  static const String stagingBaseUrl = 'https://vekolo-staging.up.railway.app';
  static const String productionBaseUrl = 'https://vekolo.cc';

  /// Get the base URL for the current environment
  /// Uses dart-define DISTRIBUTION to determine which environment to use.
  /// Falls back to production if not specified.
  static String get baseUrl {
    const distribution = String.fromEnvironment('DISTRIBUTION', defaultValue: 'prod');
    switch (distribution) {
      case 'dev':
        return devBaseUrl;
      case 'staging':
        return stagingBaseUrl;
      case 'prod':
      default:
        if (kDebugMode) {
          return stagingBaseUrl;
        } else {
          return productionBaseUrl;
        }
    }
  }
}
