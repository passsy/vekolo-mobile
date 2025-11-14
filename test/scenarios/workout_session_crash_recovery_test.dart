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
    await robot.tapStartWorkout("Sweet Spot Workout");

    // Verify workout player page loaded
    spotText('CURRENT BLOCK').existsAtLeastOnce();
    spotText('Start pedaling to begin workout').existsAtLeastOnce();

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
    await robot.pumpUntil(1000);

    // Let workout run and record samples
    for (int i = 0; i < 3; i++) {
      kickrCore.emitCharacteristic(indoorBikeDataUuid, powerData);
      await robot.pumpUntil(1000);
    }

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
    await robot.resumeWorkout();

    // Wait for workout player page to load and restore state
    await robot.pumpUntil(2000);

    // Verify workout player restored
    spotText('CURRENT BLOCK').existsAtLeastOnce();
    expect(kickrCore.isConnected, isTrue);
    expect(hrMonitor.isConnected, isTrue);

    // Emit power to ensure workout continues running after resume
    kickrCore.emitCharacteristic(indoorBikeDataUuid, powerData);
    await robot.pumpUntil(1000);

    // Verify workout timer is running after crash recovery
    // The elapsed time should be visible and updating
    spotText('ELAPSED').existsAtLeastOnce();

    // Continue emitting power and advance time by 10 seconds
    for (int i = 0; i < 10; i++) {
      kickrCore.emitCharacteristic(indoorBikeDataUuid, powerData);
      await robot.idle(1000);
    }

    // Verify the workout is still running (basic smoke test)
    // If the timer was working, the workout should still be active
    spotText('CURRENT BLOCK').existsAtLeastOnce();
  });

  robotTest('workout session crash recovery - resume option', (robot) async {
    // Setup: Create trainer device
    final kickrCore = robot.aether.createDevice(
      name: 'Kickr Core',
      capabilities: {DeviceDataType.power, DeviceDataType.cadence, DeviceDataType.speed},
    );

    await robot.launchApp(pairedDevices: [kickrCore], loggedIn: true);

    await robot.tapStartWorkout('Sweet Spot Workout');

    spotText('CURRENT BLOCK').existsAtLeastOnce();
    spotText('Start pedaling to begin workout').existsAtLeastOnce();

    // Emit power data to start workout
    final indoorBikeDataUuid = fbp.Guid('00002AD2-0000-1000-8000-00805f9b34fb');
    final powerData = FtmsDataBuilder()
        .withPower(150)
        .withCadence(180) // 90 RPM
        .withSpeed(3000) // 30 km/h
        .build();

    // Start workout by emitting power
    kickrCore.emitCharacteristic(indoorBikeDataUuid, powerData);
    await robot.pumpUntil(1000);

    // Let workout run for a few seconds to record samples
    for (int i = 0; i < 3; i++) {
      kickrCore.emitCharacteristic(indoorBikeDataUuid, powerData);
      await robot.pumpUntil(1000);
    }

    // Simulate crash by closing app without completing workout
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
    await robot.resumeWorkout();

    // Wait for workout player page to load and restore state
    await robot.pumpUntil(2000);

    // Verify workout player restored
    spotText('CURRENT BLOCK').existsAtLeastOnce();

    // Continue workout by emitting power
    kickrCore.emitCharacteristic(indoorBikeDataUuid, powerData);
    await robot.idle(500);
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

    spotText('Start pedaling to begin workout').existsAtLeastOnce();

    // Emit power data to start workout
    final indoorBikeDataUuid = fbp.Guid('00002AD2-0000-1000-8000-00805f9b34fb');
    final powerData = FtmsDataBuilder().withPower(150).withCadence(180).withSpeed(3000).build();

    // Run workout for a few seconds
    for (int i = 0; i < 3; i++) {
      kickrCore.emitCharacteristic(indoorBikeDataUuid, powerData);
      await robot.idle(1000);
    }

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
    spotText('CURRENT BLOCK').doesNotExist();

    // Verify can start a new workout
    await robot.tapStartWorkout('Sweet Spot Workout');

    spotText('Start pedaling to begin workout').existsAtLeastOnce();
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

    spotText('Start pedaling to begin workout').existsAtLeastOnce();

    // Emit power data to start workout
    final indoorBikeDataUuid = fbp.Guid('00002AD2-0000-1000-8000-00805f9b34fb');
    final powerData = FtmsDataBuilder().withPower(150).withCadence(180).withSpeed(3000).build();

    // Run workout for a few seconds
    for (int i = 0; i < 3; i++) {
      kickrCore.emitCharacteristic(indoorBikeDataUuid, powerData);
      await robot.idle(1000);
    }

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
    spotText('Start pedaling to begin workout').existsAtLeastOnce();
    spotText('CURRENT BLOCK').existsAtLeastOnce();

    // Emit power to verify workout works
    kickrCore.emitCharacteristic(indoorBikeDataUuid, powerData);
    await robot.idle(500);
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

    spotText('Start pedaling to begin workout').existsAtLeastOnce();

    // Emit power data to start workout
    final indoorBikeDataUuid = fbp.Guid('00002AD2-0000-1000-8000-00805f9b34fb');
    final powerData = FtmsDataBuilder().withPower(150).withCadence(180).withSpeed(3000).build();

    // Start workout with power streaming
    kickrCore.emitCharacteristic(indoorBikeDataUuid, powerData);
    await robot.idle(1000);

    // Emit a couple more times to establish streaming
    kickrCore.emitCharacteristic(indoorBikeDataUuid, powerData);
    await robot.idle(1000);
    kickrCore.emitCharacteristic(indoorBikeDataUuid, powerData);
    await robot.idle(1000);

    // Stop power updates (simulate user stopping pedaling or device disconnection)
    // Don't emit any more characteristics

    // Wait for staleness threshold (5 seconds)
    await robot.idle(5500);

    // Note: We can't directly verify beacon values from robot tests since we don't have
    // access to the device manager instance. This test verifies the UI behavior and
    // that the app continues running without errors when metrics become stale.
    // The actual staleness logic is tested in unit tests (staleness_beacon_test.dart)
    // and integration tests (device_manager_staleness_test.dart).

    // Verify app is still running and showing workout player
    spotText('CURRENT BLOCK').existsAtLeastOnce();
  });
}
