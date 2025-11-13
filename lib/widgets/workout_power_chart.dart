/// Real-time power visualization widget for workout player.
///
/// Displays a scrolling chart of actual vs target power over time,
/// with each bar representing a 15-second interval.
library;

import 'package:flutter/material.dart';
import 'package:vekolo/domain/models/power_history.dart';

/// Displays a scrolling power chart with actual vs target power bars.
///
/// Shows power data points as vertical bars, where:
/// - Target power is shown as a lighter background bar
/// - Actual power is shown as a colored bar overlaid on top
/// - Colors indicate power zones (recovery, endurance, tempo, threshold, VO2max, anaerobic)
/// - Chart scrolls as new data arrives, showing the most recent data on the right
///
/// Example usage:
/// ```dart
/// WorkoutPowerChart(
///   powerHistory: playerService.powerHistory,
///   maxVisibleBars: 20,
/// )
/// ```
class WorkoutPowerChart extends StatelessWidget {
  /// Creates a workout power chart.
  const WorkoutPowerChart({
    super.key,
    required this.powerHistory,
    this.maxVisibleBars = 20,
    this.height = 120,
    this.ftp,
  });

  /// Power history data to display.
  final PowerHistory powerHistory;

  /// Maximum number of bars to show at once.
  ///
  /// Older bars will scroll off to the left as new ones arrive.
  final int maxVisibleBars;

  /// Height of the chart in pixels.
  final double height;

  /// Functional Threshold Power for zone calculations.
  ///
  /// If provided, bars will be colored based on power zones.
  /// If null, bars will use a default color scheme.
  final int? ftp;

  @override
  Widget build(BuildContext context) {
    final dataPoints = powerHistory.dataPoints;

    // Get the last N data points to display
    final visiblePoints = dataPoints.length > maxVisibleBars
        ? dataPoints.sublist(dataPoints.length - maxVisibleBars)
        : dataPoints;

    if (visiblePoints.isEmpty) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            'Waiting for data...',
            style: TextStyle(color: Colors.grey[600], fontSize: 14),
          ),
        ),
      );
    }

    // Find max power for scaling
    final maxPower = visiblePoints.fold<int>(
      0,
      (max, point) => [max, point.actualWatts, point.targetWatts].reduce((a, b) => a > b ? a : b),
    );

    // Add some headroom (20% above max)
    final chartMaxPower = (maxPower * 1.2).ceil();

    return SizedBox(
      height: height,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final point in visiblePoints)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: _buildPowerBar(
                  point: point,
                  maxPower: chartMaxPower,
                  ftp: ftp,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Builds a single power bar showing actual vs target.
  Widget _buildPowerBar({
    required PowerDataPoint point,
    required int maxPower,
    required int? ftp,
  }) {
    final targetHeight = (point.targetWatts / maxPower).clamp(0.0, 1.0);
    final actualHeight = (point.actualWatts / maxPower).clamp(0.0, 1.0);

    // Determine color based on power zone (relative to FTP if available)
    final actualColor = _getPowerZoneColor(point.actualWatts, ftp);
    final targetColor = Colors.grey[400]!;

    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        // Target power bar (background)
        FractionallySizedBox(
          heightFactor: targetHeight,
          child: Container(
            decoration: BoxDecoration(
              color: targetColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        // Actual power bar (foreground)
        FractionallySizedBox(
          heightFactor: actualHeight,
          child: Container(
            decoration: BoxDecoration(
              color: actualColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ],
    );
  }

  /// Gets the color for a power value based on training zones.
  ///
  /// Zones (based on FTP):
  /// - Recovery: < 55% FTP (blue)
  /// - Endurance: 55-75% FTP (green)
  /// - Tempo: 75-90% FTP (yellow-green)
  /// - Threshold: 90-105% FTP (orange)
  /// - VO2max: 105-120% FTP (red-orange)
  /// - Anaerobic: > 120% FTP (red/pink)
  ///
  /// If FTP is not provided, uses absolute power values.
  Color _getPowerZoneColor(int watts, int? ftp) {
    if (ftp == null || ftp == 0) {
      // Fallback to absolute power colors
      if (watts < 100) return const Color(0xFF00BCD4); // Cyan
      if (watts < 150) return const Color(0xFF4CAF50); // Green
      if (watts < 200) return const Color(0xFF8BC34A); // Light green
      if (watts < 250) return const Color(0xFFFFA726); // Orange
      if (watts < 300) return const Color(0xFFFF6F00); // Deep orange
      return const Color(0xFFE91E63); // Pink
    }

    final percent = watts / ftp;

    if (percent < 0.55) return const Color(0xFF00BCD4); // Recovery - Cyan
    if (percent < 0.75) return const Color(0xFF4CAF50); // Endurance - Green
    if (percent < 0.90) return const Color(0xFF8BC34A); // Tempo - Light green
    if (percent < 1.05) return const Color(0xFFFFA726); // Threshold - Orange
    if (percent < 1.20) return const Color(0xFFFF6F00); // VO2max - Deep orange
    return const Color(0xFFE91E63); // Anaerobic - Pink
  }
}
