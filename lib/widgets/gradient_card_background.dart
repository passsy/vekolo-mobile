import 'package:flutter/material.dart';

/// A background widget with a solid color and a black gradient overlay.
///
/// The gradient goes from semi-transparent black at the top to opaque black
/// at the bottom, creating a darkening effect.
///
/// Usage:
/// ```dart
/// Stack(
///   children: [
///     GradientCardBackground(
///       color: Colors.blue,
///       gradientStart: 0.6, // 60% opacity at top
///       gradientEnd: 1.0,   // 100% opacity at bottom
///     ),
///     // Your content here
///   ],
/// )
/// ```
class GradientCardBackground extends StatelessWidget {
  const GradientCardBackground({
    super.key,
    required this.color,
    this.gradientStart = 0.6,
    this.gradientEnd = 1.0,
  });

  final Color color;

  /// Opacity of the black gradient at the top (0.0 to 1.0)
  final double gradientStart;

  /// Opacity of the black gradient at the bottom (0.0 to 1.0)
  final double gradientEnd;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: gradientStart),
            Colors.black.withValues(alpha: gradientEnd),
          ],
        ),
      ),
    );
  }
}
