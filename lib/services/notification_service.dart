import 'package:flutter/material.dart';
import 'package:state_beacon/state_beacon.dart';

/// Types of notifications that can be shown
enum NotificationType { workoutResumeAvailable, info, warning, error }

/// Action button for a notification
class NotificationAction {
  const NotificationAction({required this.label, required this.onTap, this.isPrimary = false});

  final String label;
  final VoidCallback onTap;
  final bool isPrimary;
}

/// A notification to be displayed in the UI
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.icon,
    required this.title,
    required this.message,
    required this.backgroundColor,
    this.iconColor,
    this.actionLabel,
    this.onAction,
    this.actions = const [],
    this.autoDismissSeconds,
  });

  final String id;
  final NotificationType type;
  final IconData icon;
  final String title;
  final String message;
  final Color backgroundColor;
  final Color? iconColor;
  final String? actionLabel;
  final VoidCallback? onAction;
  final List<NotificationAction> actions;
  final int? autoDismissSeconds;

  /// Creates a workout resume notification
  factory AppNotification.workoutResume({
    required String workoutTitle,
    required String elapsedTime,
    required VoidCallback onResume,
    required VoidCallback onDiscard,
    required VoidCallback onStartFresh,
  }) {
    return AppNotification(
      id: 'workout_resume_${DateTime.now().millisecondsSinceEpoch}',
      type: NotificationType.workoutResumeAvailable,
      icon: Icons.restore,
      title: 'Resume $workoutTitle?',
      message: 'We found an incomplete workout session from earlier.\n\nElapsed: $elapsedTime',
      backgroundColor: const Color(0xFF1565C0), // Blue
      iconColor: Colors.white,
      actions: [
        NotificationAction(label: 'Resume', onTap: onResume, isPrimary: true),
        NotificationAction(label: 'Discard', onTap: onDiscard),
        NotificationAction(label: 'Start Fresh', onTap: onStartFresh),
      ],
    );
  }
}

/// Service for managing in-app notifications
class NotificationService {
  NotificationService();

  /// List of active notifications
  final _notifications = Beacon.writable<List<AppNotification>>([]);
  ReadableBeacon<List<AppNotification>> get notifications => _notifications;

  /// Shows a notification
  void show(AppNotification notification) {
    _notifications.value = [..._notifications.value, notification];

    // Auto-dismiss if specified
    if (notification.autoDismissSeconds != null) {
      Future.delayed(Duration(seconds: notification.autoDismissSeconds!), () {
        dismiss(notification.id);
      });
    }
  }

  /// Dismisses a notification by ID
  void dismiss(String notificationId) {
    _notifications.value = _notifications.value.where((n) => n.id != notificationId).toList();
  }

  /// Clears all notifications
  void clearAll() {
    _notifications.value = [];
  }

  /// Disposes resources
  void dispose() {
    _notifications.dispose();
  }
}
