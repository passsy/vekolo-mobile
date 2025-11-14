// ignore_for_file: use_setters_to_change_properties

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

  /// Loading state for activities
  late final isLoadingActivities = B.writable(false);

  /// Error message if loading fails
  late final activitiesError = B.writable<String?>(null);

  /// Filtered activities based on current filters
  late final filteredActivities = B.derived(() {
    final all = activities.value;
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

  Future<void> loadActivities() async {
    isLoadingActivities.value = true;
    activitiesError.value = null;

    try {
      final timeline = sourceFilter.value == SourceFilter.everybody ? 'public' : 'mine';
      final response = await apiClient.activities(timeline: timeline);
      activities.value = response.activities;
    } catch (e, stackTrace) {
      activitiesError.value = 'Failed to load activities: $e';
      print('[HomePageController.loadActivities] Error loading activities: $e');
      print(stackTrace);
    } finally {
      isLoadingActivities.value = false;
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
              extra: {'plan': incompleteSession.workoutPlan, 'name': incompleteSession.workoutName},
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
                extra: {'plan': incompleteSession.workoutPlan, 'name': incompleteSession.workoutName},
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
