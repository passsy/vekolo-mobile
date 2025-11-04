import 'dart:convert';

import 'package:deep_pick/deep_pick.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vekolo/app/logger.dart';

/// Storage key for device assignments
const String _storageKey = 'device_assignments_v1';

/// Current storage format version
const int _currentVersion = 1;

/// Device assignment record.
///
/// Represents a single device assigned to a specific role.
/// The role is implicit based on which parameter this is passed to in [saveAssignments].
class DeviceAssignment {
  const DeviceAssignment({required this.deviceId, required this.deviceName, required this.transport});

  final String deviceId;
  final String deviceName;
  final String transport;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DeviceAssignment &&
          runtimeType == other.runtimeType &&
          deviceId == other.deviceId &&
          deviceName == other.deviceName &&
          transport == other.transport;

  @override
  int get hashCode => Object.hash(deviceId, deviceName, transport);
}

/// Loaded device assignments.
///
/// Represents all device assignments loaded from persistent storage.
class DeviceAssignments {
  const DeviceAssignments({
    this.primaryTrainer,
    this.powerSource,
    this.cadenceSource,
    this.speedSource,
    this.heartRateSource,
  });

  final DeviceAssignment? primaryTrainer;
  final DeviceAssignment? powerSource;
  final DeviceAssignment? cadenceSource;
  final DeviceAssignment? speedSource;
  final DeviceAssignment? heartRateSource;
}

/// Service for persisting device assignments.
///
/// Handles saving and loading device role assignments (powerSource, heartRateSource, etc.)
/// to/from persistent storage so they can be auto-reconnected on app restart.
class DeviceAssignmentPersistence {
  DeviceAssignmentPersistence(this._prefs);

  final SharedPreferencesAsync _prefs;

  /// Save device assignments to persistent storage.
  ///
  /// Saves which devices are assigned to which roles so they can be
  /// auto-reconnected on app restart.
  Future<void> saveAssignments({
    DeviceAssignment? primaryTrainer,
    DeviceAssignment? powerSource,
    DeviceAssignment? cadenceSource,
    DeviceAssignment? speedSource,
    DeviceAssignment? heartRateSource,
  }) async {
    final assignments = <Map<String, dynamic>>[];

    if (primaryTrainer != null) {
      assignments.add({
        'deviceId': primaryTrainer.deviceId,
        'deviceName': primaryTrainer.deviceName,
        'transport': primaryTrainer.transport,
        'role': 'primaryTrainer',
      });
    }

    if (powerSource != null) {
      assignments.add({
        'deviceId': powerSource.deviceId,
        'deviceName': powerSource.deviceName,
        'transport': powerSource.transport,
        'role': 'powerSource',
      });
    }

    if (cadenceSource != null) {
      assignments.add({
        'deviceId': cadenceSource.deviceId,
        'deviceName': cadenceSource.deviceName,
        'transport': cadenceSource.transport,
        'role': 'cadenceSource',
      });
    }

    if (speedSource != null) {
      assignments.add({
        'deviceId': speedSource.deviceId,
        'deviceName': speedSource.deviceName,
        'transport': speedSource.transport,
        'role': 'speedSource',
      });
    }

    if (heartRateSource != null) {
      assignments.add({
        'deviceId': heartRateSource.deviceId,
        'deviceName': heartRateSource.deviceName,
        'transport': heartRateSource.transport,
        'role': 'heartRateSource',
      });
    }

    final data = {'version': _currentVersion, 'savedAt': DateTime.now().toIso8601String(), 'assignments': assignments};

    final json = jsonEncode(data);
    await _prefs.setString(_storageKey, json);

    talker.info('[DeviceAssignments] Saved ${assignments.length} assignment(s)');
  }

  /// Load saved device assignments.
  ///
  /// Returns all saved device assignments organized by role.
  Future<DeviceAssignments> loadAssignments() async {
    final json = await _prefs.getString(_storageKey);
    if (json == null) {
      talker.info('[DeviceAssignments] No saved assignments found');
      return const DeviceAssignments();
    }

    try {
      final data = jsonDecode(json);

      // Check version
      final version = pick(data, 'version').asIntOrNull();
      if (version == null) {
        talker.info('[DeviceAssignments] No version field, ignoring');
        return const DeviceAssignments();
      }

      if (version != _currentVersion) {
        talker.info('[DeviceAssignments] Unknown version $version (expected $_currentVersion), ignoring');
        // Future: handle version migration here if needed
        return const DeviceAssignments();
      }

      // Parse assignments list
      final assignmentsList = pick(data, 'assignments').asListOrNull<dynamic>((p) => p.value);
      if (assignmentsList == null) {
        talker.info('[DeviceAssignments] No assignments list found');
        return const DeviceAssignments();
      }

      DeviceAssignment? primaryTrainer;
      DeviceAssignment? powerSource;
      DeviceAssignment? cadenceSource;
      DeviceAssignment? speedSource;
      DeviceAssignment? heartRateSource;

      for (final item in assignmentsList) {
        try {
          final deviceId = pick(item, 'deviceId').asStringOrThrow();
          final deviceName = pick(item, 'deviceName').asStringOrThrow();
          final transport = pick(item, 'transport').asStringOrThrow();
          final role = pick(item, 'role').asStringOrThrow();

          final assignment = DeviceAssignment(deviceId: deviceId, deviceName: deviceName, transport: transport);

          switch (role) {
            case 'primaryTrainer':
              primaryTrainer = assignment;
            case 'powerSource':
              powerSource = assignment;
            case 'cadenceSource':
              cadenceSource = assignment;
            case 'speedSource':
              speedSource = assignment;
            case 'heartRateSource':
              heartRateSource = assignment;
            default:
              talker.info('[DeviceAssignments] Unknown role: $role');
          }
        } catch (e) {
          // Skip invalid assignments
          talker.info('[DeviceAssignments] Skipping invalid assignment: $e');
        }
      }

      talker.info('[DeviceAssignments] Loaded assignments');

      return DeviceAssignments(
        primaryTrainer: primaryTrainer,
        powerSource: powerSource,
        cadenceSource: cadenceSource,
        speedSource: speedSource,
        heartRateSource: heartRateSource,
      );
    } catch (e, stackTrace) {
      talker.error('[DeviceAssignments] Failed to load assignments, resetting', e, stackTrace);
      return const DeviceAssignments();
    }
  }

  /// Clear all saved device assignments.
  ///
  /// Useful for testing or when user wants to reset device connections.
  Future<void> clearAssignments() async {
    await _prefs.remove(_storageKey);
    talker.info('[DeviceAssignments] Cleared all assignments');
  }
}
