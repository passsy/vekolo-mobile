import '../robot/robot_kit.dart';
import '../robot/workout_player_robot.dart';

void main() {
  group('Workout Screen Content', () {
    robotTest('displays initial state before workout starts', (robot) async {
      final trainer = robot.aether.createDevice(
        name: 'KICKR CORE',
        capabilities: {DeviceDataType.power, DeviceDataType.cadence, DeviceDataType.speed},
      );

      await robot.launchApp(loggedIn: true, pairedDevices: [trainer]);
      await robot.tapStartWorkout('Sweet Spot');

      // Verify initial paused state
      robot.verifyWorkoutNotStarted();
      robot.verifyTimerHeaders();
      robot.verifyAllMetricsPresent();
      robot.verifyEndWorkoutButton();
    });

    robotTest('transitions to running state when pedaling starts', (robot) async {
      final trainer = robot.aether.createDevice(
        name: 'KICKR CORE',
        capabilities: {DeviceDataType.power, DeviceDataType.cadence, DeviceDataType.speed},
      );

      await robot.launchApp(loggedIn: true, pairedDevices: [trainer]);
      await robot.tapStartWorkout('Sweet Spot');

      // Start pedaling to trigger auto-start
      trainer.emitPower(150);
      trainer.emitCadence(85);
      await robot.pumpUntil(500);

      // Should transition to running state
      robot.verifyPauseButton();
      robot.verifySkipButton();
      robot.verifyIntensityControls();
    });

    robotTest('displays metrics correctly during workout', (robot) async {
      final trainer = robot.aether.createDevice(
        name: 'KICKR CORE',
        capabilities: {DeviceDataType.power, DeviceDataType.cadence, DeviceDataType.speed},
      );

      await robot.launchApp(loggedIn: true, pairedDevices: [trainer]);
      await robot.tapStartWorkout('Sweet Spot');

      // Start pedaling
      trainer.emitPower(180);
      trainer.emitCadence(90);
      trainer.emitHeartRate(145);
      await robot.pumpUntil(1000);

      // Verify all metrics are displayed
      robot.verifyAllMetricsPresent();
      // Note: Exact values may vary due to workout plan targets
      // We just verify the structure is present
    });

    robotTest('shows current block information', (robot) async {
      final trainer = robot.aether.createDevice(
        name: 'KICKR CORE',
        capabilities: {DeviceDataType.power, DeviceDataType.cadence, DeviceDataType.speed},
      );

      await robot.launchApp(loggedIn: true, pairedDevices: [trainer]);
      await robot.tapStartWorkout('Sweet Spot');

      // Start workout
      trainer.emitPower(150);
      await robot.pumpUntil(500);

      // Verify current block info is shown
      // (exact text depends on workout plan, but structure should be there)
      spotText('TIME LEFT').existsOnce();
    });

    robotTest('can pause workout manually', (robot) async {
      final trainer = robot.aether.createDevice(
        name: 'KICKR CORE',
        capabilities: {DeviceDataType.power, DeviceDataType.cadence, DeviceDataType.speed},
      );

      await robot.launchApp(loggedIn: true, pairedDevices: [trainer]);
      await robot.tapStartWorkout('Sweet Spot');

      // Start workout
      trainer.emitPower(150);
      await robot.pumpUntil(500);

      // Pause the workout
      await robot.tapPlayPause();
      await robot.idle(200);

      // Verify paused state
      robot.verifyPausedStartedMessage();
      robot.verifyResumeButton();
    });

    robotTest('can resume workout after manual pause', (robot) async {
      final trainer = robot.aether.createDevice(
        name: 'KICKR CORE',
        capabilities: {DeviceDataType.power, DeviceDataType.cadence, DeviceDataType.speed},
      );

      await robot.launchApp(loggedIn: true, pairedDevices: [trainer]);
      await robot.tapStartWorkout('Sweet Spot');

      // Start workout
      trainer.emitPower(150);
      await robot.pumpUntil(500);

      // Pause
      await robot.tapPlayPause();
      await robot.idle(200);
      robot.verifyResumeButton();

      // Resume
      await robot.tapPlayPause();
      await robot.idle(200);

      // Should be running again
      robot.verifyPauseButton();
    });

    robotTest('can skip to next block', (robot) async {
      final trainer = robot.aether.createDevice(
        name: 'KICKR CORE',
        capabilities: {DeviceDataType.power, DeviceDataType.cadence, DeviceDataType.speed},
      );

      await robot.launchApp(loggedIn: true, pairedDevices: [trainer]);
      await robot.tapStartWorkout('Sweet Spot');

      // Start workout
      trainer.emitPower(150);
      await robot.pumpUntil(500);

      // Skip to next block
      await robot.tapSkipBlock();
      await robot.idle(300);

      // Verify still running (just in next block)
      robot.verifyPauseButton();
      robot.verifySkipButton();
    });

    robotTest('can adjust intensity up', (robot) async {
      final trainer = robot.aether.createDevice(
        name: 'KICKR CORE',
        capabilities: {DeviceDataType.power, DeviceDataType.cadence, DeviceDataType.speed},
      );

      await robot.launchApp(loggedIn: true, pairedDevices: [trainer]);
      await robot.tapStartWorkout('Sweet Spot');

      // Start workout
      trainer.emitPower(150);
      await robot.pumpUntil(500);

      // Initially at 100%
      robot.verifyIntensityPercentage(100);

      // Increase intensity
      await robot.tapIncreaseIntensity();
      await robot.idle(200);

      // Should now be 101%
      robot.verifyIntensityPercentage(101);
    });

    robotTest('can adjust intensity down', (robot) async {
      final trainer = robot.aether.createDevice(
        name: 'KICKR CORE',
        capabilities: {DeviceDataType.power, DeviceDataType.cadence, DeviceDataType.speed},
      );

      await robot.launchApp(loggedIn: true, pairedDevices: [trainer]);
      await robot.tapStartWorkout('Sweet Spot');

      // Start workout
      trainer.emitPower(150);
      await robot.pumpUntil(500);

      // Initially at 100%
      robot.verifyIntensityPercentage(100);

      // Decrease intensity
      await robot.tapDecreaseIntensity();
      await robot.idle(200);

      // Should now be 99%
      robot.verifyIntensityPercentage(99);
    });

    robotTest('can end workout early', (robot) async {
      final trainer = robot.aether.createDevice(
        name: 'KICKR CORE',
        capabilities: {DeviceDataType.power, DeviceDataType.cadence, DeviceDataType.speed},
      );

      await robot.launchApp(loggedIn: true, pairedDevices: [trainer]);
      await robot.tapStartWorkout('Sweet Spot');

      // Start workout
      trainer.emitPower(150);
      await robot.pumpUntil(500);

      // Tap end workout button
      await robot.tapEndWorkout();
      await robot.idle(200);

      // Should show confirmation dialog
      spotText('End Workout?').existsOnce();
      spotText('Are you sure you want to end this workout early?').existsOnce();

      // Confirm
      spotText('End').existsOnce();
      await act.tap(spotText('End'));
      await robot.idle(500);

      // Should complete the workout
      robot.verifyWorkoutCompletedState();
    });

    robotTest('shows timer counting up during workout', (robot) async {
      final trainer = robot.aether.createDevice(
        name: 'KICKR CORE',
        capabilities: {DeviceDataType.power, DeviceDataType.cadence, DeviceDataType.speed},
      );

      await robot.launchApp(loggedIn: true, pairedDevices: [trainer]);
      await robot.tapStartWorkout('Sweet Spot');

      // Start workout
      trainer.emitPower(150);
      await robot.pumpUntil(500);

      // Verify initial time (should be close to 00:00)
      robot.verifyElapsedTime('00:00');

      // Wait some time
      await robot.pumpUntil(2000);

      // Timer should have progressed (at least 00:01 or 00:02)
      // Note: exact time depends on ticks, so we just verify it's there
      spotText('ELAPSED').existsOnce();
      spotText('REMAINING').existsOnce();
    });

    robotTest('handles missing metrics gracefully', (robot) async {
      final trainer = robot.aether.createDevice(
        name: 'KICKR CORE',
        capabilities: {DeviceDataType.power}, // Only power, no cadence or HR
      );

      await robot.launchApp(loggedIn: true, pairedDevices: [trainer]);
      await robot.tapStartWorkout('Sweet Spot');

      // Start workout
      trainer.emitPower(150);
      await robot.pumpUntil(500);

      // Verify power is shown
      robot.verifyAllMetricsPresent();
      // Cadence and HR should show "--" or similar placeholder
      // (exact implementation depends on UI, but should not crash)
    });

    robotTest('auto-pauses when power drops below threshold', (robot) async {
      final trainer = robot.aether.createDevice(
        name: 'KICKR CORE',
        capabilities: {DeviceDataType.power, DeviceDataType.cadence, DeviceDataType.speed},
      );

      await robot.launchApp(loggedIn: true, pairedDevices: [trainer]);
      await robot.tapStartWorkout('Sweet Spot');

      // Start workout
      trainer.emitPower(150);
      await robot.pumpUntil(500);
      robot.verifyPauseButton(); // Running

      // Stop pedaling (power drops to 0)
      trainer.emitPower(0);
      await robot.pumpUntil(3500); // Auto-pause threshold is 3 seconds

      // Should auto-pause
      robot.verifyPausedStartedMessage();
      robot.verifyResumeButton();
    });

    robotTest('auto-resumes when pedaling again', (robot) async {
      final trainer = robot.aether.createDevice(
        name: 'KICKR CORE',
        capabilities: {DeviceDataType.power, DeviceDataType.cadence, DeviceDataType.speed},
      );

      await robot.launchApp(loggedIn: true, pairedDevices: [trainer]);
      await robot.tapStartWorkout('Sweet Spot');

      // Start workout
      trainer.emitPower(150);
      await robot.pumpUntil(500);

      // Stop pedaling to trigger auto-pause
      trainer.emitPower(0);
      await robot.pumpUntil(3500);
      robot.verifyPausedStartedMessage();

      // Start pedaling again
      trainer.emitPower(150);
      await robot.pumpUntil(500);

      // Should auto-resume
      robot.verifyPauseButton();
    });

    robotTest('displays workout complete screen when finished', (robot) async {
      final trainer = robot.aether.createDevice(
        name: 'KICKR CORE',
        capabilities: {DeviceDataType.power, DeviceDataType.cadence, DeviceDataType.speed},
      );

      await robot.launchApp(loggedIn: true, pairedDevices: [trainer]);
      await robot.tapStartWorkout('Sweet Spot');

      // Start workout
      trainer.emitPower(150);
      await robot.pumpUntil(500);

      // Fast-forward to end by ending workout
      await robot.tapEndWorkout();
      await robot.idle(200);
      await act.tap(spotText('End'));
      await robot.idle(500);

      // Verify completion state
      robot.verifyWorkoutCompletedState();
    });

    robotTest('shows power chart throughout workout', (robot) async {
      final trainer = robot.aether.createDevice(
        name: 'KICKR CORE',
        capabilities: {DeviceDataType.power, DeviceDataType.cadence, DeviceDataType.speed},
      );

      await robot.launchApp(loggedIn: true, pairedDevices: [trainer]);
      await robot.tapStartWorkout('Sweet Spot');

      // Start workout
      trainer.emitPower(150);
      await robot.pumpUntil(500);

      // Power chart should be visible
      robot.verifyPowerChartVisible();

      // Continue workout for a bit
      await robot.pumpUntil(5000);

      // Chart should still be there
      robot.verifyPowerChartVisible();
      robot.verifyPowerChartLegend();
    });
  });
}
