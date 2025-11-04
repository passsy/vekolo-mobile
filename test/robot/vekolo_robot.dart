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
import 'package:vekolo/pages/devices_page.dart';
import 'package:vekolo/pages/scanner_page.dart';
import 'package:vekolo/services/device_assignment_persistence.dart';

import '../ble/fake_ble_platform.dart';
import '../fake/fake_auth_service.dart';
import '../fake/fake_vekolo_api_client.dart';
import '../helpers/shared_preferences_helper.dart';
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

  bool _isSetup = false;

  Future<void> _setup() async {
    // Only setup once per test to preserve SharedPreferences across app restarts
    if (_isSetup) return;

    TestWidgetsFlutterBinding.ensureInitialized();
    await loadAppFonts();

    // Setup mock SharedPreferences and SecureStorage ONCE per test
    // This ensures data persists across app restarts within the same test
    createTestSharedPreferencesAsync();
    FlutterSecureStorage.setMockInitialValues({});

    _isSetup = true;
  }

  /// Launch the app, optionally with pre-paired devices.
  ///
  /// If [pairedDevices] is provided, device assignments will be saved to persistent
  /// storage before launching the app, allowing auto-connect to reconnect them on startup.
  /// This is much faster than going through the UI pairing flow.
  ///
  /// Example without devices:
  /// ```dart
  /// await robot.launchApp(loggedIn: true);
  /// ```
  ///
  /// Example with pre-paired devices:
  /// ```dart
  /// final kickrCore = robot.aether.createDevice(
  ///   name: 'Kickr Core',
  ///   capabilities: {DeviceDataType.power, DeviceDataType.cadence, DeviceDataType.speed},
  /// );
  /// await robot.launchApp(
  ///   pairedDevices: [kickrCore],
  ///   loggedIn: true,
  /// );
  /// // kickrCore is now connected and ready to use
  /// ```
  Future<void> launchApp({bool loggedIn = false, List<FakeDevice> pairedDevices = const []}) async {
    await _setup();

    // If devices should be pre-paired, save assignments before launching app
    if (pairedDevices.isNotEmpty) {
      await _saveDeviceAssignments(pairedDevices);
    }

    tester.view.physicalSize = const Size(1179 / 3, 2556 / 3); // iPhone 15″
    addTearDown(tester.view.resetPhysicalSize);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);

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

    // If devices were pre-paired, wait for auto-connect to complete
    if (pairedDevices.isNotEmpty) {
      // Wait for auto-connect to complete
      await idle(500);

      // Verify all devices are connected
      for (final device in pairedDevices) {
        expect(device.isConnected, isTrue, reason: 'Device ${device.name} should be auto-connected');
      }
    }
  }

  /// Save device assignments to persistent storage.
  ///
  /// This allows auto-connect to reconnect devices on app startup without
  /// going through the UI pairing flow.
  Future<void> _saveDeviceAssignments(List<FakeDevice> devices) async {
    if (devices.isEmpty) return;

    final persistence = DeviceAssignmentPersistence(SharedPreferencesAsync());

    // For simplicity in tests, we assign the first device to all roles
    // (In a real scenario, you'd assign specific roles based on capabilities)
    final device = devices.first;

    // Determine transport from device services
    final transport = _getTransportIdFromServices(device.services);

    final assignment = DeviceAssignment(deviceId: device.id, deviceName: device.name, transport: transport);

    await persistence.saveAssignments(
      primaryTrainer: assignment,
      powerSource: assignment,
      cadenceSource: assignment,
      speedSource: assignment,
    );
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
    await tester.pumpWidget(const SizedBox.shrink());
    await idle();
  }

  Future<void> openManageDevicesPage() async {
    final button = spot<IconButton>().withChild(spotIcon(Icons.devices));
    await act.tap(button);
    await idle(500);
    spot<DevicesPage>().existsOnce();
  }

  Future<void> openScanner() async {
    await act.tap(spotText('Scan'));
    await idle(500);
    spot<ScannerPage>().existsOnce();
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

  /// Determines the transport ID from advertised service UUIDs.
  ///
  /// Maps Bluetooth service UUIDs to transport IDs for device assignment persistence.
  String _getTransportIdFromServices(List<fbp.Guid> services) {
    // FTMS service UUID (0x1826)
    final ftmsServiceUuid = fbp.Guid('00001826-0000-1000-8000-00805f9b34fb');
    // Heart Rate service UUID (0x180D)
    final heartRateServiceUuid = fbp.Guid('0000180d-0000-1000-8000-00805f9b34fb');
    // Cycling Power service UUID (0x1818)
    final cyclingPowerServiceUuid = fbp.Guid('00001818-0000-1000-8000-00805f9b34fb');
    // Cycling Speed and Cadence service UUID (0x1816)
    final cyclingSpeedCadenceServiceUuid = fbp.Guid('00001816-0000-1000-8000-00805f9b34fb');

    // Check services in priority order (FTMS is most capable)
    if (services.contains(ftmsServiceUuid)) {
      return 'ftms';
    } else if (services.contains(heartRateServiceUuid)) {
      return 'heart-rate';
    } else if (services.contains(cyclingPowerServiceUuid)) {
      return 'cycling-power';
    } else if (services.contains(cyclingSpeedCadenceServiceUuid)) {
      return 'cycling-speed-cadence';
    }

    // Fallback to ftms if unknown (most test devices will be trainers)
    return 'ftms';
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

  List<FakeDevice> get devices => fakeBlePlatform.devices;

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
