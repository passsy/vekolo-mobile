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

                          // Status messages
                          if (!hasStarted || isPaused) ...[
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: spacing.horizontal * 2),
                              child: Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: spacing.medium,
                                  vertical: spacing.medium,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  !hasStarted
                                      ? 'Start pedaling to begin workout'
                                      : 'Paused - Start pedaling to resume',
                                  style: GoogleFonts.publicSans(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                            SizedBox(height: spacing.section),
                          ],

                          // KPI row at top
                          WorkoutKpiRow(
                            currentPower: currentPower,
                            currentCadence: currentCadence,
                            currentHeartRate: currentHeartRate,
                            currentSpeed: currentSpeed,
                            kpiValueFontSize: spacing.kpiValue,
                            horizontalPadding: spacing.horizontal,
                            verticalPadding: spacing.small,
                            smallSpacing: spacing.small / 2,
                            onTap: onDevicesPressed,
                          ),
                          SizedBox(height: spacing.section),

                          // Progress bar
                          WorkoutProgressBar(
                            elapsedTime: elapsedTime,
                            remainingTime: remainingTime,
                            horizontalPadding: spacing.horizontal * 3,
                          ),
                          SizedBox(height: spacing.large),

                          // TIME metric - only show remaining time in current interval
                          WorkoutMetricRow(
                            label: const Text('TIME'),
                            current: Text(_formatValue(currentBlockRemainingTime)),
                            valueColor: Colors.white,
                            metricLabelFontSize: spacing.metricLabel,
                            metricValueFontSize: spacing.metricValue,
                            horizontalPadding: spacing.horizontal * 2,
                            smallSpacing: spacing.small / 2,
                            mediumSpacing: spacing.medium,
                          ),
                          SizedBox(height: spacing.section),

                          // Large interval visualization
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: spacing.horizontal),
                            child: WorkoutIntervalVisualization(
                              intervals: _generateZoomedIntervals(),
                              elapsedTime: elapsedTime,
                              height: spacing.intervalHeight,
                            ),
                          ),
                          SizedBox(height: spacing.section),

                          // WATT metric with current target and next target
                          WorkoutMetricRow(
                            label: const Text('WATT'),
                            current: Text(_formatValue(currentPower ?? 0)),
                            valueColor: _getMetricColor(currentPower ?? 0, powerTarget, threshold: 10),
                            target: Text(_formatValue(powerTarget)),
                            nextTarget: _getNextPower() > 0 ? Text(_formatValue(_getNextPower())) : null,
                            metricLabelFontSize: spacing.metricLabel,
                            metricValueFontSize: spacing.metricValue,
                            horizontalPadding: spacing.horizontal * 2,
                            smallSpacing: spacing.small / 2,
                            mediumSpacing: spacing.medium,
                          ),
                          SizedBox(height: spacing.medium),

                          // RPM metric with current target and next target
                          WorkoutMetricRow(
                            label: const Text('RPM'),
                            current: Text(_formatValue(currentCadence ?? 0)),
                            valueColor: _getMetricColor(currentCadence ?? 0, cadenceTarget, threshold: 5),
                            target: cadenceTarget != null ? Text(_formatValue(cadenceTarget!)) : null,
                            nextTarget: _getNextCadence() != null ? Text(_formatValue(_getNextCadence()!)) : null,
                            metricLabelFontSize: spacing.metricLabel,
                            metricValueFontSize: spacing.metricValue,
                            horizontalPadding: spacing.horizontal * 2,
                            smallSpacing: spacing.small / 2,
                            mediumSpacing: spacing.medium,
                          ),
                          SizedBox(height: spacing.large),

                          // Control buttons: Skip and Difficulty adjustment
                          WorkoutControlButtons(
                            powerScaleFactor: powerScaleFactor,
                            onPowerScaleDecrease: onPowerScaleDecrease,
                            onPowerScaleIncrease: onPowerScaleIncrease,
                            onSkip: onSkip,
                            horizontalPadding: spacing.horizontal * 2,
                            mediumSpacing: spacing.medium,
                            largeSpacing: spacing.large,
                            smallSpacing: spacing.small,
                          ),
                          SizedBox(height: spacing.medium),
                        ],
                      ),
                    ),
                  ),

                  // Fixed bottom timeline and timestamps
                  WorkoutBottomTimeline(
                    intervals: _generateIntervalsFromWorkout(),
                    elapsedTime: elapsedTime,
                    remainingTime: remainingTime,
                  ),
                  SizedBox(height: spacing.small),
                  WorkoutTimestamps(
                    elapsedTime: elapsedTime,
                    remainingTime: remainingTime,
                  ),
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

}

