import 'package:flutter/material.dart';

/// Displays colorful vertical bars representing workout intervals
///
/// Each bar represents a segment of the workout with varying height
/// based on intensity and colors based on power zones.
class WorkoutIntervalBars extends StatelessWidget {
  const WorkoutIntervalBars({super.key, required this.intervals, this.height = 40});

  final List<IntervalBar> intervals;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (intervals.isEmpty) {
      return SizedBox(height: height);
    }

    return SizedBox(
      height: height,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final interval in intervals)
            Expanded(
              flex: interval.duration,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 0.5),
                height: height * interval.intensity,
                decoration: BoxDecoration(color: interval.color, borderRadius: BorderRadius.circular(2)),
              ),
            ),
        ],
      ),
    );
  }
}

class IntervalBar {
  const IntervalBar({required this.intensity, required this.duration, required this.color});

  /// Intensity from 0.0 to 1.0 (determines bar height)
  final double intensity;

  /// Relative duration (flex value for spacing)
  final int duration;

  /// Color of the interval bar
  final Color color;
}

/// Helper to generate sample workout interval bars for demonstration
List<IntervalBar> generateSampleIntervals() {
  return [
    // Warm-up (blue/green)
    const IntervalBar(intensity: 0.3, duration: 2, color: Color(0xFF00BCD4)),
    const IntervalBar(intensity: 0.4, duration: 2, color: Color(0xFF00BCD4)),
    const IntervalBar(intensity: 0.5, duration: 2, color: Color(0xFF4CAF50)),

    // Build (green/orange)
    const IntervalBar(intensity: 0.6, duration: 2, color: Color(0xFF4CAF50)),
    const IntervalBar(intensity: 0.7, duration: 2, color: Color(0xFF8BC34A)),
    const IntervalBar(intensity: 0.8, duration: 2, color: Color(0xFFFFA726)),

    // Work intervals (orange/pink)
    const IntervalBar(intensity: 0.9, duration: 3, color: Color(0xFFFF6F00)),
    const IntervalBar(intensity: 0.5, duration: 2, color: Color(0xFF4CAF50)),
    const IntervalBar(intensity: 0.9, duration: 3, color: Color(0xFFFF6F00)),
    const IntervalBar(intensity: 0.5, duration: 2, color: Color(0xFF4CAF50)),
    const IntervalBar(intensity: 0.95, duration: 3, color: Color(0xFFE91E63)),
    const IntervalBar(intensity: 0.5, duration: 2, color: Color(0xFF4CAF50)),

    // Cool-down (green/blue)
    const IntervalBar(intensity: 0.4, duration: 2, color: Color(0xFF4CAF50)),
    const IntervalBar(intensity: 0.3, duration: 2, color: Color(0xFF00BCD4)),
    const IntervalBar(intensity: 0.2, duration: 2, color: Color(0xFF00BCD4)),
  ];
}
