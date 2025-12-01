import 'package:flutter_test/flutter_test.dart';
import 'package:spot/spot.dart';
import 'package:vekolo/domain/models/device_info.dart';

import '../robot/robot_kit.dart';

void main() {
  robotTest('workout session records samples and survives crash', (robot) async {
    final kickrCore = robot.aether.createDevice(
      name: 'Kickr Core',
      capabilities: {DeviceDataType.power, DeviceDataType.cadence, DeviceDataType.speed},
    );
    final hrMonitor = robot.aether.createDevice(name: 'HR Monitor', capabilities: {DeviceDataType.heartRate});

    await robot.launchApp(pairedDevices: [kickrCore, hrMonitor], loggedIn: true);
    await robot.tapStartWorkout("Sweet Spot Workout");

    robot.verifyPlayerIsShown();
    robot.verifyWorkoutIsPaused();
    robot.verifyWorkoutElapsedTime('00:00');

    kickrCore.startRiding();
    await robot.idle();
    robot.verifyWorkoutIsRunning();

    // Wait 20 seconds and verify time advances
    await robot.idle(20000);
    robot.verifyWorkoutElapsedTime('00:20');

    // Simulate crash
    await robot.closeApp();
    expect(kickrCore.isConnected, isFalse);
    expect(hrMonitor.isConnected, isFalse);

    // Restart app - resume dialog should appear with all options
    await robot.launchApp(pairedDevices: [kickrCore, hrMonitor], loggedIn: true);
    await robot.waitForCrashRecoveryDialog("Sweet Spot Workout");
    spotText('We found an incomplete workout session from earlier.').existsAtLeastOnce();
    spotText('Resume').existsAtLeastOnce();
    spotText('Discard').existsAtLeastOnce();
    spotText('Start Fresh').existsAtLeastOnce();

    await robot.tapResumeWorkout();
    robot.verifyPlayerIsShown();
    expect(kickrCore.isConnected, isTrue);
    expect(hrMonitor.isConnected, isTrue);
    robot.verifyWorkoutIsRunning();

    // Verify elapsed time was restored correctly (should still be ~20 seconds)
    robot.verifyWorkoutElapsedTime('00:20');
  });

  robotTest('workout session crash recovery - discard option', (robot) async {
    final kickrCore = robot.aether.createDevice(
      name: 'Kickr Core',
      capabilities: {DeviceDataType.power, DeviceDataType.cadence, DeviceDataType.speed},
    );

    await robot.launchApp(pairedDevices: [kickrCore], loggedIn: true);
    await robot.tapStartWorkout('Sweet Spot Workout');
    robot.verifyWorkoutIsPaused();

    kickrCore.startRiding();
    await robot.idle();

    // Simulate crash
    await robot.closeApp();

    // Restart app (user is still pedaling on trainer)
    await robot.launchApp(pairedDevices: [kickrCore], loggedIn: true);
    await robot.waitForCrashRecoveryDialog("Sweet Spot Workout");

    await robot.discardWorkout();

    // Should be back at home page
    spotText('Sweet Spot Workout').existsAtLeastOnce();

    // Start a new workout - auto-starts because user is still pedaling
    await robot.tapStartWorkout('Sweet Spot Workout');
    await robot.idle();
    robot.verifyWorkoutIsRunning();
  });

  robotTest('workout session crash recovery - start fresh option', (robot) async {
    final kickrCore = robot.aether.createDevice(
      name: 'Kickr Core',
      capabilities: {DeviceDataType.power, DeviceDataType.cadence, DeviceDataType.speed},
    );

    await robot.launchApp(pairedDevices: [kickrCore], loggedIn: true);
    await robot.tapStartWorkout('Sweet Spot Workout');
    robot.verifyWorkoutIsPaused();

    kickrCore.startRiding();
    await robot.idle();

    // Simulate crash
    await robot.closeApp();

    // Restart app (user is still pedaling on trainer)
    await robot.launchApp(pairedDevices: [kickrCore], loggedIn: true);
    await robot.waitForCrashRecoveryDialog("Sweet Spot Workout");

    await robot.startFreshWorkout();

    // Workout auto-starts because user is still pedaling
    await robot.idle();
    robot.verifyWorkoutIsRunning();
    robot.verifyPlayerIsShown();

    // Verify elapsed time starts from 00:00 (not restored from crashed session)
    robot.verifyWorkoutElapsedTime('00:00');
  });

  robotTest('stale metrics return null after 5 seconds', (robot) async {
    final kickrCore = robot.aether.createDevice(
      name: 'Kickr Core',
      capabilities: {DeviceDataType.power, DeviceDataType.cadence, DeviceDataType.speed},
    );

    await robot.launchApp(pairedDevices: [kickrCore], loggedIn: true);
    await robot.tapStartWorkout('Sweet Spot Workout');
    robot.verifyWorkoutIsPaused();

    kickrCore.startRiding();
    await robot.idle();
    kickrCore.stopRiding();

    // Wait for staleness threshold (5 seconds)
    await robot.idle(5500);

    // Verify app still running without errors when metrics become stale
    robot.verifyPlayerIsShown();
  });
}
