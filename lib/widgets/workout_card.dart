import 'package:flutter/material.dart';

/// Displays a workout card with name, duration, blocks, and a Start button.
///
/// This widget makes it easy to find and interact with workouts in tests.
class WorkoutCard extends StatelessWidget {
  const WorkoutCard({
    super.key,
    required this.name,
    required this.duration,
    required this.blocks,
    required this.onStart,
  });

  final String name;
  final int duration;
  final List<WorkoutBlockInfo> blocks;
  final VoidCallback onStart;

  String _formatDuration(int milliseconds) {
    final minutes = milliseconds ~/ 60000;
    return '$minutes min';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.fitness_center, size: 32, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                      Text(
                        _formatDuration(duration),
                        style: Theme.of(
                          context,
                        ).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.secondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),
            // Workout blocks
            ...blocks.expand(
              (block) => [
                WorkoutBlockItem(icon: block.icon, title: block.title, subtitle: block.subtitle, color: block.color),
                const SizedBox(height: 12),
              ],
            ),
            const SizedBox(height: 12),
            // Start button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onStart,
                icon: const Icon(Icons.play_circle_filled, size: 28),
                label: const Text('Start', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Displays a single workout block with an icon, title, and subtitle.
///
/// Used within [WorkoutCard] to show individual workout segments like
/// warm-up, intervals, or cool-down periods.
class WorkoutBlockItem extends StatelessWidget {
  const WorkoutBlockItem({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
  });

  final IconData icon;
  final Widget title;
  final Widget subtitle;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DefaultTextStyle(
                style:
                    Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold) ??
                    const TextStyle(fontWeight: FontWeight.bold),
                child: title,
              ),
              DefaultTextStyle(
                style:
                    Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600]) ??
                    TextStyle(color: Colors.grey[600]),
                child: subtitle,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Information about a workout block for display in WorkoutCard.
class WorkoutBlockInfo {
  const WorkoutBlockInfo({required this.icon, required this.title, required this.subtitle, required this.color});

  final IconData icon;
  final Widget title;
  final Widget subtitle;
  final Color color;
}
