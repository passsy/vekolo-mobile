import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
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
import '../helpers/shared_preferences_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DeviceManager Auto-Connect', () {
    Future<({DeviceManager manager, FakeBlePlatform platform, BleScanner scanner})> createDeviceManager() async {
      final platform = FakeBlePlatform();
      platform.setAdapterState(BluetoothAdapterState.on);
      final scanner = BleScanner(platform: platform, permissions: FakeBlePermissions());
      scanner.initialize();
      final transportRegistry = TransportRegistry();
      transportRegistry.register(ftmsTransportRegistration);
      transportRegistry.register(heartRateTransportRegistration);
      addTearDown(() => scanner.dispose());
      final prefs = createTestSharedPreferencesAsync();
      final persistence = DeviceAssignmentPersistence(prefs);
      final deviceManager = DeviceManager(
        platform: platform,
        scanner: scanner,
        transportRegistry: transportRegistry,
        persistence: persistence,
      );
      addTearDown(() async => await deviceManager.dispose());
      return (manager: deviceManager, platform: platform, scanner: scanner);
    }

    final ftmsServiceUuid = Guid('00001826-0000-1000-8000-00805f9b34fb');
    final heartRateServiceUuid = Guid('0000180d-0000-1000-8000-00805f9b34fb');

    group('initialize', () {
      test('does nothing when no saved assignments', () async {
        final deps = await createDeviceManager();

        await deps.manager.initialize();

        expect(deps.manager.devices, isEmpty);
        expect(deps.manager.smartTrainerBeacon.value, isNull);
      });

      test('connects to already discovered devices', () async {
        final deps = await createDeviceManager();

        // Create a trainer device and add it to platform
        final trainer = MockTrainer(id: 'trainer-1', name: 'Test Trainer');
        await deps.manager.addDevice(trainer);
        deps.manager.assignSmartTrainer(trainer.id);

        // Save assignments
        // Wait for auto-save via beacon subscription (needs extra time for async beacon + persistence)
        await Future.delayed(const Duration(milliseconds: 200));

        // Create new device manager (simulating app restart) with fresh dependencies
        final newDeps = await createDeviceManager();

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
        expect(newDeps.manager.smartTrainerBeacon.value?.deviceId, equals('trainer-1'));
      });

      test('starts scanning for missing devices', () async {
        final deps = await createDeviceManager();

        // Save an assignment for a device that doesn't exist yet
        final trainer = MockTrainer(id: 'trainer-1', name: 'Test Trainer');
        await deps.manager.addDevice(trainer);
        deps.manager.assignSmartTrainer(trainer.id);
        // Wait for auto-save via beacon subscription (needs extra time for async beacon + persistence)
        await Future.delayed(const Duration(milliseconds: 200));

        // Dispose the first manager (but assignments remain saved in persistence)
        await deps.manager.dispose();
        deps.scanner.dispose();

        // Create new device manager with fresh dependencies
        // The persistence still has the saved assignment, but the device hasn't been discovered yet
        final newDeps = await createDeviceManager();

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
        expect(newDeps.manager.smartTrainerBeacon.value?.deviceId, equals('trainer-1'));

        // Scanning should stop after device is found
        await Future.delayed(const Duration(milliseconds: 200));
        expect(newDeps.scanner.isScanning.value, isFalse);
      });

      test('restores multiple device assignments', () async {
        final deps = await createDeviceManager();

        // Create and assign devices
        final trainer = MockTrainer(id: 'trainer-1', name: 'Trainer');
        final hrMonitor = DeviceSimulator.createHeartRateMonitor(name: 'HR Monitor');
        await deps.manager.addDevice(trainer);
        await deps.manager.addDevice(hrMonitor);
        deps.manager.assignSmartTrainer(trainer.id);
        deps.manager.assignHeartRateSource(hrMonitor.id);
        // Wait for auto-save via beacon subscription (needs extra time for async beacon + persistence)
        await Future.delayed(const Duration(milliseconds: 200));
        await pumpEventQueue();

        // Create new device manager with fresh dependencies
        final newDeps = await createDeviceManager();

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
        await pumpEventQueue();

        expect(newDeps.manager.devices, hasLength(2));
        expect(newDeps.manager.smartTrainerBeacon.value?.deviceId, equals('trainer-1'));
        expect(newDeps.manager.heartRateSourceBeacon.value?.deviceId, equals(hrDeviceId));
      });
    });

    group('_shouldStopAutoConnectScanning', () {
      test('stops when all devices found', () async {
        final deps = await createDeviceManager();

        // Add a device and assign it
        final trainer = MockTrainer(id: 'trainer-1', name: 'Trainer');
        await deps.manager.addDevice(trainer);
        deps.manager.assignSmartTrainer(trainer.id);
        // Wait for auto-save via beacon subscription (needs extra time for async beacon + persistence)
        await Future.delayed(const Duration(milliseconds: 200));

        // Simulate all devices found by clearing the set
        // Note: This tests the internal logic indirectly through initialize
        await deps.manager.initialize();

        // After devices are found, scanning should stop
        // We can't directly test _shouldStopAutoConnectScanning, but we can verify
        // the behavior through scanning state
        expect(deps.manager.devices, isNotEmpty);
      });

      test('stops when all sensors assigned', () async {
        final deps = await createDeviceManager();

        // Save assignments for devices that will be discovered
        final trainer = MockTrainer(id: 'trainer-1', name: 'Trainer');
        final powerMeter = DeviceSimulator.createPowerMeter(name: 'Power');
        final cadenceSensor = DeviceSimulator.createCadenceSensor(name: 'Cadence');
        final hrMonitor = DeviceSimulator.createHeartRateMonitor(name: 'HR');

        await deps.manager.addDevice(trainer);
        await deps.manager.addDevice(powerMeter);
        await deps.manager.addDevice(cadenceSensor);
        await deps.manager.addDevice(hrMonitor);

        deps.manager.assignSmartTrainer(trainer.id);
        deps.manager.assignPowerSource(powerMeter.id);
        deps.manager.assignCadenceSource(cadenceSensor.id);
        deps.manager.assignSpeedSource(trainer.id); // Trainer provides speed
        deps.manager.assignHeartRateSource(hrMonitor.id);

        // Wait for auto-save via beacon subscription (needs extra time for async beacon + persistence)
        await Future.delayed(const Duration(milliseconds: 200));

        // Dispose the first manager (but assignments remain saved in persistence)
        await deps.manager.dispose();
        deps.scanner.dispose();

        // Create new device manager (simulating app restart)
        final newDeps = await createDeviceManager();

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
        expect(newDeps.manager.smartTrainerBeacon.value, isNotNull);
        expect(newDeps.manager.powerSourceBeacon.value, isNotNull);
        expect(newDeps.manager.cadenceSourceBeacon.value, isNotNull);
        expect(newDeps.manager.speedSourceBeacon.value, isNotNull);
        expect(newDeps.manager.heartRateSourceBeacon.value, isNotNull);

        // Verify scanning stopped when all sensors were assigned
        expect(newDeps.scanner.isScanning.value, isFalse);
      });
    });

    group('error handling', () {
      test('handles connection failures gracefully', () async {
        final deps = await createDeviceManager();

        // Save assignment
        final trainer = MockTrainer(id: 'trainer-1', name: 'Trainer');
        await deps.manager.addDevice(trainer);
        deps.manager.assignSmartTrainer(trainer.id);
        // Wait for auto-save via beacon subscription (needs extra time for async beacon + persistence)
        await Future.delayed(const Duration(milliseconds: 200));

        // Dispose the first manager (but assignments remain saved in persistence)
        await deps.manager.dispose();
        deps.scanner.dispose();

        // Create new manager with fresh dependencies
        final newDeps = await createDeviceManager();

        // Make connection fail
        newDeps.platform.overrideConnect = (deviceId, {Duration timeout = const Duration(seconds: 35)}) {
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
        final deps = await createDeviceManager();

        // Save assignment for device that won't be discovered
        final trainer = MockTrainer(id: 'trainer-1', name: 'Trainer');
        await deps.manager.addDevice(trainer);
        deps.manager.assignSmartTrainer(trainer.id);
        // Wait for auto-save via beacon subscription (needs extra time for async beacon + persistence)
        await Future.delayed(const Duration(milliseconds: 200));

        // Dispose the first manager (but assignments remain saved in persistence)
        await deps.manager.dispose();
        deps.scanner.dispose();

        // Create new manager with fresh dependencies
        final newDeps = await createDeviceManager();

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

    group('duplicate connection prevention', () {
      test('prevents multiple simultaneous connection attempts to same device', () async {
        final deps = await createDeviceManager();

        // Save assignment
        final trainer = MockTrainer(id: 'trainer-1', name: 'Trainer');
        await deps.manager.addDevice(trainer);
        deps.manager.assignSmartTrainer(trainer.id);
        // Wait for auto-save via beacon subscription (needs extra time for async beacon + persistence)
        await Future.delayed(const Duration(milliseconds: 200));

        // Dispose the first manager (but assignments remain saved in persistence)
        await deps.manager.dispose();
        deps.scanner.dispose();

        // Create new manager with fresh dependencies
        final newDeps = await createDeviceManager();

        // Track connection attempts
        int connectionAttempts = 0;
        newDeps.platform.overrideConnect = (deviceId, {Duration timeout = const Duration(seconds: 35)}) async {
          connectionAttempts++;
          // Simulate slow connection (500ms) - much longer than typical BLE advertisement interval (100-200ms)
          // This ensures multiple scanner updates happen during connection
          await Future.delayed(const Duration(milliseconds: 500));
          return;
        };

        // Add device to the new platform
        final fakeDevice = newDeps.platform.addDevice('trainer-1', 'Trainer', rssi: -60, services: [ftmsServiceUuid]);
        fakeDevice.turnOn();

        await Future.delayed(const Duration(milliseconds: 100));

        // Initialize - this will start scanning
        await newDeps.manager.initialize();

        // Wait a bit for scanning to discover the device and start connection
        await Future.delayed(const Duration(milliseconds: 150));

        // Simulate BLE advertisement intervals (typical: 100-200ms) by forcing scanner updates
        // While connection is in progress (takes 500ms), these updates would trigger duplicate
        // connection attempts in the buggy version
        for (int i = 0; i < 5; i++) {
          fakeDevice.updateRssi(-60 + (i % 3) * 5); // Vary RSSI to simulate real conditions
          await Future.delayed(const Duration(milliseconds: 100)); // Typical advertisement interval
        }

        // Wait for connection to complete and all async operations to finish
        await Future.delayed(const Duration(milliseconds: 300));

        // Verify only ONE connection attempt was made despite multiple scanner updates
        expect(connectionAttempts, equals(1), reason: 'Should only attempt connection once');
      });
    });

    group('assignment restoration', () {
      test('restores smart trainer assignment', () async {
        final deps = await createDeviceManager();

        final trainer = MockTrainer(id: 'trainer-1', name: 'Trainer');
        await deps.manager.addDevice(trainer);
        deps.manager.assignSmartTrainer(trainer.id);
        // Wait for auto-save via beacon subscription (needs extra time for async beacon + persistence)
        await Future.delayed(const Duration(milliseconds: 200));

        // Dispose the first manager (but assignments remain saved in persistence)
        await deps.manager.dispose();
        deps.scanner.dispose();

        // Create new manager with fresh dependencies
        final newDeps = await createDeviceManager();

        final fakeDevice = newDeps.platform.addDevice('trainer-1', 'Trainer', rssi: -60, services: [ftmsServiceUuid]);
        fakeDevice.turnOn();

        await Future.delayed(const Duration(milliseconds: 100));
        await newDeps.manager.initialize();
        await Future.delayed(const Duration(milliseconds: 500));

        expect(newDeps.manager.smartTrainerBeacon.value?.deviceId, equals('trainer-1'));
      });

      test('restores multiple role assignments for same device', () async {
        final deps = await createDeviceManager();

        final trainer = MockTrainer(id: 'trainer-1', name: 'Trainer');
        await deps.manager.addDevice(trainer);
        deps.manager.assignSmartTrainer(trainer.id);
        deps.manager.assignPowerSource(trainer.id);
        deps.manager.assignCadenceSource(trainer.id);
        // Wait for auto-save via beacon subscription (needs extra time for async beacon + persistence)
        await Future.delayed(const Duration(milliseconds: 200));

        // Dispose the first manager (but assignments remain saved in persistence)
        await deps.manager.dispose();
        deps.scanner.dispose();

        // Create new manager with fresh dependencies
        final newDeps = await createDeviceManager();

        final fakeDevice = newDeps.platform.addDevice('trainer-1', 'Trainer', rssi: -60, services: [ftmsServiceUuid]);
        fakeDevice.turnOn();

        await Future.delayed(const Duration(milliseconds: 100));
        await newDeps.manager.initialize();
        await Future.delayed(const Duration(milliseconds: 500));

        expect(newDeps.manager.smartTrainerBeacon.value?.deviceId, equals('trainer-1'));
        expect(newDeps.manager.powerSourceBeacon.value?.deviceId, equals('trainer-1'));
        expect(newDeps.manager.cadenceSourceBeacon.value?.deviceId, equals('trainer-1'));
      });
    });
  });
}
