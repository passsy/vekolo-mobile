import 'package:flutter/material.dart';
import 'package:vekolo/pages/home_page_v2/home_page_controller.dart';

/// Modal for filtering workouts by source and type
class FilterModal extends StatelessWidget {
  const FilterModal({
    super.key,
    required this.sourceFilter,
    required this.workoutTypeFilters,
    required this.onSourceFilterChanged,
    required this.onWorkoutTypeToggled,
    required this.onClose,
  });

  final SourceFilter sourceFilter;
  final Set<WorkoutType> workoutTypeFilters;
  final ValueChanged<SourceFilter> onSourceFilterChanged;
  final ValueChanged<WorkoutType> onWorkoutTypeToggled;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF2B2520), // Dark brown
        borderRadius: BorderRadius.circular(32),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.6), blurRadius: 24, offset: const Offset(0, 12))],
      ),
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Source Filter Toggle
          Row(
            children: [
              Expanded(
                child: _SourceFilterButton(
                  label: const Text('Everybody'),
                  icon: Icons.public,
                  isSelected: sourceFilter == SourceFilter.everybody,
                  onTap: () => onSourceFilterChanged(SourceFilter.everybody),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _SourceFilterButton(
                  label: const Text('Bookmarked'),
                  icon: Icons.bookmark,
                  isSelected: sourceFilter == SourceFilter.bookmarked,
                  onTap: () => onSourceFilterChanged(SourceFilter.bookmarked),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Workout Type Filters
          _WorkoutTypeFilterButton(
            label: const Text('RECOVERY'),
            icon: Icons.water,
            isSelected: workoutTypeFilters.contains(WorkoutType.recovery),
            onTap: () => onWorkoutTypeToggled(WorkoutType.recovery),
            workoutType: WorkoutType.recovery,
          ),
          const SizedBox(height: 16),
          _WorkoutTypeFilterButton(
            label: const Text('ENDURANCE'),
            icon: Icons.favorite,
            isSelected: workoutTypeFilters.contains(WorkoutType.endurance),
            onTap: () => onWorkoutTypeToggled(WorkoutType.endurance),
            workoutType: WorkoutType.endurance,
          ),
          const SizedBox(height: 16),
          _WorkoutTypeFilterButton(
            label: const Text('TEMPO'),
            icon: Icons.fast_forward,
            isSelected: workoutTypeFilters.contains(WorkoutType.tempo),
            onTap: () => onWorkoutTypeToggled(WorkoutType.tempo),
            workoutType: WorkoutType.tempo,
          ),
          const SizedBox(height: 16),
          _WorkoutTypeFilterButton(
            label: const Text('THRESHOLD'),
            icon: Icons.flash_on,
            isSelected: workoutTypeFilters.contains(WorkoutType.threshold),
            onTap: () => onWorkoutTypeToggled(WorkoutType.threshold),
            workoutType: WorkoutType.threshold,
          ),
          const SizedBox(height: 16),
          _WorkoutTypeFilterButton(
            label: const Text('VO2MAX'),
            icon: Icons.local_fire_department,
            isSelected: workoutTypeFilters.contains(WorkoutType.vo2max),
            onTap: () => onWorkoutTypeToggled(WorkoutType.vo2max),
            workoutType: WorkoutType.vo2max,
          ),
          const SizedBox(height: 16),
          _WorkoutTypeFilterButton(
            label: const Text('FTP'),
            icon: Icons.rocket_launch,
            isSelected: workoutTypeFilters.contains(WorkoutType.ftp),
            onTap: () => onWorkoutTypeToggled(WorkoutType.ftp),
            workoutType: WorkoutType.ftp,
          ),
        ],
      ),
    );
  }
}

class _SourceFilterButton extends StatelessWidget {
  const _SourceFilterButton({required this.label, required this.icon, required this.isSelected, required this.onTap});

  final Widget label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected ? const Color(0xFFFF6F00) : const Color(0xFF4A3F39),
      borderRadius: BorderRadius.circular(100),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(100),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: isSelected ? Colors.black : const Color(0xFFD4B896), size: 20),
              const SizedBox(width: 12),
              DefaultTextStyle(
                style: TextStyle(
                  color: isSelected ? Colors.black : const Color(0xFFD4B896),
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
                child: label,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkoutTypeFilterButton extends StatelessWidget {
  const _WorkoutTypeFilterButton({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
    required this.workoutType,
  });

  final Widget label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;
  final WorkoutType workoutType;

  @override
  Widget build(BuildContext context) {
    final Color backgroundColor;
    final Color foregroundColor;

    if (isSelected) {
      foregroundColor = Colors.black;
      backgroundColor = workoutType.color;
    } else {
      backgroundColor = const Color(0xFF4A3F39); // Dark gray/brown
      foregroundColor = const Color(0xFFD4B896); // Tan/beige
    }

    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(100),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(100),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
          child: Row(
            children: [
              Icon(icon, color: foregroundColor, size: 28),
              const SizedBox(width: 16),
              DefaultTextStyle(
                style: TextStyle(color: foregroundColor, fontSize: 18, fontWeight: FontWeight.w600, letterSpacing: 0.5),
                child: label,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
