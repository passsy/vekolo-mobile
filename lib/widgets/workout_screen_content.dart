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
    return Stack(
      children: [
        // Background gradient
        const Positioned.fill(
          child: GradientCardBackground(color: Color(0xFF1B4332), gradientStart: 0.0, gradientEnd: 0.8),
        ),
        // Content
        SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 24),
              // KPI row at top
              _buildKPIRow(),
              const SizedBox(height: 32),

              // Progress bar
              _buildProgressBar(),
              const SizedBox(height: 48),

              // TIME metric - only show remaining time in current interval
              _buildSimpleMetricRow('TIME', currentBlockRemainingTime, Colors.white),
              const SizedBox(height: 32),

              // Large interval visualization
              Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: _buildIntervalVisualization()),
              const SizedBox(height: 32),

              // WATT metric with current target and next target
              _buildSimpleMetricRow(
                'WATT',
                currentPower ?? 0,
                _getMetricColor(currentPower ?? 0, powerTarget, threshold: 10),
                target: powerTarget,
                nextTarget: _getNextPower(),
              ),
              const SizedBox(height: 24),

              // RPM metric with current target and next target
              _buildSimpleMetricRow(
                'RPM',
                currentCadence ?? 0,
                _getMetricColor(currentCadence ?? 0, cadenceTarget, threshold: 5),
                target: cadenceTarget,
                nextTarget: _getNextCadence(),
              ),
              const SizedBox(height: 40),

              // Control buttons: Skip and Difficulty adjustment
              _buildControlButtons(),

              const Spacer(),

              // Bottom timeline and timestamps
              _buildBottomTimeline(),
              const SizedBox(height: 8),
              _buildTimestamps(),
              const SizedBox(height: 16),
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

  Widget _buildKPIRow() {
    return InkWell(
      onTap: onDevicesPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildKPI('WATT', (currentPower ?? 0).toString()),
            _buildKPI('RPM', (currentCadence ?? 0).toString()),
            _buildKPI('HR', (currentHeartRate ?? 0).toString()),
            _buildKPI('SPEED', currentSpeed != null ? currentSpeed!.toStringAsFixed(1) : '0'),
          ],
        ),
      ),
    );
  }

  Widget _buildKPI(String label, String value) {
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
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.sairaExtraCondensed(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w400),
        ),
      ],
    );
  }

  Widget _buildProgressBar() {
    final progress = remainingTime > 0 ? elapsedTime / (elapsedTime + remainingTime) : 1.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48),
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

  Widget _buildControlButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
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
          const SizedBox(width: 16),

          // Difficulty indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${(powerScaleFactor * 100).toStringAsFixed(0)}%',
              style: GoogleFonts.publicSans(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 16),

          // Difficulty increase button
          IconButton(
            onPressed: onPowerScaleIncrease,
            icon: const Icon(Icons.add, color: Colors.white, size: 24),
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.1),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(width: 32),

          // Skip button
          ElevatedButton.icon(
            onPressed: onSkip,
            icon: const Icon(Icons.skip_next, size: 20),
            label: const Text('SKIP'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.15),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              textStyle: GoogleFonts.publicSans(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
              ),
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
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            label,
            style: GoogleFonts.publicSans(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
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
                  fontSize: 64,
                  fontWeight: FontWeight.w400,
                  height: 1.0,
                ),
              ),
              if (target != null) ...[
                const SizedBox(width: 16),
                // Target value of current block (dim)
                Text(
                  _formatValue(target),
                  style: GoogleFonts.sairaExtraCondensed(
                    color: Colors.white.withValues(alpha: 0.3),
                    fontSize: 64,
                    fontWeight: FontWeight.w400,
                    height: 1.0,
                  ),
                ),
              ],
              if (nextTarget != null) ...[
                const SizedBox(width: 16),
                // Target value of next block (dim)
                Text(
                  _formatValue(nextTarget),
                  style: GoogleFonts.sairaExtraCondensed(
                    color: Colors.white.withValues(alpha: 0.3),
                    fontSize: 64,
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

  Widget _buildIntervalVisualization() {
    final intervals = _generateZoomedIntervals();
    const windowSize = 15 * 60 * 1000; // 15 minutes in milliseconds
    final windowStart = (elapsedTime - windowSize).clamp(0, double.infinity).toInt();

    // Calculate current position relative to the zoomed window
    final currentTimeInWindow = elapsedTime - windowStart;
    final totalWindowDuration = windowSize * 2; // ±15 minutes = 30 minute window

    return WorkoutIntervalBars(
      intervals: intervals,
      height: 150,
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

            final adjustedIntensityStart = interval.intensityStart! +
              (interval.intensityEnd! - interval.intensityStart!) * startFraction;
            final adjustedIntensityEnd = interval.intensityStart! +
              (interval.intensityEnd! - interval.intensityStart!) * endFraction;

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
              IntervalBar(
                intensity: interval.intensity,
                duration: visibleDuration,
                color: interval.color,
              ),
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
      child: WorkoutIntervalBars(
        intervals: intervals,
        height: 40,
        currentTimeMs: elapsedTime,
        totalDurationMs: totalDuration,
      ),
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