/// Displays a row of KPI metrics (power, cadence, heart rate, speed).
class WorkoutKpiRow extends StatelessWidget {
  const WorkoutKpiRow({
    required this.currentPower,
    required this.currentCadence,
    required this.currentHeartRate,
    required this.currentSpeed,
    required this.kpiValueFontSize,
    required this.horizontalPadding,
    required this.verticalPadding,
    required this.smallSpacing,
    required this.onTap,
    super.key,
  });

  final int? currentPower;
  final int? currentCadence;
  final int? currentHeartRate;
  final double? currentSpeed;
  final double kpiValueFontSize;
  final double horizontalPadding;
  final double verticalPadding;
  final double smallSpacing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: verticalPadding),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _KpiMetric(label: const Text('WATT'), value: Text((currentPower ?? 0).toString()), fontSize: kpiValueFontSize, spacing: smallSpacing),
            _KpiMetric(label: const Text('RPM'), value: Text((currentCadence ?? 0).toString()), fontSize: kpiValueFontSize, spacing: smallSpacing),
            _KpiMetric(label: const Text('HR'), value: Text((currentHeartRate ?? 0).toString()), fontSize: kpiValueFontSize, spacing: smallSpacing),
            _KpiMetric(label: const Text('SPEED'), value: Text(currentSpeed != null ? currentSpeed!.toStringAsFixed(1) : '0'), fontSize: kpiValueFontSize, spacing: smallSpacing),
          ],
        ),
      ),
    );
  }
}

/// Single KPI metric display with label and value.
class _KpiMetric extends StatelessWidget {
  const _KpiMetric({
    required this.label,
    required this.value,
    required this.fontSize,
    required this.spacing,
  });

  final Widget label;
  final Widget value;
  final double fontSize;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        DefaultTextStyle(
          style: GoogleFonts.publicSans(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
          child: label,
        ),
        SizedBox(height: spacing),
        DefaultTextStyle(
          style: GoogleFonts.sairaExtraCondensed(
            color: Colors.white,
            fontSize: fontSize,
            fontWeight: FontWeight.w400,
          ),
          child: value,
        ),
      ],
    );
  }
}

/// Displays a metric row with current value, target, and next target.
class WorkoutMetricRow extends StatelessWidget {
  const WorkoutMetricRow({
    required this.label,
    required this.current,
    required this.valueColor,
    required this.metricLabelFontSize,
    required this.metricValueFontSize,
    required this.horizontalPadding,
    required this.smallSpacing,
    required this.mediumSpacing,
    this.target,
    this.nextTarget,
    super.key,
  });

