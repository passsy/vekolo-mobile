import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Duration of the splash screen animation
const splashScreenAnimationDuration = Duration(milliseconds: 1500);

/// Shown during app initialization while checking auth state.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fillAnimation;
  late Animation<double> _waveAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(duration: splashScreenAnimationDuration, vsync: this);

    // Fill animation: goes from 0.0 to 1.0
    _fillAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    // Wave animation: continuous wave motion
    _waveAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.linear));

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A), // offBlack
      body: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return SizedBox(
              width: 120 * 2,
              height: 168 * 2,
              child: CustomPaint(
                painter: _LogoWaveFillPainter(fillValue: _fillAnimation.value, waveValue: _waveAnimation.value),
                child: Stack(
                  children: [
                    // Base outline logo
                    SvgPicture.asset('assets/images/logo-outline.svg', width: 120 * 2, height: 168 * 2),
                    // Clipped filled logo on top
                    ClipPath(
                      clipper: _WaveClipper(fillValue: _fillAnimation.value, waveValue: _waveAnimation.value),
                      child: SvgPicture.asset('assets/images/logo-filled.svg', width: 120 * 2, height: 168 * 2),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Custom clipper that creates a wave effect filling from bottom to top
class _WaveClipper extends CustomClipper<Path> {
  final double fillValue; // 0.0 to 1.0 (bottom to top)
  final double waveValue; // 0.0 to 1.0 (wave phase)

  _WaveClipper({required this.fillValue, required this.waveValue});

  @override
  Path getClip(Size size) {
    final path = Path();

    // Calculate the baseline of the wave (from bottom going up)
    final waveBaseline = size.height * (1.0 - fillValue);

    // Wave parameters
    const waveAmplitude = 5.0;
    const waveFrequency = 3.0;

    // Start from bottom-left
    path.moveTo(0, size.height);
    path.lineTo(0, waveBaseline);

    // Draw the wave across the width
    for (double x = 0; x <= size.width; x += 1.0) {
      final y =
          waveBaseline +
          math.sin((x / size.width * 2 * math.pi * waveFrequency) + 2 * math.pi * waveValue) * waveAmplitude;
      path.lineTo(x, y);
    }

    // Complete the path to fill the bottom
    path.lineTo(size.width, size.height);
    path.close();

    return path;
  }

  @override
  bool shouldReclip(_WaveClipper oldClipper) {
    return oldClipper.fillValue != fillValue || oldClipper.waveValue != waveValue;
  }
}

/// Optional painter for debugging the wave path (not used in final implementation)
class _LogoWaveFillPainter extends CustomPainter {
  final double fillValue;
  final double waveValue;

  _LogoWaveFillPainter({required this.fillValue, required this.waveValue});

  @override
  void paint(Canvas canvas, Size size) {
    // This painter is currently not drawing anything.
    // The wave effect is handled by the ClipPath with _WaveClipper.
    // This is kept as a placeholder if you want to add additional visual effects.
  }

  @override
  bool shouldRepaint(_LogoWaveFillPainter oldDelegate) {
    return oldDelegate.fillValue != fillValue || oldDelegate.waveValue != waveValue;
  }
}
