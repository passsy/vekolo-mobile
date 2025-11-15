import 'package:pubspec_manager/pubspec_manager.dart';
import 'package:sidekick_core/sidekick_core.dart';
import 'package:vekolo_sidekick/src/commands/build_vekolo/android_build_config.dart';
import 'package:vekolo_sidekick/src/commands/build_vekolo/bootstrap/bootstrap_command.dart';
import 'package:vekolo_sidekick/src/commands/build_vekolo/distribute/android_build_spec.dart';
import 'package:vekolo_sidekick/src/commands/build_vekolo/distribute/distribution.dart';

class BuildAndroidCommand extends Command {
  @override
  String get description => 'Build the application for Android';

  @override
  String get name => 'android';

  static List<AndroidDistribution> get _allowedDistributions =>
      availableAndroidDistributionSpecs.map((spec) => spec.distribution).toList();

  BuildAndroidCommand() {
    argParser.addOption(
      'distribution',
      allowed: _allowedDistributions.map((it) => it.name),
      help: 'Where this build should be distributed, that decides which signing key to use',
    );
    argParser.addFlag('clean', help: 'Run flutter clean before building', defaultsTo: true);
    argParser.addOption(
      'outputFormat',
      help: 'The output format',
      allowed: AndroidOutputFormat.values.map((it) => it.name),
      defaultsTo: AndroidOutputFormat.apk.name,
    );
    argParser.addOption(
      'signingConfig',
      help: 'How to sign the app',
      allowed: SigningConfig.values.map((it) => it.name),
    );
  }

  late final Directory _releaseDir = mainProject!.buildDir.directory('release');

  AndroidDistribution? get distribution {
    final value = argResults!['distribution'] as String?;
    return _allowedDistributions.firstOrNullWhere((element) => element.name == value);
  }

  AndroidOutputFormat outputFormat(AndroidDistributionSpec spec) {
    final value = argResults!['outputFormat'] as String?;
    return AndroidOutputFormat.values.firstOrNullWhere((element) => element.name == value) ??
        spec.build.defaultOutputFormat;
  }

  SigningConfig? get signingConfig {
    final value = argResults!['signingConfig'] as String?;
    return SigningConfig.values.firstOrNullWhere((element) => element.name == value);
  }

  /// Use the signingConfig argument if provided, otherwise use the default signing config for the distribution
  SigningConfig resolvedSigningConfig(AndroidDistributionSpec spec) {
    if (signingConfig != null) {
      return signingConfig!;
    }
    return spec.build.defaultSigningConfig;
  }

  String releaseName(AndroidDistributionSpec spec, String buildNumber) {
    final File versionFile = mainProject!.pubspec;
    final version = PubSpec.loadFromPath(versionFile.absolute.path).version.semVersion;

    return 'vekolo-'
        '${distribution!.name}-'
        '${version.major}.${version.minor}.${version.patch}-'
        '$buildNumber-'
        '${resolvedSigningConfig(spec).name}';
  }

  @override
  Future<void> run() async {
    if (distribution == null) {
      print(
        'No --distribution specified, '
        'use one of ${_allowedDistributions.joinToString(transform: (it) => it.name)}',
      );
      return;
    }

    // resolve distribution spec
    final specMap = Map.fromEntries(availableAndroidDistributionSpecs.map((s) => MapEntry(s.distribution, s)));
    final spec = specMap[distribution]!;
    final signing = resolvedSigningConfig(spec);
    setSigningConfig(signing);

    // load signing passwords to env if available
    if (signing == SigningConfig.playUpload) {
      if (spec.build.storePasswordProvider != null) {
        env['ANDROID_PLAY_STORE_PASSWORD'] = spec.build.storePasswordProvider!();
      }
      if (spec.build.keyPasswordProvider != null) {
        env['ANDROID_PLAY_KEY_PASSWORD'] = spec.build.keyPasswordProvider!();
      }
    }
    if (signing == SigningConfig.adHoc) {
      if (spec.build.storePasswordProvider != null) {
        env['ANDROID_ADHOC_STORE_PASSWORD'] = spec.build.storePasswordProvider!();
      }
      if (spec.build.keyPasswordProvider != null) {
        env['ANDROID_ADHOC_KEY_PASSWORD'] = spec.build.keyPasswordProvider!();
      }
    }
    // dev uses hardcoded credentials, no need to set env vars

    final shouldClean = argResults!['clean'] as bool;

    // Changing the env isn't picked up by the gradle plugin without cleaning
    if (shouldClean) {
      await flutter(['clean']);
    }

    final currentOutputFormat = outputFormat(spec);
    print('Building Android app (${currentOutputFormat.name}) in release mode...');
    if (_releaseDir.existsSync()) {
      _releaseDir.deleteSync(recursive: true);
    }

    bootstrap(distribution!, os: OperatingSystem.android);

    final buildNumber = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final mainDartFile = spec.build.mainDartFile;

    await flutter(
      [
        'build',
        currentOutputFormat.name,
        '--target=$mainDartFile',
        '--build-number=$buildNumber',
        '--dart-define=DISTRIBUTION=${distribution!.name}',
        '--dart-define=BUILDNUMBER=$buildNumber',
      ],
      workingDirectory: mainProject!.root,
    );

    switch (currentOutputFormat) {
      case AndroidOutputFormat.apk:
        final File apk = mainProject!.buildDir.file('app/outputs/flutter-apk/app-release.apk');
        final outputLocation = _copyApkToReleaseDir(apk, spec, buildNumber: buildNumber.toString());
        env['ANDROID_APK_PATH'] = outputLocation.absolute.path;
        print(green('Successfully built APK: ${outputLocation.absolute.path}'));
      case AndroidOutputFormat.aab:
        final File aab = mainProject!.buildDir.file('app/outputs/bundle/release/app-release.aab');
        final outputLocation = _copyAabToReleaseDir(aab, spec, buildNumber: buildNumber.toString());
        env['ANDROID_AAB_PATH'] = outputLocation.absolute.path;
        print(green('Successfully built AAB: ${outputLocation.absolute.path}'));
    }

    // cleanup, return to defaults
    bootstrap(AndroidDistribution.dev, os: OperatingSystem.android);
    setSigningConfig(SigningConfig.dev);
  }

  /// Place the apk properly named in the /build/release directory
  File _copyApkToReleaseDir(File apkFile, AndroidDistributionSpec spec, {required String buildNumber}) {
    _releaseDir.createSync(recursive: true);
    final releaseApk = _releaseDir.file('${releaseName(spec, buildNumber)}.apk');
    apkFile.copySync(releaseApk.absolute.path);
    return releaseApk;
  }

  /// Place the aab properly named in the /build/release directory
  File _copyAabToReleaseDir(File aabFile, AndroidDistributionSpec spec, {required String buildNumber}) {
    _releaseDir.createSync(recursive: true);
    final releaseAab = _releaseDir.file('${releaseName(spec, buildNumber)}.aab');
    aabFile.copySync(releaseAab.absolute.path);
    return releaseAab;
  }
}
