import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';

import 'robot/robot_kit.dart';

void main() {
  robotTest('verify file persistence across app launches', (robot) async {
    await robot.launchApp(loggedIn: true);

    // Get app documents directory
    final appDir = await getApplicationDocumentsDirectory();
    final testFile = File('${appDir.path}/test.txt');

    // Write a file
    await testFile.writeAsString('Hello from first launch');
    print('File created at: ${testFile.path}');
    print('File exists: ${await testFile.exists()}');

    // Close app
    await robot.closeApp();

    // Relaunch app
    await robot.launchApp(loggedIn: true);

    // Check if file still exists
    final appDir2 = await getApplicationDocumentsDirectory();
    final testFile2 = File('${appDir2.path}/test.txt');

    print('After relaunch - File path: ${testFile2.path}');
    print('After relaunch - File exists: ${await testFile2.exists()}');

    if (await testFile2.exists()) {
      final content = await testFile2.readAsString();
      print('File content: $content');
      expect(content, 'Hello from first launch');
    } else {
      fail('File should exist after relaunch but does not');
    }
  });
}
