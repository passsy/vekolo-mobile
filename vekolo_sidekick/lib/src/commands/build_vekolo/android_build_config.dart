import 'package:sidekick_core/sidekick_core.dart';
import 'package:vekolo_sidekick/src/commands/build_vekolo/distribute/android_build_spec.dart';

/// Enable or disable app signing based on the distribution.
void setSigningConfig(SigningConfig signingConfig) {
  final File buildGradle = mainProject!.root.directory('android').file('app/build.gradle.kts');

  if (signingConfig == SigningConfig.unsigned) {
    print("Configure APK/AAB to be unsigned");
    buildGradle.replaceSectionWith(
      startTag: '// begin: release signingConfig',
      endTag: '// end: release signingConfig',
      content: '''

            // unsigned
            ''',
    );
  } else {
    // Convert enum name to gradle config name (playUpload -> play-upload, adHoc -> ad-hoc)
    final configName = switch (signingConfig) {
      SigningConfig.dev => 'dev',
      SigningConfig.playUpload => 'play-upload',
      SigningConfig.adHoc => 'ad-hoc',
      SigningConfig.unsigned => throw 'unsigned handled above',
    };
    print("Configure release signingConfig $configName");
    buildGradle.replaceSectionWith(
      startTag: '// begin: release signingConfig',
      endTag: '// end: release signingConfig',
      content: '''

            signingConfig = signingConfigs.getByName("$configName")
            ''',
    );
  }
}
