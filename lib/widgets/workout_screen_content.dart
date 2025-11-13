/// Modern workout screen content widget.
///
/// Displays the workout player UI with:
/// - Real-time power chart
/// - Current metrics (power, cadence, HR)
/// - Timer and progress
/// - Current block information
/// - Playback controls
library;

import 'package:flutter/material.dart';
import 'package:vekolo/domain/models/power_history.dart';
import 'package:vekolo/domain/models/workout/workout_models.dart';
import 'package:vekolo/widgets/workout_power_chart.dart';

/// Modern workout screen layout.
class WorkoutScreenContent extends StatelessWidget {
  const WorkoutScreenContent({
    super.key,
    required this.powerHistory,
    required this.currentBlock,
    required this.nextBlock,
    required this.elapsedTime,
    required this.remainingTime,
    required this.currentBlockRemainingTime,
    required this.powerTarget,
    required this.currentPower,
    required this.cadenceTarget,
    required this.currentCadence,
    required this.currentHeartRate,
    required this.isPaused,
    required this.isComplete,
    required this.hasStarted,
    required this.ftp,
    required this.powerScaleFactor,
    required this.onPlayPause,
    required this.onSkip,
    required this.onEndWorkout,
    required this.onPowerScaleIncrease,
    required this.onPowerScaleDecrease,
  });

  final PowerHistory powerHistory;
  final dynamic currentBlock;
  final dynamic nextBlock;
  final int elapsedTime;
  final int remainingTime;
  final int currentBlockRemainingTime;
  final int powerTarget;
  final int? currentPower;
  final int? cadenceTarget;
  final int? currentCadence;
  final int? currentHeartRate;
  final bool isPaused;
  final bool isComplete;
  final bool hasStarted;
  final int ftp;
  final double powerScaleFactor;
  final VoidCallback onPlayPause;
  final VoidCallback onSkip;
  final VoidCallback onEndWorkout;
  final VoidCallback onPowerScaleIncrease;
  final VoidCallback onPowerScaleDecrease;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Timer header
        _buildTimerHeader(),
        const SizedBox(height: 16),

        // Main metrics display
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: [
                // Power chart
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildPowerChartCard(),
                ),
                const SizedBox(height: 16),

