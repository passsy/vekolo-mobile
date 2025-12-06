import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:state_beacon/state_beacon.dart';
import 'package:vekolo/domain/models/workout/workout_models.dart';
import 'package:vekolo/pages/home_page_v2/home_page_controller.dart';
import 'package:vekolo/pages/home_page_v2/widgets/notification_card.dart';
import 'package:vekolo/pages/home_page_v2/widgets/workout_card_v2.dart';
import 'package:vekolo/pages/home_page_v2/widgets/workout_interval_bars.dart';

/// Generate interval bars from a workout plan
///
/// Flattens the workout plan by processing all blocks and repeating intervals.
/// Based on the web implementation in vekolo-web/shared/utils/workout.ts
List<IntervalBar> generateIntervalsFromPlan(WorkoutPlan plan) {
  final intervals = <IntervalBar>[];

  void processItem(Object item) {
    if (item is PowerBlock) {
      intervals.add(
        IntervalBar(
          intensity: item.power,
          duration: (item.duration / 60000).round(),
          color: _getColorForPower(item.power),
        ),
      );
    } else if (item is RampBlock) {
      final avgPower = (item.powerStart + item.powerEnd) / 2;
      intervals.add(
        IntervalBar(
          intensity: avgPower,
          intensityStart: item.powerStart,
          intensityEnd: item.powerEnd,
          duration: (item.duration / 60000).round(),
          color: _getColorForPower(avgPower),
        ),
      );
    } else if (item is WorkoutInterval) {
      // IMPORTANT: Process all repeats of the interval
      for (var i = 0; i < item.repeat; i++) {
        for (final part in item.parts) {
          processItem(part as Object);
        }
      }
    }
  }

  for (final item in plan.plan) {
    processItem(item as Object);
  }

  return intervals.isEmpty ? generateSampleIntervals() : intervals;
}

Color _getColorForPower(double power) {
  if (power < 0.5) return const Color(0xFF4CAF50);
  if (power < 0.7) return const Color(0xFF8BC34A);
  if (power < 0.85) return const Color(0xFFFFC107);
  if (power < 0.95) return const Color(0xFFFF9800);
  return const Color(0xFFE91E63);
}

/// Displays the activities feed with workout cards
class ActivitiesTab extends StatelessWidget {
  const ActivitiesTab({super.key, required this.controller, this.onFilterTap});

  final HomePageController controller;
  final VoidCallback? onFilterTap;

  @override
  Widget build(BuildContext context) {
    final isLoading = controller.isLoadingActivities.watch(context);
    final error = controller.activitiesError.watch(context);
    final activities = controller.filteredActivities.watch(context);
    final notifications = controller.notificationService.notifications.watch(context);

    return CustomScrollView(
      slivers: [
        // Pull to refresh
        CupertinoSliverRefreshControl(onRefresh: () => controller.loadActivities(isRefresh: true)),

        // Top Bar (not an AppBar, just padding with icons)
        const SliverToBoxAdapter(child: SizedBox(height: 120)),

        // Notifications
        if (notifications.isNotEmpty)
          SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              final notification = notifications[index];
              // Only allow dismissing notifications with autoDismissSeconds (not workout resume)
              final canDismiss = notification.autoDismissSeconds != null;
              return NotificationCard(
                icon: notification.icon,
                title: notification.title,
                message: notification.message,
                backgroundColor: notification.backgroundColor,
                iconColor: notification.iconColor,
                actionLabel: notification.actionLabel,
                onAction: notification.onAction,
                actions: notification.actions,
                onDismiss: canDismiss ? () => controller.notificationService.dismiss(notification.id) : null,
              );
            }, childCount: notifications.length),
          ),

        // Loading state
        if (isLoading)
          const SliverFillRemaining(
            child: Center(child: CircularProgressIndicator(color: Color(0xFFFF6F00))),
          ),

        // Error state
        if (!isLoading && error != null)
          SliverFillRemaining(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, color: Colors.white54, size: 64),
                  const SizedBox(height: 16),
                  Text(
                    error,
                    style: const TextStyle(color: Colors.white70, fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () => controller.loadActivities(),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF6F00),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),

        // Empty state
        if (!isLoading && error == null && activities.isEmpty)
          const SliverFillRemaining(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.fitness_center, color: Colors.white24, size: 64),
                  SizedBox(height: 16),
                  Text('No activities found', style: TextStyle(color: Colors.white54, fontSize: 18)),
                  SizedBox(height: 8),
                  Text('Try adjusting your filters', style: TextStyle(color: Colors.white38, fontSize: 14)),
                ],
              ),
            ),
          ),

        // Activities List
        if (!isLoading && error == null && activities.isNotEmpty)
          SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              final activity = activities[index];
              return WorkoutCardV2(
                key: ValueKey(activity.id),
                authorName: activity.user.name,
                authorAvatarUrl: activity.user.avatar,
                date: _formatDate(DateTime.parse(activity.createdAt)),
                title: activity.workout.title,
                duration: _formatDuration(activity.duration),
                intervals: generateIntervalsFromPlan(activity.workout.plan),
                backgroundColor: _getBackgroundColorForCategory(activity.workout.category?.value),
                isLocal: activity.id.startsWith('local-'),
                onTap: () async {
                  final result = await context.push('/activity/${activity.id}', extra: activity);
                  // Refresh activities if a workout was deleted
                  if (result == true) {
                    controller.loadActivities();
                  }
                },
              );
            }, childCount: activities.length),
          ),

        // Bottom padding for tab bar
        const SliverPadding(padding: EdgeInsets.only(bottom: 80)),
      ],
    );
  }

  String _formatDate(DateTime date) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[date.month - 1]} ${date.day.toString().padLeft(2, '0')}, ${date.year}';
  }

  String _formatDuration(int milliseconds) {
    final seconds = milliseconds ~/ 1000;
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    } else {
      return '${minutes}:${secs.toString().padLeft(2, '0')}';
    }
  }

  Color _getBackgroundColorForCategory(String? category) {
    if (category == null) return const Color(0xFF5D4A3A);

    switch (category.toLowerCase()) {
      case 'recovery':
      case 'endurance':
        return const Color(0xFF4A5D3A); // Greenish brown
      case 'tempo':
        return const Color(0xFF5D4A3A); // Brown
      case 'threshold':
        return const Color(0xFF5D3A3A); // Reddish brown
      case 'vo2max':
      case 'ftp':
        return const Color(0xFF5C2E3E); // Dark red/burgundy
      default:
        return const Color(0xFF5D4A3A); // Brown
    }
  }
}
