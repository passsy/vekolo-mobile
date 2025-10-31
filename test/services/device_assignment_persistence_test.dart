import 'dart:convert';

import 'package:deep_pick/deep_pick.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vekolo/domain/devices/device_manager.dart';
import 'package:vekolo/domain/mocks/mock_trainer.dart';
import 'package:vekolo/services/device_assignment_persistence.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Device Assignment Persistence', () {
    setUp(() {
      // Clear SharedPreferences before each test
      SharedPreferences.setMockInitialValues({});
    });

    group('saveDeviceAssignments', () {
      test('saves no assignments when no devices assigned', () async {
        final deviceManager = DeviceManager();
        addTearDown(() => deviceManager.dispose());

        await saveDeviceAssignments(deviceManager);

        final prefs = await SharedPreferences.getInstance();
        final json = prefs.getString('device_assignments_v1');
        expect(json, isNotNull);

        final data = jsonDecode(json!);
        expect(pick(data, 'version').asIntOrNull(), 1);
        expect(pick(data, 'assignments').asListOrNull<dynamic>((p) => p.value), isEmpty);
      });

      test('saves primary trainer assignment', () async {
        final deviceManager = DeviceManager();
        addTearDown(() => deviceManager.dispose());

        final trainer = MockTrainer(id: 'trainer-1', name: 'KICKR CORE');
        await deviceManager.addDevice(trainer);
        deviceManager.assignPrimaryTrainer(trainer.id);

        await saveDeviceAssignments(deviceManager);

        final prefs = await SharedPreferences.getInstance();
        final json = prefs.getString('device_assignments_v1');
        expect(json, isNotNull);

        final data = jsonDecode(json!);
        expect(pick(data, 'version').asIntOrNull(), 1);

        final assignments = pick(data, 'assignments').asListOrNull<dynamic>((p) => p.value)!;
        expect(assignments.length, 1);
        expect(pick(assignments[0], 'deviceId').asStringOrNull(), 'trainer-1');
        expect(pick(assignments[0], 'deviceName').asStringOrNull(), 'KICKR CORE');
        expect(pick(assignments[0], 'role').asStringOrNull(), 'primaryTrainer');
        expect(pick(assignments[0], 'assignedAt').asStringOrNull(), isNotNull);
      });

      test('saves multiple role assignments for same device', () async {
        final deviceManager = DeviceManager();
        addTearDown(() => deviceManager.dispose());

        final trainer = MockTrainer(id: 'trainer-1', name: 'KICKR CORE');
        await deviceManager.addDevice(trainer);
        deviceManager.assignPrimaryTrainer(trainer.id);
        deviceManager.assignPowerSource(trainer.id);

        await saveDeviceAssignments(deviceManager);

        final prefs = await SharedPreferences.getInstance();
        final json = prefs.getString('device_assignments_v1');
        final data = jsonDecode(json!);

        final assignments = pick(data, 'assignments').asListOrNull<dynamic>((p) => p.value)!;
        expect(assignments.length, 2);

        final roles = assignments
            .map((a) => pick(a, 'role').asStringOrNull()!)
            .toSet();
        expect(roles, containsAll(['primaryTrainer', 'powerSource']));
      });

      test('saves all assigned role types', () async {
        final deviceManager = DeviceManager();
        addTearDown(() => deviceManager.dispose());

        final trainer = MockTrainer(id: 'trainer-1', name: 'KICKR');

        await deviceManager.addDevice(trainer);

        // Assign all roles to same device (valid for a multi-function device like KICKR)
        deviceManager.assignPrimaryTrainer(trainer.id);
        deviceManager.assignPowerSource(trainer.id);
        deviceManager.assignCadenceSource(trainer.id);
        deviceManager.assignSpeedSource(trainer.id);

        await saveDeviceAssignments(deviceManager);

        final prefs = await SharedPreferences.getInstance();
        final json = prefs.getString('device_assignments_v1');
        final data = jsonDecode(json!);

        final assignments = pick(data, 'assignments').asListOrNull<dynamic>((p) => p.value)!;
        expect(assignments.length, 4);

        final roles = assignments
            .map((a) => pick(a, 'role').asStringOrNull()!)
            .toSet();
        expect(
          roles,
          containsAll(['primaryTrainer', 'powerSource', 'cadenceSource', 'speedSource']),
        );
      });
    });

    group('loadDeviceAssignments', () {
      test('returns empty map when no assignments saved', () async {
        final assignments = await loadDeviceAssignments();
        expect(assignments, isEmpty);
      });

      test('loads single device with single role', () async {
        final prefs = await SharedPreferences.getInstance();
        final data = {
          'version': 1,
          'assignments': [
            {
              'deviceId': 'trainer-1',
              'deviceName': 'KICKR CORE',
              'role': 'powerSource',
              'assignedAt': '2025-01-31T10:00:00.000Z',
            },
          ],
        };
        await prefs.setString('device_assignments_v1', jsonEncode(data));

        final assignments = await loadDeviceAssignments();

        expect(assignments.length, 1);
        expect(assignments['trainer-1'], {'powerSource'});
      });

      test('loads single device with multiple roles', () async {
        final prefs = await SharedPreferences.getInstance();
        final data = {
          'version': 1,
          'assignments': [
            {
              'deviceId': 'trainer-1',
              'deviceName': 'KICKR CORE',
              'role': 'primaryTrainer',
              'assignedAt': '2025-01-31T10:00:00.000Z',
            },
            {
              'deviceId': 'trainer-1',
              'deviceName': 'KICKR CORE',
              'role': 'powerSource',
              'assignedAt': '2025-01-31T10:00:00.000Z',
            },
          ],
        };
        await prefs.setString('device_assignments_v1', jsonEncode(data));

        final assignments = await loadDeviceAssignments();

        expect(assignments.length, 1);
        expect(assignments['trainer-1'], {'primaryTrainer', 'powerSource'});
      });

      test('loads multiple devices with different roles', () async {
        final prefs = await SharedPreferences.getInstance();
        final data = {
          'version': 1,
          'assignments': [
            {
              'deviceId': 'trainer-1',
              'deviceName': 'KICKR',
              'role': 'powerSource',
              'assignedAt': '2025-01-31T10:00:00.000Z',
            },
            {
              'deviceId': 'hr-1',
              'deviceName': 'Polar H9',
              'role': 'heartRateSource',
              'assignedAt': '2025-01-31T10:00:00.000Z',
            },
          ],
        };
        await prefs.setString('device_assignments_v1', jsonEncode(data));

        final assignments = await loadDeviceAssignments();

        expect(assignments.length, 2);
        expect(assignments['trainer-1'], {'powerSource'});
        expect(assignments['hr-1'], {'heartRateSource'});
      });

      test('handles unknown version gracefully', () async {
        final prefs = await SharedPreferences.getInstance();
        final data = {
          'version': 99,
          'assignments': [
            {'deviceId': 'test', 'deviceName': 'Test', 'role': 'powerSource'},
          ],
        };
        await prefs.setString('device_assignments_v1', jsonEncode(data));

        final assignments = await loadDeviceAssignments();

        expect(assignments, isEmpty);
      });

      test('handles missing version field gracefully', () async {
        final prefs = await SharedPreferences.getInstance();
        final data = {
          'assignments': [
            {'deviceId': 'test', 'deviceName': 'Test', 'role': 'powerSource'},
          ],
        };
        await prefs.setString('device_assignments_v1', jsonEncode(data));

        final assignments = await loadDeviceAssignments();

        expect(assignments, isEmpty);
      });

      test('handles corrupted JSON gracefully', () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('device_assignments_v1', 'not valid json');

        final assignments = await loadDeviceAssignments();

        expect(assignments, isEmpty);
      });

      test('handles missing required fields gracefully', () async {
        final prefs = await SharedPreferences.getInstance();
        final data = {
          'version': 1,
          'assignments': [
            {
              // Missing deviceId
              'deviceName': 'KICKR',
              'role': 'powerSource',
            },
          ],
        };
        await prefs.setString('device_assignments_v1', jsonEncode(data));

        final assignments = await loadDeviceAssignments();

        expect(assignments, isEmpty);
      });
    });

    group('clearDeviceAssignments', () {
      test('clears saved assignments', () async {
        final prefs = await SharedPreferences.getInstance();
        final data = {
          'version': 1,
          'assignments': [
            {
              'deviceId': 'trainer-1',
              'deviceName': 'KICKR',
              'role': 'powerSource',
              'assignedAt': '2025-01-31T10:00:00.000Z',
            },
          ],
        };
        await prefs.setString('device_assignments_v1', jsonEncode(data));

        await clearDeviceAssignments();

        final json = prefs.getString('device_assignments_v1');
        expect(json, isNull);
      });

      test('works when no assignments exist', () async {
        // Should not throw
        await clearDeviceAssignments();

        final prefs = await SharedPreferences.getInstance();
        final json = prefs.getString('device_assignments_v1');
        expect(json, isNull);
      });
    });

    group('Round-trip', () {
      test('save and load preserves assignments', () async {
        final deviceManager = DeviceManager();
        addTearDown(() => deviceManager.dispose());

        final trainer = MockTrainer(id: 'trainer-1', name: 'KICKR CORE');
        await deviceManager.addDevice(trainer);
        deviceManager.assignPrimaryTrainer(trainer.id);
        deviceManager.assignPowerSource(trainer.id);

        await saveDeviceAssignments(deviceManager);
        final loaded = await loadDeviceAssignments();

        expect(loaded.length, 1);
        expect(loaded['trainer-1'], {'primaryTrainer', 'powerSource'});
      });
    });
  });
}
