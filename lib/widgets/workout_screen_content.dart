/// Modern workout screen content widget.
///
/// Displays the workout player UI with:
/// - Real-time power chart
/// - Current metrics (power, cadence, HR)
/// - Timer and progress
/// - Current block information
/// - Playback controls
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vekolo/domain/models/power_history.dart';
import 'package:vekolo/domain/models/workout/workout_models.dart';
import 'package:vekolo/pages/home_page_v2/widgets/workout_interval_bars.dart';
import 'package:vekolo/widgets/gradient_card_background.dart';

/// Responsive spacing configuration based on screen height.
class _ResponsiveSpacing {
  _ResponsiveSpacing({
    required this.small,
    required this.medium,
    required this.large,
    required this.section,
    required this.horizontal,
    required this.kpiValue,
    required this.metricValue,
    required this.metricLabel,
    required this.intervalHeight,
  });

  factory _ResponsiveSpacing.fromHeight(double height) {
    // Define min and max values for smooth interpolation
    const minHeight = 500.0; // Small phone screens
    const maxHeight = 900.0; // Large screens/tablets

    // Clamp height to valid range
    final clampedHeight = height.clamp(minHeight, maxHeight);

    // Calculate interpolation factor (0.0 = min, 1.0 = max)
    final t = (clampedHeight - minHeight) / (maxHeight - minHeight);

    return _ResponsiveSpacing(
      small: _lerp(1, 8, t), // Much tighter spacing on small screens
      medium: _lerp(4, 16, t), // Reduced from 6
      large: _lerp(6, 32, t), // Reduced from 10
      section: _lerp(8, 32, t), // Reduced from 12
      horizontal: _lerp(8, 16, t), // Reduced from 10
      kpiValue: _lerp(16, 36, t), // Smaller text on small screens
      metricValue: _lerp(48, 64, t), // Reduced from 38
      metricLabel: _lerp(16, 16, t), // Reduced from 8
      intervalHeight: _lerp(60, 150, t), // Much shorter on small screens
    );
  }

  /// Linear interpolation between min and max values
  static double _lerp(double min, double max, double t) {
    return min + (max - min) * t;
  }

  final double small;
  final double medium;
  final double large;
  final double section;
  final double horizontal;
  final double kpiValue;
  final double metricValue;
  final double metricLabel;
  final double intervalHeight;
}

/// Modern workout screen layout.
class WorkoutScreenContent extends StatelessWidget {
  const WorkoutScreenContent({
    super.key,
    required this.powerHistory,
    required this.workoutPlan,
    required this.currentBlock,
    required this.nextBlock,
    required this.elapsedTime,
    required this.remainingTime,
    required this.currentBlockRemainingTime,
    required this.powerTarget,
    required this.currentPower,
    required this.cadenceTarget,
    required this.currentCadence,
    required this.currentHeartRate,
    required this.currentSpeed,
    required this.isPaused,
    required this.isComplete,
    required this.hasStarted,
    required this.ftp,
    required this.powerScaleFactor,
    required this.onPlayPause,
    required this.onSkip,
    required this.onEndWorkout,
    required this.onPowerScaleIncrease,
    required this.onPowerScaleDecrease,
    required this.onDevicesPressed,
    required this.onClose,
  });

  final PowerHistory powerHistory;
  final WorkoutPlan workoutPlan;
  final dynamic currentBlock;
  final dynamic nextBlock;
  final int elapsedTime;
  final int remainingTime;
  final int currentBlockRemainingTime;
  final int powerTarget;
  final int? currentPower;
  final int? cadenceTarget;
  final int? currentCadence;
  final int? currentHeartRate;
  final double? currentSpeed;
  final bool isPaused;
  final bool isComplete;
  final bool hasStarted;
  final int ftp;
  final double powerScaleFactor;
  final VoidCallback onPlayPause;
  final VoidCallback onSkip;
  final VoidCallback onEndWorkout;
  final VoidCallback onPowerScaleIncrease;
  final VoidCallback onPowerScaleDecrease;
  final VoidCallback onDevicesPressed;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        final spacing = _ResponsiveSpacing.fromHeight(height);

