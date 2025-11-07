import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vekolo/ble/ble_scanner.dart';
import 'package:vekolo/ble/transport_registry.dart';
import 'package:vekolo/domain/devices/device_manager.dart';
import 'package:vekolo/domain/models/fitness_data.dart';
import 'package:vekolo/services/device_assignment_persistence.dart';

import '../../ble/fake_ble_platform.dart';
import '../../ble/fake_ble_permissions.dart';
import '../../fake/fake_fitness_device.dart';
import '../../helpers/shared_preferences_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Creates test dependencies. Call this at the start of each test.
  /// Automatically registers cleanup with addTearDown.
  ({DeviceManager deviceManager, FakeFitnessDevice fakeDevice}) createTestDependencies() {
    final platform = FakeBlePlatform();
    final scanner = BleScanner(platform: platform, permissions: FakeBlePermissions());
    scanner.initialize();
    final transportRegistry = TransportRegistry();
    final prefs = createTestSharedPreferencesAsync();
    final persistence = DeviceAssignmentPersistence(prefs);

    final deviceManager = DeviceManager(
      platform: platform,
      scanner: scanner,
      transportRegistry: transportRegistry,
      persistence: persistence,
    );

    final fakeDevice = FakeFitnessDevice(id: 'device-1', name: 'Test Device');

    // Register cleanup
    addTearDown(() async {
      await deviceManager.dispose();
    });

    return (deviceManager: deviceManager, fakeDevice: fakeDevice);
  }

  group('Stale Data Detection - Power', () {
    test('returns fresh power data immediately after emission', () async {
      final deps = createTestDependencies();

      await deps.deviceManager.addDevice(deps.fakeDevice);
      deps.deviceManager.assignPowerSource(deps.fakeDevice.id);

      // Emit power data
      deps.fakeDevice.emitPower(PowerData(watts: 195, timestamp: clock.now()));

      // Wait a bit for subscription to process
      await Future.delayed(const Duration(milliseconds: 50));

      // Should return the data since it's fresh
      expect(deps.deviceManager.powerStream.value, isNotNull);
      expect(deps.deviceManager.powerStream.value!.watts, 195);
    });

    test('returns null after 5 seconds of no new data', () async {
      final deps = createTestDependencies();

      await deps.deviceManager.addDevice(deps.fakeDevice);
      deps.deviceManager.assignPowerSource(deps.fakeDevice.id);

      // Emit power data
      deps.fakeDevice.emitPower(PowerData(watts: 195, timestamp: clock.now()));

      // Wait a bit for subscription to process
      await Future.delayed(const Duration(milliseconds: 50));
      expect(deps.deviceManager.powerStream.value, isNotNull);

      // Wait for staleness timer to fire (5 seconds + buffer)
      await Future.delayed(const Duration(milliseconds: 5100));

      // Should return null since no new data for >5 seconds
      expect(deps.deviceManager.powerStream.value, isNull);
    });

    test('resets timer when new data arrives', () async {
      final deps = createTestDependencies();

      await deps.deviceManager.addDevice(deps.fakeDevice);
      deps.deviceManager.assignPowerSource(deps.fakeDevice.id);

      // Emit initial power data
      deps.fakeDevice.emitPower(PowerData(watts: 195, timestamp: clock.now()));
      await Future.delayed(const Duration(milliseconds: 50));
      expect(deps.deviceManager.powerStream.value, isNotNull);

      // Wait 3 seconds (not enough to go stale)
      await Future.delayed(const Duration(seconds: 3));

      // Emit new data - this should reset the timer
      deps.fakeDevice.emitPower(PowerData(watts: 200, timestamp: clock.now()));
      await Future.delayed(const Duration(milliseconds: 50));

      // Data should still be fresh
      expect(deps.deviceManager.powerStream.value, isNotNull);
      expect(deps.deviceManager.powerStream.value!.watts, 200);

      // Wait another 3 seconds (total of 6s from first emission, but only 3s from second)
      await Future.delayed(const Duration(seconds: 3));

      // Should still be fresh because timer was reset
      expect(deps.deviceManager.powerStream.value, isNotNull);
    });
  });

  group('Stale Data Detection - Cadence', () {
    test('returns fresh cadence data immediately after emission', () async {
      final deps = createTestDependencies();

      await deps.deviceManager.addDevice(deps.fakeDevice);
      deps.deviceManager.assignCadenceSource(deps.fakeDevice.id);

      deps.fakeDevice.emitCadence(CadenceData(rpm: 90, timestamp: clock.now()));
      await Future.delayed(const Duration(milliseconds: 50));

      expect(deps.deviceManager.cadenceStream.value, isNotNull);
      expect(deps.deviceManager.cadenceStream.value!.rpm, 90);
    });

    test('returns null after 5 seconds of no new data', () async {
      final deps = createTestDependencies();

      await deps.deviceManager.addDevice(deps.fakeDevice);
      deps.deviceManager.assignCadenceSource(deps.fakeDevice.id);

      deps.fakeDevice.emitCadence(CadenceData(rpm: 90, timestamp: clock.now()));
      await Future.delayed(const Duration(milliseconds: 50));
      expect(deps.deviceManager.cadenceStream.value, isNotNull);

      await Future.delayed(const Duration(milliseconds: 5100));
      expect(deps.deviceManager.cadenceStream.value, isNull);
    });
  });

  group('Stale Data Detection - Speed', () {
    test('returns fresh speed data immediately after emission', () async {
      final deps = createTestDependencies();

      await deps.deviceManager.addDevice(deps.fakeDevice);
      deps.deviceManager.assignSpeedSource(deps.fakeDevice.id);

      deps.fakeDevice.emitSpeed(SpeedData(kmh: 30.5, timestamp: clock.now()));
      await Future.delayed(const Duration(milliseconds: 50));

      expect(deps.deviceManager.speedStream.value, isNotNull);
      expect(deps.deviceManager.speedStream.value!.kmh, 30.5);
    });

    test('returns null after 5 seconds of no new data', () async {
      final deps = createTestDependencies();

      await deps.deviceManager.addDevice(deps.fakeDevice);
      deps.deviceManager.assignSpeedSource(deps.fakeDevice.id);

      deps.fakeDevice.emitSpeed(SpeedData(kmh: 30.5, timestamp: clock.now()));
      await Future.delayed(const Duration(milliseconds: 50));
      expect(deps.deviceManager.speedStream.value, isNotNull);

      await Future.delayed(const Duration(milliseconds: 5100));
      expect(deps.deviceManager.speedStream.value, isNull);
    });
  });

  group('Stale Data Detection - Heart Rate', () {
    test('returns fresh heart rate data immediately after emission', () async {
      final deps = createTestDependencies();

      await deps.deviceManager.addDevice(deps.fakeDevice);
      deps.deviceManager.assignHeartRateSource(deps.fakeDevice.id);

      deps.fakeDevice.emitHeartRate(HeartRateData(bpm: 145, timestamp: clock.now()));
      await Future.delayed(const Duration(milliseconds: 50));

      expect(deps.deviceManager.heartRateStream.value, isNotNull);
      expect(deps.deviceManager.heartRateStream.value!.bpm, 145);
    });

    test('returns null after 5 seconds of no new data', () async {
      final deps = createTestDependencies();

      await deps.deviceManager.addDevice(deps.fakeDevice);
      deps.deviceManager.assignHeartRateSource(deps.fakeDevice.id);

      deps.fakeDevice.emitHeartRate(HeartRateData(bpm: 145, timestamp: clock.now()));
      await Future.delayed(const Duration(milliseconds: 50));
      expect(deps.deviceManager.heartRateStream.value, isNotNull);

      await Future.delayed(const Duration(milliseconds: 5100));
      expect(deps.deviceManager.heartRateStream.value, isNull);
    });
  });

  group('Stale Data Detection - Edge Cases', () {
    test('returns null when no data has ever been emitted', () async {
      final deps = createTestDependencies();

      await deps.deviceManager.addDevice(deps.fakeDevice);
      deps.deviceManager.assignPowerSource(deps.fakeDevice.id);

      // Never emit any data
      expect(deps.deviceManager.powerStream.value, isNull);
    });

    test('cancels timer when device is unassigned', () async {
      final deps = createTestDependencies();

      await deps.deviceManager.addDevice(deps.fakeDevice);
      deps.deviceManager.assignPowerSource(deps.fakeDevice.id);

      deps.fakeDevice.emitPower(PowerData(watts: 195, timestamp: clock.now()));
      await Future.delayed(const Duration(milliseconds: 50));
      expect(deps.deviceManager.powerStream.value, isNotNull);

      // Unassign the device
      deps.deviceManager.assignPowerSource(null);
      await Future.delayed(const Duration(milliseconds: 50));

      // Should be null immediately after unassignment
      expect(deps.deviceManager.powerStream.value, isNull);
    });
  });
}
