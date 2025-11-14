import 'package:flutter/material.dart';

/// Displays colorful vertical bars representing workout intervals
///
/// Each bar represents a segment of the workout with varying height
/// based on intensity and colors based on power zones.
///
/// Shows progress by desaturating completed intervals to grey and
/// displaying a progress indicator line.
class WorkoutIntervalBars extends StatelessWidget {
  const WorkoutIntervalBars({
    super.key,
    required this.intervals,
    this.height = 40,
    this.currentTimeMs,
    this.totalDurationMs,
  });

  final List<IntervalBar> intervals;
  final double height;

  /// Current elapsed time in milliseconds (for progress indication)
  final int? currentTimeMs;

  /// Total duration of all intervals in milliseconds (for progress calculation)
  final int? totalDurationMs;

  @override
  Widget build(BuildContext context) {
    if (intervals.isEmpty) {
      return SizedBox(height: height);
    }

    // Calculate cumulative durations to determine past/future
    final cumulativeDurations = <int>[];
    var cumulative = 0;
    for (final interval in intervals) {
      cumulative += interval.duration * 1000; // Convert to ms
      cumulativeDurations.add(cumulative);
    }

    final currentTime = currentTimeMs ?? 0;

    return Stack(
      children: [
        SizedBox(
          height: height,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < intervals.length; i++)
                Builder(
                  builder: (context) {
                    final interval = intervals[i];
                    final intervalStart = i == 0 ? 0 : cumulativeDurations[i - 1];
                    final intervalEnd = cumulativeDurations[i];

                    // Determine if this interval is in the past, current, or future
                    final isPast = currentTime >= intervalEnd;
                    final isCurrent = currentTime >= intervalStart && currentTime < intervalEnd;

                    // Desaturate color if in the past
                    final displayColor = isPast || (isCurrent && currentTimeMs != null)
                        ? _desaturateColor(interval.color, currentTime, intervalStart, intervalEnd, isCurrent)
                        : interval.color;

                    return Expanded(
                      flex: interval.duration,
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 0.5),
                        child: interval.isRamp
                            ? CustomPaint(
                                size: Size.infinite,
                                painter: _RampBarPainter(
                                  startIntensity: interval.intensityStart!,
                                  endIntensity: interval.intensityEnd!,
                                  color: displayColor,
                                  maxHeight: height,
                                ),
                              )
                            : Container(
                                height: height * interval.intensity,
                                decoration: BoxDecoration(
                                  color: displayColor,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
        // Progress indicator line
        if (currentTimeMs != null && totalDurationMs != null && totalDurationMs! > 0)
          Positioned.fill(
            child: CustomPaint(
              painter: _ProgressIndicatorPainter(
                progress: currentTimeMs! / totalDurationMs!,
                height: height,
              ),
            ),
          ),
      ],
    );
  }

  /// Desaturate color for past intervals
  Color _desaturateColor(Color color, int currentTime, int intervalStart, int intervalEnd, bool isCurrent) {
    if (isCurrent) {
      // For current interval, partially desaturate based on progress through interval
      final intervalProgress = (currentTime - intervalStart) / (intervalEnd - intervalStart);
      final desaturated = Colors.grey.shade600;

      // Blend from desaturated at start to colored at end
      return Color.lerp(desaturated, color, 1 - intervalProgress.clamp(0.0, 1.0)) ?? color;
    } else {
      // Fully desaturate past intervals
      return Colors.grey.shade600;
    }
  }
}

class IntervalBar {
  const IntervalBar({
    required this.intensity,
    required this.duration,
    required this.color,
    this.intensityStart,
    this.intensityEnd,
  });

  /// Intensity from 0.0 to 1.0 (determines bar height)
  /// For flat power blocks, this is the constant intensity.
  /// For ramps, this is ignored if intensityStart/End are provided.
  final double intensity;

  /// Starting intensity for ramp blocks (0.0 to 1.0)
  /// If provided with intensityEnd, creates a sloped bar
  final double? intensityStart;

  /// Ending intensity for ramp blocks (0.0 to 1.0)
  /// If provided with intensityStart, creates a sloped bar
  final double? intensityEnd;

  /// Relative duration (flex value for spacing)
  final int duration;

  /// Color of the interval bar
  final Color color;

  /// Whether this is a ramp (has different start/end intensities)
  bool get isRamp => intensityStart != null && intensityEnd != null;
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

/// Custom painter for ramp bars that show intensity changes
class _RampBarPainter extends CustomPainter {
  const _RampBarPainter({
    required this.startIntensity,
    required this.endIntensity,
    required this.color,
    required this.maxHeight,
  });

  final double startIntensity;
  final double endIntensity;
  final Color color;
  final double maxHeight;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final startHeight = maxHeight * startIntensity;
    final endHeight = maxHeight * endIntensity;

    final path = Path()
      ..moveTo(0, size.height) // Bottom left
      ..lineTo(0, size.height - startHeight) // Top left (start intensity)
      ..lineTo(size.width, size.height - endHeight) // Top right (end intensity)
      ..lineTo(size.width, size.height) // Bottom right
      ..close();

    canvas.drawPath(path, paint);

    // Draw rounded corners using a rounded rect clip
    final rrect = RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, size.width, size.height), const Radius.circular(2));
    canvas.clipRRect(rrect);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_RampBarPainter oldDelegate) =>
      startIntensity != oldDelegate.startIntensity ||
      endIntensity != oldDelegate.endIntensity ||
      color != oldDelegate.color ||
      maxHeight != oldDelegate.maxHeight;
}

/// Custom painter for the progress indicator line
class _ProgressIndicatorPainter extends CustomPainter {
  const _ProgressIndicatorPainter({
    required this.progress,
    required this.height,
  });

  final double progress;
  final double height;

  @override
  void paint(Canvas canvas, Size size) {
    final xPosition = size.width * progress.clamp(0.0, 1.0);

    // Draw a vertical line at the current position
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    canvas.drawLine(
      Offset(xPosition, 0),
      Offset(xPosition, size.height),
      paint,
    );

    // Draw a small circle at the top for better visibility
    final circlePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    canvas.drawCircle(
      Offset(xPosition, 0),
      3,
      circlePaint,
    );
  }

  @override
  bool shouldRepaint(_ProgressIndicatorPainter oldDelegate) => progress != oldDelegate.progress;
}
