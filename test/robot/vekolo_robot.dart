import 'package:clock/clock.dart' show clock;
import 'package:context_plus/context_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spot/spot.dart';
import 'package:vekolo/app/app.dart';
import 'package:vekolo/app/refs.dart';
import 'package:vekolo/domain/models/device_info.dart';

import '../ble/fake_ble_platform.dart';
import '../fake/fake_auth_service.dart';
import '../fake/fake_vekolo_api_client.dart';
import 'robot_test_fn.dart';

// Cache for robot instances by WidgetTester identity
final Map<WidgetTester, VekoloRobot> _robotCache = <WidgetTester, VekoloRobot>{};

extension RobotExtensions on WidgetTester {
  VekoloRobot get robot {
    return _robotCache.putIfAbsent(this, () => VekoloRobot(tester: this));
  }
}

class VekoloRobot {
  VekoloRobot({required this.tester}) {
    addFlutterTearDown(() {
      _blePlatform.dispose();
    });
  }

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

    // Setup mock SharedPreferences and SecureStorage
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});

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
    await idle();

    // If loggedIn is requested, perform the login after the app is built
    if (loggedIn) {
      // TODO
    }
  }

  /// A faster version of idle waiting less real world time.
  Future<void> idle([int? durationMs]) async {
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
    final state = spot<AppRestart>().snapshotState<AppRestartState>();
    state.stopApp();
    await idle();
    await idle();
    await idle();
    await idle();
    await idle();
    await idle();
  }

  Future<void> startApp() async {
    final state = spot<AppRestart>().snapshotState<AppRestartState>();
    state.startApp();
    await idle();
  }

  Future<void> openManageDevicesPage() async {
    final button = spot<IconButton>().withChild(spotIcon(Icons.devices));
    await act.tap(button);
    await idle(500);
  }

  Future<void> openScanner() async {
    await act.tap(spotText('Scan'));
    await idle(500);
  }

  Future<void> selectDeviceInScanner(String name) async {
    final deviceTile = spot<ListTile>().withChild(spotText(name));
    await act.tap(deviceTile);
    await idle(500);
  }

  Future<void> waitUntilConnected() async {
    final connected = spot<AlertDialog>().spotText('Connected!');
    await tester.verify.waitUntilExistsAtLeastOnce(connected);
    // wait another 1s for the dialog to disappear
    await idle(1000);
    await idle();
    connected.doesNotExist();
  }
}

// Cache for robot instances by WidgetTester identity
final Map<WidgetTester, Verify> _verifyCache = <WidgetTester, Verify>{};

extension VerifyExtensions on WidgetTester {
  Verify get verify {
    return _verifyCache.putIfAbsent(this, () => Verify(tester: this));
  }
}

class Verify {
  final WidgetTester tester;

  Verify({required this.tester});

  Future<void> waitUntilExistsAtLeastOnce(WidgetSelector selector, {Duration? timeout}) async {
    final actualTimeout = timeout ?? const Duration(seconds: 1);
    final start = clock.now();
    while (!existsAtLeastOnce(selector)) {
      final now = clock.now();
      if (now.difference(start) > actualTimeout) {
        selector.existsAtLeastOnce();
        throw TestFailure('Could not find at least one $selector after $timeout');
      }
      await idle(100);
    }
    selector.existsAtLeastOnce();
  }

  /// A faster version of idle waiting less real world time.
  Future<void> idle([int? durationMs]) async {
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

  bool existsAtLeastOnce(WidgetSelector selector) {
    try {
      selector.snapshot().existsAtLeastOnce();
      return true;
    } on TestFailure {
      final lastEvent = timeline.events.last;
      if (lastEvent.eventType.label == 'Assertion Failed') {
        timeline.removeEvent(lastEvent.id);
      }
      return false;
    }
  }
}

class Aether {
  Aether({required this.fakeBlePlatform});

  final FakeBlePlatform fakeBlePlatform;

  int _deviceCounter = 0;

  // Service UUIDs for different protocols
  static final _ftmsServiceUuid = fbp.Guid('00001826-0000-1000-8000-00805f9b34fb');
  static final _heartRateServiceUuid = fbp.Guid('0000180d-0000-1000-8000-00805f9b34fb');
  static final _cyclingPowerServiceUuid = fbp.Guid('00001818-0000-1000-8000-00805f9b34fb');
  static final _cyclingSpeedCadenceServiceUuid = fbp.Guid('00001816-0000-1000-8000-00805f9b34fb');

  /// Create a simulated BLE device.
  ///
  /// Parameters:
  /// - [name]: The device name (e.g., 'Kickr Core')
  /// - [capabilities]: Set of data types this device can provide. Determines which
  ///   service UUIDs will be advertised. If not provided, defaults to an empty set.
  /// - [rssi]: Signal strength, defaults to -50
  FakeDevice createDevice({required String name, Set<DeviceDataType> capabilities = const {}, int rssi = -50}) {
    // Generate a unique device ID
    final deviceId = 'DEVICE_${_deviceCounter++}';

    // Map capabilities to service UUIDs
    final serviceUuids = _capabilitiesToServiceUuids(capabilities);

    final device = fakeBlePlatform.addDevice(deviceId, name, rssi: rssi, services: serviceUuids);
    device.turnOn();

    return device;
  }

  /// Map device capabilities to BLE service UUIDs.
  List<fbp.Guid> _capabilitiesToServiceUuids(Set<DeviceDataType> capabilities) {
    final serviceUuids = <fbp.Guid>{};

    final hasPower = capabilities.contains(DeviceDataType.power);
    final hasCadence = capabilities.contains(DeviceDataType.cadence);
    final hasSpeed = capabilities.contains(DeviceDataType.speed);
    final hasHeartRate = capabilities.contains(DeviceDataType.heartRate);

    // FTMS provides power, cadence, and speed
    if (hasPower || hasCadence || hasSpeed) {
      serviceUuids.add(_ftmsServiceUuid);
    }

    // Heart rate service
    if (hasHeartRate) {
      serviceUuids.add(_heartRateServiceUuid);
    }

    // Cycling Power Service (standalone power meter)
    if (hasPower && !hasCadence && !hasSpeed) {
      serviceUuids.add(_cyclingPowerServiceUuid);
    }

    // Cycling Speed and Cadence Service (standalone sensors)
    if ((hasCadence || hasSpeed) && !hasPower) {
      serviceUuids.add(_cyclingSpeedCadenceServiceUuid);
    }

    return serviceUuids.toList();
  }
}