        return Stack(
          children: [
            // Background gradient
            const Positioned.fill(
              child: GradientCardBackground(color: Color(0xFF1B4332), gradientStart: 0.0, gradientEnd: 0.8),
            ),
            // Content with scrollable area and fixed bottom
            SafeArea(
              child: Column(
                children: [
                  // Scrollable content area
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          SizedBox(height: spacing.section),
                          // KPI row at top
                          _buildKPIRow(spacing),
                          SizedBox(height: spacing.section),

                          // Progress bar
                          _buildProgressBar(spacing),
                          SizedBox(height: spacing.large),

                          // TIME metric - only show remaining time in current interval
                          _buildSimpleMetricRow('TIME', currentBlockRemainingTime, Colors.white, spacing: spacing),
                          SizedBox(height: spacing.section),

                          // Large interval visualization
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: spacing.horizontal),
                            child: _buildIntervalVisualization(spacing),
                          ),
                          SizedBox(height: spacing.section),

                          // WATT metric with current target and next target
                          _buildSimpleMetricRow(
                            'WATT',
                            currentPower ?? 0,
                            _getMetricColor(currentPower ?? 0, powerTarget, threshold: 10),
                            target: powerTarget,
                            nextTarget: _getNextPower(),
                            spacing: spacing,
                          ),
                          SizedBox(height: spacing.medium),

                          // RPM metric with current target and next target
                          _buildSimpleMetricRow(
                            'RPM',
                            currentCadence ?? 0,
                            _getMetricColor(currentCadence ?? 0, cadenceTarget, threshold: 5),
                            target: cadenceTarget,
                            nextTarget: _getNextCadence(),
                            spacing: spacing,
                          ),
                          SizedBox(height: spacing.large),

                          // Control buttons: Skip and Difficulty adjustment
                          _buildControlButtons(spacing),
                          SizedBox(height: spacing.medium),
                        ],
                      ),
                    ),
                  ),

                  // Fixed bottom timeline and timestamps
                  _buildBottomTimeline(),
                  SizedBox(height: spacing.small),
                  _buildTimestamps(),
                  SizedBox(height: spacing.medium),
                ],
              ),
            ),
            // Close button at top-right
            Positioned(
              top: 0,
              right: 0,
              child: SafeArea(
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 28),
                  onPressed: onClose,
                  padding: const EdgeInsets.all(16),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // Helper methods to get next block values
  int _getNextPower() {
    if (nextBlock == null) return 0;
    if (nextBlock is PowerBlock) {
      final block = nextBlock as PowerBlock;
      return (block.power * ftp).round();
    } else if (nextBlock is RampBlock) {
      final block = nextBlock as RampBlock;
      return (block.powerStart * ftp).round();
    }
    return 0;
  }

  int? _getNextCadence() {
    if (nextBlock == null) return null;
    if (nextBlock is PowerBlock) {
      final block = nextBlock as PowerBlock;
      return block.cadence;
    } else if (nextBlock is RampBlock) {
      final block = nextBlock as RampBlock;
      return block.cadenceStart;
    }
    return null;
  }

  /// Calculate color for metric based on how close it is to target
  ///
  /// - Red: when current > target + threshold (too high)
  /// - Yellow: when current < target - threshold (too low)
  /// - Green: when within threshold range (good)
  Color _getMetricColor(int current, int? target, {required int threshold}) {
    if (target == null || target == 0) {
      // No target set, use default green
      return const Color(0xFF52B788);
    }

    final difference = current - target;

    if (difference > threshold) {
      // Too high - red
      return const Color(0xFFE74C3C); // Red
    } else if (difference < -threshold) {
      // Too low - yellow
      return const Color(0xFFF39C12); // Yellow/Orange
    } else {
      // Within range - green
      return const Color(0xFF52B788); // Green
    }
  }

  Widget _buildKPIRow(_ResponsiveSpacing spacing) {
    return InkWell(
      onTap: onDevicesPressed,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: spacing.horizontal, vertical: spacing.small),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildKPI('WATT', (currentPower ?? 0).toString(), spacing),
            _buildKPI('RPM', (currentCadence ?? 0).toString(), spacing),
            _buildKPI('HR', (currentHeartRate ?? 0).toString(), spacing),
            _buildKPI('SPEED', currentSpeed != null ? currentSpeed!.toStringAsFixed(1) : '0', spacing),
          ],
        ),
      ),
    );
  }

  Widget _buildKPI(String label, String value, _ResponsiveSpacing spacing) {
    return Column(
      children: [
        Text(
          label,
          style: GoogleFonts.publicSans(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: spacing.small / 2),
        Text(
          value,
          style: GoogleFonts.sairaExtraCondensed(
            color: Colors.white,
            fontSize: spacing.kpiValue,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }

  Widget _buildProgressBar(_ResponsiveSpacing spacing) {
    final progress = remainingTime > 0 ? elapsedTime / (elapsedTime + remainingTime) : 1.0;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: spacing.horizontal * 3),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: progress,
          minHeight: 6,
          backgroundColor: Colors.white.withValues(alpha: 0.2),
          valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF52B788)),
        ),
      ),
    );
  }

  Widget _buildControlButtons(_ResponsiveSpacing spacing) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: spacing.horizontal * 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Difficulty decrease button
          IconButton(
            onPressed: onPowerScaleDecrease,
            icon: const Icon(Icons.remove, color: Colors.white, size: 24),
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.1),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          SizedBox(width: spacing.medium),

          // Difficulty indicator
          Container(
            padding: EdgeInsets.symmetric(horizontal: spacing.medium, vertical: spacing.small),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${(powerScaleFactor * 100).toStringAsFixed(0)}%',
              style: GoogleFonts.publicSans(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          SizedBox(width: spacing.medium),

          // Difficulty increase button
          IconButton(
            onPressed: onPowerScaleIncrease,
            icon: const Icon(Icons.add, color: Colors.white, size: 24),
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.1),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          SizedBox(width: spacing.large),

          // Skip button
          ElevatedButton.icon(
            onPressed: onSkip,
            icon: const Icon(Icons.skip_next, size: 20),
            label: const Text('SKIP'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.15),
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(horizontal: spacing.large, vertical: spacing.medium),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              textStyle: GoogleFonts.publicSans(fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 1.0),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSimpleMetricRow(
    String label,
    int current,
    Color valueColor, {
    int? target,
    int? nextTarget,
    required _ResponsiveSpacing spacing,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: spacing.horizontal * 2),
      child: Column(
        children: [
          Text(
            label,
            style: GoogleFonts.publicSans(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: spacing.metricLabel,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: spacing.small / 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              // Current value (highlighted)
              Text(
                _formatValue(current),
                style: GoogleFonts.sairaExtraCondensed(
                  color: valueColor,
                  fontSize: spacing.metricValue,
                  fontWeight: FontWeight.w400,
                  height: 1.0,
                ),
              ),
              if (target != null) ...[
                SizedBox(width: spacing.medium),
                // Target value of current block (dim)
                Text(
                  _formatValue(target),
                  style: GoogleFonts.sairaExtraCondensed(
                    color: Colors.white.withValues(alpha: 0.3),
                    fontSize: spacing.metricValue,
                    fontWeight: FontWeight.w400,
                    height: 1.0,
                  ),
                ),
              ],
              if (nextTarget != null) ...[
                SizedBox(width: spacing.medium),
                // Target value of next block (dim)
                Text(
                  _formatValue(nextTarget),
                  style: GoogleFonts.sairaExtraCondensed(
                    color: Colors.white.withValues(alpha: 0.3),
                    fontSize: spacing.metricValue,
                    fontWeight: FontWeight.w400,
                    height: 1.0,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  String _formatValue(int value) {
    // Convert milliseconds to seconds for time values (values >= 1000)
    if (value >= 1000) {
      final totalSeconds = (value / 1000).floor();
      final minutes = totalSeconds ~/ 60;
      final seconds = totalSeconds % 60;
      return '$minutes:${seconds.toString().padLeft(2, '0')}';
    }
    return value.toString();
  }

  /// Converts workout plan blocks into interval bars for visualization
  List<IntervalBar> _generateIntervalsFromWorkout() {
    final intervals = <IntervalBar>[];

    for (final block in workoutPlan.plan) {
      _addBlockIntervals(block, intervals);
    }

    return intervals;
  }

  void _addBlockIntervals(dynamic block, List<IntervalBar> intervals) {
    if (block is PowerBlock) {
      final color = _getPowerZoneColor(block.power);
      intervals.add(
        IntervalBar(
          intensity: block.power,
          duration: block.duration ~/ 1000, // Convert ms to seconds for flex value
          color: color,
        ),
      );
    } else if (block is RampBlock) {
      final color = _getPowerZoneColor((block.powerStart + block.powerEnd) / 2);
      intervals.add(
        IntervalBar(
          intensity: (block.powerStart + block.powerEnd) / 2,
          intensityStart: block.powerStart,
          intensityEnd: block.powerEnd,
          duration: block.duration ~/ 1000,
          color: color,
        ),
      );
    } else if (block is WorkoutInterval) {
      // Expand intervals into individual parts
      for (var i = 0; i < block.repeat; i++) {
        for (final part in block.parts) {
          _addBlockIntervals(part, intervals);
        }
      }
    }
  }

  Color _getPowerZoneColor(double powerFraction) {
    if (powerFraction < 0.55) return const Color(0xFF00BCD4); // Recovery - cyan
    if (powerFraction < 0.75) return const Color(0xFF4CAF50); // Endurance - green
    if (powerFraction < 0.90) return const Color(0xFF8BC34A); // Tempo - light green
    if (powerFraction < 1.05) return const Color(0xFFFFA726); // Threshold - orange
    if (powerFraction < 1.20) return const Color(0xFFFF6F00); // VO2max - deep orange
    return const Color(0xFFE91E63); // Anaerobic - pink
  }

  Widget _buildIntervalVisualization(_ResponsiveSpacing spacing) {
    final intervals = _generateZoomedIntervals();
    const windowSize = 15 * 60 * 1000; // 15 minutes in milliseconds
    final windowStart = (elapsedTime - windowSize).clamp(0, double.infinity).toInt();

    // Calculate current position relative to the zoomed window
    final currentTimeInWindow = elapsedTime - windowStart;
    // Calculate actual total duration of visible intervals (sum of all interval durations)
    final totalWindowDuration = intervals.fold<int>(0, (sum, interval) => sum + (interval.duration * 1000));

    return WorkoutIntervalBars(
      intervals: intervals,
      height: spacing.intervalHeight,
      currentTimeMs: currentTimeInWindow,
      totalDurationMs: totalWindowDuration,
    );
  }

  /// Generate a zoomed view of intervals (±15 minutes around current position)
  List<IntervalBar> _generateZoomedIntervals() {
    final allIntervals = _generateIntervalsFromWorkout();
    const windowSize = 15 * 60 * 1000; // 15 minutes in milliseconds
    final currentTime = elapsedTime;
    final windowStart = (currentTime - windowSize).clamp(0, double.infinity).toInt();
    final windowEnd = currentTime + windowSize;

    // Calculate cumulative times for each interval
    final zoomedIntervals = <IntervalBar>[];
    var cumulativeTime = 0;

    for (final interval in allIntervals) {
      final intervalDuration = interval.duration * 1000; // Convert seconds to ms
      final intervalStart = cumulativeTime;
      final intervalEnd = cumulativeTime + intervalDuration;

      // Check if this interval overlaps with our window
      if (intervalEnd > windowStart && intervalStart < windowEnd) {
        // Calculate the visible portion of this interval
        final visibleStart = intervalStart < windowStart ? windowStart : intervalStart;
        final visibleEnd = intervalEnd > windowEnd ? windowEnd : intervalEnd;
        final visibleDuration = ((visibleEnd - visibleStart) / 1000).round(); // Back to seconds

        if (visibleDuration > 0) {
          // For partially visible intervals, we need to adjust the intensity if it's a ramp
          if (interval.intensityStart != null && interval.intensityEnd != null) {
            // Calculate where we are in the ramp
            final startFraction = (visibleStart - intervalStart) / intervalDuration;
            final endFraction = (visibleEnd - intervalStart) / intervalDuration;

            final adjustedIntensityStart =
                interval.intensityStart! + (interval.intensityEnd! - interval.intensityStart!) * startFraction;
            final adjustedIntensityEnd =
                interval.intensityStart! + (interval.intensityEnd! - interval.intensityStart!) * endFraction;

            zoomedIntervals.add(
              IntervalBar(
                intensity: (adjustedIntensityStart + adjustedIntensityEnd) / 2,
                intensityStart: adjustedIntensityStart,
                intensityEnd: adjustedIntensityEnd,
                duration: visibleDuration,
                color: interval.color,
              ),
            );
          } else {
            zoomedIntervals.add(
              IntervalBar(intensity: interval.intensity, duration: visibleDuration, color: interval.color),
            );
          }
        }
      }

      cumulativeTime = intervalEnd;

      // Early exit if we're past the window
      if (intervalStart > windowEnd) break;
    }

    return zoomedIntervals;
  }

  Widget _buildBottomTimeline() {
    final intervals = _generateIntervalsFromWorkout();
    final totalDuration = elapsedTime + remainingTime;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: WorkoutIntervalBars(intervals: intervals, currentTimeMs: elapsedTime, totalDurationMs: totalDuration),
    );
  }

  Widget _buildTimestamps() {
    final elapsedSeconds = (elapsedTime / 1000).floor();
    final elapsedMinutes = elapsedSeconds ~/ 60;
    final elapsedSecondsOnly = elapsedSeconds % 60;

    final remainingSeconds = (remainingTime / 1000).floor();
    final remainingMinutes = remainingSeconds ~/ 60;
    final remainingSecondsOnly = remainingSeconds % 60;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '${elapsedMinutes.toString().padLeft(2, '0')}:${elapsedSecondsOnly.toString().padLeft(2, '0')}',
            style: GoogleFonts.publicSans(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
          ),
          Text(
            '${remainingMinutes.toString().padLeft(2, '0')}:${remainingSecondsOnly.toString().padLeft(2, '0')}',
            style: GoogleFonts.publicSans(
              color: Colors.white.withValues(alpha: 0.3),
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
