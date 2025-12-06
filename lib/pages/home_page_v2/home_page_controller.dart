// ignore_for_file: use_setters_to_change_properties

import 'package:chirp/chirp.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:state_beacon/state_beacon.dart';
import 'package:vekolo/api/vekolo_api_client.dart';
import 'package:vekolo/app/colors.dart';
import 'package:vekolo/domain/models/workout_session.dart';
import 'package:vekolo/models/activity.dart';
import 'package:vekolo/services/notification_service.dart';
import 'package:vekolo/services/workout_session_persistence.dart';

/// Reactive controller for the Home Page
class HomePageController extends BeaconController {
  HomePageController({
    required this.apiClient,
    required this.notificationService,
    required this.workoutSessionPersistence,
    required this.context,
  });

  final VekoloApiClient apiClient;
  final NotificationService notificationService;
  final WorkoutSessionPersistence workoutSessionPersistence;
  final BuildContext context;

  /// Currently selected tab index (0: Activities, 1: Library, 2: Create)
  late final selectedTabIndex = B.writable(0);

  /// Whether the filter modal is currently visible
  late final isFilterModalVisible = B.writable(false);

  /// Current source filter selection ('everybody' or 'bookmarked')
  late final sourceFilter = B.writable<SourceFilter>(SourceFilter.everybody);

  /// Currently selected workout type filters
  late final workoutTypeFilters = B.writable<Set<WorkoutType>>({
    WorkoutType.recovery,
    WorkoutType.endurance,
    WorkoutType.tempo,
    WorkoutType.threshold,
    WorkoutType.vo2max,
    WorkoutType.ftp,
  });

  /// All activities from API
  late final activities = B.writable<List<Activity>>([]);

  /// Local workout activities (completed sessions from disk)
  late final localActivities = B.writable<List<Activity>>([]);

  /// Loading state for activities
  late final isLoadingActivities = B.writable(false);

  /// Error message if loading fails
  late final activitiesError = B.writable<String?>(null);

  /// Filtered activities based on current filters
  late final filteredActivities = B.derived(() {
    // Merge API activities and local activities
    final apiActivities = activities.value;
    final local = localActivities.value;

    // Combine and sort by timestamp (latest first)
    final all = [...apiActivities, ...local]
      ..sort((a, b) {
        final aTime = DateTime.parse(a.createdAt);
        final bTime = DateTime.parse(b.createdAt);
        return bTime.compareTo(aTime); // Descending order (latest first)
      });

    final source = sourceFilter.value;
    final types = workoutTypeFilters.value;

    var filtered = all;

    // Apply source filter
    if (source == SourceFilter.bookmarked) {
      // TODO: Implement bookmarked filter when bookmark functionality is added
      // For now, just return empty list
      filtered = [];
    }

    // Apply workout type filters
    if (types.isNotEmpty) {
      filtered = filtered.where((activity) {
        final category = activity.workout.category?.value.toLowerCase();
        if (category == null) return false;

        // Map category to WorkoutType
        if (types.contains(WorkoutType.recovery) && category == 'recovery') return true;
        if (types.contains(WorkoutType.endurance) && category == 'endurance') return true;
        if (types.contains(WorkoutType.tempo) && category == 'tempo') return true;
        if (types.contains(WorkoutType.threshold) && category == 'threshold') return true;
        if (types.contains(WorkoutType.vo2max) && category == 'vo2max') return true;
        if (types.contains(WorkoutType.ftp) && category == 'ftp') return true;

        return false;
      }).toList();
    }

    return filtered;
  });

  /// Whether any filters are active (derived)
  late final hasActiveFilters = B.derived(() {
    return sourceFilter.value != SourceFilter.everybody || workoutTypeFilters.value.isNotEmpty;
  });

  /// Active filter colors for the PillButton
  late final activeFilterColors = B.derived(() {
    final types = workoutTypeFilters.value;

    return [
      WorkoutType.recovery,
      WorkoutType.endurance,
      WorkoutType.tempo,
      WorkoutType.threshold,
      WorkoutType.vo2max,
      WorkoutType.ftp,
    ].map((type) {
      if (types.contains(type)) {
        return type.color;
      }
      return Color(0x1AFFFFFF);
    }).toList();
  });

  void selectTab(int index) {
    selectedTabIndex.value = index;
  }

  void setSourceFilter(SourceFilter filter) {
    sourceFilter.value = filter;
  }

  void toggleWorkoutType(WorkoutType type) {
    final current = Set<WorkoutType>.from(workoutTypeFilters.value);
    if (current.contains(type)) {
      current.remove(type);
    } else {
      current.add(type);
    }
    workoutTypeFilters.value = current;
  }

  void clearFilters() {
    sourceFilter.value = SourceFilter.everybody;
    workoutTypeFilters.value = {};
  }

  Future<void> loadActivities({bool isRefresh = false}) async {
    // Only show loading indicator for initial load, not refresh
    // (CupertinoSliverRefreshControl provides its own spinner)
    if (!isRefresh) {
      isLoadingActivities.value = true;
    }
    activitiesError.value = null;

    try {
      // Load API activities and local activities in parallel
      await Future.wait([_loadApiActivities(), _loadLocalActivities()]);
    } catch (e, stackTrace) {
      activitiesError.value = 'Failed to load activities: $e';
      print('[HomePageController.loadActivities] Error loading activities: $e');
      print(stackTrace);
    } finally {
      if (!isRefresh) {
        isLoadingActivities.value = false;
      }
    }
  }

  /// Load activities from API
  Future<void> _loadApiActivities() async {
    try {
      final timeline = sourceFilter.value == SourceFilter.everybody ? 'public' : 'mine';
      final response = await apiClient.activities(timeline: timeline);
      activities.value = response.activities;
    } catch (e, stackTrace) {
      print('[HomePageController._loadApiActivities] Error loading API activities: $e');
      print(stackTrace);
      rethrow;
    }
  }

