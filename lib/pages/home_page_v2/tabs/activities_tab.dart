import 'package:flutter/material.dart';
import 'package:vekolo/pages/home_page_v2/widgets/workout_card_v2.dart';
import 'package:vekolo/pages/home_page_v2/widgets/workout_interval_bars.dart';

/// Displays the activities feed with workout cards
class ActivitiesTab extends StatelessWidget {
  const ActivitiesTab({super.key, this.onFilterTap});

  final VoidCallback? onFilterTap;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        // Top Bar (not an AppBar, just padding with icons)
        SliverToBoxAdapter(child: SizedBox(height: 120)),

        // Workout List
        SliverList(
          delegate: SliverChildBuilderDelegate((context, index) {
            final workout = _getSampleWorkouts()[index];
            return WorkoutCardV2(
              workout: workout,
              onTap: () {
                // TODO: Navigate to workout details
              },
            );
          }, childCount: _getSampleWorkouts().length),
        ),

        // Bottom padding for tab bar
        const SliverPadding(padding: EdgeInsets.only(bottom: 80)),
      ],
    );
  }

  /// Sample workouts for demonstration
  static List<WorkoutInfo> _getSampleWorkouts() {
    return [
      WorkoutInfo(
        authorName: 'John Doe',
        date: 'Nov 05, 2025',
        title: 'Summit Peak',
        duration: '1:10:45',
        intervals: generateSampleIntervals(),
        backgroundColor: const Color(0xFF5D4A3A), // Brown
      ),
      WorkoutInfo(
        authorName: 'Freddy Krüggar',
        date: 'Nov 05, 2025',
        title: 'High-Intensity Summit',
        duration: '45:30',
        intervals: generateSampleIntervals(),
        backgroundColor: const Color(0xFF5C2E3E), // Dark red/burgundy
      ),
      WorkoutInfo(
        authorName: 'Jason Voorhees',
        date: 'Oct 31, 2025',
        title: 'Horror Movie Marathon',
        duration: '50:15',
        intervals: generateSampleIntervals(),
        backgroundColor: const Color(0xFF5C2E3E), // Dark red/burgundy
      ),
      WorkoutInfo(
        authorName: 'Michael Myers',
        date: 'Dec 15, 2025',
        title: 'Slasher Film Fest',
        duration: '55:45',
        intervals: generateSampleIntervals(),
        backgroundColor: const Color(0xFF5C2E3E), // Dark red/burgundy
      ),
      WorkoutInfo(
        authorName: 'John Doe',
        date: 'Nov 05, 2025',
        title: 'Summit Peak',
        duration: '1:10:45',
        intervals: generateSampleIntervals(),
        backgroundColor: const Color(0xFF5D4A3A), // Brown
      ),
      WorkoutInfo(
        authorName: 'Freddy Krüggar',
        date: 'Nov 05, 2025',
        title: 'High-Intensity Summit',
        duration: '45:30',
        intervals: generateSampleIntervals(),
        backgroundColor: const Color(0xFF5C2E3E), // Dark red/burgundy
      ),
      WorkoutInfo(
        authorName: 'Jason Voorhees',
        date: 'Oct 31, 2025',
        title: 'Horror Movie Marathon',
        duration: '50:15',
        intervals: generateSampleIntervals(),
        backgroundColor: const Color(0xFF5C2E3E), // Dark red/burgundy
      ),
      WorkoutInfo(
        authorName: 'Michael Myers',
        date: 'Dec 15, 2025',
        title: 'Slasher Film Fest',
        duration: '55:45',
        intervals: generateSampleIntervals(),
        backgroundColor: const Color(0xFF5C2E3E), // Dark red/burgundy
      ),
    ];
  }
}