  final Widget label;
  final Widget current;
  final Color valueColor;
  final Widget? target;
  final Widget? nextTarget;
  final double metricLabelFontSize;
  final double metricValueFontSize;
  final double horizontalPadding;
  final double smallSpacing;
  final double mediumSpacing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      child: Column(
        children: [
          DefaultTextStyle(
            style: GoogleFonts.publicSans(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: metricLabelFontSize,
              fontWeight: FontWeight.w600,
            ),
            child: label,
          ),
          SizedBox(height: smallSpacing),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              // Current value (highlighted)
              DefaultTextStyle(
                style: GoogleFonts.sairaExtraCondensed(
                  color: valueColor,
                  fontSize: metricValueFontSize,
                  fontWeight: FontWeight.w400,
                  height: 1.0,
                ),
                child: current,
              ),
              if (target != null) ...[
                SizedBox(width: mediumSpacing),
                // Target value of current block (dim)
                DefaultTextStyle(
                  style: GoogleFonts.sairaExtraCondensed(
                    color: Colors.white.withValues(alpha: 0.3),
                    fontSize: metricValueFontSize,
                    fontWeight: FontWeight.w400,
                    height: 1.0,
                  ),
                  child: target!,
                ),
              ],
              if (nextTarget != null) ...[
                SizedBox(width: mediumSpacing),
                // Target value of next block (dim)
                DefaultTextStyle(
                  style: GoogleFonts.sairaExtraCondensed(
                    color: Colors.white.withValues(alpha: 0.3),
                    fontSize: metricValueFontSize,
                    fontWeight: FontWeight.w400,
                    height: 1.0,
                  ),
                  child: nextTarget!,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
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

/// Displays workout progress bar.
class WorkoutProgressBar extends StatelessWidget {
  const WorkoutProgressBar({
    required this.elapsedTime,
    required this.remainingTime,
    required this.horizontalPadding,
    super.key,
  });

  final int elapsedTime;
  final int remainingTime;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    final progress = remainingTime > 0 ? elapsedTime / (elapsedTime + remainingTime) : 1.0;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
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
}

/// Displays zoomed interval visualization around current position.
class WorkoutIntervalVisualization extends StatelessWidget {
  const WorkoutIntervalVisualization({
    required this.intervals,
    required this.elapsedTime,
    required this.height,
    super.key,
  });

  final List<IntervalBar> intervals;
  final int elapsedTime;
  final double height;

  @override
  Widget build(BuildContext context) {
    const windowSize = 15 * 60 * 1000; // 15 minutes in milliseconds
    final windowStart = (elapsedTime - windowSize).clamp(0, double.infinity).toInt();

    // Calculate current position relative to the zoomed window
    final currentTimeInWindow = elapsedTime - windowStart;
    // Calculate actual total duration of visible intervals (sum of all interval durations)
    final totalWindowDuration = intervals.fold<int>(0, (sum, interval) => sum + (interval.duration * 1000));

    return WorkoutIntervalBars(
      intervals: intervals,
      height: height,
      currentTimeMs: currentTimeInWindow,
      totalDurationMs: totalWindowDuration,
    );
  }
}

/// Displays bottom timeline showing full workout progress.
class WorkoutBottomTimeline extends StatelessWidget {
  const WorkoutBottomTimeline({
    required this.intervals,
    required this.elapsedTime,
    required this.remainingTime,
    super.key,
  });

  final List<IntervalBar> intervals;
  final int elapsedTime;
  final int remainingTime;

  @override
  Widget build(BuildContext context) {
    final totalDuration = elapsedTime + remainingTime;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: WorkoutIntervalBars(intervals: intervals, currentTimeMs: elapsedTime, totalDurationMs: totalDuration),
    );
  }
}

/// Displays elapsed and remaining time timestamps.
class WorkoutTimestamps extends StatelessWidget {
  const WorkoutTimestamps({
    required this.elapsedTime,
    required this.remainingTime,
    super.key,
  });

  final int elapsedTime;
  final int remainingTime;

  @override
  Widget build(BuildContext context) {
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

/// Control buttons for workout playback: difficulty adjustment and skip.
class WorkoutControlButtons extends StatelessWidget {
  const WorkoutControlButtons({
    required this.powerScaleFactor,
    required this.onPowerScaleDecrease,
    required this.onPowerScaleIncrease,
    required this.onSkip,
    required this.horizontalPadding,
    required this.mediumSpacing,
    required this.largeSpacing,
    required this.smallSpacing,
    super.key,
  });

  final double powerScaleFactor;
  final VoidCallback onPowerScaleDecrease;
  final VoidCallback onPowerScaleIncrease;
  final VoidCallback onSkip;
  final double horizontalPadding;
  final double mediumSpacing;
  final double largeSpacing;
  final double smallSpacing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: mediumSpacing,
        runSpacing: smallSpacing,
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

          // Difficulty indicator
          Container(
            padding: EdgeInsets.symmetric(horizontal: mediumSpacing, vertical: smallSpacing),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${(powerScaleFactor * 100).toStringAsFixed(0)}%',
              style: GoogleFonts.publicSans(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),

          // Difficulty increase button
          IconButton(
            onPressed: onPowerScaleIncrease,
            icon: const Icon(Icons.add, color: Colors.white, size: 24),
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.1),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),

          // Skip button
          ElevatedButton.icon(
            onPressed: onSkip,
            icon: const Icon(Icons.skip_next, size: 20),
            label: const Text('SKIP'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.15),
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(horizontal: largeSpacing, vertical: mediumSpacing),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              textStyle: GoogleFonts.publicSans(fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 1.0),
            ),
          ),
        ],
      ),
    );
  }
}
