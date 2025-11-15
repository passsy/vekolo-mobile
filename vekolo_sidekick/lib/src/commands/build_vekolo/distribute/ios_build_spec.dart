import 'package:phntmxyz_ios_publishing_sidekick_plugin/phntmxyz_ios_publishing_sidekick_plugin.dart';
import 'package:sidekick_core/sidekick_core.dart';
import 'package:vekolo_sidekick/src/commands/build_vekolo/distribute/distribution.dart';
import 'package:vekolo_sidekick/vekolo_sidekick.dart';

/// Complete distribution specification for iOS
class IosDistributionSpec {
  final IosDistribution distribution;
  final IosBootstrapSpecs bootstrap;
  final IosBuildSpecs build;
  final IosDeploySpecs? deploy;

  IosDistributionSpec({
    required this.distribution,
    required this.bootstrap,
    required this.build,
    this.deploy,
  });
}

/// Bootstrap configuration for iOS distributions
class IosBootstrapSpecs {
  /// Human readable app name that may be shown in system UIs
  final String appName;

  /// The iOS bundle identifier
  final String bundleId;

  /// The provisioning profile specifier name as shown in Xcode
  final String provisioningProfileSpecifier;

  IosBootstrapSpecs({
    required this.appName,
    required this.bundleId,
    required this.provisioningProfileSpecifier,
  });
}

/// Build configuration for iOS distributions
class IosBuildSpecs {
  /// The main entrypoint to use for this distribution
  final String mainDartFile;

  /// Signing configuration
  final ProvisioningProfile Function() provisioningProfileProvider;
  final File Function() certificateProvider;
  final String Function()? certificatePasswordProvider;
  final ExportMethod exportMethod;
  final bool createNewKeychainByDefault;

  IosBuildSpecs({
    this.mainDartFile = 'lib/main.dart',
    required this.provisioningProfileProvider,
    required this.certificateProvider,
    this.certificatePasswordProvider,
    required this.exportMethod,
    this.createNewKeychainByDefault = false,
  });
}

/// Deploy configuration for iOS distributions
class IosDeploySpecs {
  /// App Store Connect API key for deployment
  final File Function()? apiKeyFileProvider;

  IosDeploySpecs({
    this.apiKeyFileProvider,
  });
}

/// Available iOS distribution specifications
final List<IosDistributionSpec> availableIosDistributionSpecs = [
  // Development
  IosDistributionSpec(
    distribution: IosDistribution.dev,
    bootstrap: IosBootstrapSpecs(
      appName: 'Vekolo Dev',
      bundleId: 'cc.vekolo.dev',
      provisioningProfileSpecifier: 'Vekolo Dev',
    ),
    build: IosBuildSpecs(
      exportMethod: ExportMethod.developerId,
      createNewKeychainByDefault: false,
      provisioningProfileProvider: () => vault.loadFile('ios_dev.mobileprovision.gpg').asProvisioningProfile(),
      certificateProvider: () => vault.loadFile('ios_dev.p12.gpg'),
      certificatePasswordProvider: () => env['IOS_DEV_CERT_PASSWORD'] ?? '',
    ),
  ),

  // Staging
  IosDistributionSpec(
    distribution: IosDistribution.staging,
    bootstrap: IosBootstrapSpecs(
      appName: 'Vekolo Staging',
      bundleId: 'cc.vekolo.staging',
      provisioningProfileSpecifier: 'Vekolo Staging',
    ),
    build: IosBuildSpecs(
      exportMethod: ExportMethod.appStoreConnect,
      createNewKeychainByDefault: true,
      provisioningProfileProvider: () => vault.loadFile('ios_staging.mobileprovision.gpg').asProvisioningProfile(),
      certificateProvider: () => vault.loadFile('ios_staging.p12.gpg'),
      certificatePasswordProvider: () => env['IOS_STAGING_CERT_PASSWORD'] ?? '',
    ),
    deploy: IosDeploySpecs(
      apiKeyFileProvider: () => vault.loadFile('appstore_api_key.json.gpg'),
    ),
  ),

  // Production
  IosDistributionSpec(
    distribution: IosDistribution.prod,
    bootstrap: IosBootstrapSpecs(
      appName: 'Vekolo',
      bundleId: 'cc.vekolo',
      provisioningProfileSpecifier: 'Vekolo',
    ),
    build: IosBuildSpecs(
      exportMethod: ExportMethod.appStoreConnect,
      createNewKeychainByDefault: true,
      provisioningProfileProvider: () => vault.loadFile('ios_prod.mobileprovision.gpg').asProvisioningProfile(),
      certificateProvider: () => vault.loadFile('ios_prod.p12.gpg'),
      certificatePasswordProvider: () => env['IOS_PROD_CERT_PASSWORD'] ?? '',
    ),
    deploy: IosDeploySpecs(
      apiKeyFileProvider: () => vault.loadFile('appstore_api_key.json.gpg'),
    ),
  ),
];
