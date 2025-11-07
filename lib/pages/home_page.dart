import 'package:context_plus/context_plus.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:state_beacon/state_beacon.dart';
import 'package:vekolo/app/refs.dart';
import 'package:vekolo/widgets/user_avatar.dart';
import 'package:vekolo/domain/models/workout/workout_models.dart';

/// Entry point after app startup.
///
/// Shows login/signup buttons for unauthenticated users and a sample workout
/// that can be started in the player.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  /// Sample workout for demonstration.
  static WorkoutPlan _getSampleWorkout() {
    return WorkoutPlan(
      plan: [
        // Warm-up: 5 minutes at 60% FTP
        PowerBlock(
          id: 'warmup',
          duration: 300000, // 5 minutes
          power: 0.6,
          description: 'Warm-up',
        ),
        // Main set: 3x (3 min at 90% FTP, 2 min at 60% FTP)
        WorkoutInterval(
          id: 'main-set',
          description: 'Sweet Spot Intervals',
          repeat: 3,
          parts: [
            PowerBlock(
              id: 'work',
              duration: 180000, // 3 minutes
              power: 0.9,
              description: 'Work',
            ),
            PowerBlock(
              id: 'recovery',
              duration: 120000, // 2 minutes
              power: 0.6,
              description: 'Recovery',
            ),
          ],
        ),
        // Cool-down: 5 minutes at 50% FTP
        PowerBlock(
          id: 'cooldown',
          duration: 300000, // 5 minutes
          power: 0.5,
          description: 'Cool-down',
        ),
      ],
      events: [
        MessageEvent(
          id: 'welcome',
          parentBlockId: 'warmup',
          relativeTimeOffset: 10000, // 10 seconds in
          text: 'Welcome to your workout! Ease into the warm-up.',
          duration: 5000,
        ),
        MessageEvent(
          id: 'main-set-ready',
          parentBlockId: 'warmup',
          relativeTimeOffset: 270000, // 30 seconds before end
          text: 'Main set coming up! Get ready for some hard work.',
          duration: 5000,
        ),
      ],
    );
  }

  String _formatDuration(int milliseconds) {
    final minutes = milliseconds ~/ 60000;
    return '$minutes min';
  }

  int _calculateTotalDuration(WorkoutPlan plan) {
    int total = 0;
    for (final item in plan.plan) {
      if (item is PowerBlock) {
        total += item.duration;
      } else if (item is RampBlock) {
        total += item.duration;
      } else if (item is WorkoutInterval) {
        int intervalDuration = 0;
        for (final part in item.parts) {
          if (part is PowerBlock) {
            intervalDuration += part.duration;
          } else if (part is RampBlock) {
            intervalDuration += part.duration;
          }
        }
        total += intervalDuration * item.repeat;
      }
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    final authService = Refs.authService.of(context);
    final user = authService.currentUser.watch(context);
    final sampleWorkout = _getSampleWorkout();
    final totalDuration = _calculateTotalDuration(sampleWorkout);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vekolo'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.devices),
            onPressed: () => context.push('/devices'),
            tooltip: 'Manage Devices',
          ),
          if (user != null)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: IconButton(
                icon: UserAvatar(
                  user: user,
                  backgroundColor: Colors.white,
                  foregroundColor: Theme.of(context).colorScheme.primary,
                ),
                onPressed: () => context.push('/profile'),
                tooltip: 'Profile',
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Welcome section
              if (user != null) ...[
                Text(
                  'Welcome back, ${user.name}!',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
              ],
              Text('Ready to train?', style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
              const SizedBox(height: 32),

              // Sample Workout Card
              Card(
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
                                Text(
                                  'Sweet Spot Workout',
                                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  _formatDuration(totalDuration),
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

                      // Workout structure
                      _buildWorkoutBlock(
                        context,
                        icon: Icons.play_arrow,
                        title: 'Warm-up',
                        subtitle: '5 min at 60% FTP',
                        color: Colors.green,
                      ),
                      const SizedBox(height: 12),
                      _buildWorkoutBlock(
                        context,
                        icon: Icons.trending_up,
                        title: 'Main Set',
                        subtitle: '3x (3 min work, 2 min recovery)',
                        color: Colors.orange,
                      ),
                      const SizedBox(height: 12),
                      _buildWorkoutBlock(
                        context,
                        icon: Icons.done,
                        title: 'Cool-down',
                        subtitle: '5 min at 50% FTP',
                        color: Colors.blue,
                      ),
                      const SizedBox(height: 24),

                      // Start workout button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () => context.push('/workout-player'),
                          icon: const Icon(Icons.play_circle_filled, size: 28),
                          label: const Text(
                            'Start Workout',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
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
              ),

              const SizedBox(height: 32),

              // Quick actions
              Text(
                'Quick Actions',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => context.push('/scanner?connectMode=true'),
                    icon: const Icon(Icons.bluetooth_searching),
                    label: const Text('Scan Devices'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => context.push('/devices'),
                    icon: const Icon(Icons.devices),
                    label: const Text('My Devices'),
                  ),
                ],
              ),

              // Auth section for non-authenticated users
              if (user == null) ...[
                const SizedBox(height: 48),
                const Divider(),
                const SizedBox(height: 24),
                Text(
                  'Get started with Vekolo',
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlinedButton(onPressed: () => context.push('/login'), child: const Text('Login')),
                    const SizedBox(width: 16),
                    ElevatedButton(onPressed: () => context.push('/signup'), child: const Text('Sign Up')),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWorkoutBlock(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
  }) {
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
              Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600])),
            ],
          ),
        ),
      ],
    );
  }
}
