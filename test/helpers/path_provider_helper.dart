import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// Fake PathProviderPlatform for testing.
///
/// Creates subdirectories for each path type under a base temp directory.
class FakePathProviderPlatform extends PathProviderPlatform {
  late final Directory baseDir;

  FakePathProviderPlatform() {
    baseDir = Directory.systemTemp.createTempSync('vekolo_test_');
  }

  @override
  Future<String?> getTemporaryPath() async {
    return _setUpPath('temporary').path;
  }

  @override
  Future<String?> getApplicationSupportPath() async {
    return _setUpPath('applicationSupport').path;
  }

  @override
  Future<String?> getLibraryPath() async {
    return _setUpPath('library').path;
  }

  @override
  Future<String?> getApplicationDocumentsPath() async {
    return _setUpPath('applicationDocuments').path;
  }

  @override
  Future<String?> getExternalStoragePath() async {
    return _setUpPath('externalStorage').path;
  }

  @override
  Future<List<String>?> getExternalCachePaths() async {
    final path = _setUpPath('externalCache').path;
    return <String>[path];
  }

  @override
  Future<List<String>?> getExternalStoragePaths({
    StorageDirectory? type,
  }) async {
    final path = _setUpPath('externalStorage').path;
    return <String>[path];
  }

  @override
  Future<String?> getDownloadsPath() async {
    return _setUpPath('downloads').path;
  }

  Directory _setUpPath(String directory) {
    final dir = Directory('${baseDir.path}/$directory');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }
}

/// Setup path_provider with a temporary directory for testing.
///
/// Returns the base temporary directory that will be automatically cleaned up
/// via addTearDown.
///
/// Example:
/// ```dart
/// test('my test', () async {
///   final tempDir = await setupPathProvider();
///   // Test code that uses path_provider...
/// });
/// ```
Future<Directory> setupPathProvider() async {
  final platform = FakePathProviderPlatform();
  PathProviderPlatform.instance = platform;

  addTearDown(() async {
    if (await platform.baseDir.exists()) {
      await platform.baseDir.delete(recursive: true);
    }
  });

  return platform.baseDir;
}
