import 'dart:convert';
import 'dart:developer' as developer;

import 'package:deep_pick/deep_pick.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vekolo/domain/devices/device_manager.dart';

/// Storage key for device assignments
const String _storageKey = 'device_assignments_v1';

/// Current storage format version
const int _currentVersion = 1;

/// Save current device assignments to persistent storage.
///
/// Saves which devices are assigned to which roles (powerSource, heartRateSource, etc.)
/// so they can be auto-reconnected on app restart.
Future<void> saveDeviceAssignments(DeviceManager deviceManager) async {
  final prefs = await SharedPreferences.getInstance();

  final assignments = <Map<String, dynamic>>[];

  // Add all assigned devices to the list
  if (deviceManager.primaryTrainerBeacon.value != null) {
    final device = deviceManager.primaryTrainerBeacon.value!;
    assignments.add({
      'deviceId': device.id,
      'deviceName': device.name,
      'role': 'primaryTrainer',
      'assignedAt': DateTime.now().toIso8601String(),
    });
  }

  if (deviceManager.powerSourceBeacon.value != null) {
    final device = deviceManager.powerSourceBeacon.value!;
    assignments.add({
      'deviceId': device.id,
      'deviceName': device.name,
      'role': 'powerSource',
      'assignedAt': DateTime.now().toIso8601String(),
    });
  }

  if (deviceManager.cadenceSourceBeacon.value != null) {
    final device = deviceManager.cadenceSourceBeacon.value!;
    assignments.add({
      'deviceId': device.id,
      'deviceName': device.name,
      'role': 'cadenceSource',
      'assignedAt': DateTime.now().toIso8601String(),
    });
  }

  if (deviceManager.speedSourceBeacon.value != null) {
    final device = deviceManager.speedSourceBeacon.value!;
    assignments.add({
      'deviceId': device.id,
      'deviceName': device.name,
      'role': 'speedSource',
      'assignedAt': DateTime.now().toIso8601String(),
    });
  }

  if (deviceManager.heartRateSourceBeacon.value != null) {
    final device = deviceManager.heartRateSourceBeacon.value!;
    assignments.add({
      'deviceId': device.id,
      'deviceName': device.name,
      'role': 'heartRateSource',
      'assignedAt': DateTime.now().toIso8601String(),
    });
  }

  final data = {
    'version': _currentVersion,
    'assignments': assignments,
  };

  final json = jsonEncode(data);
  await prefs.setString(_storageKey, json);

  developer.log(
    '[DeviceAssignments] Saved ${assignments.length} assignment(s)',
    name: 'DeviceAssignments',
  );
}

/// Load saved device assignments.
///
/// Returns a map of deviceId -> set of roles, which can be used to reconnect devices.
/// For example: `{'device-123': {'powerSource', 'primaryTrainer'}}`
Future<Map<String, Set<String>>> loadDeviceAssignments() async {
  final prefs = await SharedPreferences.getInstance();
  final json = prefs.getString(_storageKey);
  if (json == null) {
    developer.log('[DeviceAssignments] No saved assignments found', name: 'DeviceAssignments');
    return {};
  }

  try {
    final data = jsonDecode(json);

    // Check version
    final version = pick(data, 'version').asIntOrNull();
    if (version == null) {
      developer.log('[DeviceAssignments] No version field, ignoring', name: 'DeviceAssignments');
      return {};
    }

    if (version != _currentVersion) {
      developer.log(
        '[DeviceAssignments] Unknown version $version (expected $_currentVersion), ignoring',
        name: 'DeviceAssignments',
      );
      // Future: handle version migration here if needed
      return {};
    }

    // Parse assignments list
    final assignmentsList = pick(data, 'assignments').asListOrNull<dynamic>((p) => p.value);
    if (assignmentsList == null) {
      developer.log('[DeviceAssignments] No assignments list found', name: 'DeviceAssignments');
      return {};
    }

    final assignments = <({String deviceId, String deviceName, String role, String assignedAt})>[];

    for (final item in assignmentsList) {
      try {
        assignments.add((
          deviceId: pick(item, 'deviceId').asStringOrThrow(),
          deviceName: pick(item, 'deviceName').asStringOrThrow(),
          role: pick(item, 'role').asStringOrThrow(),
          assignedAt: pick(item, 'assignedAt').asStringOrThrow(),
        ));
      } catch (e) {
        // Skip invalid assignments
        developer.log('[DeviceAssignments] Skipping invalid assignment: $e', name: 'DeviceAssignments');
      }
    }

    // Build map of deviceId -> roles
    final result = <String, Set<String>>{};
    for (final assignment in assignments) {
      result.putIfAbsent(assignment.deviceId, () => {}).add(assignment.role);
    }

    developer.log(
      '[DeviceAssignments] Loaded ${assignments.length} assignment(s) for ${result.length} device(s)',
      name: 'DeviceAssignments',
    );

    return result;
  } catch (e, stackTrace) {
    developer.log(
      '[DeviceAssignments] Failed to load assignments, resetting',
      name: 'DeviceAssignments',
      error: e,
      stackTrace: stackTrace,
    );
    return {};
  }
}

/// Clear all saved device assignments.
///
/// Useful for testing or when user wants to reset device connections.
Future<void> clearDeviceAssignments() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(_storageKey);
  developer.log('[DeviceAssignments] Cleared all assignments', name: 'DeviceAssignments');
}
