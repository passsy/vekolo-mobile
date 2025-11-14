import 'package:flutter/material.dart';
import 'package:spot/spot.dart';
import 'package:vekolo/widgets/workout_power_chart.dart';
import 'package:vekolo/widgets/workout_screen_content.dart';

import 'vekolo_robot.dart';

/// Robot for interacting with the Workout Player screen.
///
/// This robot provides methods to interact with and verify the workout player UI
/// without handling pumping - that's the responsibility of VekoloRobot.
extension WorkoutPlayerRobot on VekoloRobot {
  // ==========================================================================
  // Finders
  // ==========================================================================

  /// Find the workout player screen content.
  WidgetSelector<WorkoutScreenContent> get workoutScreen => spot<WorkoutScreenContent>();

  /// Find the power chart widget.
  WidgetSelector<WorkoutPowerChart> get powerChart => spot<WorkoutPowerChart>();

  // ==========================================================================
  // Timer Section
  // ==========================================================================

  /// Verify the elapsed time is displayed.
  void verifyElapsedTime(String time) {
    logger.robotLog('verify elapsed time: $time');
    spotText(time).existsOnce();
    spotText('ELAPSED').existsOnce();
  }

  /// Verify the remaining time is displayed.
  void verifyRemainingTime(String time) {
    logger.robotLog('verify remaining time: $time');
    spotText(time).existsOnce();
    spotText('REMAINING').existsOnce();
  }

  // ==========================================================================
  // Power Chart Section
  // ==========================================================================

  /// Verify the power chart is displayed.
  void verifyPowerChartVisible() {
    logger.robotLog('verify power chart visible');
    powerChart.existsOnce();
  }

  /// Verify the power chart legend is displayed.
  void verifyPowerChartLegend() {
    logger.robotLog('verify power chart legend');
    spotText('Target').existsOnce();
    spotText('Actual').existsOnce();
  }

  // ==========================================================================
  // Metrics Section
  // ==========================================================================

  /// Verify the power metric shows the given values.
  void verifyPowerMetric({required String current, required String target}) {
    logger.robotLog('verify power metric: $current W (target: $target W)');
    spotText('POWER').existsOnce();
    spotText(current).existsOnce();
    spotText('Target: $target').existsOnce();
  }

  /// Verify the cadence metric shows the given values.
  void verifyCadenceMetric({required String current, String? target}) {
    logger.robotLog('verify cadence metric: $current RPM${target != null ? ' (target: $target RPM)' : ''}');
    spotText('CADENCE').existsOnce();
    spotText(current).existsOnce();
    if (target != null) {
      spotText('Target: $target').existsOnce();
    }
  }

  /// Verify the heart rate metric shows the given value.
  void verifyHeartRateMetric({required String current}) {
    logger.robotLog('verify heart rate metric: $current BPM');
    spotText('HR').existsOnce();
    spotText(current).existsOnce();
  }

  /// Verify all metric cards are present.
  void verifyAllMetricsPresent() {
    logger.robotLog('verify all metrics present');
    spotText('POWER').existsOnce();
    spotText('CADENCE').existsOnce();
    spotText('HR').existsOnce();
  }

  // ==========================================================================
  // Current Block Section
  // ==========================================================================

  /// Verify the current block title.
  void verifyCurrentBlock(String title) {
    logger.robotLog('verify current block: $title');
    spotText(title.toUpperCase()).existsOnce();
  }

  /// Verify the current block description (power percentage).
  void verifyCurrentBlockPower(String powerDescription) {
    logger.robotLog('verify current block power: $powerDescription');
    spotText(powerDescription).existsOnce();
  }

  /// Verify the current block time remaining.
  void verifyCurrentBlockTimeRemaining(String time) {
    logger.robotLog('verify current block time remaining: $time');
    spotText('TIME LEFT').existsOnce();
    spotText(time).existsAtLeastOnce();
  }

  // ==========================================================================
  // Next Block Section
  // ==========================================================================

  /// Verify the next block is displayed.
  void verifyNextBlock(String title, String powerDescription) {
    logger.robotLog('verify next block: $title - $powerDescription');
    spotText('NEXT: ${title.toUpperCase()}').existsOnce();
    spotText(powerDescription).existsOnce();
  }

  /// Verify no next block is displayed.
  void verifyNoNextBlock() {
    logger.robotLog('verify no next block displayed');
    // Check that "NEXT BLOCK" text doesn't exist (which indicates a next block card)
    spotText('NEXT BLOCK').doesNotExist();
  }

  // ==========================================================================
  // Workout Complete Section
  // ==========================================================================

  /// Verify the workout complete card is displayed.
  void verifyWorkoutComplete() {
    logger.robotLog('verify workout complete');
    spotText('Workout Complete!').existsOnce();
    spotText('Great job! You finished the workout.').existsOnce();
    spotIcon(Icons.emoji_events).existsOnce();
  }

  // ==========================================================================
  // Status Messages Section
  // ==========================================================================

  /// Verify the paused message when workout has not started.
  void verifyPausedNotStartedMessage() {
    logger.robotLog('verify paused not started message');
    spotText('Start pedaling to begin workout').existsOnce();
    spotIcon(Icons.pedal_bike).existsOnce();
  }

  /// Verify the paused message when workout has started.
  void verifyPausedStartedMessage() {
    logger.robotLog('verify paused after start message');
    spotText('Paused - Start pedaling to resume').existsOnce();
    spotIcon(Icons.pause_circle).existsOnce();
  }

