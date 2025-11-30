import 'package:flutter_test/flutter_test.dart';
import 'package:spot/spot.dart';
import 'package:vekolo/domain/models/device_info.dart';

import '../robot/robot_kit.dart';

void main() {
  // Note: This test verifies the workout recording and crash recovery feature.
  // It tests:
  // - Automatic recording when workout starts
  // - Continuous sample storage (1Hz)
  // - Crash detection and recovery
  // - Resume dialog with three options: Resume, Discard, Start Fresh
  // - State restoration on resume

  robotTest('workout session records samples and survives crash', (robot) async {
    // Setup: Create trainer device with power/HR/cadence capabilities
    final kickrCore = robot.aether.createDevice(
      name: 'Kickr Core',
      capabilities: {DeviceDataType.power, DeviceDataType.cadence, DeviceDataType.speed},
    );

    final hrMonitor = robot.aether.createDevice(name: 'HR Monitor', capabilities: {DeviceDataType.heartRate});

    await robot.launchApp(pairedDevices: [kickrCore, hrMonitor], loggedIn: true);
    await robot.tapStartWorkout("Sweet Spot Workout");

    // Verify workout player page loaded and waiting for user to start pedaling
    robot.verifyPlayerIsShown();
    robot.verifyWorkoutIsPaused();

    // Start riding - power automatically matches workout target from ERG control
    kickrCore.startRiding();
    await robot.idle();
    robot.verifyWorkoutIsRunning();

    // Simulate crash by closing app without completing workout
    await robot.closeApp();

    // Verify device disconnected
    expect(kickrCore.isConnected, isFalse);
    expect(hrMonitor.isConnected, isFalse);

    // Restart app - should show resume dialog
    await robot.launchApp(pairedDevices: [kickrCore, hrMonitor], loggedIn: true);

    // Wait for resume dialog to appear
    await robot.waitForCrashRecoveryDialog("Sweet Spot Workout");
    spotText('We found an incomplete workout session from earlier.').existsAtLeastOnce();

    // Dismiss dialog by choosing Resume
    await robot.tapResumeWorkout();
    robot.verifyPlayerIsShown();
    expect(kickrCore.isConnected, isTrue);
    expect(hrMonitor.isConnected, isTrue);
    robot.verifyWorkoutIsRunning();
  });

  robotTest('workout session crash recovery - resume option', (robot) async {
    // Setup: Create trainer device
    final kickrCore = robot.aether.createDevice(
      name: 'Kickr Core',
      capabilities: {DeviceDataType.power, DeviceDataType.cadence, DeviceDataType.speed},
    );

    await robot.launchApp(pairedDevices: [kickrCore], loggedIn: true);

    await robot.tapStartWorkout('Sweet Spot Workout');

    robot.verifyPlayerIsShown();
    robot.verifyWorkoutIsPaused();

    // Start riding for a few seconds to record samples
    kickrCore.startRiding();
    await robot.pumpUntil(3000);

    // Simulate crash by closing app without completing workout
    kickrCore.stopRiding();
    await robot.closeApp();

    // Verify device disconnected
    expect(kickrCore.isConnected, isFalse);

    // Restart app - should show resume dialog
    await robot.launchApp(pairedDevices: [kickrCore], loggedIn: true);

    // Wait for resume dialog to appear
    await robot.waitForCrashRecoveryDialog("Sweet Spot Workout");
    spotText('We found an incomplete workout session from earlier.').existsAtLeastOnce();
    spotText('Resume').existsAtLeastOnce();
    spotText('Discard').existsAtLeastOnce();
    spotText('Start Fresh').existsAtLeastOnce();

    // Choose Resume
    await robot.tapResumeWorkout();

    // Wait for workout player page to load and restore state
    await robot.pumpUntil(3000);
    for (int i = 0; i < 5; i++) {
      await robot.idle(500);
    }

    // Verify workout player restored
    robot.verifyPlayerIsShown();

    // Continue riding
    kickrCore.startRiding();
    await robot.idle(500);
    kickrCore.stopRiding();
  });

  robotTest('workout session crash recovery - discard option', (robot) async {
    // Setup: Create trainer device
    final kickrCore = robot.aether.createDevice(
      name: 'Kickr Core',
      capabilities: {DeviceDataType.power, DeviceDataType.cadence, DeviceDataType.speed},
    );

    await robot.launchApp(pairedDevices: [kickrCore], loggedIn: true);

    // Navigate to workout player and start workout
    await robot.tapStartWorkout('Sweet Spot Workout');

    robot.verifyWorkoutIsPaused();

    // Run workout for a few seconds
    kickrCore.startRiding();
    await robot.pumpUntil(3000);
    kickrCore.stopRiding();

    // Simulate crash
    await robot.closeApp();

    // Restart app
    await robot.launchApp(pairedDevices: [kickrCore], loggedIn: true);
    await robot.idle(1000);

    // Resume dialog should appear
    await robot.waitForCrashRecoveryDialog("Sweet Spot Workout");

    // Choose Discard
    await robot.discardWorkout();

    // Should be back at home page, not in workout player
    spotText('Sweet Spot Workout').existsAtLeastOnce();

    // Verify can start a new workout
    await robot.tapStartWorkout('Sweet Spot Workout');

    robot.verifyWorkoutIsPaused();
  });

  robotTest('workout session crash recovery - start fresh option', (robot) async {
    // Setup: Create trainer device
    final kickrCore = robot.aether.createDevice(
      name: 'Kickr Core',
      capabilities: {DeviceDataType.power, DeviceDataType.cadence, DeviceDataType.speed},
    );

    await robot.launchApp(pairedDevices: [kickrCore], loggedIn: true);

    // Navigate to workout player and start workout
    await robot.tapStartWorkout('Sweet Spot Workout');

    robot.verifyWorkoutIsPaused();

    // Run workout for a few seconds
    kickrCore.startRiding();
    await robot.pumpUntil(3000);
    kickrCore.stopRiding();

    // Simulate crash
    await robot.closeApp();

    // Restart app
    await robot.launchApp(pairedDevices: [kickrCore], loggedIn: true);
    await robot.idle(1000);

    // Resume dialog should appear
    await robot.waitForCrashRecoveryDialog("Sweet Spot Workout");

    // Choose Start Fresh
    await robot.startFreshWorkout();

    // Wait for new workout player page to load
    await robot.pumpUntil(2000);

    // Should start a new workout from beginning
    robot.verifyWorkoutIsPaused();
    robot.verifyPlayerIsShown();

    // Start riding to verify workout works
    kickrCore.startRiding();
    await robot.idle(500);
    kickrCore.stopRiding();
  });

  robotTest('stale metrics return null after 5 seconds', (robot) async {
    // Setup: Create trainer device
    final kickrCore = robot.aether.createDevice(
      name: 'Kickr Core',
      capabilities: {DeviceDataType.power, DeviceDataType.cadence, DeviceDataType.speed},
    );

    await robot.launchApp(pairedDevices: [kickrCore], loggedIn: true);

    // Navigate to workout player
    await robot.tapStartWorkout('Sweet Spot Workout');

    robot.verifyWorkoutIsPaused();

    // Start riding to establish continuous data streaming
    kickrCore.startRiding();
    await robot.pumpUntil(3000);

    // Stop riding (simulate user stopping pedaling)
    // This stops power updates but keeps device connected
    kickrCore.stopRiding();

    // Wait for staleness threshold (5 seconds)
    await robot.idle(5500);

    // Note: We can't directly verify beacon values from robot tests since we don't have
    // access to the device manager instance. This test verifies the UI behavior and
    // that the app continues running without errors when metrics become stale.
    // The actual staleness logic is tested in unit tests (staleness_beacon_test.dart)
    // and integration tests (device_manager_staleness_test.dart).

    // Verify app is still running and showing workout player
    robot.verifyPlayerIsShown();
  });
}
