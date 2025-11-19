import 'package:phntmxyz_ios_publishing_sidekick_plugin/phntmxyz_ios_publishing_sidekick_plugin.dart';
import 'package:sidekick_core/sidekick_core.dart';
import 'package:vekolo_sidekick/src/commands/build_vekolo/distribute/ios_build_spec.dart';

/// Bootstraps the iOS project for development or distribution.
void bootstrapIos(IosDistributionSpec spec) {
  final pbxproj = XcodePbxproj(mainProject!.root.file('ios/Runner.xcodeproj/project.pbxproj'));

  pbxproj.setBundleIdentifier(spec.bootstrap.bundleId);
  pbxproj.setProvisioningProfileSpecifier(spec.bootstrap.provisioningProfileSpecifier);
  setIosAppName(spec.bootstrap.appName);
}

void setIosAppName(String appName) {
  print('Setting iOS app name to "$appName"');
  final File infoPlist = mainProject!.root.file('ios/Runner/Info.plist');

  if (infoPlist.existsSync()) {
    final content = infoPlist.readAsStringSync();
    // Check if CFBundleDisplayName already exists
    if (content.contains('<key>CFBundleDisplayName</key>')) {
      // Update existing CFBundleDisplayName
      final lines = content.split('\n');
      final updatedLines = <String>[];

      for (int i = 0; i < lines.length; i++) {
        updatedLines.add(lines[i]);
        if (lines[i].contains('<key>CFBundleDisplayName</key>')) {
          // Replace the next line (the value)
          if (i + 1 < lines.length) {
            i++;
            updatedLines.add('\t<string>$appName</string>');
          }
        }
      }

      infoPlist.writeAsStringSync(updatedLines.join('\n'));
    } else {
      // Add CFBundleDisplayName after CFBundleName
      final lines = content.split('\n');
      final updatedLines = <String>[];

      for (int i = 0; i < lines.length; i++) {
        updatedLines.add(lines[i]);
        if (lines[i].contains('<key>CFBundleName</key>')) {
          // Skip the next line (value) and add our key/value pair after
          if (i + 1 < lines.length) {
            i++;
            updatedLines.add(lines[i]);
            updatedLines.add('\t<key>CFBundleDisplayName</key>');
            updatedLines.add('\t<string>$appName</string>');
          }
        }
      }

      infoPlist.writeAsStringSync(updatedLines.join('\n'));
    }
  }
}