  // ==========================================================================
  // Controls Section
  // ==========================================================================

  /// Verify the resume button is displayed.
  void verifyResumeButton() {
    logger.robotLog('verify resume button');
    spotText('Resume').existsOnce();
    spotIcon(Icons.play_arrow).existsOnce();
  }

  /// Verify the pause button is displayed.
  void verifyPauseButton() {
    logger.robotLog('verify pause button');
    spotText('Pause').existsOnce();
    spotIcon(Icons.pause).existsOnce();
  }

  /// Verify the skip button is displayed.
  void verifySkipButton() {
    logger.robotLog('verify skip button');
    spotIcon(Icons.skip_next).existsOnce();
  }

  /// Verify the skip button is not displayed.
  void verifyNoSkipButton() {
    logger.robotLog('verify no skip button');
    spotIcon(Icons.skip_next).doesNotExist();
  }

  /// Verify the end workout button is displayed.
  void verifyEndWorkoutButton() {
    logger.robotLog('verify end workout button');
    spotText('End Workout').existsOnce();
  }

  /// Verify the end workout button is not displayed.
  void verifyNoEndWorkoutButton() {
    logger.robotLog('verify no end workout button');
    spotText('End Workout').doesNotExist();
  }

  /// Verify intensity controls (+ and - buttons) are displayed.
  void verifyIntensityControls() {
    logger.robotLog('verify intensity controls');
    spotIcon(Icons.add_circle_outline).existsOnce();
    spotIcon(Icons.remove_circle_outline).existsOnce();
  }

  /// Verify intensity controls are not displayed.
  void verifyNoIntensityControls() {
    logger.robotLog('verify no intensity controls');
    spotIcon(Icons.add_circle_outline).doesNotExist();
    spotIcon(Icons.remove_circle_outline).doesNotExist();
  }

  /// Verify the intensity percentage is displayed.
  void verifyIntensityPercentage(int percentage) {
    logger.robotLog('verify intensity: $percentage%');
    spotText('Intensity: $percentage%').existsOnce();
  }

  // ==========================================================================
  // Actions
  // ==========================================================================

  /// Tap the play/pause button.
  Future<void> tapPlayPause() async {
    logger.robotLog('tap play/pause button');
    // Try to find and tap whichever button is visible (Resume, Pause, or Complete)
    try {
      final resumeButton = spot<ElevatedButton>().withChild(spotText('Resume'));
      resumeButton.existsAtMostOnce();
      await act.tap(resumeButton);
    } catch (_) {
      try {
        final pauseButton = spot<ElevatedButton>().withChild(spotText('Pause'));
        pauseButton.existsAtMostOnce();
        await act.tap(pauseButton);
      } catch (_) {
        final completeButton = spot<ElevatedButton>().withChild(spotText('Complete'));
        await act.tap(completeButton);
      }
    }
    await idle();
  }

  /// Tap the skip button.
  Future<void> tapSkipBlock() async {
    logger.robotLog('tap skip button');
    final button = spot<IconButton>().withChild(spotIcon(Icons.skip_next));
    await act.tap(button);
    await idle();
  }

  /// Tap the end workout button.
  Future<void> tapEndWorkout() async {
    logger.robotLog('tap end workout button');
    await act.tap(spotText('End Workout'));
    await idle();
  }

  /// Tap the increase intensity button.
  Future<void> tapIncreaseIntensity() async {
    logger.robotLog('tap increase intensity button');
    final button = spot<IconButton>().withChild(spotIcon(Icons.add_circle_outline));
    await act.tap(button);
    await idle();
  }

  /// Tap the decrease intensity button.
  Future<void> tapDecreaseIntensity() async {
    logger.robotLog('tap decrease intensity button');
    final button = spot<IconButton>().withChild(spotIcon(Icons.remove_circle_outline));
    await act.tap(button);
    await idle();
  }

  // ==========================================================================
  // Complete Workout Flow Verification
  // ==========================================================================

  /// Verify the workout screen is in a running state.
  void verifyWorkoutRunning({
    required String elapsedTime,
    required String remainingTime,
    required String currentBlock,
    required String currentBlockPower,
  }) {
    logger.robotLog('verify workout running state');
    workoutScreen.existsOnce();
    verifyElapsedTime(elapsedTime);
    verifyRemainingTime(remainingTime);
    verifyCurrentBlock(currentBlock);
    verifyCurrentBlockPower(currentBlockPower);
    verifyPauseButton();
    verifySkipButton();
    verifyIntensityControls();
  }

  /// Verify the workout screen is in a paused state (not started).
  void verifyWorkoutNotStarted() {
    logger.robotLog('verify workout not started');
    workoutScreen.existsOnce();
    verifyPausedNotStartedMessage();
    verifyResumeButton();
    verifySkipButton();
    verifyIntensityControls();
  }

  /// Verify the workout screen is in a paused state (after starting).
  void verifyWorkoutPaused() {
    logger.robotLog('verify workout paused');
    workoutScreen.existsOnce();
    verifyPausedStartedMessage();
    verifyResumeButton();
    verifySkipButton();
    verifyIntensityControls();
  }

  /// Verify the workout screen is in a completed state.
  void verifyWorkoutCompletedState() {
    logger.robotLog('verify workout completed state');
    workoutScreen.existsOnce();
    verifyWorkoutComplete();
    verifyNoSkipButton();
    verifyNoIntensityControls();
    verifyNoEndWorkoutButton();
  }
}
