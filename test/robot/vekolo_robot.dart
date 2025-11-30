import 'package:chirp/chirp.dart';
import 'package:clock/clock.dart' show clock;
import 'package:context_plus/context_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spot/spot.dart';
import 'package:state_beacon/state_beacon.dart';
import 'package:vekolo/app/app.dart';
import 'package:vekolo/app/logger.dart';
import 'package:vekolo/app/refs.dart';
import 'package:vekolo/domain/models/device_info.dart';
import 'package:vekolo/pages/devices_page.dart';
import 'package:vekolo/pages/home_page_v2/home_page_v2.dart';
import 'package:vekolo/pages/scanner_page.dart';
import 'package:vekolo/services/device_assignment_persistence.dart';
import 'package:vekolo/widgets/splash_screen.dart';
import 'package:vekolo/widgets/workout_screen_content.dart';

import '../ble/fake_ble_platform.dart';
import '../fake/fake_auth_service.dart';
import '../fake/fake_vekolo_api_client.dart';
import '../helpers/path_provider_helper.dart';
import '../helpers/shared_preferences_helper.dart';
import 'robot_kit.dart';

// Cache for robot instances by WidgetTester identity
final Map<WidgetTester, VekoloRobot> _robotCache = <WidgetTester, VekoloRobot>{};

extension RobotExtensions on WidgetTester {
  VekoloRobot get robot {
    return _robotCache.putIfAbsent(this, () => VekoloRobot(tester: this));
  }
}

class VekoloRobot {
  VekoloRobot({required this.tester}) {
    initializeLogger();

    addFlutterTearDown(() {
      _blePlatform.dispose();
    });

    addTearDown(() {
      // Clear rootBundle cache to prevent hangs in subsequent tests caused by rootBundle.loadString('file');
      // See: https://github.com/flutter/flutter/issues/96123
      rootBundle.clear();
    });
  }

  final WidgetTester tester;

  late final Aether aether = Aether(fakeBlePlatform: _blePlatform);

  final _blePlatform = FakeBlePlatform();

  bool _isSetup = false;

  static const int _idlePumpStepMs = 100; // Pump in 100ms steps to process callbacks

  late final logger = ChirpLogger(name: 'Robot')
    ..addConsoleWriter(formatter: RainbowMessageFormatter())
    ..addWriter(SpotTimelineWriter());

