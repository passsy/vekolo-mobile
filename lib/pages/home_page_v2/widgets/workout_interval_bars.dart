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
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      const Radius.circular(2),
    );
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
