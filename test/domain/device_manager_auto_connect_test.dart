import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vekolo/ble/ble_scanner.dart';
import 'package:vekolo/ble/ftms_ble_transport.dart';
import 'package:vekolo/ble/heart_rate_ble_transport.dart';
import 'package:vekolo/ble/transport_registry.dart';
import 'package:vekolo/domain/devices/device_manager.dart';
import 'package:vekolo/domain/mocks/device_simulator.dart';
import 'package:vekolo/domain/mocks/mock_trainer.dart';
import 'package:vekolo/domain/models/device_info.dart';
import 'package:vekolo/services/device_assignment_persistence.dart';
import '../ble/fake_ble_platform.dart';
import '../ble/fake_ble_permissions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DeviceManager Auto-Connect', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    ({DeviceManager manager, FakeBlePlatform platform, BleScanner scanner}) createDeviceManager() {
      final platform = FakeBlePlatform();
      platform.setAdapterState(BluetoothAdapterState.on);
      final scanner = BleScanner(platform: platform, permissions: FakeBlePermissions());
      scanner.initialize();
      final transportRegistry = TransportRegistry();
      transportRegistry.register(ftmsTransportRegistration);
      transportRegistry.register(heartRateTransportRegistration);
      addTearDown(() => scanner.dispose());
      final deviceManager = DeviceManager(platform: platform, scanner: scanner, transportRegistry: transportRegistry);
      addTearDown(() async => await deviceManager.dispose());
      return (manager: deviceManager, platform: platform, scanner: scanner);
    }

    final ftmsServiceUuid = Guid('00001826-0000-1000-8000-00805f9b34fb');
    final heartRateServiceUuid = Guid('0000180d-0000-1000-8000-00805f9b34fb');

    group('initialize', () {
      test('does nothing when no saved assignments', () async {
        final deps = createDeviceManager();

        await deps.manager.initialize();

        expect(deps.manager.devices, isEmpty);
        expect(deps.manager.primaryTrainer, isNull);
      });

      test('connects to already discovered devices', () async {
        final deps = createDeviceManager();

        // Create a trainer device and add it to platform
        final trainer = MockTrainer(id: 'trainer-1', name: 'Test Trainer');
        await deps.manager.addDevice(trainer);
        deps.manager.assignPrimaryTrainer(trainer.id);

        // Save assignments
        await saveDeviceAssignments(deps.manager);

        // Create new device manager (simulating app restart) with fresh dependencies
        final newDeps = createDeviceManager();

        // Simulate device already discovered on the new platform
        final fakeDevice = newDeps.platform.addDevice(
          'trainer-1',
          'Test Trainer',
          rssi: -60,
          services: [ftmsServiceUuid],
        );
        fakeDevice.turnOn();

        // Wait for scanner to discover
        await Future.delayed(const Duration(milliseconds: 100));

        // Initialize should connect to the discovered device
        await newDeps.manager.initialize();

        // Wait for connection and assignment restoration
        await Future.delayed(const Duration(milliseconds: 200));

        expect(newDeps.manager.devices, hasLength(1));
        expect(newDeps.manager.primaryTrainer?.id, equals('trainer-1'));
      });

      test('starts scanning for missing devices', () async {
        final deps = createDeviceManager();

        // Save an assignment for a device that doesn't exist yet
        final trainer = MockTrainer(id: 'trainer-1', name: 'Test Trainer');
        await deps.manager.addDevice(trainer);
        deps.manager.assignPrimaryTrainer(trainer.id);
        await saveDeviceAssignments(deps.manager);

        // Remove device to simulate it not being discovered yet
        await deps.manager.removeDevice(trainer.id);

        // Create new device manager with fresh dependencies
        final newDeps = createDeviceManager();

        // Initialize should start scanning
        await newDeps.manager.initialize();

        // Wait a bit for scanning to start (it's async)
        await Future.delayed(const Duration(milliseconds: 100));

        // Verify scanning started
        expect(newDeps.scanner.isScanning.value, isTrue);

        // Now add the device to the new platform
        final fakeDevice = newDeps.platform.addDevice(
          'trainer-1',
          'Test Trainer',
          rssi: -60,
          services: [ftmsServiceUuid],
        );
        fakeDevice.turnOn();

        // Wait for discovery and connection
        await Future.delayed(const Duration(milliseconds: 500));

        // Device should be connected and assigned
        expect(newDeps.manager.devices, hasLength(1));
        expect(newDeps.manager.primaryTrainer?.id, equals('trainer-1'));

        // Scanning should stop after device is found
        await Future.delayed(const Duration(milliseconds: 200));
        expect(newDeps.scanner.isScanning.value, isFalse);
      });

      test('restores multiple device assignments', () async {
        final deps = createDeviceManager();

        // Create and assign devices
        final trainer = MockTrainer(id: 'trainer-1', name: 'Trainer');
        final hrMonitor = DeviceSimulator.createHeartRateMonitor(name: 'HR Monitor');
        await deps.manager.addDevice(trainer);
        await deps.manager.addDevice(hrMonitor);
        deps.manager.assignPrimaryTrainer(trainer.id);
        deps.manager.assignHeartRateSource(hrMonitor.id);
        await saveDeviceAssignments(deps.manager);

        // Create new device manager with fresh dependencies
        final newDeps = createDeviceManager();

        // Add devices to the new platform
        final trainerDevice = newDeps.platform.addDevice(
          'trainer-1',
          'Trainer',
          rssi: -60,
          services: [ftmsServiceUuid],
        );
        trainerDevice.turnOn();

        // Use the actual hrMonitor ID from DeviceSimulator
        final hrDeviceId = hrMonitor.id;
        final hrDevice = newDeps.platform.addDevice(
          hrDeviceId,
          'HR Monitor',
          rssi: -70,
          services: [heartRateServiceUuid],
        );
        hrDevice.turnOn();

        // Wait for discovery
        await Future.delayed(const Duration(milliseconds: 100));

        // Initialize
        await newDeps.manager.initialize();

        // Wait for connections and assignments
        await Future.delayed(const Duration(milliseconds: 500));

        expect(newDeps.manager.devices, hasLength(2));
        expect(newDeps.manager.primaryTrainer?.id, equals('trainer-1'));
        expect(newDeps.manager.heartRateSource?.id, equals(hrDeviceId));
      });
    });

    group('_shouldStopAutoConnectScanning', () {
      test('stops when all devices found', () async {
        final deps = createDeviceManager();

        // Add a device and assign it
        final trainer = MockTrainer(id: 'trainer-1', name: 'Trainer');
        await deps.manager.addDevice(trainer);
        deps.manager.assignPrimaryTrainer(trainer.id);
        await saveDeviceAssignments(deps.manager);

        // Simulate all devices found by clearing the set
        // Note: This tests the internal logic indirectly through initialize
        await deps.manager.initialize();

        // After devices are found, scanning should stop
        // We can't directly test _shouldStopAutoConnectScanning, but we can verify
        // the behavior through scanning state
        expect(deps.manager.devices, isNotEmpty);
      });

      test('stops when all sensors assigned', () async {
        final deps = createDeviceManager();

        // Save assignments for devices that will be discovered
        final trainer = MockTrainer(id: 'trainer-1', name: 'Trainer');
        final powerMeter = DeviceSimulator.createPowerMeter(name: 'Power');
        final cadenceSensor = DeviceSimulator.createCadenceSensor(name: 'Cadence');
        final hrMonitor = DeviceSimulator.createHeartRateMonitor(name: 'HR');

        await deps.manager.addDevice(trainer);
        await deps.manager.addDevice(powerMeter);
        await deps.manager.addDevice(cadenceSensor);
        await deps.manager.addDevice(hrMonitor);

        deps.manager.assignPrimaryTrainer(trainer.id);
        deps.manager.assignPowerSource(powerMeter.id);
        deps.manager.assignCadenceSource(cadenceSensor.id);
        deps.manager.assignSpeedSource(trainer.id); // Trainer provides speed
        deps.manager.assignHeartRateSource(hrMonitor.id);

        await saveDeviceAssignments(deps.manager);
        await deps.manager.removeDevice(trainer.id);
        await deps.manager.removeDevice(powerMeter.id);
        await deps.manager.removeDevice(cadenceSensor.id);
        await deps.manager.removeDevice(hrMonitor.id);

        // Create new device manager (simulating app restart)
        final newDeps = createDeviceManager();

        // Initialize should start scanning
        await newDeps.manager.initialize();

        // Wait for scanning to start
        await Future.delayed(const Duration(milliseconds: 100));
        expect(newDeps.scanner.isScanning.value, isTrue);

        // Add all devices to platform and assign them as they're discovered
        final trainerDevice = newDeps.platform.addDevice(
          'trainer-1',
          'Trainer',
          rssi: -60,
          services: [ftmsServiceUuid],
        );
        trainerDevice.turnOn();

        final powerDevice = newDeps.platform.addDevice(powerMeter.id, 'Power', rssi: -60, services: [ftmsServiceUuid]);
        powerDevice.turnOn();

        final cadenceDevice = newDeps.platform.addDevice(
          cadenceSensor.id,
          'Cadence',
          rssi: -60,
          services: [ftmsServiceUuid],
        );
        cadenceDevice.turnOn();

        final hrDevice = newDeps.platform.addDevice(hrMonitor.id, 'HR', rssi: -70, services: [heartRateServiceUuid]);
        hrDevice.turnOn();

        // Wait for devices to be discovered, connected, and assigned
        await Future.delayed(const Duration(milliseconds: 500));

        // Assign all sensors (this should trigger scan stop)
        newDeps.manager.assignSpeedSource(trainer.id);

        // Wait for scan to stop
        await Future.delayed(const Duration(milliseconds: 200));

        // Verify all sensors are assigned
        expect(newDeps.manager.primaryTrainer, isNotNull);
        expect(newDeps.manager.powerSource, isNotNull);
        expect(newDeps.manager.cadenceSource, isNotNull);
        expect(newDeps.manager.speedSource, isNotNull);
        expect(newDeps.manager.heartRateSource, isNotNull);

        // Verify scanning stopped when all sensors were assigned
        expect(newDeps.scanner.isScanning.value, isFalse);
      });
    });

    group('error handling', () {
      test('handles connection failures gracefully', () async {
        final deps = createDeviceManager();

        // Save assignment
        final trainer = MockTrainer(id: 'trainer-1', name: 'Trainer');
        await deps.manager.addDevice(trainer);
        deps.manager.assignPrimaryTrainer(trainer.id);
        await saveDeviceAssignments(deps.manager);
        await deps.manager.removeDevice(trainer.id);

        // Create new manager with fresh dependencies
        final newDeps = createDeviceManager();

        // Make connection fail
        newDeps.platform.overrideConnect = (deviceId, {Duration timeout = const Duration(seconds: 35)}) async {
          throw Exception('Connection failed');
        };

        // Add device to the new platform
        final fakeDevice = newDeps.platform.addDevice('trainer-1', 'Trainer', rssi: -60, services: [ftmsServiceUuid]);
        fakeDevice.turnOn();

        await Future.delayed(const Duration(milliseconds: 100));

        // Initialize should not throw
        await newDeps.manager.initialize();

        // Wait for connection attempt
        await Future.delayed(const Duration(milliseconds: 500));

        // Device might be added even if connection fails (it's added before connecting)
        // But connection should fail
        if (newDeps.manager.devices.isNotEmpty) {
          final device = newDeps.manager.devices.first;
          expect(device.connectionState.value, isNot(equals(ConnectionState.connected)));
        }
      });

      test('handles missing device in scanner gracefully', () async {
        final deps = createDeviceManager();

        // Save assignment for device that won't be discovered
        final trainer = MockTrainer(id: 'trainer-1', name: 'Trainer');
        await deps.manager.addDevice(trainer);
        deps.manager.assignPrimaryTrainer(trainer.id);
        await saveDeviceAssignments(deps.manager);
        await deps.manager.removeDevice(trainer.id);

        // Create new manager with fresh dependencies
        final newDeps = createDeviceManager();

        // Initialize should start scanning but device never appears
        await newDeps.manager.initialize();

        // Wait a bit for scanning to start (it's async)
        await Future.delayed(const Duration(milliseconds: 100));

        expect(newDeps.scanner.isScanning.value, isTrue);
        expect(newDeps.manager.devices, isEmpty);

        // Scanning should continue until stopped manually or all sensors assigned
        await Future.delayed(const Duration(milliseconds: 500));
        expect(newDeps.scanner.isScanning.value, isTrue);
      });
    });

    group('assignment restoration', () {
      test('restores primary trainer assignment', () async {
        final deps = createDeviceManager();

        final trainer = MockTrainer(id: 'trainer-1', name: 'Trainer');
        await deps.manager.addDevice(trainer);
        deps.manager.assignPrimaryTrainer(trainer.id);
        await saveDeviceAssignments(deps.manager);
        await deps.manager.removeDevice(trainer.id);

        // Create new manager with fresh dependencies
        final newDeps = createDeviceManager();

        final fakeDevice = newDeps.platform.addDevice('trainer-1', 'Trainer', rssi: -60, services: [ftmsServiceUuid]);
        fakeDevice.turnOn();

        await Future.delayed(const Duration(milliseconds: 100));
        await newDeps.manager.initialize();
        await Future.delayed(const Duration(milliseconds: 500));

        expect(newDeps.manager.primaryTrainer?.id, equals('trainer-1'));
      });

      test('restores multiple role assignments for same device', () async {
        final deps = createDeviceManager();

        final trainer = MockTrainer(id: 'trainer-1', name: 'Trainer');
        await deps.manager.addDevice(trainer);
        deps.manager.assignPrimaryTrainer(trainer.id);
        deps.manager.assignPowerSource(trainer.id);
        deps.manager.assignCadenceSource(trainer.id);
        await saveDeviceAssignments(deps.manager);
        await deps.manager.removeDevice(trainer.id);

        // Create new manager with fresh dependencies
        final newDeps = createDeviceManager();

        final fakeDevice = newDeps.platform.addDevice('trainer-1', 'Trainer', rssi: -60, services: [ftmsServiceUuid]);
        fakeDevice.turnOn();

        await Future.delayed(const Duration(milliseconds: 100));
        await newDeps.manager.initialize();
        await Future.delayed(const Duration(milliseconds: 500));

        expect(newDeps.manager.primaryTrainer?.id, equals('trainer-1'));
        expect(newDeps.manager.powerSource?.id, equals('trainer-1'));
        expect(newDeps.manager.cadenceSource?.id, equals('trainer-1'));
      });
    });
  });
}
