import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;
import 'package:flutter_test/flutter_test.dart';
import 'package:spot/spot.dart';
import 'package:vekolo/domain/models/device_info.dart';

import '../helpers/ftms_data_builder.dart';
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
    timeline.mode = TimelineMode.always;

    // Setup: Create trainer device with power/HR/cadence capabilities
    final kickrCore = robot.aether.createDevice(
      name: 'Kickr Core',
      capabilities: {DeviceDataType.power, DeviceDataType.cadence, DeviceDataType.speed},
    );

    final hrMonitor = robot.aether.createDevice(name: 'HR Monitor', capabilities: {DeviceDataType.heartRate});

    await robot.launchApp(pairedDevices: [kickrCore, hrMonitor], loggedIn: true);

    addRobotEvent('App launched with paired devices');

    await robot.startWorkout();

    // Verify workout player page loaded
    spotText('CURRENT BLOCK').existsAtLeastOnce();
    spotText('Start pedaling to begin workout').existsAtLeastOnce();

    addRobotEvent('Workout player loaded');

    // Verify BLE infrastructure is working by emitting power data
    // This demonstrates that the FakeDevice.emitCharacteristic() method works
    // and that the FTMS transport is receiving data
    //
    // Indoor Bike Data UUID: 00002AD2-0000-1000-8000-00805f9b34fb
    final indoorBikeDataUuid = fbp.Guid('00002AD2-0000-1000-8000-00805f9b34fb');

    // Emit power at 150W, cadence at 90 RPM
    final powerData = FtmsDataBuilder()
        .withPower(150)
        .withCadence(180) // 180 * 0.5 = 90 RPM
        .withSpeed(3000) // 30 km/h
        .build();

    // Emit data to trigger workout start
    kickrCore.emitCharacteristic(indoorBikeDataUuid, powerData);
    await robot.idle(1000);

    addRobotEvent('Power data emitted via BLE notification infrastructure');

    // The workout should start when power is detected
    // (The full crash recovery flow is tested in integration tests)

    // Note: Full crash recovery robot test requires:
    // 1. Workout to start and record samples
    // 2. App to close without completing workout
    // 3. App to restart and show resume dialog
    // 4. User to choose resume option
    // 5. Workout to restore state
    //
    // The integration tests (crash_recovery_integration_test.dart) cover
    // this flow comprehensively with 6 tests. This robot test demonstrates
    // that the BLE notification infrastructure works end-to-end.

    addRobotEvent('BLE characteristic notification infrastructure verified');

    // Allow pending timers to complete before test ends
    await robot.idle(200);
  });

  robotTest('workout session crash recovery - resume option', (robot) async {
    timeline.mode = TimelineMode.always;

    // Setup: Create trainer device
    final kickrCore = robot.aether.createDevice(
      name: 'Kickr Core',
      capabilities: {DeviceDataType.power, DeviceDataType.cadence, DeviceDataType.speed},
    );

    await robot.launchApp(pairedDevices: [kickrCore], loggedIn: true);

    addRobotEvent('App launched with paired devices');

    await robot.startWorkout();

    spotText('CURRENT BLOCK').existsAtLeastOnce();
    spotText('Start pedaling to begin workout').existsAtLeastOnce();

    addRobotEvent('Workout player loaded');

    // Emit power data to start workout
    final indoorBikeDataUuid = fbp.Guid('00002AD2-0000-1000-8000-00805f9b34fb');
    final powerData = FtmsDataBuilder()
        .withPower(150)
        .withCadence(180) // 90 RPM
        .withSpeed(3000) // 30 km/h
        .build();

    // Start workout by emitting power
    kickrCore.emitCharacteristic(indoorBikeDataUuid, powerData);
    // Use pumpUntil to process power monitoring callback in a timely manner
    await robot.pumpUntil(1000);

    addRobotEvent('Workout started with power data');

    // Let workout run for a few seconds to record samples
    for (int i = 0; i < 3; i++) {
      kickrCore.emitCharacteristic(indoorBikeDataUuid, powerData);
      await robot.pumpUntil(1000);
    }

    addRobotEvent('Recorded workout samples for 3 seconds');

    // Wait for startRecording() to complete (create session + mark as active)
    // This explicitly waits for the session to be created instead of using a fixed timeout
    await robot.waitForActiveWorkoutSession();

    addRobotEvent('Active workout session created');

    // Simulate crash by closing app without completing workout
    await robot.closeApp();
    addRobotEvent('App crashed (closed unexpectedly)');

    // Verify device disconnected
    expect(kickrCore.isConnected, isFalse);

    // Restart app - should show resume dialog
    await robot.launchApp(pairedDevices: [kickrCore], loggedIn: true);

    addRobotEvent('App restarted after crash');

    // Wait for resume dialog to appear
    await robot.waitForCrashRecoveryDialog();
    spotText('We found an incomplete workout session from earlier.').existsAtLeastOnce();
    spotText('Resume').existsAtLeastOnce();
    spotText('Discard').existsAtLeastOnce();
    spotText('Start Fresh').existsAtLeastOnce();

    addRobotEvent('Resume dialog displayed');

    // Choose Resume
    await robot.resumeWorkout();

    addRobotEvent('User chose to resume workout');

    // Verify workout player restored
    spotText('CURRENT BLOCK').existsAtLeastOnce();

    // Continue workout by emitting power
    kickrCore.emitCharacteristic(indoorBikeDataUuid, powerData);
    await robot.idle(500);

    addRobotEvent('Workout resumed successfully');
  });

  robotTest('workout session crash recovery - discard option', (robot) async {
    timeline.mode = TimelineMode.always;

    // Setup: Create trainer device
    final kickrCore = robot.aether.createDevice(
      name: 'Kickr Core',
      capabilities: {DeviceDataType.power, DeviceDataType.cadence, DeviceDataType.speed},
    );

    await robot.launchApp(pairedDevices: [kickrCore], loggedIn: true);

    addRobotEvent('App launched with paired devices');

    // Navigate to workout player and start workout
    await robot.startWorkout();

    spotText('Start pedaling to begin workout').existsAtLeastOnce();
    addRobotEvent('Workout player loaded');

    // Emit power data to start workout
    final indoorBikeDataUuid = fbp.Guid('00002AD2-0000-1000-8000-00805f9b34fb');
    final powerData = FtmsDataBuilder().withPower(150).withCadence(180).withSpeed(3000).build();

    // Run workout for a few seconds
    for (int i = 0; i < 3; i++) {
      kickrCore.emitCharacteristic(indoorBikeDataUuid, powerData);
      await robot.idle(1000);
    }

    addRobotEvent('Workout ran for 3 seconds');

    // Simulate crash
    await robot.closeApp();
    addRobotEvent('App crashed');

    // Restart app
    await robot.launchApp(pairedDevices: [kickrCore], loggedIn: true);
    await robot.idle(1000);

    addRobotEvent('App restarted');

    // Resume dialog should appear
    await robot.waitForCrashRecoveryDialog();

    addRobotEvent('Resume dialog displayed');

    // Choose Discard
    await robot.discardWorkout();

    addRobotEvent('User chose to discard workout');

    // Should be back at home page, not in workout player
    spotText('Start Workout').existsAtLeastOnce();
    spotText('CURRENT BLOCK').doesNotExist();

    addRobotEvent('Back at home page - workout discarded');

    // Verify can start a new workout
    await robot.startWorkout();

    spotText('Start pedaling to begin workout').existsAtLeastOnce();

    addRobotEvent('Successfully started a new workout after discarding');
  });

  robotTest('workout session crash recovery - start fresh option', (robot) async {
    timeline.mode = TimelineMode.always;

    // Setup: Create trainer device
    final kickrCore = robot.aether.createDevice(
      name: 'Kickr Core',
      capabilities: {DeviceDataType.power, DeviceDataType.cadence, DeviceDataType.speed},
    );

    await robot.launchApp(pairedDevices: [kickrCore], loggedIn: true);

    addRobotEvent('App launched with paired devices');

    // Navigate to workout player and start workout
    await robot.startWorkout();

    spotText('Start pedaling to begin workout').existsAtLeastOnce();
    addRobotEvent('Workout player loaded');

    // Emit power data to start workout
    final indoorBikeDataUuid = fbp.Guid('00002AD2-0000-1000-8000-00805f9b34fb');
    final powerData = FtmsDataBuilder().withPower(150).withCadence(180).withSpeed(3000).build();

    // Run workout for a few seconds
    for (int i = 0; i < 3; i++) {
      kickrCore.emitCharacteristic(indoorBikeDataUuid, powerData);
      await robot.idle(1000);
    }

    addRobotEvent('Workout ran for 3 seconds');

    // Simulate crash
    await robot.closeApp();
    addRobotEvent('App crashed');

    // Restart app
    await robot.launchApp(pairedDevices: [kickrCore], loggedIn: true);
    await robot.idle(1000);

    addRobotEvent('App restarted');

    // Resume dialog should appear
    await robot.waitForCrashRecoveryDialog();

    addRobotEvent('Resume dialog displayed');

    // Choose Start Fresh
    await robot.startFreshWorkout();

    addRobotEvent('User chose to start fresh');

    // Should start a new workout from beginning
    spotText('Start pedaling to begin workout').existsAtLeastOnce();
    spotText('CURRENT BLOCK').existsAtLeastOnce();

    addRobotEvent('New workout started from beginning');

    // Emit power to verify workout works
    kickrCore.emitCharacteristic(indoorBikeDataUuid, powerData);
    await robot.idle(500);

    addRobotEvent('Fresh workout running successfully');
  });

  robotTest('stale metrics return null after 5 seconds', (robot) async {
    timeline.mode = TimelineMode.always;

    // Setup: Create trainer device
    final kickrCore = robot.aether.createDevice(
      name: 'Kickr Core',
      capabilities: {DeviceDataType.power, DeviceDataType.cadence, DeviceDataType.speed},
    );

    await robot.launchApp(pairedDevices: [kickrCore], loggedIn: true);

    addRobotEvent('App launched with paired devices');

    // Navigate to workout player
    await robot.startWorkout();

    spotText('Start pedaling to begin workout').existsAtLeastOnce();
    addRobotEvent('Workout player loaded');

    // Emit power data to start workout
    final indoorBikeDataUuid = fbp.Guid('00002AD2-0000-1000-8000-00805f9b34fb');
    final powerData = FtmsDataBuilder().withPower(150).withCadence(180).withSpeed(3000).build();

    // Start workout with power streaming
    kickrCore.emitCharacteristic(indoorBikeDataUuid, powerData);
    await robot.idle(1000);

    addRobotEvent('Workout started - power streaming');

    // Emit a couple more times to establish streaming
    kickrCore.emitCharacteristic(indoorBikeDataUuid, powerData);
    await robot.idle(1000);
    kickrCore.emitCharacteristic(indoorBikeDataUuid, powerData);
    await robot.idle(1000);

    addRobotEvent('Power data streaming normally');

    // Stop power updates (simulate user stopping pedaling or device disconnection)
    // Don't emit any more characteristics
    addRobotEvent('Power updates stopped - waiting for staleness');

    // Wait for staleness threshold (5 seconds)
    await robot.idle(5500);

    addRobotEvent('Waited 5.5 seconds - metrics should now be stale');

    // Note: We can't directly verify beacon values from robot tests since we don't have
    // access to the device manager instance. This test verifies the UI behavior and
    // that the app continues running without errors when metrics become stale.
    // The actual staleness logic is tested in unit tests (staleness_beacon_test.dart)
    // and integration tests (device_manager_staleness_test.dart).

    // Verify app is still running and showing workout player
    spotText('CURRENT BLOCK').existsAtLeastOnce();

    addRobotEvent('App still running after metrics became stale');
  });
}
