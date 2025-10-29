import 'dart:ui';

import 'package:context_plus/context_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spot/spot.dart';
import 'package:vekolo/app/app.dart';
import 'package:vekolo/app/refs.dart';

import '../fake/fake_auth_service.dart';
import '../fake/fake_vekolo_api_client.dart';

// Cache for robot instances by WidgetTester identity
final Map<WidgetTester, VekoloRobot> _robotCache = <WidgetTester, VekoloRobot>{};

extension RobotExtensions on WidgetTester {
  VekoloRobot get robot {
    return _robotCache.putIfAbsent(this, () => VekoloRobot(tester: this));
  }
}

class VekoloRobot {
  VekoloRobot({required this.tester});

  final WidgetTester tester;

  Future<void> launchApp({bool loggedIn = false}) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tester.view.physicalSize = const Size(1179 / 3, 2556 / 3); // iPhone 15″
    addTearDown(tester.view.resetPhysicalSize);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    await loadAppFonts();

    // Setup mock SharedPreferences
    SharedPreferences.setMockInitialValues({});

    final fakeAuthService = FakeAuthService();
    final fakeApiClient = FakeVekoloApiClient();

    final app = ContextPlus.root(
      child: Builder(
        builder: (context) {
          // Bind controllers to context
          Refs.authService.bind(context, () => fakeAuthService);
          Refs.apiClient.bind(context, () => fakeApiClient);

          return VekoloApp();
        },
      ),
    );

    await tester.pumpWidget(app);
    await fastIdle();

    // If loggedIn is requested, perform the login after the app is built
    if (loggedIn) {
      // TODO
    }
  }

  /// A faster version of idle waiting less real world time.
  Future<void> fastIdle([int? durationMs]) async {
    final TestWidgetsFlutterBinding binding = tester.binding;
    try {
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 10)));
      await binding.delayed(Duration.zero);
      await tester.pump(Duration(milliseconds: durationMs ?? 500));
    } catch (e) {
      if (e is TestFailure) {
        if (e.message != null && e.message!.contains('Reentrant call to runAsync() denied')) {
          // ignore
          return;
        }
      }
      rethrow;
    }
  }
}
