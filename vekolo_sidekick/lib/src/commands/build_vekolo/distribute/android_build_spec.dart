import 'package:sidekick_core/sidekick_core.dart';
import 'package:vekolo_sidekick/src/commands/build_vekolo/distribute/distribution.dart';
import 'package:vekolo_sidekick/vekolo_sidekick.dart';

enum AndroidOutputFormat { apk, aab }

/// See android/app/build.gradle.kts (android.signingConfigs)
enum SigningConfig {
  /// Development signing (hardcoded credentials)
  dev,

  /// Play Store upload signing (credentials from env/vault)
  playUpload,

  /// Ad-hoc APK distribution signing (credentials from env/vault)
  adHoc,

  /// No signing
  unsigned,
}

/// Complete distribution specification for Android
class AndroidDistributionSpec {
  final AndroidDistribution distribution;
  final AndroidBootstrapSpecs bootstrap;
  final AndroidBuildSpecs build;
  final AndroidDeploySpecs? deploy;

  AndroidDistributionSpec({required this.distribution, required this.bootstrap, required this.build, this.deploy});
}

/// Bootstrap configuration for Android distributions
class AndroidBootstrapSpecs {
  /// Human readable app name that may be shown in system UIs
  final String appName;

  /// The Android applicationId used in Gradle
  final String applicationId;

  AndroidBootstrapSpecs({required this.appName, required this.applicationId});
}

/// Build configuration for Android distributions
class AndroidBuildSpecs {
  /// Default output format when not specified on CLI
  final AndroidOutputFormat defaultOutputFormat;

  /// Default signing config for this distribution
  final SigningConfig defaultSigningConfig;

  /// The main entrypoint to use for this distribution
  final String mainDartFile;

  /// Signing store password provider (loaded from vault or env)
  final String Function()? storePasswordProvider;

  /// Signing key password provider (loaded from vault or env)
  final String Function()? keyPasswordProvider;

  AndroidBuildSpecs({
    required this.defaultOutputFormat,
    required this.defaultSigningConfig,
    this.mainDartFile = 'lib/main.dart',
    this.storePasswordProvider,
    this.keyPasswordProvider,
  });
}

/// Deploy configuration for Android distributions
class AndroidDeploySpecs {
  /// Service account JSON file provider for Google Play deployment
  final File Function()? serviceAccountFileProvider;

  /// Track to upload to (e.g., 'internal', 'alpha', 'beta', 'production')
  final String? playStoreTrack;

  AndroidDeploySpecs({this.serviceAccountFileProvider, this.playStoreTrack});
}

/// Available Android distribution specifications
final List<AndroidDistributionSpec> availableAndroidDistributionSpecs = [
  // Development
  AndroidDistributionSpec(
    distribution: AndroidDistribution.dev,
    bootstrap: AndroidBootstrapSpecs(appName: 'Vekolo Dev', applicationId: 'cc.vekolo.dev'),
    build: AndroidBuildSpecs(
      defaultOutputFormat: AndroidOutputFormat.apk,
      defaultSigningConfig: SigningConfig.dev,
      // Dev uses hardcoded credentials in build.gradle.kts
      // ignore: avoid_redundant_argument_values
      storePasswordProvider: null,
      // ignore: avoid_redundant_argument_values
      keyPasswordProvider: null,
    ),
  ),

  // Staging - uses ad-hoc signing for APK distribution
  AndroidDistributionSpec(
    distribution: AndroidDistribution.staging,
    bootstrap: AndroidBootstrapSpecs(appName: 'Vekolo Staging', applicationId: 'cc.vekolo.staging'),
    build: AndroidBuildSpecs(
      defaultOutputFormat: AndroidOutputFormat.apk,
      defaultSigningConfig: SigningConfig.adHoc,
      storePasswordProvider: () => env['ANDROID_ADHOC_STORE_PASSWORD'] ?? '',
      keyPasswordProvider: () => env['ANDROID_ADHOC_KEY_PASSWORD'] ?? '',
    ),
    deploy: AndroidDeploySpecs(
      playStoreTrack: 'internal',
      serviceAccountFileProvider: () => vault.loadFile('android_service_account.json.gpg'),
    ),
  ),

  // Production - uses play-upload signing for AAB
  AndroidDistributionSpec(
    distribution: AndroidDistribution.prod,
    bootstrap: AndroidBootstrapSpecs(appName: 'Vekolo', applicationId: 'cc.vekolo'),
    build: AndroidBuildSpecs(
      defaultOutputFormat: AndroidOutputFormat.aab,
      defaultSigningConfig: SigningConfig.playUpload,
      storePasswordProvider: () => env['ANDROID_PLAY_STORE_PASSWORD'] ?? '',
      keyPasswordProvider: () => env['ANDROID_PLAY_KEY_PASSWORD'] ?? '',
    ),
    deploy: AndroidDeploySpecs(
      playStoreTrack: 'production',
      serviceAccountFileProvider: () => vault.loadFile('android_service_account.json.gpg'),
    ),
  ),
];
