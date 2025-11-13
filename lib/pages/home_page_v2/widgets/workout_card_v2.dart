import 'package:flutter/material.dart';
import 'package:vekolo/pages/home_page_v2/widgets/workout_interval_bars.dart';

/// A card displaying workout information with author, title, and interval visualization
class WorkoutCardV2 extends StatelessWidget {
  const WorkoutCardV2({super.key, required this.workout, this.onTap});

  final WorkoutInfo workout;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      color: workout.backgroundColor,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: Author and Date
              Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundImage: workout.authorAvatarUrl != null ? NetworkImage(workout.authorAvatarUrl!) : null,
                    backgroundColor: Colors.white.withValues(alpha: 0.2),
                    child: workout.authorAvatarUrl == null
                        ? Text(
                            workout.authorName.isNotEmpty ? workout.authorName[0].toUpperCase() : '?',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    workout.authorName,
                    style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500),
                  ),
                  const Spacer(),
                  Text(workout.date, style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13)),
                ],
              ),
              const SizedBox(height: 20),

              // Title and Duration
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      workout.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 36,
                        fontWeight: FontWeight.w700,
                        height: 1.0,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    workout.duration,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 28,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Interval Bars
              WorkoutIntervalBars(intervals: workout.intervals, height: 50),
            ],
          ),
        ),
      ),
    );
  }
}

/// Data model for workout information
class WorkoutInfo {
  const WorkoutInfo({
    required this.authorName,
    this.authorAvatarUrl,
    required this.date,
    required this.title,
    required this.duration,
    required this.intervals,
    required this.backgroundColor,
  });

  final String authorName;
  final String? authorAvatarUrl;
  final String date;
  final String title;
  final String duration;
  final List<IntervalBar> intervals;
  final Color backgroundColor;
}
