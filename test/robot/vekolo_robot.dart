import 'package:context_plus/context_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spot/spot.dart';
import 'package:vekolo/app/app.dart';
import 'package:vekolo/app/refs.dart';

import '../ble/fake_ble_platform.dart';
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

  late final Aether aether = Aether(fakeBlePlatform: _blePlatform);

  final _blePlatform = FakeBlePlatform();

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
          Refs.blePlatform.bindValue(context, _blePlatform);

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

  Future<void> closeApp() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await fastIdle(1000);
  }
}

class Aether {
  Aether({required this.fakeBlePlatform});

  final FakeBlePlatform fakeBlePlatform;

  int _deviceCounter = 0;

  /// Create a simulated BLE device.
  ///
  /// Parameters:
  /// - [name]: The device name (e.g., 'Kickr Core')
  /// - [protocols]: List of supported protocols (e.g., ['ftms', 'bluetooth_power'])
  ///   These will be converted to appropriate service UUIDs
  /// - [rssi]: Signal strength, defaults to -50
  FakeDevice createDevice({required String name, List<String> protocols = const [], int rssi = -50}) {
    // Generate a unique device ID
    final deviceId = 'DEVICE_${_deviceCounter++}';

    // TODO: Convert protocols to actual service UUIDs when implementing auto-connect
    // For now, just create the device with empty services to make the test compile
    final device = fakeBlePlatform.addDevice(deviceId, name, rssi: rssi);

    return device;
  }
}
