import 'package:flutter/material.dart';
import 'package:vekolo/domain/models/workout_session.dart';

/// User choice from the workout resume dialog.
enum ResumeChoice {
  /// Resume the workout from where it was interrupted.
  resume,

  /// Discard the workout data but keep it marked as incomplete.
  discard,

  /// Delete the workout data entirely and start fresh.
  startFresh,
}

/// Dialog shown when an incomplete workout session is detected.
///
/// Offers the user three options:
/// - Resume: Continue the workout from where it was interrupted
/// - Discard: Mark the workout as abandoned but keep the data
/// - Start Fresh: Delete the workout data entirely and start over
///
/// Returns [ResumeChoice] or null if dismissed.
class WorkoutResumeDialog extends StatelessWidget {
  const WorkoutResumeDialog({required this.session, super.key});

  final WorkoutSession session;

  @override
  Widget build(BuildContext context) {
    final duration = Duration(milliseconds: session.elapsedMs);
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.restore, color: Colors.blue),
          SizedBox(width: 12),
          Text('Resume Workout?'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('We found an incomplete workout session from earlier.', style: TextStyle(fontSize: 16)),
          const SizedBox(height: 16),
          WorkoutInfoRow(
            icon: Icons.timer,
            label: const Text('Elapsed time'),
            value: Text('$minutes:${seconds.toString().padLeft(2, '0')}'),
          ),
          const SizedBox(height: 8),
          WorkoutInfoRow(icon: Icons.calendar_today, label: const Text('Started'), value: Text(_formatTimestamp(session.startTime))),
          const SizedBox(height: 16),
          const Text(
            'Would you like to resume where you left off?',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(ResumeChoice.startFresh),
          child: const Text('Start Fresh'),
        ),
        TextButton(onPressed: () => Navigator.of(context).pop(ResumeChoice.discard), child: const Text('Discard')),
        ElevatedButton.icon(
          onPressed: () => Navigator.of(context).pop(ResumeChoice.resume),
          icon: const Icon(Icons.play_arrow),
          label: const Text('Resume'),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
        ),
      ],
    );
  }


  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }
}

/// Displays a single row of information with an icon, label, and value.
///
/// Used in dialogs to show metadata like elapsed time or timestamps in a
/// consistent format with an icon prefix.
class WorkoutInfoRow extends StatelessWidget {
  const WorkoutInfoRow({
    required this.icon,
    required this.label,
    required this.value,
    super.key,
  });

  /// Icon to display at the start of the row.
  final IconData icon;

  /// Label widget describing what the value represents.
  final Widget label;

  /// The actual value widget to display.
  final Widget value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey[600]),
        const SizedBox(width: 8),
        DefaultTextStyle(
          style: TextStyle(fontSize: 14, color: Colors.grey[700]),
          child: label,
        ),
        const Text(': '),
        DefaultTextStyle(
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          child: value,
        ),
      ],
    );
  }
}
