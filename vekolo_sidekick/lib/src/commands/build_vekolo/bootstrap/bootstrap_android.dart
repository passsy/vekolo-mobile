import 'package:sidekick_core/sidekick_core.dart';
import 'package:vekolo_sidekick/src/commands/build_vekolo/distribute/android_build_spec.dart';

/// Bootstraps the Android project for development or distribution.
void bootstrapAndroid(AndroidDistributionSpec spec) {
  final androidDir = mainProject!.root.directory('android');
  setAndroidApplicationId(androidDir, spec.bootstrap.applicationId);
  setAndroidAppName(androidDir, spec.bootstrap.appName);
}

void setAndroidApplicationId(Directory androidDir, String applicationId) {
  print('Setting applicationId to "$applicationId"');
  final File buildGradle = androidDir.file('app/build.gradle.kts');
  buildGradle.replaceSectionWith(
    startTag: 'applicationId = "',
    endTag: '"',
    content: applicationId,
  );
}

void setAndroidAppName(Directory androidDir, String appName) {
  print('Setting Android app name to "$appName"');
  final File stringsXml = androidDir.file(
    'app/src/main/res/values/strings.xml',
  );

  if (!stringsXml.existsSync()) {
    // Create strings.xml if it doesn't exist
    stringsXml.parent.createSync(recursive: true);
    stringsXml.writeAsStringSync('''
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="app_name">$appName</string>
</resources>
''');
  } else {
    // Update existing strings.xml
    stringsXml.replaceSectionWith(
      startTag: '<string name="app_name">',
      endTag: '</string>',
      content: appName,
    );
  }
}
