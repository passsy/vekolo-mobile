import 'dart:convert';
import 'package:vekolo/app/logger.dart';

import 'package:context_plus/context_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:state_beacon/state_beacon.dart';
import 'package:vekolo/app/refs.dart';
import 'package:vekolo/domain/models/workout/workout_models.dart';
import 'package:vekolo/services/workout_player_service.dart';

/// Page for executing structured workouts with real-time power control.
///
/// Features:
/// - Live workout progress visualization
/// - Current/next block display with power/cadence targets
/// - Real-time metrics (power, cadence, HR) from sensors
/// - Playback controls (play/pause, skip, end workout)
/// - Power scale factor adjustment (+/-1%)
/// - Event notifications (messages during workout)
/// - Timer display (elapsed/remaining/total)
///
/// The page integrates with WorkoutPlayerService for workout execution
/// and DeviceManager for real-time sensor data.
class WorkoutPlayerPage extends StatefulWidget {
  const WorkoutPlayerPage({super.key});

  @override
  State<WorkoutPlayerPage> createState() => _WorkoutPlayerPageState();
}

class _WorkoutPlayerPageState extends State<WorkoutPlayerPage> {
  WorkoutPlayerService? _playerService;
  bool _isLoading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadWorkout();
  }

  @override
  void dispose() {
    _playerService?.dispose();
    super.dispose();
  }

  Future<void> _loadWorkout() async {
    try {
      talker.info('[WorkoutPlayerPage] Loading workout from save.json');

      // Load workout JSON from assets
      final jsonString = await rootBundle.loadString('save.json');
      final jsonData = json.decode(jsonString) as Map<String, dynamic>;

      // Parse workout plan
      final workoutPlan = WorkoutPlan.fromJson(jsonData);

      talker.info(
        '[WorkoutPlayerPage] Loaded workout: ${workoutPlan.plan.length} items, ${workoutPlan.events.length} events',
      );

      // Initialize player service
      if (!mounted) return;
      final deviceManager = Refs.deviceManager.of(context);
      final playerService = WorkoutPlayerService(
        workoutPlan: workoutPlan,
        deviceManager: deviceManager,
        ftp: 200, // TODO: Get from user profile
      );

      // Listen to triggered events
      playerService.triggeredEvent$.listen((event) {
        if (event is FlattenedMessageEvent && mounted) {
          _showEventMessage(event.text);
        }
      });

      setState(() {
        _playerService = playerService;
        _isLoading = false;
      });

      talker.info('[WorkoutPlayerPage] Workout player initialized');
    } catch (e, stackTrace) {
      talker.error('[WorkoutPlayerPage] Error loading workout', e, stackTrace);
      setState(() {
        _loadError = e.toString();
        _isLoading = false;
      });
    }
  }

  void _showEventMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 5), behavior: SnackBarBehavior.floating),
    );
  }

  Future<bool> _onWillPop(BuildContext context) async {
    final player = _playerService;
    if (player == null || player.isComplete.value) {
      return true;
    }

    // Workout is in progress, confirm exit
    if (!context.mounted) return false;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('End Workout?'),
        content: const Text('Are you sure you want to end this workout? Your progress will not be saved.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('End Workout'),
          ),
        ],
      ),
    );

    if (result == true) {
      player.completeEarly();
    }

    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Loading Workout...')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_loadError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Error')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                const Text('Failed to load workout', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(
                  _loadError!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[700]),
                ),
                const SizedBox(height: 24),
                ElevatedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Go Back')),
              ],
            ),
          ),
        ),
      );
    }

    return Builder(
      builder: (builderContext) {
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) async {
            if (!didPop && builderContext.mounted) {
              final shouldPop = await _onWillPop(builderContext);
              if (shouldPop && builderContext.mounted) {
                Navigator.of(builderContext).pop();
              }
            }
          },
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Workout'),
              automaticallyImplyLeading: false,
              actions: [
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () async {
                    final shouldPop = await _onWillPop(builderContext);
                    if (shouldPop && builderContext.mounted) {
                      Navigator.of(builderContext).pop();
                    }
                  },
                ),
              ],
            ),
            body: _buildWorkoutPlayer(),
          ),
        );
      },
    );
  }

  Widget _buildWorkoutPlayer() {
    final player = _playerService!;

    return Builder(
      builder: (context) {
        final isPaused = player.isPaused.watch(context);
        final isComplete = player.isComplete.watch(context);
        final currentBlock = player.currentBlock$.watch(context);
        final nextBlock = player.nextBlock$.watch(context);
        final powerTarget = player.powerTarget$.watch(context);
        final cadenceTarget = player.cadenceTarget$.watch(context);
        final progress = player.progress$.watch(context);
        final elapsedTime = player.elapsedTime$.watch(context);
        final remainingTime = player.remainingTime$.watch(context);
        final currentBlockRemainingTime = player.currentBlockRemainingTime$.watch(context);
        final powerScaleFactor = player.powerScaleFactor.watch(context);

        // Watch real-time metrics from DeviceManager
        final deviceManager = Refs.deviceManager.of(context);
        final currentPower = deviceManager.powerStream.watch(context);
        final currentCadence = deviceManager.cadenceStream.watch(context);
        final currentHeartRate = deviceManager.heartRateStream.watch(context);

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Progress bar
            _buildProgressBar(progress),
            const SizedBox(height: 24),

            // Timer display
            _buildTimerDisplay(elapsedTime, remainingTime),
            const SizedBox(height: 24),

            // Current block
            _buildCurrentBlockCard(currentBlock, currentBlockRemainingTime),
            const SizedBox(height: 16),

            // Next block preview
            if (nextBlock != null) ...[
              _buildNextBlockCard(nextBlock),
              const SizedBox(height: 24),
            ] else if (isComplete) ...[
              _buildWorkoutCompleteCard(),
              const SizedBox(height: 24),
            ] else ...[
              const SizedBox(height: 24),
            ],

            // Real-time metrics
            _buildMetricsCard(
              powerTarget: powerTarget,
              currentPower: currentPower?.watts,
              cadenceTarget: cadenceTarget,
              currentCadence: currentCadence?.rpm,
              currentHeartRate: currentHeartRate?.bpm,
            ),
            const SizedBox(height: 24),

            // Playback controls
            _buildPlaybackControls(
              isPaused: isPaused,
              isComplete: isComplete,
              onPlayPause: () {
                if (isPaused) {
                  player.start();
                } else {
                  player.pause();
                }
              },
              onSkip: () => player.skip(),
              onEndWorkout: () async {
                if (!context.mounted) return;
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('End Workout?'),
                    content: const Text('Are you sure you want to end this workout early?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        style: TextButton.styleFrom(foregroundColor: Colors.red),
                        child: const Text('End'),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  player.completeEarly();
                }
              },
            ),
            const SizedBox(height: 24),

            // Power scale factor adjustment
            _buildPowerScaleCard(
              powerScaleFactor: powerScaleFactor,
              onDecrease: () => player.setPowerScaleFactor(powerScaleFactor - 0.01),
              onIncrease: () => player.setPowerScaleFactor(powerScaleFactor + 0.01),
            ),
          ],
        );
      },
    );
  }

  Widget _buildProgressBar(double progress) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('WORKOUT PROGRESS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            Text(
              '${(progress * 100).toStringAsFixed(1)}%',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 12,
            backgroundColor: Colors.grey[300],
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.green),
          ),
        ),
      ],
    );
  }

  Widget _buildTimerDisplay(int elapsedTime, int remainingTime) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [_buildTimeColumn('ELAPSED', elapsedTime), _buildTimeColumn('REMAINING', remainingTime)],
    );
  }

  Widget _buildTimeColumn(String label, int timeMs) {
    final totalSeconds = (timeMs / 1000).floor();
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;

    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
        ),
        const SizedBox(height: 4),
        Text(
          '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}',
          style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildCurrentBlockCard(dynamic block, int remainingTime) {
    if (block == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Icon(Icons.check_circle_outline, size: 48, color: Colors.green),
              const SizedBox(height: 8),
              const Text('Workout Complete!', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      );
    }

    final totalSeconds = (remainingTime / 1000).floor();
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;

    return Card(
      color: Colors.blue[50],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.play_circle_filled, color: Colors.blue),
                const SizedBox(width: 8),
                const Text('CURRENT BLOCK', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            if (block is PowerBlock) ...[
              Text(
                block.description ?? 'Power Block',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text('Target: ${(block.power * 100).toStringAsFixed(0)}% FTP', style: const TextStyle(fontSize: 16)),
              if (block.cadence != null) Text('Cadence: ${block.cadence} RPM', style: const TextStyle(fontSize: 16)),
            ] else if (block is RampBlock) ...[
              Text(
                block.description ?? 'Ramp Block',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Ramping: ${(block.powerStart * 100).toStringAsFixed(0)}% → ${(block.powerEnd * 100).toStringAsFixed(0)}% FTP',
                style: const TextStyle(fontSize: 16),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.timer, size: 16, color: Colors.grey),
                const SizedBox(width: 4),
                Text(
                  'Block time remaining: ${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}',
                  style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNextBlockCard(dynamic block) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.next_plan_outlined, color: Colors.grey[600]),
                const SizedBox(width: 8),
                const Text(
                  'NEXT BLOCK',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (block is PowerBlock) ...[
              Text(
                block.description ?? 'Power Block',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              Text(
                'Target: ${(block.power * 100).toStringAsFixed(0)}% FTP',
                style: TextStyle(fontSize: 14, color: Colors.grey[700]),
              ),
            ] else if (block is RampBlock) ...[
              Text(
                block.description ?? 'Ramp Block',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              Text(
                'Ramping: ${(block.powerStart * 100).toStringAsFixed(0)}% → ${(block.powerEnd * 100).toStringAsFixed(0)}% FTP',
                style: TextStyle(fontSize: 14, color: Colors.grey[700]),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildWorkoutCompleteCard() {
    return Card(
      color: Colors.green[50],
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.emoji_events, size: 64, color: Colors.amber),
            const SizedBox(height: 16),
            const Text('Workout Complete!', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              'Great job! You finished the workout.',
              style: TextStyle(fontSize: 16, color: Colors.grey[700]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricsCard({
    required int powerTarget,
    required int? currentPower,
    required int? cadenceTarget,
    required int? currentCadence,
    required int? currentHeartRate,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('REAL-TIME METRICS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildMetricColumn(
                  icon: Icons.bolt,
                  label: 'POWER',
                  value: currentPower?.toString() ?? '--',
                  target: powerTarget.toString(),
                  unit: 'W',
                  color: Colors.orange,
                ),
                _buildMetricColumn(
                  icon: Icons.refresh,
                  label: 'CADENCE',
                  value: currentCadence?.toString() ?? '--',
                  target: cadenceTarget?.toString(),
                  unit: 'RPM',
                  color: Colors.blue,
                ),
                _buildMetricColumn(
                  icon: Icons.favorite,
                  label: 'HEART RATE',
                  value: currentHeartRate?.toString() ?? '--',
                  target: null,
                  unit: 'BPM',
                  color: Colors.red,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricColumn({
    required IconData icon,
    required String label,
    required String value,
    required String? target,
    required String unit,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, color: color),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color),
        ),
        Text(unit, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        if (target != null) ...[
          const SizedBox(height: 4),
          Text('Target: $target', style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ],
    );
  }

  Widget _buildPlaybackControls({
    required bool isPaused,
    required bool isComplete,
    required VoidCallback onPlayPause,
    required VoidCallback onSkip,
    required VoidCallback onEndWorkout,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('CONTROLS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                if (!isComplete) ...[
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: onPlayPause,
                      icon: Icon(isPaused ? Icons.play_arrow : Icons.pause),
                      label: Text(isPaused ? 'Start' : 'Pause'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isPaused ? Colors.green : Colors.orange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: onSkip,
                      icon: const Icon(Icons.skip_next),
                      label: const Text('Skip'),
                      style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                    ),
                  ),
                ] else ...[
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.check),
                      label: const Text('Finish'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            if (!isComplete) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: onEndWorkout,
                  icon: const Icon(Icons.stop),
                  label: const Text('End Workout'),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPowerScaleCard({
    required double powerScaleFactor,
    required VoidCallback onDecrease,
    required VoidCallback onIncrease,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('INTENSITY', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: onDecrease,
                  icon: const Icon(Icons.remove_circle_outline),
                  iconSize: 32,
                  color: Colors.red,
                ),
                const SizedBox(width: 16),
                Column(
                  children: [
                    Text(
                      '${(powerScaleFactor * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                    ),
                    const Text('Power Scale', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
                const SizedBox(width: 16),
                IconButton(
                  onPressed: onIncrease,
                  icon: const Icon(Icons.add_circle_outline),
                  iconSize: 32,
                  color: Colors.green,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Adjust workout intensity up or down by 1% increments.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }
}
