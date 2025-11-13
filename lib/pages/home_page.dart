import 'package:context_plus/context_plus.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:state_beacon/state_beacon.dart';
import 'package:chirp/chirp.dart';
import 'package:vekolo/app/refs.dart';
import 'package:vekolo/domain/models/workout_session.dart';
import 'package:vekolo/widgets/user_avatar.dart';
import 'package:vekolo/widgets/workout_resume_dialog.dart';
import 'package:vekolo/domain/models/workout/workout_models.dart';

/// Entry point after app startup.
///
/// Shows login/signup buttons for unauthenticated users and a sample workout
/// that can be started in the player.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForIncompleteWorkout();
    });
  }

  Future<void> _checkForIncompleteWorkout() async {
    if (!mounted) return;

    chirp.info('Checking for incomplete workout');
    final persistence = Refs.workoutSessionPersistence.of(context);
    final incompleteSession = await persistence.getActiveSession();
    chirp.info('Incomplete session: ${incompleteSession?.id ?? "none"}');

    if (incompleteSession != null && mounted) {
      chirp.info('Showing resume dialog for session: ${incompleteSession.id}');
      final choice = await showDialog<ResumeChoice>(
        context: context,
        barrierDismissible: false,
        builder: (context) => WorkoutResumeDialog(session: incompleteSession),
      );

      if (!mounted) return;

      if (choice == ResumeChoice.resume) {
        // Navigate to workout player - pass parameter to skip showing dialog again
        context.push('/workout-player?resuming=true');
      } else if (choice == ResumeChoice.discard) {
        await persistence.updateSessionStatus(incompleteSession.id, SessionStatus.abandoned);
        await persistence.clearActiveWorkout();
      } else if (choice == ResumeChoice.startFresh) {
        await persistence.deleteSession(incompleteSession.id);
        await persistence.clearActiveWorkout();
        // Navigate to workout player to start fresh
        if (!mounted) return;
        context.push('/workout-player');
      }
    }
  }

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

              // Navigate to new HomePage2
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF6F00), Color(0xFFE91E63)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFF6F00).withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    const Icon(Icons.auto_awesome, size: 48, color: Colors.white),
                    const SizedBox(height: 12),
                    const Text(
                      'Try New Home Page',
                      style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Experience the redesigned interface',
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () => context.push('/home2'),
                      icon: const Icon(Icons.arrow_forward),
                      label: const Text('Open HomePage2'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFFFF6F00),
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // Sample Workout Card
              WorkoutCard(
                name: 'Sweet Spot Workout',
                duration: totalDuration,
                blocks: [
                  _WorkoutBlockInfo(
                    icon: Icons.play_arrow,
                    title: 'Warm-up',
                    subtitle: '5 min at 60% FTP',
                    color: Colors.green,
                  ),
                  _WorkoutBlockInfo(
                    icon: Icons.trending_up,
                    title: 'Main Set',
                    subtitle: '3x (3 min work, 2 min recovery)',
                    color: Colors.orange,
                  ),
                  _WorkoutBlockInfo(
                    icon: Icons.done,
                    title: 'Cool-down',
                    subtitle: '5 min at 50% FTP',
                    color: Colors.blue,
                  ),
                ],
                onStart: () => context.push('/workout-player'),
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
}

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
  final List<_WorkoutBlockInfo> blocks;
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
                _buildWorkoutBlock(
                  context,
                  icon: block.icon,
                  title: block.title,
                  subtitle: block.subtitle,
                  color: block.color,
                ),
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

/// Information about a workout block for display in WorkoutCard.
class _WorkoutBlockInfo {
  const _WorkoutBlockInfo({required this.icon, required this.title, required this.subtitle, required this.color});

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
}