  Future<void> _setup() async {
    // Only setup once per test to preserve SharedPreferences across app restarts
    if (_isSetup) return;

    await loadAppFonts();
    await GoogleFonts.pendingFonts([
      GoogleFonts.publicSans(fontWeight: FontWeight.w300),
      GoogleFonts.publicSans(fontWeight: FontWeight.w400),
      GoogleFonts.publicSans(fontWeight: FontWeight.w600),
      GoogleFonts.sairaExtraCondensed(fontWeight: FontWeight.w400),
    ]);

    // Setup mock disk based storage ONCE per test
    // This ensures data persists across app restarts within the same test
    createTestSharedPreferencesAsync();
    // Vekolo always uses the async version, but packages like wiredash depend on the sync one
    SharedPreferences.setMockInitialValues({});
    // store for auth tokens
    FlutterSecureStorage.setMockInitialValues({});

    // Setup path_provider for workout session persistence
    // This is needed for tests that emit power data and trigger workout recording
    await setupPathProvider();

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
  Future<void> launchApp({
    bool loggedIn = false,
    List<FakeDevice> pairedDevices = const [],
    bool awaitLaunchScreen = true,
  }) async {
    logger.robotLog(
      'Launching the app',
      data: {
        'loggedIn': loggedIn,
        if (pairedDevices.isNotEmpty) 'devices': pairedDevices.map((it) => it.name).join(", "),
      },
    );
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

    // If loggedIn is requested, set up authentication before building the app
    if (loggedIn) {
      await fakeAuthService.setUpLoggedInUser();
    }

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

    // If devices were pre-paired, wait for auto-connect to complete
    if (pairedDevices.isNotEmpty) {
      // Wait for auto-connect to complete (with timeout)
      final startTime = clock.now();
      while (pairedDevices.any((d) => !d.isConnected)) {
        await idle(100);
        final elapsed = clock.now().difference(startTime);
        if (elapsed > const Duration(seconds: 10)) {
          // Timeout - show which devices failed
          final disconnected = pairedDevices.where((d) => !d.isConnected).map((d) => d.name).toList();
          throw TestFailure('Auto-connect timeout after ${elapsed.inSeconds}s. Disconnected devices: $disconnected');
        }
      }

      // Verify all devices are connected
      for (final device in pairedDevices) {
        expect(device.isConnected, isTrue, reason: 'Device ${device.name} should be auto-connected');
      }
    }

    if (awaitLaunchScreen) {
      await waitForHomePage();
    }
  }

  /// Save device assignments to persistent storage.
  ///
  /// This allows auto-connect to reconnect devices on app startup without
  /// going through the UI pairing flow.
  Future<void> _saveDeviceAssignments(List<FakeDevice> devices) async {
    if (devices.isEmpty) return;

    final persistence = DeviceAssignmentPersistence(SharedPreferencesAsync());

    // Find devices by capability
    FakeDevice? trainerDevice;
    FakeDevice? hrDevice;

    for (final device in devices) {
      final transport = _getTransportIdFromServices(device.services);
      if (transport == 'ftms' || transport == 'cycling-power') {
        trainerDevice = device;
      } else if (transport == 'heart-rate') {
        hrDevice = device;
      }
    }

    // Assign devices to roles based on their capabilities
    final trainer = trainerDevice ?? devices.first;
    final trainerTransport = _getTransportIdFromServices(trainer.services);
    final trainerAssignment = DeviceAssignment(
      deviceId: trainer.id,
      deviceName: trainer.name,
      transport: trainerTransport,
    );

    // Heart rate device assignment (optional)
    DeviceAssignment? hrAssignment;
    if (hrDevice != null) {
      hrAssignment = DeviceAssignment(deviceId: hrDevice.id, deviceName: hrDevice.name, transport: 'heart-rate');
    }

    await persistence.saveAssignments(
      smartTrainer: trainerAssignment,
      powerSource: trainerAssignment,
      cadenceSource: trainerAssignment,
      speedSource: trainerAssignment,
      heartRateSource: hrAssignment,
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

  /// Pumps the event queue in small increments to process callbacks.
  ///
  /// Use this instead of idle() when you need to ensure subscription callbacks
  /// are processed in a timely manner.
  Future<void> pumpUntil(int durationMs) async {
    final TestWidgetsFlutterBinding binding = tester.binding;
    try {
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 10)));
      await binding.delayed(Duration.zero);

      // Pump in steps to process subscription callbacks
      final steps = (durationMs / _idlePumpStepMs).ceil();

      for (int i = 0; i < steps; i++) {
        final remaining = durationMs - (i * _idlePumpStepMs);
        final thisPump = remaining < _idlePumpStepMs ? remaining : _idlePumpStepMs;
        await tester.pump(Duration(milliseconds: thisPump));
      }
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

  /// Waits for the [SplashScreen] to disappear and the [HomePage2] to become visible
  Future<void> waitForHomePage() async {
    await idle(1000);
    await idle();
    spot<HomePage2>().existsOnce();
  }

  Future<void> closeApp() async {
    logger.robotLog('closing app');
    await tester.pumpWidget(const SizedBox.shrink());
    // Wait for all async operations to complete, including:
    // - Widget disposal
    // - Recording service disposal and file flushing
    // - Any fire-and-forget Futures (like startRecording()) that are still running
    // The startRecording() Future can take 500-700ms to complete, and may not have
    // been called yet due to beacon callback delays. Wait long enough to ensure it completes.
    await idle(5000);
  }

  Future<void> openManageDevicesPage() async {
    logger.robotLog('open DevicesPage');
    // In the new UI, the devices button is an Icon inside a GestureDetector, not an IconButton
    final devicesIcon = spotIcon(Icons.devices);
    await act.tap(devicesIcon);
    await idle(500);
    spot<DevicesPage>().existsOnce();
  }

  Future<void> openScanner() async {
    logger.robotLog('open ScannerPage');
    await act.tap(spotText('Scan'));
    await idle(500);
    spot<ScannerPage>().existsOnce();
  }

  Future<void> selectDeviceInScanner(String name) async {
    logger.robotLog('select device in scanner: $name');
    final deviceTile = spot<ListTile>().withChild(spotText(name));
    await act.tap(deviceTile);
    await idle(500);
  }

  Future<void> waitUntilConnected() async {
    logger.robotLog('waiting until connected');
    await idle(1000);

    // Check if we're already on devices page by looking for "Devices" text
    final onDevicesPage = tester.verify.existsAtLeastOnce(spot<DevicesPage>());
    if (onDevicesPage) {
      logger.robotLog('already on devices page');
    } else {
      logger.robotLog('not on devices page, need to navigate there');
    }

    if (!onDevicesPage) {
      // Navigate back to home first if needed
      bool foundBackButton = true;
      while (foundBackButton) {
        await tester.pumpAndSettle();
        try {
          final backButton = spotIcon(Icons.arrow_back);
          backButton.existsAtLeastOnce();
          logger.robotLog('found back button, navigating back');
          await act.tap(backButton);
          await idle(500);
          await idle(500);
        } catch (e) {
          foundBackButton = false;
          logger.robotLog('no back button found');
        }
      }

      // Make sure we're settled
      await idle(500);

      // Navigate to devices page from home
      logger.robotLog('navigating to devices page');
      await act.tap(spotIcon(Icons.devices));
      await idle(1000);
    }

    // Wait for device to be connected (Disconnect button appears)
    // Using longer timeout to allow for auto-reconnect
    logger.robotLog('waiting for device to be connected (looking for Disconnect button)');
    final disconnectButton = spotText('Disconnect');
    await tester.verify.waitUntilExistsAtLeastOnce(disconnectButton, timeout: const Duration(seconds: 10));
  }

  /// Verify the state of a device card's buttons and connection state.
  ///
  /// Example usage:
  /// ```dart
  /// // Check that connect button exists and is enabled
  /// robot.verifyDeviceState("POWER SOURCE", connectButtonEnabled: true);
  ///
  /// // Check that disconnect button exists and is enabled, and connect button is not visible
  /// robot.verifyDeviceState("POWER SOURCE", disconnectButtonEnabled: true, connectButtonVisible: false);
  ///
  /// // Check device is connecting
  /// robot.verifyDeviceState("POWER SOURCE", isConnecting: true);
  ///
  /// // Check unassign and remove buttons
  /// robot.verifyDeviceState("HEART RATE", unassignButtonVisible: true, removeButtonVisible: true);
  ///
  /// // Check assignment buttons
  /// robot.verifyDeviceState("POWER SOURCE", assignPowerButtonVisible: true, assignPowerButtonEnabled: true);
  /// ```
  ///
  /// Parameters:
  /// - [dataSourceName]: The name of the data source section (e.g., "POWER SOURCE", "HEART RATE")
  /// - [connectButtonEnabled]: If specified, verifies the Connect button is enabled (onPressed != null)
  /// - [connectButtonVisible]: If specified, verifies the Connect button exists or doesn't exist
  /// - [isConnecting]: If specified, verifies the Connect button shows "Connecting..." state
  /// - [disconnectButtonEnabled]: If specified, verifies the Disconnect button is enabled (onPressed != null)
  /// - [disconnectButtonVisible]: If specified, verifies the Disconnect button exists or doesn't exist
  /// - [unassignButtonEnabled]: If specified, verifies the Unassign button is enabled (onPressed != null)
  /// - [unassignButtonVisible]: If specified, verifies the Unassign button exists or doesn't exist
  /// - [removeButtonEnabled]: If specified, verifies the Remove button is enabled (onPressed != null)
  /// - [removeButtonVisible]: If specified, verifies the Remove button exists or doesn't exist
  /// - [assignPowerButtonEnabled]: If specified, verifies the "Assign to Power" button is enabled
  /// - [assignPowerButtonVisible]: If specified, verifies the "Assign to Power" button exists
  /// - [assignCadenceButtonEnabled]: If specified, verifies the "Assign to Cadence" button is enabled
  /// - [assignCadenceButtonVisible]: If specified, verifies the "Assign to Cadence" button exists
  /// - [assignSpeedButtonEnabled]: If specified, verifies the "Assign to Speed" button is enabled
  /// - [assignSpeedButtonVisible]: If specified, verifies the "Assign to Speed" button exists
  /// - [assignHRButtonEnabled]: If specified, verifies the "Assign to HR" button is enabled
  /// - [assignHRButtonVisible]: If specified, verifies the "Assign to HR" button exists
  void verifyDeviceState(
    String dataSourceName, {
    bool? connectButtonEnabled,
    bool? connectButtonVisible,
    bool? isConnecting,
    bool? disconnectButtonEnabled,
    bool? disconnectButtonVisible,
    bool? unassignButtonEnabled,
    bool? unassignButtonVisible,
    bool? removeButtonEnabled,
    bool? removeButtonVisible,
    bool? assignPowerButtonEnabled,
    bool? assignPowerButtonVisible,
    bool? assignCadenceButtonEnabled,
    bool? assignCadenceButtonVisible,
    bool? assignSpeedButtonEnabled,
    bool? assignSpeedButtonVisible,
    bool? assignHRButtonEnabled,
    bool? assignHRButtonVisible,
  }) {
    spot<DevicesPage>().existsOnce();

    // Build log message from specified checks
    final checks = <String>[];
    if (isConnecting != null) checks.add(isConnecting ? 'connecting' : 'not connecting');
    if (connectButtonEnabled != null) checks.add('connect ${connectButtonEnabled ? "enabled" : "disabled"}');
    if (connectButtonVisible != null) checks.add('connect ${connectButtonVisible ? "visible" : "hidden"}');
    if (disconnectButtonEnabled != null) checks.add('disconnect ${disconnectButtonEnabled ? "enabled" : "disabled"}');
    if (disconnectButtonVisible != null) checks.add('disconnect ${disconnectButtonVisible ? "visible" : "hidden"}');
    if (unassignButtonEnabled != null) checks.add('unassign ${unassignButtonEnabled ? "enabled" : "disabled"}');
    if (unassignButtonVisible != null) checks.add('unassign ${unassignButtonVisible ? "visible" : "hidden"}');
    if (removeButtonEnabled != null) checks.add('remove ${removeButtonEnabled ? "enabled" : "disabled"}');
    if (removeButtonVisible != null) checks.add('remove ${removeButtonVisible ? "visible" : "hidden"}');
    if (assignPowerButtonEnabled != null)
      checks.add('assign-power ${assignPowerButtonEnabled ? "enabled" : "disabled"}');
    if (assignPowerButtonVisible != null) checks.add('assign-power ${assignPowerButtonVisible ? "visible" : "hidden"}');
    if (assignCadenceButtonEnabled != null)
      checks.add('assign-cadence ${assignCadenceButtonEnabled ? "enabled" : "disabled"}');
    if (assignCadenceButtonVisible != null)
      checks.add('assign-cadence ${assignCadenceButtonVisible ? "visible" : "hidden"}');
    if (assignSpeedButtonEnabled != null)
      checks.add('assign-speed ${assignSpeedButtonEnabled ? "enabled" : "disabled"}');
    if (assignSpeedButtonVisible != null) checks.add('assign-speed ${assignSpeedButtonVisible ? "visible" : "hidden"}');
    if (assignHRButtonEnabled != null) checks.add('assign-hr ${assignHRButtonEnabled ? "enabled" : "disabled"}');
    if (assignHRButtonVisible != null) checks.add('assign-hr ${assignHRButtonVisible ? "visible" : "hidden"}');

    logger.robotLog('verify device state: $dataSourceName [${checks.join(", ")}]');

    final card = spot<DataSourceSection>().withChild(spotText(dataSourceName)).spot<DeviceCard>()..existsOnce();

    // Verify connecting state
    if (isConnecting != null) {
      final connectingText = card.spotText('Connecting...');
      if (isConnecting) {
        connectingText.existsOnce();
      } else {
        connectingText.doesNotExist();
      }
    }

    // Verify Connect button visibility
    if (connectButtonVisible != null) {
      final connectButton = card.spot<ElevatedButton>().withChild(spotText('Connect'));
      if (connectButtonVisible) {
        connectButton.existsOnce();
      } else {
        connectButton.doesNotExist();
      }
    }

    // Verify Connect button enabled state
    if (connectButtonEnabled != null) {
      final connectButton = card.spot<ElevatedButton>().withChild(spotText('Connect')).existsOnce();
      connectButton.hasWidgetProp(
        prop: widgetProp('onPressed', (it) => it.onPressed),
        match: (it) => connectButtonEnabled ? it.isNotNull() : it.isNull(),
      );
    }

    // Verify Disconnect button visibility
    if (disconnectButtonVisible != null) {
      final disconnectButton = card.spot<ElevatedButton>().withChild(spotText('Disconnect'));
      if (disconnectButtonVisible) {
        disconnectButton.existsOnce();
      } else {
        disconnectButton.doesNotExist();
      }
    }

    // Verify Disconnect button enabled state
    if (disconnectButtonEnabled != null) {
      final disconnectButton = card.spot<ElevatedButton>().withChild(spotText('Disconnect')).existsOnce();
      disconnectButton.hasWidgetProp(
        prop: widgetProp('onPressed', (it) => it.onPressed),
        match: (it) => disconnectButtonEnabled ? it.isNotNull() : it.isNull(),
      );
    }

    // Verify Unassign button visibility
    if (unassignButtonVisible != null) {
      final unassignButton = card.spot<OutlinedButton>().withChild(spotText('Unassign'));
      if (unassignButtonVisible) {
        unassignButton.existsOnce();
      } else {
        unassignButton.doesNotExist();
      }
    }

    // Verify Unassign button enabled state
    if (unassignButtonEnabled != null) {
      final unassignButton = card.spot<OutlinedButton>().withChild(spotText('Unassign')).existsOnce();
      unassignButton.hasWidgetProp(
        prop: widgetProp('onPressed', (it) => it.onPressed),
        match: (it) => unassignButtonEnabled ? it.isNotNull() : it.isNull(),
      );
    }

    // Verify Remove button visibility
    if (removeButtonVisible != null) {
      final removeButton = card.spot<OutlinedButton>().withChild(spotText('Remove'));
      if (removeButtonVisible) {
        removeButton.existsOnce();
      } else {
        removeButton.doesNotExist();
      }
    }

    // Verify Remove button enabled state
    if (removeButtonEnabled != null) {
      final removeButton = card.spot<OutlinedButton>().withChild(spotText('Remove')).existsOnce();
      removeButton.hasWidgetProp(
        prop: widgetProp('onPressed', (it) => it.onPressed),
        match: (it) => removeButtonEnabled ? it.isNotNull() : it.isNull(),
      );
    }

    // Verify Assign to Power button visibility
    if (assignPowerButtonVisible != null) {
      final assignButton = card.spot<OutlinedButton>().withChild(spotText('Assign to Power'));
      if (assignPowerButtonVisible) {
        assignButton.existsOnce();
      } else {
        assignButton.doesNotExist();
      }
    }

    // Verify Assign to Power button enabled state
    if (assignPowerButtonEnabled != null) {
      final assignButton = card.spot<OutlinedButton>().withChild(spotText('Assign to Power')).existsOnce();
      assignButton.hasWidgetProp(
        prop: widgetProp('onPressed', (it) => it.onPressed),
        match: (it) => assignPowerButtonEnabled ? it.isNotNull() : it.isNull(),
      );
    }

    // Verify Assign to Cadence button visibility
    if (assignCadenceButtonVisible != null) {
      final assignButton = card.spot<OutlinedButton>().withChild(spotText('Assign to Cadence'));
      if (assignCadenceButtonVisible) {
        assignButton.existsOnce();
      } else {
        assignButton.doesNotExist();
      }
    }

    // Verify Assign to Cadence button enabled state
    if (assignCadenceButtonEnabled != null) {
      final assignButton = card.spot<OutlinedButton>().withChild(spotText('Assign to Cadence')).existsOnce();
      assignButton.hasWidgetProp(
        prop: widgetProp('onPressed', (it) => it.onPressed),
        match: (it) => assignCadenceButtonEnabled ? it.isNotNull() : it.isNull(),
      );
    }

    // Verify Assign to Speed button visibility
    if (assignSpeedButtonVisible != null) {
      final assignButton = card.spot<OutlinedButton>().withChild(spotText('Assign to Speed'));
      if (assignSpeedButtonVisible) {
        assignButton.existsOnce();
      } else {
        assignButton.doesNotExist();
      }
    }

    // Verify Assign to Speed button enabled state
    if (assignSpeedButtonEnabled != null) {
      final assignButton = card.spot<OutlinedButton>().withChild(spotText('Assign to Speed')).existsOnce();
      assignButton.hasWidgetProp(
        prop: widgetProp('onPressed', (it) => it.onPressed),
        match: (it) => assignSpeedButtonEnabled ? it.isNotNull() : it.isNull(),
      );
    }

    // Verify Assign to HR button visibility
    if (assignHRButtonVisible != null) {
      final assignButton = card.spot<OutlinedButton>().withChild(spotText('Assign to HR'));
      if (assignHRButtonVisible) {
        assignButton.existsOnce();
      } else {
        assignButton.doesNotExist();
      }
    }

    // Verify Assign to HR button enabled state
    if (assignHRButtonEnabled != null) {
      final assignButton = card.spot<OutlinedButton>().withChild(spotText('Assign to HR')).existsOnce();
      assignButton.hasWidgetProp(
        prop: widgetProp('onPressed', (it) => it.onPressed),
        match: (it) => assignHRButtonEnabled ? it.isNotNull() : it.isNull(),
      );
    }
  }

  Future<void> tapDisconnectButton() async {
    logger.robotLog('tap disconnect button');
    final card = spot<DataSourceSection>().withChild(spotText('POWER SOURCE')).spot<DeviceCard>()..existsOnce();

    final disconnectButton = card.spot<ElevatedButton>().withChild(spotText('Disconnect'));
    await act.tap(disconnectButton);
    await idle(100);
  }

  Future<void> tapConnectButton() async {
    logger.robotLog('tap connect button');
    final card = spot<DataSourceSection>().withChild(spotText('POWER SOURCE')).spot<DeviceCard>()..existsOnce();

    final connectButton = card.spot<ElevatedButton>().withChild(spotText('Connect'));
    await act.tap(connectButton);
    await idle(100);
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

  Future<void> tapStartWorkout(String name) async {
    logger.robotLog('starting workout: $name');

    // Wait for activities to load - look for the workout card with the matching title
    final workoutCardTitle = spotText(name);
    await tester.verify.waitUntilExistsAtLeastOnce(workoutCardTitle, timeout: const Duration(seconds: 10));
    await idle(500);

    // Tap the workout card to open activity detail page
    await act.tap(workoutCardTitle);
    await idle(500);

    // Wait for activity detail page to load - look for "Ride Now" button
    final rideNowButton = spotText('Ride Now');
    await tester.verify.waitUntilExistsAtLeastOnce(rideNowButton, timeout: const Duration(seconds: 5));
    await idle(300);

    // Tap "Ride Now" button to start the workout
    await act.tap(rideNowButton);
    await idle(500);

    // Wait for workout player page to fully load by waiting for a key indicator
    await tester.verify.waitUntilExistsAtLeastOnce(spot<WorkoutScreenContent>(), timeout: const Duration(seconds: 5));
    await idle(500);
  }

  /// Verifies that the workout player page is shown.
  ///
  /// This checks for the presence of WorkoutScreenContent, which is the main
  /// widget displayed on the workout player page.
  void verifyPlayerIsShown() {
    logger.robotLog('verify workout player is shown');
    spot<WorkoutScreenContent>().existsOnce();
  }

  Future<void> resumeWorkout() async {
    logger.robotLog('resuming workout from crash recovery notification');
    // Tap the "Resume" button (there will be 2 matches: title has "Resume Workout?" and button has "Resume")
    await act.tap(spotText('Resume').atIndex(1));
    // Wait for navigation and workout player to load
    await idle(3000);
  }

  Future<void> discardWorkout() async {
    logger.robotLog('discarding workout from crash recovery notification');
    await act.tap(spotText('Discard'));
    await idle(500);
  }

  Future<void> startFreshWorkout() async {
    logger.robotLog('starting fresh workout from crash recovery notification');
    await act.tap(spotText('Start Fresh'));
    // Wait for navigation and workout player to load
    await idle(3000);
  }

  /// Wait for the crash recovery notification card to appear
  Future<void> waitForCrashRecoveryDialog(String workoutName) async {
    logger.robotLog('waiting for crash recovery notification card');
    // Note: Title includes workout name, currently hardcoded to "Workout" in workout_player_page.dart
    await tester.verify.waitUntilExistsAtLeastOnce(
      spotText('Resume $workoutName?'),
      timeout: const Duration(seconds: 5),
    );
    await idle(500); // wait for notification to appear
  }

  /// Wait for a workout session to be created and marked as active.
  ///
  /// This is useful in tests that need to ensure startRecording() has completed
  /// before simulating a crash.
  ///
  /// Due to test framework limitations, beacon subscription callbacks can be significantly
  /// delayed. We wait 2 seconds to ensure the startRecording() call (which happens in a
  /// power monitoring beacon callback) has time to execute and complete.
  Future<void> waitForActiveWorkoutSession({Duration timeout = const Duration(seconds: 10)}) async {
    logger.robotLog('waiting for active workout session');

    // Wait long enough for:
    // 1. Beacon callback to fire (can be delayed several seconds by test framework)
    // 2. startRecording() to complete (~500-700ms)
    // Total: Can be 4+ seconds in some test runs, using 5s to be very safe
    await idle(5000);

    logger.robotLog('active workout session should be created');
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

class SpotTimelineWriter implements ChirpWriter {
  final formatter = SimpleConsoleMessageFormatter();

  @override
  void write(LogRecord record) {
    final builder = ConsoleMessageBuffer(supportsColors: false);
    formatter.format(record, builder);
    final msg = builder.toString();
    timeline.addEvent(details: msg, eventType: 'Robot');
  }
}

final robotLogLevel = ChirpLogLevel('robot', 400);

extension RobotLoggerExtension on ChirpLogger {
  void robotLog(String message, {Map<String, Object?>? data}) {
    log(message, level: robotLogLevel, data: data, skipFrames: 1);
  }
}
