import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dartx/dartx_io.dart';

import 'my_fake_async.dart';
import 'robot_kit.dart';

void main() {
  robotTest('disk io sync', (robot) async {
    final systemTemp = Directory.systemTemp;
    final tempDir = systemTemp.createTempSync();
    final exists = tempDir.existsSync();
    expect(exists, isTrue);
    final file = tempDir.file('thing.txt');
    file.writeAsStringSync('contents');

    final content = file.readAsStringSync();
    expect(content, 'contents');
  });

  robotTest('disk io async', (tester) async {
    final systemTemp = Directory.systemTemp;
    final tempDir = await systemTemp.createTemp();
    final exists = await tempDir.exists();
    expect(exists, isTrue);
    final file = tempDir.file('thing.txt');
    await file.writeAsString('contents');

    final content = await file.readAsString();
    expect(content, 'contents');
  });

  robotTest('disk io async with runAsync', (robot) async {
    await robot.tester.runAsync(() async {
      final systemTemp = Directory.systemTemp;
      final tempDir = await systemTemp.createTemp();
      final exists = await tempDir.exists();
      expect(exists, isTrue);
      final file = tempDir.file('thing.txt');
      await file.writeAsString('contents');

      final content = await file.readAsString();
      expect(content, 'contents');
      print('end of runAsync');
    });
    print('after runAsync');
  });

  // https://github.com/dart-lang/test/issues/2310
  robotTest('stream close hangs', (robot) async {
    final streamController = Stream.value(1);
    print('hi before await');
    await streamController.toList();
    print('hi after await');
  });

  test('stream close normal test', () async {
    final streamController = Stream.value(1);
    print('hi before await');
    await streamController.toList();
    print('hi after await');
  });

  test('stream close normal test with fakeAsync', () async {
    await fakeAsync((async) async {
      final streamController = Stream.value(1);
      print('hi before await');
      await streamController.toList();
      print('hi after await');
    });
    print('after fakeAsync');
  }, skip: true);

  test('stream close normal test with myFakeAsync', () async {
    await myFakeAsync((async) async {
      final streamController = Stream.value(1);
      print('hi before await');
      await streamController.toList();
      print('hi after await');
    });
    print('after fakeAsync');
  });
}
