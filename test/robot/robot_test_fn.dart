import 'dart:async';

import 'package:flutter/animation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

// ignore: depend_on_referenced_packages
import 'package:meta/meta.dart';
import 'package:clock/clock.dart';
import 'package:spot/spot.dart';

// ignore: depend_on_referenced_packages
import 'package:test_api/src/backend/invoker.dart';

import 'vekolo_robot.dart';

@isTest
void robotTest(
  String description,
  Future<void> Function(VekoloRobot robot) callback, {
  bool? skip,
  Timeout? timeout,
  bool semanticsEnabled = true,
  dynamic tags,
}) {
  final List<dynamic Function()> flutterTearDowns = [() => _lastTestStartTime = null];

  testWidgets(
    description,
    (tester) async {
      return runZoned(() async {
        try {
          final robot = VekoloRobot(tester: tester);
          await callback(robot);

          runApp(Container(key: UniqueKey()));
          await tester.pump();
          // await Future.delayed(Duration(milliseconds: 100));
        } catch (e) {
          // In case of an error, Flutter does not cleanup the widget tree.
          // (see: TestWidgetsFlutterBinding._runTestBody)
          // This is required, so that all widget dispose methods are called, and all subscriptions to plugins are canceled.
          // Only then channel.setMockMethodCallHandler can be set to null. without causing all following test to fail

          // Unmount any remaining widgets.
          runApp(Container(key: UniqueKey(), child: _postTestErrorMessage(e)));
          await tester.pump();
          rethrow;
        } finally {
          await Invoker.current!.runTearDowns(flutterTearDowns);
          flutterTearDowns.clear();
        }
      }, zoneValues: {#flutter_test.teardowns: flutterTearDowns});
    },
    skip: skip,
    timeout: timeout,
    semanticsEnabled: semanticsEnabled,
    tags: tags,
  );
}

DateTime? _lastTestStartTime;
void addRobotEvent(String message, {bool isError = false}) {
  _lastTestStartTime ??= clock.now();
  final duration = clock.now().difference(_lastTestStartTime!);

  final type = isError ? 'Robot Error' : 'Robot';
  final formatted = '$type [${duration.inSeconds}s]: $message';
  // ignore: avoid_print
  print(formatted);
  final color = isError ? const Color(0xFFA31616) : const Color(0xFF166316);
  timeline.addEvent(details: formatted, eventType: type, color: color);
  if (isError) {
    throw message;
  }
}

Widget _postTestErrorMessage(Object e) {
  return Center(
    child: Text(
      'Test errored with $e',
      style: const TextStyle(color: Color(0xFF917FFF), fontSize: 40.0),
      textDirection: TextDirection.ltr,
    ),
  );
}

/// A special version of [addTearDown] that is executed before [testWidgets] completes.
///
/// Only to be used in conjunction with [robotTest].
///
/// It is required for configurations that need to be reset before the flutter test finishes, like:
///
/// - [debugDefaultTargetPlatformOverride]
/// - [debugImageOverheadAllowance]
/// - [debugInvertOversizedImages]
/// - [debugOnPaintImage]
/// - [debugNetworkImageHttpClientProvider]
void addFlutterTearDown(dynamic Function() callback) {
  if (Invoker.current == null) {
    throw StateError('addFlutterTearDown() may only be called within a test.');
  }

  final list = Zone.current[#flutter_test.teardowns] as List?;
  if (list == null) {
    throw StateError('addFlutterTearDown() may only be called within using testWidgets2');
  }
  list.add(callback);
}
