import 'package:flutter_test/flutter_test.dart';
import 'package:vekolo/domain/devices/device_manager.dart';
import 'package:vekolo/domain/mocks/device_simulator.dart';
import 'package:vekolo/state/device_state.dart';
import 'package:vekolo/state/device_state_manager.dart';

void main() {
  group('DeviceStateManager', () {
    late DeviceManager deviceManager;
    late DeviceStateManager stateManager;

    setUp(() {
      deviceManager = DeviceManager();
      stateManager = DeviceStateManager(deviceManager);
    });

    tearDown(() {
      stateManager.dispose();
      deviceManager.dispose();
    });

    test('initializes all beacons with empty/null values', () {
      expect(connectedDevicesBeacon.value, isEmpty);
      expect(primaryTrainerBeacon.value, isNull);
      expect(powerSourceBeacon.value, isNull);
      expect(cadenceSourceBeacon.value, isNull);
      expect(heartRateSourceBeacon.value, isNull);
      expect(currentPowerBeacon.value, isNull);
      expect(currentCadenceBeacon.value, isNull);
      expect(currentHeartRateBeacon.value, isNull);
    });

    test('updates connectedDevicesBeacon when device is added', () async {
      final trainer = DeviceSimulator.createRealisticTrainer(name: 'Test Trainer');

      await deviceManager.addDevice(trainer);

      // Wait for polling to update
      await Future<void>.delayed(const Duration(milliseconds: 600));

      expect(connectedDevicesBeacon.value, hasLength(1));
      expect(connectedDevicesBeacon.value.first.name, equals('Test Trainer'));
    });

    test('updates primaryTrainerBeacon when trainer is assigned', () async {
      final trainer = DeviceSimulator.createRealisticTrainer(name: 'Test Trainer');

      await deviceManager.addDevice(trainer);
      deviceManager.assignPrimaryTrainer(trainer.id);

      // Wait for polling to update
      await Future<void>.delayed(const Duration(milliseconds: 600));

      expect(primaryTrainerBeacon.value, isNotNull);
      expect(primaryTrainerBeacon.value?.id, equals(trainer.id));
    });

    test('updates currentPowerBeacon when power data is emitted', () async {
      final trainer = DeviceSimulator.createRealisticTrainer(name: 'Test Trainer');

      await deviceManager.addDevice(trainer);
      deviceManager.assignPrimaryTrainer(trainer.id);

      // Connect and start generating power data
      await trainer.connect();
      await trainer.setTargetPower(200);

      // Wait for data to flow through
      await Future<void>.delayed(const Duration(milliseconds: 500));

      expect(currentPowerBeacon.value, isNotNull);
      expect(currentPowerBeacon.value?.watts, greaterThan(0));
    });

    test('updates currentCadenceBeacon when cadence data is emitted', () async {
      final trainer = DeviceSimulator.createRealisticTrainer(name: 'Test Trainer');

      await deviceManager.addDevice(trainer);
      deviceManager.assignPrimaryTrainer(trainer.id);

      // Connect and start generating cadence data
      await trainer.connect();
      await trainer.setTargetPower(200);

      // Wait for data to flow through
      await Future<void>.delayed(const Duration(milliseconds: 500));

      expect(currentCadenceBeacon.value, isNotNull);
      expect(currentCadenceBeacon.value?.rpm, greaterThan(0));
    });

    test('updates heartRateSourceBeacon when HR monitor is assigned', () async {
      final hrMonitor = DeviceSimulator.createHeartRateMonitor(name: 'Test HRM');

      await deviceManager.addDevice(hrMonitor);
      deviceManager.assignHeartRateSource(hrMonitor.id);

      // Wait for polling to update
      await Future<void>.delayed(const Duration(milliseconds: 600));

      expect(heartRateSourceBeacon.value, isNotNull);
      expect(heartRateSourceBeacon.value?.id, equals(hrMonitor.id));
    });

    test('updates currentHeartRateBeacon when HR data is emitted', () async {
      final hrMonitor = DeviceSimulator.createHeartRateMonitor(name: 'Test HRM');

      await deviceManager.addDevice(hrMonitor);
      deviceManager.assignHeartRateSource(hrMonitor.id);

      // Connect to start generating HR data
      await hrMonitor.connect();

      // Wait for data to flow through
      await Future<void>.delayed(const Duration(milliseconds: 1100));

      expect(currentHeartRateBeacon.value, isNotNull);
      expect(currentHeartRateBeacon.value?.bpm, greaterThan(0));
    });

    test('clears beacons when devices are removed', () async {
      final trainer = DeviceSimulator.createRealisticTrainer(name: 'Test Trainer');

      await deviceManager.addDevice(trainer);
      deviceManager.assignPrimaryTrainer(trainer.id);
      await trainer.connect();
      await trainer.setTargetPower(200);

      // Wait for data to flow
      await Future<void>.delayed(const Duration(milliseconds: 600));

      expect(connectedDevicesBeacon.value, isNotEmpty);
      expect(primaryTrainerBeacon.value, isNotNull);

      // Remove the device
      await deviceManager.removeDevice(trainer.id);

      // Wait for polling to update
      await Future<void>.delayed(const Duration(milliseconds: 600));

      expect(connectedDevicesBeacon.value, isEmpty);
      expect(primaryTrainerBeacon.value, isNull);
    });

    test('disposes subscriptions and stops polling', () {
      // This should not throw
      stateManager.dispose();

      // Beacons should still be accessible (they're global singletons)
      expect(() => connectedDevicesBeacon.value, returnsNormally);
    });
  });
}
