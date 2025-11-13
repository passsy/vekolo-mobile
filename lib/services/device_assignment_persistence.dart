import 'dart:convert';

import 'package:deep_pick/deep_pick.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chirp/chirp.dart';

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
    this.smartTrainer,
    this.powerSource,
    this.cadenceSource,
    this.speedSource,
    this.heartRateSource,
  });

  final DeviceAssignment? smartTrainer;
  final DeviceAssignment? powerSource;
  final DeviceAssignment? cadenceSource;
  final DeviceAssignment? speedSource;
  final DeviceAssignment? heartRateSource;

  bool get isEmpty {
    return smartTrainer == null &&
        powerSource == null &&
        cadenceSource == null &&
        speedSource == null &&
        heartRateSource == null;
  }
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
    DeviceAssignment? smartTrainer,
    DeviceAssignment? powerSource,
    DeviceAssignment? cadenceSource,
    DeviceAssignment? speedSource,
    DeviceAssignment? heartRateSource,
  }) async {
    final assignments = <Map<String, dynamic>>[];

    if (smartTrainer != null) {
      assignments.add({
        'deviceId': smartTrainer.deviceId,
        'deviceName': smartTrainer.deviceName,
        'transport': smartTrainer.transport,
        'role': 'smartTrainer',
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

    chirp.info('Saved ${assignments.length} assignment(s)');
  }

  /// Load saved device assignments.
  ///
  /// Returns all saved device assignments organized by role.
  Future<DeviceAssignments> loadAssignments() async {
    final json = await _prefs.getString(_storageKey);
    if (json == null) {
      chirp.info('No saved assignments found');
      return const DeviceAssignments();
    }

    try {
      final data = jsonDecode(json);

      // Check version
      final version = pick(data, 'version').asIntOrNull();
      if (version == null) {
        chirp.info('No version field, ignoring');
        return const DeviceAssignments();
      }

      if (version != _currentVersion) {
        chirp.info('Unknown version $version (expected $_currentVersion), ignoring');
        // Future: handle version migration here if needed
        return const DeviceAssignments();
      }

      // Parse assignments list
      final assignmentsList = pick(data, 'assignments').asListOrNull<dynamic>((p) => p.value);
      if (assignmentsList == null) {
        chirp.info('No assignments list found');
        return const DeviceAssignments();
      }

      DeviceAssignment? smartTrainer;
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
            case 'smartTrainer':
            case 'primaryTrainer': // Legacy support
              smartTrainer = assignment;
            case 'powerSource':
              powerSource = assignment;
            case 'cadenceSource':
              cadenceSource = assignment;
            case 'speedSource':
              speedSource = assignment;
            case 'heartRateSource':
              heartRateSource = assignment;
            default:
              chirp.info('Unknown role: $role');
          }
        } catch (e) {
          // Skip invalid assignments
          chirp.info('Skipping invalid assignment: $e');
        }
      }

      final result = DeviceAssignments(
        smartTrainer: smartTrainer,
        powerSource: powerSource,
        cadenceSource: cadenceSource,
        speedSource: speedSource,
        heartRateSource: heartRateSource,
      );

      chirp.info('Loaded assignments', data: {
        'smartTrainer': smartTrainer != null ? '${smartTrainer.deviceName} (${smartTrainer.deviceId})' : null,
        'powerSource': powerSource != null ? '${powerSource.deviceName} (${powerSource.deviceId})' : null,
        'cadenceSource': cadenceSource != null ? '${cadenceSource.deviceName} (${cadenceSource.deviceId})' : null,
        'speedSource': speedSource != null ? '${speedSource.deviceName} (${speedSource.deviceId})' : null,
        'heartRateSource': heartRateSource != null ? '${heartRateSource.deviceName} (${heartRateSource.deviceId})' : null,
      });

      return result;
    } catch (e, stackTrace) {
      chirp.error('Failed to load assignments, resetting', error: e, stackTrace: stackTrace);
      return const DeviceAssignments();
    }
  }

  /// Clear all saved device assignments.
  ///
  /// Useful for testing or when user wants to reset device connections.
  Future<void> clearAssignments() async {
    await _prefs.remove(_storageKey);
    chirp.info('Cleared all assignments');
  }
}
