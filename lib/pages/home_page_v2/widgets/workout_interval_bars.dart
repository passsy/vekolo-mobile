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

    final progress = (currentTimeMs != null && totalDurationMs != null && totalDurationMs! > 0)
        ? (currentTimeMs! / totalDurationMs!).clamp(0.0, 1.0)
        : 0.0;

    // Build the interval bars widget (will be used for both colored and greyscale)
    final intervalsWidget = _IntervalBarsRow(
      intervals: intervals,
      height: height,
    );

    return Stack(
      children: [
        // Bottom layer: Greyscale version (past)
        if (currentTimeMs != null && totalDurationMs != null)
          ClipRect(
            clipper: _LeftClipper(progress),
            child: ColorFiltered(
              colorFilter: _greyscaleFilter,
              child: intervalsWidget,
            ),
          ),
        // Top layer: Colored version (future)
        if (currentTimeMs != null && totalDurationMs != null)
          ClipRect(
            clipper: _RightClipper(progress),
            child: intervalsWidget,
          )
        else
          intervalsWidget,
        // Progress indicator line
        if (currentTimeMs != null && totalDurationMs != null && totalDurationMs! > 0)
          Positioned.fill(
            child: CustomPaint(
              painter: _ProgressIndicatorPainter(
                progress: progress,
                height: height,
              ),
            ),
          ),
      ],
    );
  }

  /// Greyscale color filter using luminance-preserving matrix
  static const _greyscaleFilter = ColorFilter.matrix([
    0.2126, 0.7152, 0.0722, 0, 0, // Red channel
    0.2126, 0.7152, 0.0722, 0, 0, // Green channel
    0.2126, 0.7152, 0.0722, 0, 0, // Blue channel
    0, 0, 0, 1, 0, // Alpha channel
  ]);
}

/// Renders a row of interval bars with varying heights and colors
///
/// Each interval is displayed as a vertical bar with height proportional to
/// its intensity. Intervals can be either flat (constant intensity) or ramps
/// (changing intensity from start to end).
///
/// The width of each bar is proportional to its duration relative to other bars.
class _IntervalBarsRow extends StatelessWidget {
  const _IntervalBarsRow({
    required this.intervals,
    required this.height,
  });

  final List<IntervalBar> intervals;
  final double height;

  @override
  Widget build(BuildContext context) {
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
                child: interval.isRamp
                    ? CustomPaint(
                        size: Size.infinite,
                        painter: _RampBarPainter(
                          startIntensity: interval.intensityStart!,
                          endIntensity: interval.intensityEnd!,
                          color: interval.color,
                          maxHeight: height,
                        ),
                      )
                    : Container(
                        height: height * interval.intensity,
                        decoration: BoxDecoration(
                          color: interval.color,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
              ),
            ),
        ],
      ),
    );
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

/// Clips the left portion (past) of the widget based on progress
class _LeftClipper extends CustomClipper<Rect> {
  const _LeftClipper(this.progress);

  final double progress;

  @override
  Rect getClip(Size size) {
    // Clip from left edge to progress position
    return Rect.fromLTRB(0, 0, size.width * progress.clamp(0.0, 1.0), size.height);
  }

  @override
  bool shouldReclip(_LeftClipper oldClipper) => progress != oldClipper.progress;
}

/// Clips the right portion (future) of the widget based on progress
class _RightClipper extends CustomClipper<Rect> {
  const _RightClipper(this.progress);

  final double progress;

  @override
  Rect getClip(Size size) {
    // Clip from progress position to right edge
    return Rect.fromLTRB(size.width * progress.clamp(0.0, 1.0), 0, size.width, size.height);
  }

  @override
  bool shouldReclip(_RightClipper oldClipper) => progress != oldClipper.progress;
}
