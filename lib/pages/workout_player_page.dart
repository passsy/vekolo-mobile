import 'dart:async';
import 'dart:convert';
import 'package:chirp/chirp.dart';
import 'package:clock/clock.dart';

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
import 'package:vekolo/widgets/workout_screen_content.dart';

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
  const WorkoutPlayerPage({super.key, this.isResuming = false, this.workoutPlan, this.workoutName});

  final bool isResuming;
  final WorkoutPlan? workoutPlan;
  final String? workoutName;

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
  Timer? _autoPauseTimer;
  bool _hasLoadedWorkout = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Load workout once after dependencies are available
    if (!_hasLoadedWorkout) {
      _hasLoadedWorkout = true;
      _loadWorkout();
    }
  }

  @override
  void dispose() {
    _powerSubscription?.call();
    _autoPauseTimer?.cancel();

    // Call dispose immediately - the async operations inside will complete
    // even after the widget is disposed. This is okay because dispose() only
    // flushes data and doesn't interact with the widget.
    _recordingService?.dispose();

    _playerService?.dispose();
    super.dispose();
  }

  Future<void> _loadWorkout() async {
    try {
      late final WorkoutPlan workoutPlan;

      // Use provided workout plan or load from save.json
      if (widget.workoutPlan != null) {
        chirp.info('Using provided workout plan');
        workoutPlan = widget.workoutPlan!;
      } else {
        chirp.info('Loading workout from save.json');

        // Load workout JSON from assets
        final jsonString = await rootBundle.loadString('save.json');
        final jsonData = json.decode(jsonString) as Map<String, dynamic>;

        // Parse workout plan
        workoutPlan = WorkoutPlan.fromJson(jsonData);
      }

      chirp.info('Loaded workout: ${workoutPlan.plan.length} items');

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
      if (incompleteSession != null && mounted && !widget.isResuming) {
        // Only show dialog if not already handled by HomePage
        chirp.info('Found incomplete session from ${incompleteSession.startTime}');

        // Show resume dialog
        resumeChoice = await showDialog<ResumeChoice>(
          context: context,
          barrierDismissible: false,
          builder: (context) => WorkoutResumeDialog(session: incompleteSession),
        );

        // Handle user choice
        if (resumeChoice == ResumeChoice.discard) {
          // Mark session as abandoned but keep the data
          chirp.info('User chose to discard session');
          await persistence.updateSessionStatus(incompleteSession.id, SessionStatus.abandoned);
        } else if (resumeChoice == ResumeChoice.startFresh) {
          // Delete the session entirely
          chirp.info('User chose to start fresh, deleting old session');
          await persistence.deleteSession(incompleteSession.id);
        } else if (resumeChoice == ResumeChoice.resume) {
          chirp.info('User chose to resume previous session');
        }
      } else if (widget.isResuming && incompleteSession != null) {
        // HomePage already handled the dialog, assume Resume choice
        chirp.info('Resuming from HomePage choice');
        resumeChoice = ResumeChoice.resume;
      }

      final playerService = WorkoutPlayerService(workoutPlan: workoutPlan, deviceManager: deviceManager, ftp: ftp);

      // Initialize recording service
      final recordingService = WorkoutRecordingService(
        playerService: playerService,
        deviceManager: deviceManager,
        persistence: persistence,
      );

      // If resuming, restore the workout state and recording
      if (resumeChoice == ResumeChoice.resume && incompleteSession != null) {
        chirp.info('Restoring workout state from saved session');

        // Restore player state (elapsed time and current block)
        playerService.restoreState(
          elapsedMs: incompleteSession.elapsedMs,
          currentBlockIndex: incompleteSession.currentBlockIndex,
        );

        // Resume recording with existing session
        await recordingService.resumeRecording(sessionId: incompleteSession.id);

        chirp.info('Workout state restored successfully');
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
          chirp.info('Workout complete, stopping recording');
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

      chirp.info('Workout player initialized');
    } catch (e, stackTrace) {
      chirp.error('Error loading workout', error: e, stackTrace: stackTrace);
      if (mounted) {
        setState(() {
          _loadError = e.toString();
          _isLoading = false;
        });
      }
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

    // Subscribe to power changes for auto-start and auto-resume
    _powerSubscription = deviceManager.powerStream.subscribe((powerData) {
      if (!mounted) return;

      final currentPower = powerData?.watts ?? 0;
      final isPaused = playerService.isPaused.value;
      final isComplete = playerService.isComplete.value;

      // Don't do anything if workout is complete
      if (isComplete) return;

      // Auto-start: workout hasn't started yet and user is pedaling
      if (!_hasStarted && currentPower >= startResumeThreshold) {
        chirp.info('Auto-starting workout - power detected: ${currentPower}W');
        playerService.start();

        // Mark as started immediately to prevent duplicate startRecording() calls
        _hasStarted = true;

        // Start recording when workout starts (fire-and-forget)
        final authService = Refs.authService.of(context);
        final user = authService.currentUser.value;
        final ftp = user?.ftp ?? ProfileDefaults.ftp;
        if (_recordingService != null) {
          chirp.info('Calling startRecording()');
          // Fire and forget - the async operation will complete in the background
          // ignore: unawaited_futures
          _recordingService!.startRecording(
            widget.workoutName ?? 'Workout',
            userId: user?.id,
            ftp: ftp,
          );
        }

        if (!mounted) return;
        setState(() {
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
        chirp.info('Auto-resuming workout - power detected: ${currentPower}W');
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
      // Power is above auto-pause threshold while running - reset timer
      else if (_hasStarted && !isPaused && currentPower >= autoPauseThreshold) {
        if (_lowPowerStartTime != null) {
          setState(() => _lowPowerStartTime = null);
        }
      }
    });

    // Set up periodic timer to check for auto-pause conditions
    // This runs independently of power stream updates, so it will catch
    // stale data (when device stops sending data, powerStream becomes null)
    _autoPauseTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      final currentPower = deviceManager.powerStream.value?.watts ?? 0;
      final isPaused = playerService.isPaused.value;
      final isComplete = playerService.isComplete.value;

      // Don't do anything if workout is complete or not started
      if (isComplete || !_hasStarted) return;

      // Only check for auto-pause when workout is running
      if (!isPaused && currentPower < autoPauseThreshold) {
        if (_lowPowerStartTime == null) {
          // First time power dropped below threshold, start timer
          setState(() => _lowPowerStartTime = clock.now());
        } else {
          // Check if power has been low for long enough
          final lowPowerDuration = clock.now().difference(_lowPowerStartTime!);
          if (lowPowerDuration >= autoPauseDelay) {
            chirp.info('Auto-pausing workout - low power detected: ${currentPower}W');
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

        return WorkoutScreenContent(
          powerHistory: player.powerHistory,
          currentBlock: currentBlock,
          nextBlock: nextBlock,
          elapsedTime: elapsedTime,
          remainingTime: remainingTime,
          currentBlockRemainingTime: currentBlockRemainingTime,
          powerTarget: powerTarget,
          currentPower: currentPower?.watts,
          cadenceTarget: cadenceTarget,
          currentCadence: currentCadence?.rpm,
          currentHeartRate: currentHeartRate?.bpm,
          isPaused: isPaused,
          isComplete: isComplete,
          hasStarted: _hasStarted,
          ftp: ftp,
          powerScaleFactor: powerScaleFactor,
          onPlayPause: () async {
            if (isPaused) {
              player.start();
              if (!_hasStarted) {
                // First time starting the workout via play button
                final authService = Refs.authService.of(context);
                final user = authService.currentUser.value;
                final ftp = user?.ftp ?? ProfileDefaults.ftp;
                if (_recordingService != null) {
                  await _recordingService!.startRecording(
                    'Workout', // TODO: Get workout name from route params or metadata
                    userId: user?.id,
                    ftp: ftp,
                  );
                }
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
          onPowerScaleIncrease: () => player.setPowerScaleFactor(powerScaleFactor + 0.01),
          onPowerScaleDecrease: () => player.setPowerScaleFactor(powerScaleFactor - 0.01),
        );
      },
    );
  }
}
