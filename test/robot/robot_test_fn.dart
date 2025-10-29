import 'dart:async';

import 'package:flutter/animation.dart';
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
