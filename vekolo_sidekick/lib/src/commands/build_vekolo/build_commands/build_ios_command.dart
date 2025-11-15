import 'dart:io';

import 'package:phntmxyz_ios_publishing_sidekick_plugin/phntmxyz_ios_publishing_sidekick_plugin.dart';
import 'package:pubspec_manager/pubspec_manager.dart';
import 'package:sidekick_core/sidekick_core.dart';
import 'package:vekolo_sidekick/src/commands/build_vekolo/bootstrap/bootstrap_command.dart';
import 'package:vekolo_sidekick/src/commands/build_vekolo/distribute/distribution.dart';
import 'package:vekolo_sidekick/src/commands/build_vekolo/distribute/ios_build_spec.dart';
import 'package:vekolo_sidekick/vekolo_sidekick.dart';

class BuildIosCommand extends Command {
  @override
  String get description => 'Build the application for iOS';

  @override
  String get name => 'ios';

  static List<IosDistribution> get _allowedDistributions =>
      availableIosDistributionSpecs.map((spec) => spec.distribution).toList();

  BuildIosCommand() {
    argParser.addFlag(
      'new-keychain',
      help: 'Creates a new keychain for this build, useful on CI',
      defaultsTo: null,
    );
    argParser.addFlag(
      'clean',
      help: 'Run flutter clean before building',
      defaultsTo: true,
    );
    argParser.addOption(
      'distribution',
      allowed: _allowedDistributions.map((it) => it.name),
      help: 'Where this build should be distributed, that decides which signing key to use',
    );
  }

  late final Directory _releaseDir = mainProject!.buildDir.directory('release');

  @override
  Future<void> run() async {
    if (!Platform.isMacOS) {
      throw "building the iOS app only works on macOS, not ${Platform.operatingSystem}";
    }

    final distributionArg = argResults!['distribution'] as String?;
    final distribution = _allowedDistributions.firstOrNullWhere((element) => element.name == distributionArg);
    if (distribution == null) {
      print(
        'No --distribution specified, '
        'use one of ${_allowedDistributions.joinToString(transform: (it) => it.name)}',
      );
      return;
    }

    vault.unlock();

    final shouldClean = argResults!['clean'] as bool;

    // Prevent any xcode leftovers from previous builds. It may use debug artifacts for the release build
    if (shouldClean) {
      await flutter(['clean'], workingDirectory: mainProject!.root);
    }

    print('Building iOS app (ipa)');
    if (!mainProject!.buildDir.existsSync()) {
      mainProject!.buildDir.createSync();
    }
    if (_releaseDir.existsSync()) {
      _releaseDir.deleteSync(recursive: true);
    }

    // resolve distribution spec
    final specMap = Map.fromEntries(availableIosDistributionSpecs.map((s) => MapEntry(s.distribution, s)));
    final spec = specMap[distribution]!;

    // Bootstrap for the target distribution
    bootstrap(distribution, os: OperatingSystem.ios);

    final buildNumber = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    print('Build number: $buildNumber');
    final mainDartFile = spec.build.mainDartFile;
    print('Entry point: $mainDartFile');

    // Load iOS dependencies and build dart source
    await flutter(
      [
        'build',
        'ios',
        '--target=$mainDartFile',
        '--config-only',
        '--build-number=$buildNumber',
        '--no-codesign',
        '--dart-define=DISTRIBUTION=${distribution.name}',
        '--dart-define=BUILDNUMBER=$buildNumber',
      ],
      workingDirectory: mainProject!.root,
    );

    bool? newKeychain = argResults!['new-keychain'] as bool?;
    newKeychain ??= env['CI'] == 'true' || spec.build.createNewKeychainByDefault;

    // Build the ipa with manual signing
    final ipa = await buildIpa(
      bundleIdentifier: spec.bootstrap.bundleId,
      provisioningProfile: spec.build.provisioningProfileProvider(),
      certificate: spec.build.certificateProvider(),
      certificatePassword: spec.build.certificatePasswordProvider?.call(),
      method: spec.build.exportMethod,
      newKeychain: newKeychain,
      package: mainProject,
    );

    final File releaseIpa = _copyIpaToReleaseDir(ipa, buildNumber: buildNumber.toString());
    env['IOS_IPA_PATH'] = releaseIpa.absolute.path;
    print(green('Successfully built IPA: ${releaseIpa.absolute.path}'));

    // cleanup - reset to dev configuration
    bootstrap(IosDistribution.dev, os: OperatingSystem.ios);
  }

  /// Place the ipa properly named in the /build/release directory
  File _copyIpaToReleaseDir(File ipaFile, {required String buildNumber}) {
    final File versionFile = mainProject!.pubspec;
    final pubSpec = PubSpec.loadFromPath(versionFile.absolute.path);
    final version = pubSpec.version;
    _releaseDir.createSync(recursive: true);
    final releaseIpa = _releaseDir.file('vekolo-${version.semVersion}-$buildNumber.ipa');
    ipaFile.copySync(releaseIpa.absolute.path);
    return releaseIpa;
  }
}
