/// API configuration for different environments
class ApiConfig {
  static const String devBaseUrl = 'https://vekolo-development.up.railway.app';
  static const String stagingBaseUrl = 'https://vekolo-staging.up.railway.app';
  static const String productionBaseUrl = 'https://vekolo.cc';

  /// Get the base URL for the current environment
  /// For now, always returns dev URL. Can be extended with flavor support.
  static String get baseUrl => productionBaseUrl;
}
