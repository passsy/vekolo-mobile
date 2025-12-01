import 'package:flutter/material.dart';
import 'package:spot/spot.dart';
import 'package:vekolo/pages/home_page_v2/widgets/workout_interval_bars.dart';
import 'package:vekolo/widgets/workout_screen_content.dart';

import 'vekolo_robot.dart';

/// Robot for interacting with the Workout Player screen.
///
/// This robot provides methods to interact with and verify the workout player UI
/// without handling pumping - that's the responsibility of VekoloRobot.
///
/// Note: The workout screen auto-starts when pedaling power >= 40W is detected,
/// and auto-pauses when power < 30W for 3 seconds. There are no manual
/// pause/resume buttons in the current UI.
extension WorkoutPlayerRobot on VekoloRobot {
  // ==========================================================================
  // Finders
  // ==========================================================================

  /// Find the workout player screen content.
  WidgetSelector<WorkoutScreenContent> get workoutScreen => spot<WorkoutScreenContent>();

  /// Find the interval bars widget (zoomed view).
  WidgetSelector<WorkoutIntervalBars> get intervalBars => spot<WorkoutIntervalBars>();

  // ==========================================================================
  // Timer Section
  // ==========================================================================

  /// Verify the elapsed time is displayed (shown as timestamp at bottom left).
  void verifyElapsedTime(String time) {
    logger.robotLog('verify elapsed time: $time');
    spotText(time).existsAtLeastOnce();
  }

  /// Verify the remaining time is displayed (shown as timestamp at bottom right).
  void verifyRemainingTime(String time) {
    logger.robotLog('verify remaining time: $time');
    spotText(time).existsAtLeastOnce();
  }

  // ==========================================================================
  // Interval Visualization Section
  // ==========================================================================

  /// Verify the interval visualization is displayed.
  void verifyIntervalBarsVisible() {
    logger.robotLog('verify interval bars visible');
    intervalBars.existsAtLeastOnce();
  }

  // ==========================================================================
  // Metrics Section
  // ==========================================================================

  /// Verify all KPI metrics are present (WATT, RPM, HR, SPEED).
  void verifyAllMetricsPresent() {
    logger.robotLog('verify all metrics present');
    spotText('WATT').existsAtLeastOnce();
    spotText('RPM').existsAtLeastOnce();
    spotText('HR').existsOnce();
    spotText('SPEED').existsOnce();
  }

  /// Verify the TIME metric section is present.
  void verifyTimeMetricPresent() {
    logger.robotLog('verify time metric present');
    spotText('TIME').existsOnce();
  }

  // ==========================================================================
  // Status Messages Section
  // ==========================================================================

  /// Verify the paused message when workout has not started.
  void verifyPausedNotStartedMessage() {
    logger.robotLog('verify paused not started message');
    spotText('Start pedaling to begin workout').existsOnce();
  }

  /// Verify the paused message when workout has started.
  void verifyPausedStartedMessage() {
    logger.robotLog('verify paused after start message');
    spotText('Paused - Start pedaling to resume').existsOnce();
  }

  // ==========================================================================
  // Controls Section
  // ==========================================================================

  /// Verify the skip button is displayed (ElevatedButton with "SKIP" text).
  void verifySkipButton() {
    logger.robotLog('verify skip button');
    spotText('SKIP').existsOnce();
    spotIcon(Icons.skip_next).existsOnce();
  }

  /// Verify the skip button is not displayed.
  void verifyNoSkipButton() {
    logger.robotLog('verify no skip button');
    spotText('SKIP').doesNotExist();
  }

  /// Verify the close button is displayed.
  void verifyCloseButton() {
    logger.robotLog('verify close button');
    spotIcon(Icons.close).existsOnce();
  }

  /// Verify intensity controls (+ and - buttons) are displayed.
  void verifyIntensityControls() {
    logger.robotLog('verify intensity controls');
    spotIcon(Icons.add).existsOnce();
    spotIcon(Icons.remove).existsOnce();
  }

  /// Verify intensity controls are not displayed.
  void verifyNoIntensityControls() {
    logger.robotLog('verify no intensity controls');
    spotIcon(Icons.add).doesNotExist();
    spotIcon(Icons.remove).doesNotExist();
  }

  /// Verify the intensity percentage is displayed.
  void verifyIntensityPercentage(int percentage) {
    logger.robotLog('verify intensity: $percentage%');
    spotText('$percentage%').existsOnce();
  }

  // ==========================================================================
  // Actions
  // ==========================================================================

  /// Tap the skip button.
  Future<void> tapSkipBlock() async {
    logger.robotLog('tap skip button');
    // Just tap the text, the gesture will bubble up to the button
    await act.tap(spotText('SKIP'));
    await idle();
  }

  /// Tap the close button (X icon at top right).
  Future<void> tapCloseButton() async {
    logger.robotLog('tap close button');
    final button = spot<IconButton>().withChild(spotIcon(Icons.close));
    await act.tap(button);
    await idle();
  }

  /// Tap the increase intensity button.
  Future<void> tapIncreaseIntensity() async {
    logger.robotLog('tap increase intensity button');
    final button = spot<IconButton>().withChild(spotIcon(Icons.add));
    await act.tap(button);
    await idle();
  }

  /// Tap the decrease intensity button.
  Future<void> tapDecreaseIntensity() async {
    logger.robotLog('tap decrease intensity button');
    final button = spot<IconButton>().withChild(spotIcon(Icons.remove));
    await act.tap(button);
    await idle();
  }

  // ==========================================================================
  // Complete Workout Flow Verification
  // ==========================================================================

  /// Verify the workout screen is displayed and in running state.
  void verifyWorkoutRunning() {
    logger.robotLog('verify workout running state');
    workoutScreen.existsOnce();
    verifyAllMetricsPresent();
    verifySkipButton();
    verifyIntensityControls();
    verifyCloseButton();
    // No pause message should be visible when running
    spotText('Start pedaling to begin workout').doesNotExist();
    spotText('Paused - Start pedaling to resume').doesNotExist();
  }

  /// Verify the workout screen is in a paused state (not started).
  void verifyWorkoutNotStarted() {
    logger.robotLog('verify workout not started');
    workoutScreen.existsOnce();
    verifyPausedNotStartedMessage();
    verifySkipButton();
    verifyIntensityControls();
    verifyCloseButton();
  }

  /// Verify the workout screen is in a paused state (after starting).
  void verifyWorkoutPaused() {
    logger.robotLog('verify workout paused');
    workoutScreen.existsOnce();
    verifyPausedStartedMessage();
    verifySkipButton();
    verifyIntensityControls();
    verifyCloseButton();
  }
}
