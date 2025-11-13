import 'package:flutter/material.dart';

/// Placeholder for the workout creation tab (coming soon)
class CreateTab extends StatelessWidget {
  const CreateTab({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        // Top padding
        const SliverToBoxAdapter(child: SizedBox(height: 60)),

        // Coming soon placeholder
        SliverFillRemaining(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.construction, size: 80, color: Colors.white.withValues(alpha: 0.3)),
                const SizedBox(height: 24),
                Text(
                  'Coming Soon',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'The workout builder is currently in development.\nStay tuned for updates!',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 14),
                ),
                const SizedBox(height: 32),
                Container(
                  padding: const EdgeInsets.all(24),
                  margin: const EdgeInsets.symmetric(horizontal: 32),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.lightbulb_outline, color: Color(0xFFFF6F00), size: 32),
                      const SizedBox(height: 12),
                      Text(
                        'Planned Features',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _FeatureItem(text: 'Visual workout builder'),
                      _FeatureItem(text: 'Custom intervals and power zones'),
                      _FeatureItem(text: 'Workout templates'),
                      _FeatureItem(text: 'Preview and testing mode'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _FeatureItem extends StatelessWidget {
  const _FeatureItem({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_outline, size: 16, color: Colors.white.withValues(alpha: 0.5)),
          const SizedBox(width: 8),
          Text(text, style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 14)),
        ],
      ),
    );
  }
}