  /// Load completed workout sessions from local storage
  Future<void> _loadLocalActivities() async {
    try {
      final workoutIds = await workoutSessionPersistence.listWorkoutIds();
      final localWorkouts = <Activity>[];

      for (final workoutId in workoutIds) {
        final metadata = await workoutSessionPersistence.loadSessionMetadata(workoutId);

        // Only include completed sessions
        if (metadata == null || metadata.status != SessionStatus.completed) {
          continue;
        }

        // Load samples to calculate metrics
        final samples = await workoutSessionPersistence.loadAllSamples(workoutId);

        // Calculate average metrics
        double? avgPower;
        double? avgCadence;
        double? avgHeartRate;

        if (samples.isNotEmpty) {
          final powerSamples = samples.where((s) => s.powerActual != null).toList();
          if (powerSamples.isNotEmpty) {
            avgPower = powerSamples.map((s) => s.powerActual!).reduce((a, b) => a + b) / powerSamples.length;
          }

          final cadenceSamples = samples.where((s) => s.cadence != null).toList();
          if (cadenceSamples.isNotEmpty) {
            avgCadence = cadenceSamples.map((s) => s.cadence!).reduce((a, b) => a + b) / cadenceSamples.length;
          }

          final hrSamples = samples.where((s) => s.heartRate != null).toList();
          if (hrSamples.isNotEmpty) {
            avgHeartRate = hrSamples.map((s) => s.heartRate!).reduce((a, b) => a + b) / hrSamples.length;
          }
        }

        // Determine category from workout plan (heuristic based on power zones)
        String? category;
        if (samples.isNotEmpty) {
          final avgTargetPower = samples.map((s) => s.powerTarget).reduce((a, b) => a + b) / samples.length;
          final powerFraction = avgTargetPower / metadata.ftp;

          if (powerFraction < 0.65) {
            category = 'recovery';
          } else if (powerFraction < 0.80) {
            category = 'endurance';
          } else if (powerFraction < 0.90) {
            category = 'tempo';
          } else if (powerFraction < 1.05) {
            category = 'threshold';
          } else {
            category = 'vo2max';
          }
        }

        // Create activity from session
        final activity = Activity.create(
          id: 'local-$workoutId', // Prefix to differentiate from API activities
          createdAt: metadata.startTime.toIso8601String(),
          duration: metadata.elapsedMs,
          averagePower: avgPower,
          averageCadence: avgCadence,
          averageHeartRate: avgHeartRate,
          visibility: ActivityVisibility.private,
          user: ActivityUser.create(id: metadata.userId ?? 'local', name: 'You'),
          workout: ActivityWorkout.create(
            id: metadata.sourceWorkoutId,
            title: metadata.workoutName,
            slug: metadata.sourceWorkoutId,
            duration: metadata.elapsedMs,
            plan: metadata.workoutPlan,
            category: category != null ? WorkoutCategory(category) : null,
            starCount: 0,
          ),
        );

        localWorkouts.add(activity);
      }

      localActivities.value = localWorkouts;
      chirp.debug('Loaded ${localWorkouts.length} local activities');
    } catch (e, stackTrace) {
      chirp.warning('Error loading local activities', error: e, stackTrace: stackTrace);
      // Don't rethrow - local activities are optional
    }
  }

  /// Checks for incomplete workouts and shows a notification if found
  Future<void> checkForIncompleteWorkouts() async {
    final incompleteSession = await workoutSessionPersistence.getActiveSession();
    if (incompleteSession != null) {
      final duration = Duration(milliseconds: incompleteSession.elapsedMs);
      final minutes = duration.inMinutes;
      final seconds = duration.inSeconds.remainder(60);
      final elapsedTime = '${minutes}m ${seconds}s';

      notificationService.show(
        AppNotification.workoutResume(
          workoutTitle: incompleteSession.workoutName,
          elapsedTime: elapsedTime,
          onResume: () {
            notificationService.clearAll();
            context.push(
              '/workout-player?resuming=true',
              extra: {
                'workoutId': incompleteSession.sourceWorkoutId,
                'plan': incompleteSession.workoutPlan,
                'name': incompleteSession.workoutName,
              },
            );
          },
          onDiscard: () async {
            await workoutSessionPersistence.updateSessionStatus(incompleteSession.id, SessionStatus.abandoned);
            notificationService.clearAll();
          },
          onStartFresh: () async {
            await workoutSessionPersistence.deleteSession(incompleteSession.id);
            notificationService.clearAll();
            if (context.mounted) {
              context.push(
                '/workout-player',
                extra: {
                  'workoutId': incompleteSession.sourceWorkoutId,
                  'plan': incompleteSession.workoutPlan,
                  'name': incompleteSession.workoutName,
                },
              );
            }
          },
        ),
      );
    }
  }
}

enum SourceFilter { everybody, bookmarked }

enum WorkoutType { recovery, endurance, tempo, threshold, vo2max, ftp }

extension WorkoutTypeColors on WorkoutType {
  Color get color {
    switch (this) {
      case WorkoutType.recovery:
        return VekoloColors.deepCoreBlue;
      case WorkoutType.endurance:
        return VekoloColors.vitalSurgeGreen;
      case WorkoutType.tempo:
        return VekoloColors.adrenalineRiseYellow;
      case WorkoutType.threshold:
        return VekoloColors.firelineOrange;
      case WorkoutType.vo2max:
        return VekoloColors.heartburstRed;
      case WorkoutType.ftp:
        return VekoloColors.limitBreakPink;
    }
  }
}
