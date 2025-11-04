/// Default profile values used when user profile data is not available.
///
/// These fallbacks ensure the app can function properly even when:
/// - User is not logged in
/// - User hasn't set their profile values yet
/// - Profile data fails to load
class ProfileDefaults {
  const ProfileDefaults._();

  /// Default FTP (Functional Threshold Power) in watts.
  ///
  /// This is a reasonable estimate for an average recreational cyclist.
  /// Users should update this in their profile for accurate workout targets.
  static const int ftp = 200;

  /// Default weight in kilograms.
  ///
  /// Used for power-to-weight calculations when user hasn't set their weight.
  static const int weight = 75;
}
