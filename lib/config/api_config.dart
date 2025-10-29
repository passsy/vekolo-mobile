/// API configuration for different environments
class ApiConfig {
  static const String devBaseUrl = 'https://vekolo-development.up.railway.app';

  /// Get the base URL for the current environment
  /// For now, always returns dev URL. Can be extended with flavor support.
  static String get baseUrl => devBaseUrl;
}
