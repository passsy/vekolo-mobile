import 'dart:convert';
import 'package:vekolo/app/logger.dart';

import 'package:context_plus/context_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:state_beacon/state_beacon.dart';
import 'package:vekolo/app/refs.dart';
import 'package:vekolo/domain/devices/device_manager.dart';
import 'package:vekolo/domain/models/workout/workout_models.dart';
import 'package:vekolo/domain/models/workout_session.dart';
import 'package:vekolo/models/profile_defaults.dart';
import 'package:vekolo/services/workout_player_service.dart';
import 'package:vekolo/services/workout_recording_service.dart';
import 'package:vekolo/widgets/workout_resume_dialog.dart';

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
  WorkoutRecordingService? _recordingService;
  bool _isLoading = true;
  String? _loadError;
  bool _hasStarted = false;
  VoidCallback? _powerSubscription;
  DateTime? _lowPowerStartTime;
  bool _isManualPause = false;

  @override
  void initState() {
    super.initState();
    _loadWorkout();
  }

  @override
  void dispose() {
    _powerSubscription?.call();
    _recordingService?.dispose();
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
      final authService = Refs.authService.of(context);
      final persistence = Refs.workoutSessionPersistence.of(context);
      final user = authService.currentUser.value;
      final ftp = user?.ftp ?? ProfileDefaults.ftp;

      // Check for incomplete workout sessions
      final incompleteSession = await persistence.getActiveSession();

      ResumeChoice? resumeChoice;
      if (incompleteSession != null && mounted) {
        talker.info('[WorkoutPlayerPage] Found incomplete session from ${incompleteSession.startTime}');

        // Show resume dialog
        resumeChoice = await showDialog<ResumeChoice>(
          context: context,
          barrierDismissible: false,
          builder: (context) => WorkoutResumeDialog(session: incompleteSession),
        );

        // Handle user choice
        if (resumeChoice == ResumeChoice.discard) {
          // Mark session as abandoned but keep the data
          talker.info('[WorkoutPlayerPage] User chose to discard session');
          await persistence.updateSessionStatus(incompleteSession.id, SessionStatus.abandoned);
        } else if (resumeChoice == ResumeChoice.startFresh) {
          // Delete the session entirely
          talker.info('[WorkoutPlayerPage] User chose to start fresh, deleting old session');
          await persistence.deleteSession(incompleteSession.id);
        } else if (resumeChoice == ResumeChoice.resume) {
          talker.info('[WorkoutPlayerPage] User chose to resume previous session');
        }
      }

      final playerService = WorkoutPlayerService(
        workoutPlan: workoutPlan,
        deviceManager: deviceManager,
        ftp: ftp,
      );

      // Initialize recording service
      final recordingService = WorkoutRecordingService(
        playerService: playerService,
        deviceManager: deviceManager,
        persistence: persistence,
      );

      // If resuming, restore the workout state and recording
      if (resumeChoice == ResumeChoice.resume && incompleteSession != null) {
        talker.info('[WorkoutPlayerPage] Restoring workout state from saved session');

        // Restore player state (elapsed time and current block)
        playerService.restoreState(
          elapsedMs: incompleteSession.elapsedMs,
          currentBlockIndex: incompleteSession.currentBlockIndex,
        );

        // Resume recording with existing session
        await recordingService.resumeRecording(sessionId: incompleteSession.id);

        talker.info('[WorkoutPlayerPage] Workout state restored successfully');
      }

      // Listen to triggered events
      playerService.triggeredEvent$.listen((event) {
        if (event is FlattenedMessageEvent && mounted) {
          _showEventMessage(event.text);
        }
      });

      // Listen to workout completion to stop recording
      playerService.isComplete.subscribe((isComplete) {
        if (isComplete) {
          talker.info('[WorkoutPlayerPage] Workout complete, stopping recording');
          recordingService.stopRecording(completed: true);
        }
      });

      setState(() {
        _playerService = playerService;
        _recordingService = recordingService;
        _isLoading = false;
      });

      // Monitor power to auto-start/resume workout when user starts pedaling
      _setupPowerMonitoring(deviceManager, playerService);

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

  /// Sets up power monitoring to auto-start/resume/pause workout based on pedaling.
  ///
  /// Auto-start: workout starts when power >= 40W is detected
  /// Auto-resume: when paused, workout resumes when power >= 40W
  /// Auto-pause: when running, workout pauses after power < 30W for 3 seconds
  ///
  /// Note: Resume threshold (40W) is higher than pause threshold (30W) to provide
  /// hysteresis and prevent rapid pause/resume cycling.
  void _setupPowerMonitoring(DeviceManager deviceManager, WorkoutPlayerService playerService) {
    const startResumeThreshold = 40; // Watts - minimum power to trigger start/resume
    const autoPauseThreshold = 30; // Watts - power below this triggers auto-pause after delay
    const autoPauseDelay = Duration(seconds: 3); // Delay before auto-pausing

    _powerSubscription = deviceManager.powerStream.subscribe((powerData) {
      if (!mounted) return;

      final currentPower = powerData?.watts ?? 0;
      final isPaused = playerService.isPaused.value;
      final isComplete = playerService.isComplete.value;

      // Don't do anything if workout is complete
      if (isComplete) return;

      // Auto-start: workout hasn't started yet and user is pedaling
      if (!_hasStarted && currentPower >= startResumeThreshold) {
        talker.info('[WorkoutPlayerPage] Auto-starting workout - power detected: ${currentPower}W');
        playerService.start();

        // Start recording when workout starts
        final authService = Refs.authService.of(context);
        final user = authService.currentUser.value;
        final ftp = user?.ftp ?? ProfileDefaults.ftp;
        _recordingService?.startRecording(
          'Workout', // TODO: Get workout name from route params or metadata
          userId: user?.id,
          ftp: ftp,
        );

        setState(() {
          _hasStarted = true;
          _lowPowerStartTime = null; // Reset low power timer
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Workout started!'),
              duration: Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
      // Auto-resume: workout is paused (but not manually paused) and user starts pedaling
      else if (_hasStarted && isPaused && !_isManualPause && currentPower >= startResumeThreshold) {
        talker.info('[WorkoutPlayerPage] Auto-resuming workout - power detected: ${currentPower}W');
        playerService.start();
        setState(() => _lowPowerStartTime = null); // Reset low power timer

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Workout resumed!'),
              duration: Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
      // Auto-pause: workout is running and power drops below threshold
      else if (_hasStarted && !isPaused && currentPower < autoPauseThreshold) {
        final now = DateTime.now();

        if (_lowPowerStartTime == null) {
          // First time power dropped below threshold, start timer
          setState(() => _lowPowerStartTime = now);
        } else {
          // Check if power has been low for long enough
          final lowPowerDuration = now.difference(_lowPowerStartTime!);
          if (lowPowerDuration >= autoPauseDelay) {
            talker.info('[WorkoutPlayerPage] Auto-pausing workout - low power detected: ${currentPower}W');
            playerService.pause();
            setState(() {
              _lowPowerStartTime = null; // Reset timer
              _isManualPause = false; // This is an auto-pause, not manual
            });

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Workout paused - start pedaling to resume'),
                  duration: Duration(seconds: 3),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          }
        }
      }
      // Power is above auto-pause threshold while running - reset timer
      else if (_hasStarted && !isPaused && currentPower >= autoPauseThreshold) {
        if (_lowPowerStartTime != null) {
          setState(() => _lowPowerStartTime = null);
        }
      }
    });
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
                  icon: const Icon(Icons.devices),
                  onPressed: () => builderContext.push('/devices'),
                  tooltip: 'Manage Devices',
                ),
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

        // Get FTP from user profile (fallback to default if not set)
        final authService = Refs.authService.of(context);
        final user = authService.currentUser.watch(context);
        final ftp = user?.ftp ?? ProfileDefaults.ftp;

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
            _buildCurrentBlockCard(currentBlock, currentBlockRemainingTime, ftp: ftp, scaleFactor: powerScaleFactor),
            const SizedBox(height: 16),

            // Next block preview
            if (nextBlock != null) ...[
              _buildNextBlockCard(nextBlock, ftp: ftp, scaleFactor: powerScaleFactor),
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
                  if (!_hasStarted) {
                    // First time starting the workout via play button
                    final authService = Refs.authService.of(context);
                    final user = authService.currentUser.value;
                    final ftp = user?.ftp ?? ProfileDefaults.ftp;
                    _recordingService?.startRecording(
                      'Workout', // TODO: Get workout name from route params or metadata
                      userId: user?.id,
                      ftp: ftp,
                    );
                    setState(() {
                      _hasStarted = true;
                      _isManualPause = false;
                    });
                  } else {
                    setState(() => _isManualPause = false); // Clear manual pause flag when resuming
                  }
                } else {
                  player.pause();
                  setState(() => _isManualPause = true); // Set manual pause flag
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

  Widget _buildCurrentBlockCard(dynamic block, int remainingTime, {required int ftp, required double scaleFactor}) {
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
              _buildPowerTarget(block.power, ftp, scaleFactor),
              if (block.cadence != null || block.cadenceLow != null || block.cadenceHigh != null)
                _buildCadenceTarget(block.cadence, block.cadenceLow, block.cadenceHigh),
            ] else if (block is RampBlock) ...[
              Text(
                block.description ?? 'Ramp Block',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              _buildRampPowerTarget(block.powerStart, block.powerEnd, ftp, scaleFactor),
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

  Widget _buildNextBlockCard(dynamic block, {required int ftp, required double scaleFactor}) {
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
              const SizedBox(height: 4),
              _buildPowerTarget(block.power, ftp, scaleFactor, isSecondary: true),
              if (block.cadence != null || block.cadenceLow != null || block.cadenceHigh != null) ...[
                const SizedBox(height: 2),
                _buildCadenceTarget(block.cadence, block.cadenceLow, block.cadenceHigh, isSecondary: true),
              ],
            ] else if (block is RampBlock) ...[
              Text(
                block.description ?? 'Ramp Block',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              _buildRampPowerTarget(block.powerStart, block.powerEnd, ftp, scaleFactor, isSecondary: true),
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

            // Show status message when paused
            if (!isComplete && isPaused) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _hasStarted ? Colors.orange.withValues(alpha: 0.1) : Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _hasStarted ? Colors.orange.withValues(alpha: 0.3) : Colors.blue.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _hasStarted ? Icons.pause_circle : Icons.pedal_bike,
                      color: _hasStarted ? Colors.orange : Colors.blue,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _hasStarted ? 'Paused - Start pedaling to resume' : 'Start pedaling to begin workout',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: _hasStarted ? Colors.orange[900] : Colors.blue[900],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                if (!isComplete) ...[
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: onPlayPause,
                      icon: const Icon(Icons.pause),
                      label: const Text('Pause'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
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

  Widget _buildPowerTarget(double powerPercent, int ftp, double scaleFactor, {bool isSecondary = false}) {
    final targetWatts = (powerPercent * ftp * scaleFactor).round();
    final percentDisplay = (powerPercent * 100).toStringAsFixed(0);

    final textStyle = isSecondary
        ? TextStyle(fontSize: 14, color: Colors.grey[700])
        : const TextStyle(fontSize: 16);

    return Text(
      'Power: $targetWatts W ($percentDisplay% FTP)',
      style: textStyle,
    );
  }

  Widget _buildRampPowerTarget(double powerStartPercent, double powerEndPercent, int ftp, double scaleFactor, {bool isSecondary = false}) {
    final startWatts = (powerStartPercent * ftp * scaleFactor).round();
    final endWatts = (powerEndPercent * ftp * scaleFactor).round();
    final startPercent = (powerStartPercent * 100).toStringAsFixed(0);
    final endPercent = (powerEndPercent * 100).toStringAsFixed(0);

    final textStyle = isSecondary
        ? TextStyle(fontSize: 14, color: Colors.grey[700])
        : const TextStyle(fontSize: 16);

    return Text(
      'Power: $startWatts → $endWatts W ($startPercent% → $endPercent% FTP)',
      style: textStyle,
    );
  }

  Widget _buildCadenceTarget(int? cadence, int? cadenceLow, int? cadenceHigh, {bool isSecondary = false}) {
    final textStyle = isSecondary
        ? TextStyle(fontSize: 14, color: Colors.grey[700])
        : const TextStyle(fontSize: 16);

    String cadenceText;
    if (cadence != null) {
      cadenceText = 'Cadence: $cadence RPM';
    } else if (cadenceLow != null && cadenceHigh != null) {
      cadenceText = 'Cadence: $cadenceLow-$cadenceHigh RPM';
    } else if (cadenceLow != null) {
      cadenceText = 'Cadence: ≥$cadenceLow RPM';
    } else if (cadenceHigh != null) {
      cadenceText = 'Cadence: ≤$cadenceHigh RPM';
    } else {
      return const SizedBox.shrink();
    }

    return Text(cadenceText, style: textStyle);
  }
}
