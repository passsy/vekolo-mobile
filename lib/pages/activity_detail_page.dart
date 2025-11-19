import 'package:context_plus/context_plus.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:vekolo/app/refs.dart';
import 'package:vekolo/domain/models/workout/workout_models.dart';
import 'package:vekolo/models/activity.dart';

/// Simple activity detail page showing workout information with a "Ride Now" button
class ActivityDetailPage extends StatelessWidget {
  const ActivityDetailPage({super.key, required this.activity});

  final Activity activity;

  bool get _isLocalWorkout => activity.id.startsWith('local-');

  String get _localWorkoutId {
    // Remove 'local-' prefix to get the actual workout ID
    return activity.id.substring('local-'.length);
  }

  @override
  Widget build(BuildContext context) {
    final workout = activity.workout;
    final plan = workout.plan;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Workout Details'),
        actions: [
          if (_isLocalWorkout)
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () => _showDeleteConfirmation(context),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Title
            Text(
              workout.title,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),

            // Summary
            if (workout.summary != null) ...[
              Text(workout.summary!, style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.grey[700])),
              const SizedBox(height: 24),
            ],

            // Stats
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    WorkoutStatColumn(
                      icon: Icons.timer,
                      label: const Text('Duration'),
                      value: Text(_formatDuration(workout.duration)),
                    ),
                    if (workout.tss != null)
                      WorkoutStatColumn(
                        icon: Icons.fitness_center,
                        label: const Text('TSS'),
                        value: Text(workout.tss.toString()),
                      ),
                    if (workout.category != null)
                      WorkoutStatColumn(
                        icon: Icons.category,
                        label: const Text('Category'),
                        value: Text(_formatCategory(workout.category!)),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Workout blocks preview
            Text(
              'Workout Structure',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...plan.plan.map((block) => _buildBlockPreview(block, _formatDuration)),
            const SizedBox(height: 32),

            // Ride Now button
            ElevatedButton.icon(
              onPressed: () {
                context.push('/workout-player', extra: {'workoutId': workout.id});
              },
              icon: const Icon(Icons.play_circle_filled, size: 32),
              label: const Text('Ride Now', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 20),
                minimumSize: const Size(double.infinity, 64),
              ),
            ),
          ],
        ),
      ),
    );
  }



  String _formatDuration(int milliseconds) {
    final totalSeconds = milliseconds ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;

    if (seconds == 0) {
      return '${minutes}min';
    }
    return '${minutes}:${seconds.toString().padLeft(2, '0')}min';
  }

  String _formatCategory(WorkoutCategory category) {
    switch (category.value) {
      case 'recovery':
        return 'Recovery';
      case 'endurance':
        return 'Endurance';
      case 'tempo':
        return 'Tempo';
      case 'threshold':
        return 'Threshold';
      case 'vo2max':
        return 'VO2max';
      case 'ftp':
        return 'FTP Test';
      default:
        return category.value;
    }
  }

  Widget _buildBlockPreview(dynamic block, String Function(int) formatDuration) {
    if (block is PowerBlock) {
      return PowerBlockPreview(block: block, formatDuration: formatDuration);
    } else if (block is RampBlock) {
      return RampBlockPreview(block: block, formatDuration: formatDuration);
    } else if (block is WorkoutInterval) {
      return IntervalBlockPreview(block: block, formatDuration: formatDuration);
    }
    return const SizedBox.shrink();
  }

  Future<void> _showDeleteConfirmation(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Workout?'),
        content: const Text('Are you sure you want to delete this workout? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      await _deleteWorkout(context);
    }
  }

  Future<void> _deleteWorkout(BuildContext context) async {
    try {
      final persistence = Refs.workoutSessionPersistence.of(context);
      await persistence.deleteSession(_localWorkoutId);

      if (context.mounted) {
        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Workout deleted successfully')),
        );

        // Navigate back and trigger a refresh by returning true
        context.pop(true);
      }
    } catch (e, stackTrace) {
      print('[ActivityDetailPage._deleteWorkout] Error deleting workout: $e');
      print(stackTrace);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete workout: $e')),
        );
      }
    }
  }
}

/// Displays a single workout statistic with an icon, label, and value.
///
/// Used to show workout metrics like duration, TSS, and category in a
/// consistent vertical layout.
class WorkoutStatColumn extends StatelessWidget {
  const WorkoutStatColumn({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final Widget label;
  final Widget value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 4),
        DefaultTextStyle(
          style: const TextStyle(fontSize: 12, color: Colors.grey),
          child: label,
        ),
        const SizedBox(height: 4),
        DefaultTextStyle(
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          child: value,
        ),
      ],
    );
  }
}

/// Displays a preview of a power block showing constant power target.
class PowerBlockPreview extends StatelessWidget {
  const PowerBlockPreview({
    super.key,
    required this.block,
    required this.formatDuration,
  });

  final PowerBlock block;
  final String Function(int milliseconds) formatDuration;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.bolt, color: Colors.orange, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    block.description ?? 'Power Block',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${formatDuration(block.duration)} at ${(block.power * 100).toStringAsFixed(0)}% FTP',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Displays a preview of a ramp block showing power transition from start to end.
class RampBlockPreview extends StatelessWidget {
  const RampBlockPreview({
    super.key,
    required this.block,
    required this.formatDuration,
  });

  final RampBlock block;
  final String Function(int milliseconds) formatDuration;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.trending_up, color: Colors.blue, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    block.description ?? 'Ramp Block',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${formatDuration(block.duration)} from ${(block.powerStart * 100).toStringAsFixed(0)}% to ${(block.powerEnd * 100).toStringAsFixed(0)}% FTP',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Displays a preview of an interval block showing repeated interval structure with nested parts.
class IntervalBlockPreview extends StatelessWidget {
  const IntervalBlockPreview({
    super.key,
    required this.block,
    required this.formatDuration,
  });

  final WorkoutInterval block;
  final String Function(int milliseconds) formatDuration;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.repeat, color: Colors.purple, size: 20),
                const SizedBox(width: 12),
                Text(
                  'Interval Set (${block.repeat}x)',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...block.parts.map((part) {
              if (part is PowerBlock) {
                return Padding(
                  padding: const EdgeInsets.only(left: 32, top: 4),
                  child: Text(
                    '${part.description ?? 'Block'}: ${formatDuration(part.duration)} at ${(part.power * 100).toStringAsFixed(0)}% FTP',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                );
              }
              return const SizedBox.shrink();
            }),
          ],
        ),
      ),
    );
  }
}