                // Current metrics
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildMetricsRow(),
                ),
                const SizedBox(height: 16),

                // Current block info
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildCurrentBlockCard(),
                ),
                const SizedBox(height: 12),

                // Next block preview
                if (nextBlock != null && !isComplete)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _buildNextBlockCard(),
                  ),

                if (isComplete)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _buildWorkoutCompleteCard(),
                  ),

                const SizedBox(height: 16),
              ],
            ),
          ),
        ),

        // Bottom controls
        _buildBottomControls(),
      ],
    );
  }

  Widget _buildTimerHeader() {
    final totalSeconds = (elapsedTime / 1000).floor();
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;

    final remainingSeconds = (remainingTime / 1000).floor();
    final remainingMinutes = remainingSeconds ~/ 60;
    final remainingSecondsOnly = remainingSeconds % 60;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      color: Colors.grey[100],
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          Column(
            children: [
              Text(
                'ELAPSED',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey[700]),
              ),
              const SizedBox(height: 4),
              Text(
                '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}',
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          Column(
            children: [
              Text(
                'REMAINING',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey[700]),
              ),
              const SizedBox(height: 4),
              Text(
                '${remainingMinutes.toString().padLeft(2, '0')}:${remainingSecondsOnly.toString().padLeft(2, '0')}',
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPowerChartCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'POWER',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey[700]),
            ),
            const SizedBox(height: 12),
            WorkoutPowerChart(
              powerHistory: powerHistory,
              maxVisibleBars: 20,
              height: 120,
              ftp: ftp,
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: Colors.grey[400],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text('Target', style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                  ],
                ),
                Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFA726),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text('Actual', style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricsRow() {
    return Row(
      children: [
        Expanded(child: _buildMetricCard('POWER', currentPower, powerTarget, 'W', Icons.bolt, Colors.orange)),
        const SizedBox(width: 8),
        Expanded(
          child: _buildMetricCard('CADENCE', currentCadence, cadenceTarget, 'RPM', Icons.refresh, Colors.blue),
        ),
        const SizedBox(width: 8),
        Expanded(child: _buildMetricCard('HR', currentHeartRate, null, 'BPM', Icons.favorite, Colors.red)),
      ],
    );
  }

  Widget _buildMetricCard(String label, int? current, int? target, String unit, IconData icon, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey[600]),
            ),
            const SizedBox(height: 4),
            Text(
              current?.toString() ?? '--',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color),
            ),
            Text(unit, style: TextStyle(fontSize: 10, color: Colors.grey[600])),
            if (target != null) ...[
              const SizedBox(height: 2),
              Text(
                'Target: $target',
                style: const TextStyle(fontSize: 9, color: Colors.grey),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentBlockCard() {
    if (currentBlock == null) {
      return const SizedBox.shrink();
    }

    final blockSeconds = (currentBlockRemainingTime / 1000).floor();
    final blockMinutes = blockSeconds ~/ 60;
    final blockSecondsOnly = blockSeconds % 60;

    String blockTitle = 'Current Block';
    String blockDescription = '';

    if (currentBlock is PowerBlock) {
      final block = currentBlock as PowerBlock;
      blockTitle = block.description ?? 'Power Block';
      final powerPercent = (block.power * 100).toStringAsFixed(0);
      blockDescription = '$powerPercent% FTP';
    } else if (currentBlock is RampBlock) {
      final block = currentBlock as RampBlock;
      blockTitle = block.description ?? 'Ramp Block';
      final startPercent = (block.powerStart * 100).toStringAsFixed(0);
      final endPercent = (block.powerEnd * 100).toStringAsFixed(0);
      blockDescription = '$startPercent% → $endPercent% FTP';
    }

    return Card(
      color: Colors.blue[50],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.play_circle_filled, color: Colors.blue[700], size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    blockTitle.toUpperCase(),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    blockDescription,
                    style: TextStyle(fontSize: 16, color: Colors.grey[800]),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'TIME LEFT',
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey[700]),
                ),
                const SizedBox(height: 2),
                Text(
                  '${blockMinutes.toString().padLeft(2, '0')}:${blockSecondsOnly.toString().padLeft(2, '0')}',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNextBlockCard() {
    if (nextBlock == null) {
      return const SizedBox.shrink();
    }

    String blockTitle = 'Next Block';
    String blockDescription = '';

    if (nextBlock is PowerBlock) {
      final block = nextBlock as PowerBlock;
      blockTitle = block.description ?? 'Power Block';
      final powerPercent = (block.power * 100).toStringAsFixed(0);
      blockDescription = '$powerPercent% FTP';
    } else if (nextBlock is RampBlock) {
      final block = nextBlock as RampBlock;
      blockTitle = block.description ?? 'Ramp Block';
      final startPercent = (block.powerStart * 100).toStringAsFixed(0);
      final endPercent = (block.powerEnd * 100).toStringAsFixed(0);
      blockDescription = '$startPercent% → $endPercent% FTP';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.next_plan_outlined, color: Colors.grey[600], size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'NEXT: ${blockTitle.toUpperCase()}',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey[700]),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    blockDescription,
                    style: TextStyle(fontSize: 14, color: Colors.grey[800]),
                  ),
                ],
              ),
            ),
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

  Widget _buildBottomControls() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Status message when paused
            if (!isComplete && isPaused) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: hasStarted ? Colors.orange.withValues(alpha: 0.1) : Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: hasStarted ? Colors.orange.withValues(alpha: 0.3) : Colors.blue.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      hasStarted ? Icons.pause_circle : Icons.pedal_bike,
                      color: hasStarted ? Colors.orange : Colors.blue,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        hasStarted ? 'Paused - Start pedaling to resume' : 'Start pedaling to begin workout',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: hasStarted ? Colors.orange[900] : Colors.blue[900],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Control buttons
            Row(
              children: [
                // Intensity decrease
                if (!isComplete) ...[
                  IconButton(
                    onPressed: onPowerScaleDecrease,
                    icon: const Icon(Icons.remove_circle_outline),
                    iconSize: 32,
                    color: Colors.red,
                  ),
                  const SizedBox(width: 8),
                ],

                // Play/Pause button
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: isComplete ? null : onPlayPause,
                    icon: Icon(isComplete ? Icons.check : (isPaused ? Icons.play_arrow : Icons.pause)),
                    label: Text(isComplete ? 'Complete' : (isPaused ? 'Resume' : 'Pause')),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isComplete ? Colors.green : (isPaused ? Colors.green : Colors.orange),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      disabledBackgroundColor: Colors.grey,
                    ),
                  ),
                ),

                // Skip button
                if (!isComplete) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: onSkip,
                    icon: const Icon(Icons.skip_next),
                    iconSize: 32,
                    color: Colors.blue,
                  ),
                ],

                // Intensity increase
                if (!isComplete) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: onPowerScaleIncrease,
                    icon: const Icon(Icons.add_circle_outline),
                    iconSize: 32,
                    color: Colors.green,
                  ),
                ],
              ],
            ),

            // End workout button
            if (!isComplete) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: onEndWorkout,
                icon: const Icon(Icons.stop),
                label: const Text('End Workout'),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
              ),
            ],

            // Power scale indicator
            if (!isComplete)
              Text(
                'Intensity: ${(powerScaleFactor * 100).toStringAsFixed(0)}%',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
          ],
        ),
      ),
    );
  }
}
