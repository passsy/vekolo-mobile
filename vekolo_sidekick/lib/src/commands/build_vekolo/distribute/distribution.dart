/// iOS distribution targets
enum IosDistribution {
  /// Development environment
  dev,

  /// Staging environment for testing before production
  staging,

  /// Production - The iOS app in the App Store
  prod,
}

/// Android distribution targets
enum AndroidDistribution {
  /// Development environment
  dev,

  /// Staging environment for testing before production
  staging,

  /// Production - The Android app in the Play Store
  prod,
}

enum OperatingSystem {
  android,
  ios,
}
