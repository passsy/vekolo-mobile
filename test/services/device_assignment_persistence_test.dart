import 'dart:convert';

import 'package:deep_pick/deep_pick.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vekolo/domain/devices/device_manager.dart';
import 'package:vekolo/domain/mocks/mock_trainer.dart';
import 'package:vekolo/services/device_assignment_persistence.dart';
import '../ble/fake_ble_platform.dart';
import '../ble/fake_ble_permissions.dart';
import '../helpers/shared_preferences_helper.dart';
import 'package:vekolo/ble/ble_scanner.dart';
import 'package:vekolo/ble/transport_registry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Device Assignment Persistence', () {
    Future<({DeviceManager manager, DeviceAssignmentPersistence persistence, SharedPreferencesAsync prefs})>
    createDeviceManager() async {
      final platform = FakeBlePlatform();
      final scanner = BleScanner(platform: platform, permissions: FakeBlePermissions());
      final transportRegistry = TransportRegistry();
      final prefs = createTestSharedPreferencesAsync();
      final persistence = DeviceAssignmentPersistence(prefs);
      final deviceManager = DeviceManager(
        platform: platform,
        scanner: scanner,
        transportRegistry: transportRegistry,
        persistence: persistence,
      );
      addTearDown(() async => await deviceManager.dispose());
      return (manager: deviceManager, persistence: persistence, prefs: prefs);
    }

    group('saveDeviceAssignments', () {
      test('saves no assignments when no devices assigned', () async {
        final deps = await createDeviceManager();

        // Wait to ensure no unexpected saves happen
        await Future.delayed(const Duration(milliseconds: 200));

        // When no devices are assigned, nothing should be saved
        final json = await deps.prefs.getString('device_assignments_v1');
        expect(json, isNull);
      });

      test('saves smart trainer assignment', () async {
        final deps = await createDeviceManager();

        final trainer = MockTrainer(id: 'trainer-1', name: 'KICKR CORE');
        await deps.manager.addDevice(trainer);
        deps.manager.assignSmartTrainer(trainer.id);

        // Wait for auto-save via beacon subscription (needs extra time for async beacon + persistence)
        await Future.delayed(const Duration(milliseconds: 200));

        final json = await deps.prefs.getString('device_assignments_v1');
        expect(json, isNotNull);

        final data = jsonDecode(json!);
        expect(pick(data, 'version').asIntOrNull(), 1);

        final assignments = pick(data, 'assignments').asListOrNull<dynamic>((p) => p.value)!;
        expect(assignments.length, 1);
        expect(pick(assignments[0], 'deviceId').asStringOrNull(), 'trainer-1');
        expect(pick(assignments[0], 'deviceName').asStringOrNull(), 'KICKR CORE');
        expect(pick(assignments[0], 'role').asStringOrNull(), 'smartTrainer');
        expect(pick(assignments[0], 'transport').asStringOrNull(), isNotNull);
      });

      test('saves multiple role assignments for same device', () async {
        final deps = await createDeviceManager();

        final trainer = MockTrainer(id: 'trainer-1', name: 'KICKR CORE');
        await deps.manager.addDevice(trainer);
        deps.manager.assignSmartTrainer(trainer.id);
        deps.manager.assignPowerSource(trainer.id);

        // Wait for auto-save via beacon subscription (needs extra time for async beacon + persistence)
        await Future.delayed(const Duration(milliseconds: 200));

        final json = await deps.prefs.getString('device_assignments_v1');
        final data = jsonDecode(json!);

        final assignments = pick(data, 'assignments').asListOrNull<dynamic>((p) => p.value)!;
        expect(assignments.length, 2);

        final roles = assignments.map((a) => pick(a, 'role').asStringOrNull()!).toSet();
        expect(roles, containsAll(['smartTrainer', 'powerSource']));
      });

      test('saves all assigned role types', () async {
        final deps = await createDeviceManager();

        final trainer = MockTrainer(id: 'trainer-1', name: 'KICKR');

        await deps.manager.addDevice(trainer);

        // Assign all roles to same device (valid for a multi-function device like KICKR)
        deps.manager.assignSmartTrainer(trainer.id);
        deps.manager.assignPowerSource(trainer.id);
        deps.manager.assignCadenceSource(trainer.id);
        deps.manager.assignSpeedSource(trainer.id);

        // Wait for auto-save via beacon subscription (needs extra time for async beacon + persistence)
        await Future.delayed(const Duration(milliseconds: 200));

        final json = await deps.prefs.getString('device_assignments_v1');
        final data = jsonDecode(json!);

        final assignments = pick(data, 'assignments').asListOrNull<dynamic>((p) => p.value)!;
        expect(assignments.length, 4);

        final roles = assignments.map((a) => pick(a, 'role').asStringOrNull()!).toSet();
        expect(roles, containsAll(['smartTrainer', 'powerSource', 'cadenceSource', 'speedSource']));
      });
    });

    group('loadDeviceAssignments', () {
      test('returns empty assignments when no assignments saved', () async {
        final persistence = (await createDeviceManager()).persistence;
        final assignments = await persistence.loadAssignments();

        expect(assignments.smartTrainer, isNull);
        expect(assignments.powerSource, isNull);
        expect(assignments.cadenceSource, isNull);
        expect(assignments.speedSource, isNull);
        expect(assignments.heartRateSource, isNull);
      });

      test('loads single device with single role', () async {
        final deps = await createDeviceManager();
        final data = {
          'version': 1,
          'assignments': [
            {
              'deviceId': 'trainer-1',
              'deviceName': 'KICKR CORE',
              'role': 'powerSource',
              'transport': 'FTMS',
              'assignedAt': '2025-01-31T10:00:00.000Z',
            },
          ],
        };
        await deps.prefs.setString('device_assignments_v1', jsonEncode(data));
        final assignments = await deps.persistence.loadAssignments();

        expect(assignments.powerSource?.deviceId, 'trainer-1');
        expect(assignments.powerSource?.deviceName, 'KICKR CORE');
        expect(assignments.powerSource?.transport, 'FTMS');
        expect(assignments.smartTrainer, isNull);
      });

      test('loads single device with multiple roles', () async {
        final deps = await createDeviceManager();
        final data = {
          'version': 1,
          'assignments': [
            {
              'deviceId': 'trainer-1',
              'deviceName': 'KICKR CORE',
              'role': 'smartTrainer',
              'transport': 'FTMS',
              'assignedAt': '2025-01-31T10:00:00.000Z',
            },
            {
              'deviceId': 'trainer-1',
              'deviceName': 'KICKR CORE',
              'role': 'powerSource',
              'transport': 'FTMS',
              'assignedAt': '2025-01-31T10:00:00.000Z',
            },
          ],
        };
        await deps.prefs.setString('device_assignments_v1', jsonEncode(data));
        final assignments = await deps.persistence.loadAssignments();

        expect(assignments.smartTrainer?.deviceId, 'trainer-1');
        expect(assignments.powerSource?.deviceId, 'trainer-1');
        expect(assignments.cadenceSource, isNull);
      });

      test('loads multiple devices with different roles', () async {
        final deps = await createDeviceManager();
        final data = {
          'version': 1,
          'assignments': [
            {
              'deviceId': 'trainer-1',
              'deviceName': 'KICKR',
              'role': 'powerSource',
              'transport': 'FTMS',
              'assignedAt': '2025-01-31T10:00:00.000Z',
            },
            {
              'deviceId': 'hr-1',
              'deviceName': 'Polar H9',
              'role': 'heartRateSource',
              'transport': 'HeartRate',
              'assignedAt': '2025-01-31T10:00:00.000Z',
            },
          ],
        };
        await deps.prefs.setString('device_assignments_v1', jsonEncode(data));
        final assignments = await deps.persistence.loadAssignments();

        expect(assignments.powerSource?.deviceId, 'trainer-1');
        expect(assignments.powerSource?.deviceName, 'KICKR');
        expect(assignments.heartRateSource?.deviceId, 'hr-1');
        expect(assignments.heartRateSource?.deviceName, 'Polar H9');
      });

      test('handles unknown version gracefully', () async {
        final deps = await createDeviceManager();
        final data = {
          'version': 99,
          'assignments': [
            {'deviceId': 'test', 'deviceName': 'Test', 'role': 'powerSource', 'transport': 'FTMS'},
          ],
        };
        await deps.prefs.setString('device_assignments_v1', jsonEncode(data));
        final assignments = await deps.persistence.loadAssignments();

        expect(assignments.smartTrainer, isNull);
        expect(assignments.powerSource, isNull);
      });

      test('handles missing version field gracefully', () async {
        final deps = await createDeviceManager();
        final data = {
          'assignments': [
            {'deviceId': 'test', 'deviceName': 'Test', 'role': 'powerSource', 'transport': 'FTMS'},
          ],
        };
        await deps.prefs.setString('device_assignments_v1', jsonEncode(data));
        final assignments = await deps.persistence.loadAssignments();

        expect(assignments.smartTrainer, isNull);
        expect(assignments.powerSource, isNull);
      });

      test('handles corrupted JSON gracefully', () async {
        final deps = await createDeviceManager();
        await deps.prefs.setString('device_assignments_v1', 'not valid json');
        final assignments = await deps.persistence.loadAssignments();

        expect(assignments.smartTrainer, isNull);
        expect(assignments.powerSource, isNull);
      });

      test('handles missing required fields gracefully', () async {
        final deps = await createDeviceManager();
        final data = {
          'version': 1,
          'assignments': [
            {
              // Missing deviceId
              'deviceName': 'KICKR',
              'role': 'powerSource',
              'transport': 'FTMS',
            },
          ],
        };
        await deps.prefs.setString('device_assignments_v1', jsonEncode(data));
        final assignments = await deps.persistence.loadAssignments();

        expect(assignments.smartTrainer, isNull);
        expect(assignments.powerSource, isNull);
      });
    });

    group('clearDeviceAssignments', () {
      test('clears saved assignments', () async {
        final deps = await createDeviceManager();
        final data = {
          'version': 1,
          'assignments': [
            {
              'deviceId': 'trainer-1',
              'deviceName': 'KICKR',
              'role': 'powerSource',
              'transport': 'FTMS',
              'assignedAt': '2025-01-31T10:00:00.000Z',
            },
          ],
        };
        await deps.prefs.setString('device_assignments_v1', jsonEncode(data));

        await deps.persistence.clearAssignments();

        final json = await deps.prefs.getString('device_assignments_v1');
        expect(json, isNull);
      });

      test('works when no assignments exist', () async {
        final deps = await createDeviceManager();

        // Should not throw
        await deps.persistence.clearAssignments();

        final json = await deps.prefs.getString('device_assignments_v1');
        expect(json, isNull);
      });
    });

    group('Round-trip', () {
      test('save and load preserves assignments', () async {
        final deps = await createDeviceManager();

        final trainer = MockTrainer(id: 'trainer-1', name: 'KICKR CORE');
        await deps.manager.addDevice(trainer);
        deps.manager.assignSmartTrainer(trainer.id);
        deps.manager.assignPowerSource(trainer.id);

        // Wait for auto-save via beacon subscription (needs extra time for async beacon + persistence)
        await Future.delayed(const Duration(milliseconds: 200));

        // Load using the persistence API
        final loaded = await deps.persistence.loadAssignments();

        expect(loaded.smartTrainer?.deviceId, 'trainer-1');
        expect(loaded.smartTrainer?.deviceName, 'KICKR CORE');
        expect(loaded.powerSource?.deviceId, 'trainer-1');
        expect(loaded.powerSource?.deviceName, 'KICKR CORE');
      });
    });
  });
}
