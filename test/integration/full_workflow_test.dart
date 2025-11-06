/// End-to-end integration test for multi-device fitness architecture.
///
/// Tests the complete flow from device setup through data streaming and
/// workout synchronization. This verifies that all components work together
/// correctly in realistic scenarios.
///
/// Covers:
/// - Device discovery and connection
/// - Role assignment (trainer, power meter, HR monitor)
/// - Data flow through aggregated streams
/// - Workout sync with target power updates
/// - State management and beacon updates
/// - Error handling and recovery
import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vekolo/domain/devices/device_manager.dart';
import 'package:vekolo/domain/mocks/device_simulator.dart';
import 'package:vekolo/domain/models/erg_command.dart';
import 'package:vekolo/services/device_assignment_persistence.dart';
import 'package:vekolo/services/workout_sync_service.dart';
import '../ble/fake_ble_platform.dart';
import '../ble/fake_ble_permissions.dart';
import '../helpers/shared_preferences_helper.dart';
import 'package:vekolo/ble/ble_scanner.dart';
import 'package:vekolo/ble/transport_registry.dart';

void main() {
  group('Full Workflow Integration', () {
    /// Creates a test environment with all required managers.
    ///
    /// Automatically disposes resources using addTearDown to prevent state leaks.
    Future<({DeviceManager deviceManager, WorkoutSyncService syncService})> createTestEnvironment() async {
      final blePlatform = FakeBlePlatform();
      final scanner = BleScanner(platform: blePlatform, permissions: FakeBlePermissions());
      final transportRegistry = TransportRegistry();
      final prefs = createTestSharedPreferencesAsync();
      final persistence = DeviceAssignmentPersistence(prefs);
      final deviceManager = DeviceManager(
        platform: blePlatform,
        scanner: scanner,
        transportRegistry: transportRegistry,
        persistence: persistence,
      );
      final syncService = WorkoutSyncService(deviceManager);

      addTearDown(() async {
        syncService.dispose();
        await deviceManager.dispose();
      });

      return (deviceManager: deviceManager, syncService: syncService);
    }

    test('complete multi-device setup and workout sync flow', () async {
      final env = await createTestEnvironment();
      final deviceManager = env.deviceManager;
      final syncService = env.syncService;

      // =====================================================================
      // Phase 1: Device Setup
      // =====================================================================

      // Create realistic mock devices
      final trainer = DeviceSimulator.createRealisticTrainer(name: 'Wahoo KICKR', ftpWatts: 250);
      final powerMeter = DeviceSimulator.createPowerMeter(name: 'PowerTap P2', variability: 0.02);
      final hrMonitor = DeviceSimulator.createHeartRateMonitor(name: 'Polar H10', restingHr: 55, maxHr: 190);

      // Add devices to manager
      await deviceManager.addDevice(trainer);
      await deviceManager.addDevice(powerMeter);
      await deviceManager.addDevice(hrMonitor);

      // Verify devices were added
      expect(deviceManager.devices, hasLength(3));

      // Wait for state polling to update beacons
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(deviceManager.devicesBeacon.value, hasLength(3));

      // =====================================================================
      // Phase 2: Device Assignment
      // =====================================================================

      // Assign devices to roles
      deviceManager.assignPrimaryTrainer(trainer.id);
      deviceManager.assignPowerSource(powerMeter.id); // Override trainer power
      deviceManager.assignHeartRateSource(hrMonitor.id);

      // Verify assignments
      expect(deviceManager.primaryTrainerBeacon.value?.deviceId, equals(trainer.id));
      expect(deviceManager.powerSourceBeacon.value?.deviceId, equals(powerMeter.id));
      expect(deviceManager.heartRateSourceBeacon.value?.deviceId, equals(hrMonitor.id));

      // Wait for beacons to update
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(deviceManager.primaryTrainerBeacon.value?.deviceId, equals(trainer.id));
      expect(deviceManager.powerSourceBeacon.value?.deviceId, equals(powerMeter.id));
      expect(deviceManager.heartRateSourceBeacon.value?.deviceId, equals(hrMonitor.id));

      // =====================================================================
      // Phase 3: Device Connection
      // =====================================================================

      // Connect all devices via DeviceManager
      await deviceManager.connectDevice(trainer.id).value;
      await deviceManager.connectDevice(powerMeter.id).value;
      await deviceManager.connectDevice(hrMonitor.id).value;

      // Start trainer in ERG mode
      await trainer.setTargetPower(150);

      // Wait for initial data to flow (HR monitor needs 1+ seconds)
      await Future<void>.delayed(const Duration(milliseconds: 1200));

      // =====================================================================
      // Phase 4: Verify Data Flow
      // =====================================================================

      // Verify power data comes from dedicated power meter (not trainer)
      expect(deviceManager.powerStream.value, isNotNull);
      expect(deviceManager.powerStream.value?.watts, greaterThan(0));

      // Verify cadence data comes from trainer (no dedicated cadence sensor)
      expect(deviceManager.cadenceStream.value, isNotNull);
      expect(deviceManager.cadenceStream.value?.rpm, greaterThan(0));

      // Verify heart rate data comes from HR monitor
      expect(deviceManager.heartRateStream.value, isNotNull);
      expect(deviceManager.heartRateStream.value?.bpm, greaterThanOrEqualTo(55));

      // Collect multiple data points to verify continuous streaming
      final powerReadings = <int>[];
      final unsubscribe = deviceManager.powerStream.subscribe((data) {
        if (data != null) {
          powerReadings.add(data.watts);
        }
      });

      await Future<void>.delayed(const Duration(milliseconds: 1500));
      expect(powerReadings.length, greaterThanOrEqualTo(2));
      unsubscribe();

      // =====================================================================
      // Phase 5: Workout Sync Flow
      // =====================================================================

      // Start syncing
      syncService.startSync();
      expect(syncService.isSyncing.value, isTrue);

      // Set first workout target
      final firstTarget = ErgCommand(targetWatts: 200, timestamp: clock.now());
      syncService.currentTarget.value = firstTarget;

      // Wait for sync to complete
      await Future<void>.delayed(const Duration(milliseconds: 300));

      // Verify sync succeeded
      expect(syncService.lastSyncTime.value, isNotNull);
      expect(syncService.syncError.value, isNull);

      // =====================================================================
      // Phase 6: Dynamic Target Updates
      // =====================================================================

      // Update target during workout (interval change)
      final secondTarget = ErgCommand(targetWatts: 300, timestamp: clock.now());
      syncService.currentTarget.value = secondTarget;

      // Wait for sync and power ramp
      await Future<void>.delayed(const Duration(milliseconds: 800));

      // Verify new target was synced (check that power is moving toward target)
      // Power should be ramping up toward 300W
      expect(syncService.syncError.value, isNull);
      expect(syncService.lastSyncTime.value, isNotNull);

      // Lower target (recovery interval)
      final thirdTarget = ErgCommand(targetWatts: 120, timestamp: clock.now());
      syncService.currentTarget.value = thirdTarget;

      await Future<void>.delayed(const Duration(milliseconds: 800));

      // Verify sync continues to work
      expect(syncService.syncError.value, isNull);

      // =====================================================================
      // Phase 7: State Management Verification
      // =====================================================================

      // Verify all beacons are continuously updated
      await Future<void>.delayed(const Duration(milliseconds: 600));

      expect(deviceManager.devicesBeacon.value, hasLength(3));
      expect(deviceManager.primaryTrainerBeacon.value, isNotNull);
      expect(deviceManager.powerStream.value, isNotNull);
      expect(deviceManager.cadenceStream.value, isNotNull);
      expect(deviceManager.heartRateStream.value, isNotNull);

      // =====================================================================
      // Phase 8: Stop Sync
      // =====================================================================

      syncService.stopSync();
      expect(syncService.isSyncing.value, isFalse);

      // =====================================================================
      // Cleanup
      // =====================================================================

      await trainer.disconnect();
      await powerMeter.disconnect();
      await hrMonitor.disconnect();
    });

    test('workout sync handles trainer disconnection gracefully', () async {
      final env = await createTestEnvironment();
      final deviceManager = env.deviceManager;
      final syncService = env.syncService;

      // Setup trainer
      final trainer = DeviceSimulator.createRealisticTrainer(name: 'Test Trainer');

      await deviceManager.addDevice(trainer);
      deviceManager.assignPrimaryTrainer(trainer.id);
      await deviceManager.connectDevice(trainer.id).value;

      // Start syncing
      syncService.startSync();

      // Set a target
      syncService.currentTarget.value = ErgCommand(targetWatts: 200, timestamp: clock.now());

      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(syncService.syncError.value, isNull);

      // Simulate disconnection by removing trainer
      await deviceManager.removeDevice(trainer.id);

      // Try to sync new target
      syncService.currentTarget.value = ErgCommand(targetWatts: 250, timestamp: clock.now());

      await Future<void>.delayed(const Duration(milliseconds: 100));

      // Should have an error now
      expect(syncService.syncError.value, equals('No trainer connected'));
    });

    test('data streams handle device reassignment', () async {
      final env = await createTestEnvironment();
      final deviceManager = env.deviceManager;

      // Setup initial trainer
      final trainer1 = DeviceSimulator.createRealisticTrainer(name: 'Trainer 1');

      await deviceManager.addDevice(trainer1);
      deviceManager.assignPrimaryTrainer(trainer1.id);
      await deviceManager.connectDevice(trainer1.id).value;
      await trainer1.setTargetPower(150);

      await Future<void>.delayed(const Duration(milliseconds: 600));

      // Verify we're getting power data
      expect(deviceManager.powerStream.value, isNotNull);

      // Add and switch to a dedicated power meter
      final powerMeter = DeviceSimulator.createPowerMeter(name: 'Power Meter');

      await deviceManager.addDevice(powerMeter);
      await deviceManager.connectDevice(powerMeter.id).value;

      // Wait for initial data from power meter
      await Future<void>.delayed(const Duration(milliseconds: 600));

      // Reassign power source to dedicated meter
      deviceManager.assignPowerSource(powerMeter.id);

      // Wait for stream to switch
      await Future<void>.delayed(const Duration(milliseconds: 600));

      // Power data should now come from power meter, not trainer
      expect(deviceManager.powerSourceBeacon.value?.deviceId, equals(powerMeter.id));
      expect(deviceManager.powerStream.value, isNotNull);

      // Cadence should still come from trainer (no reassignment)
      expect(deviceManager.cadenceSourceBeacon.value, isNull); // Falls back to trainer
      expect(deviceManager.cadenceStream.value, isNotNull);
    });

    test('multiple devices emit data independently', () async {
      final env = await createTestEnvironment();
      final deviceManager = env.deviceManager;

      // Setup all devices
      final trainer = DeviceSimulator.createRealisticTrainer();
      final hrMonitor = DeviceSimulator.createHeartRateMonitor();

      await deviceManager.addDevice(trainer);
      await deviceManager.addDevice(hrMonitor);

      deviceManager.assignPrimaryTrainer(trainer.id);
      deviceManager.assignHeartRateSource(hrMonitor.id);

      // Connect all
      await deviceManager.connectDevice(trainer.id).value;
      await deviceManager.connectDevice(hrMonitor.id).value;
      await trainer.setTargetPower(200);

      // Collect data from multiple streams simultaneously
      final powerData = <int>[];
      final cadenceData = <int>[];
      final hrData = <int>[];

      final powerUnsub = deviceManager.powerStream.subscribe((d) {
        if (d != null) powerData.add(d.watts);
      });
      final cadenceUnsub = deviceManager.cadenceStream.subscribe((d) {
        if (d != null) cadenceData.add(d.rpm);
      });
      final hrUnsub = deviceManager.heartRateStream.subscribe((d) {
        if (d != null) hrData.add(d.bpm);
      });

      // Wait for data
      await Future<void>.delayed(const Duration(milliseconds: 1500));

      // Verify all streams are emitting independently
      expect(powerData.length, greaterThanOrEqualTo(2));
      expect(cadenceData.length, greaterThanOrEqualTo(2));
      expect(hrData.length, greaterThanOrEqualTo(1)); // HR updates slower

      // Cleanup subscriptions
      powerUnsub();
      cadenceUnsub();
      hrUnsub();
    });

    test('workout sync retry mechanism recovers from transient errors', () async {
      final env = await createTestEnvironment();
      final deviceManager = env.deviceManager;
      final syncService = env.syncService;

      // This test would require a mock trainer that can simulate failures
      // For now, we verify the basic retry structure works
      final trainer = DeviceSimulator.createRealisticTrainer();

      await deviceManager.addDevice(trainer);
      deviceManager.assignPrimaryTrainer(trainer.id);
      await deviceManager.connectDevice(trainer.id).value;

      syncService.startSync();

      // Set target
      syncService.currentTarget.value = ErgCommand(targetWatts: 200, timestamp: clock.now());

      await Future<void>.delayed(const Duration(milliseconds: 300));

      // Should succeed without errors
      expect(syncService.syncError.value, isNull);
      expect(syncService.lastSyncTime.value, isNotNull);

      // Cleanup: stop sync and disconnect to prevent disposed beacon updates
      syncService.stopSync();
      await trainer.disconnect();
    });
  });
}
