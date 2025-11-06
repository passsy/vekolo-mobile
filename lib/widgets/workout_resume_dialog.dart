import 'package:flutter/material.dart';
import 'package:vekolo/domain/models/workout_session.dart';

/// Dialog shown when an incomplete workout session is detected.
///
/// Offers the user options to:
/// - Resume the incomplete workout from where they left off
/// - Start a new workout (discarding the previous session)
///
/// Returns true if the user wants to resume, false if they want to start fresh.
class WorkoutResumeDialog extends StatelessWidget {
  const WorkoutResumeDialog({
    required this.session,
    super.key,
  });

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
          const Text(
            'We found an incomplete workout session from earlier.',
            style: TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 16),
          _buildInfoRow(
            icon: Icons.timer,
            label: 'Elapsed time',
            value: '$minutes:${seconds.toString().padLeft(2, '0')}',
          ),
          const SizedBox(height: 8),
          _buildInfoRow(
            icon: Icons.calendar_today,
            label: 'Started',
            value: _formatTimestamp(session.startTime),
          ),
          const SizedBox(height: 16),
          const Text(
            'Would you like to resume where you left off?',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Start Fresh'),
        ),
        ElevatedButton.icon(
          onPressed: () => Navigator.of(context).pop(true),
          icon: const Icon(Icons.play_arrow),
          label: const Text('Resume'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[700],
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
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
