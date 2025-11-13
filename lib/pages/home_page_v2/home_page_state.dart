// ignore_for_file: use_setters_to_change_properties

import 'package:state_beacon/state_beacon.dart';

/// Reactive state for the Home Page
class HomePageState extends BeaconController {
  /// Currently selected tab index (0: Activities, 1: Library, 2: Create)
  late final selectedTabIndex = B.writable(0);

  /// Whether the filter modal is currently visible
  late final isFilterModalVisible = B.writable(false);

  /// Current source filter selection ('everybody' or 'bookmarked')
  late final sourceFilter = B.writable<SourceFilter>(SourceFilter.everybody);

  /// Currently selected workout type filters
  late final workoutTypeFilters = B.writable<Set<WorkoutType>>({});

  /// Whether any filters are active (derived)
  late final hasActiveFilters = B.derived(() {
    return sourceFilter.value != SourceFilter.everybody || workoutTypeFilters.value.isNotEmpty;
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
}

enum SourceFilter { everybody, bookmarked }

enum WorkoutType { recovery, endurance, tempo, threshold, vo2max, ftp }
