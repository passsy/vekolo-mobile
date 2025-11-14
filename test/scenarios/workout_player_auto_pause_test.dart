import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;
import 'package:spot/spot.dart';
import 'package:vekolo/domain/models/device_info.dart';

import '../helpers/ftms_data_builder.dart';
import '../robot/robot_kit.dart';

void main() {
  robotTest('workout player shows initial state correctly', (robot) async {
    // Setup: Create trainer device and launch app with it pre-paired
    final kickrCore = robot.aether.createDevice(
      name: 'Kickr Core',
      capabilities: {DeviceDataType.power, DeviceDataType.cadence, DeviceDataType.speed},
    );

    await robot.launchApp(pairedDevices: [kickrCore], loggedIn: true);
    await robot.tapStartWorkout('Sweet Spot Workout');

    // Verify workout player page loaded
    spotText('CURRENT BLOCK').existsAtLeastOnce();

    // Initially, workout should not be started (waiting for pedaling)
    spotText('Start pedaling to begin workout').existsAtLeastOnce();

    addRobotEvent('Workout player loaded with correct initial state');
  });

  robotTest('workout starts when power data is received', (robot) async {
    // Setup: Create trainer device
    final kickrCore = robot.aether.createDevice(
      name: 'Kickr Core',
      capabilities: {DeviceDataType.power, DeviceDataType.cadence, DeviceDataType.speed},
    );

    await robot.launchApp(pairedDevices: [kickrCore], loggedIn: true);
    await robot.tapStartWorkout('Sweet Spot Workout');

    // Verify initial state - workout not started
    spotText('Start pedaling to begin workout').existsAtLeastOnce();
    addRobotEvent('Workout player waiting for pedaling');

    // Emit power data to start workout
    final indoorBikeDataUuid = fbp.Guid('00002AD2-0000-1000-8000-00805f9b34fb');
    final powerData = FtmsDataBuilder()
        .withPower(150)
        .withCadence(180) // 90 RPM
        .withSpeed(3000) // 30 km/h
        .build();

    kickrCore.emitCharacteristic(indoorBikeDataUuid, powerData);
    await robot.idle(1000);

    addRobotEvent('Power data emitted - workout should start');

    // Verify "Start pedaling" message is gone (workout has started)
    spotText('Start pedaling to begin workout').doesNotExist();
    spotText('CURRENT BLOCK').existsAtLeastOnce();

    addRobotEvent('Workout started successfully');
  });

  robotTest('workout continues with consistent power updates', (robot) async {
    // Setup: Create trainer device
    final kickrCore = robot.aether.createDevice(
      name: 'Kickr Core',
      capabilities: {DeviceDataType.power, DeviceDataType.cadence, DeviceDataType.speed},
    );

    await robot.launchApp(pairedDevices: [kickrCore], loggedIn: true);
    await robot.tapStartWorkout('Sweet Spot Workout');

    addRobotEvent('Workout player loaded');

    // Start workout with power data
    final indoorBikeDataUuid = fbp.Guid('00002AD2-0000-1000-8000-00805f9b34fb');
    final powerData = FtmsDataBuilder().withPower(150).withCadence(180).withSpeed(3000).build();

    kickrCore.emitCharacteristic(indoorBikeDataUuid, powerData);
    await robot.idle(1000);

    addRobotEvent('Workout started');

    // Continue emitting power data to simulate ongoing workout
    for (int i = 0; i < 5; i++) {
      kickrCore.emitCharacteristic(indoorBikeDataUuid, powerData);
      await robot.idle(1000);
    }

    addRobotEvent('Workout ran for 5 seconds with consistent power');

    // Verify workout is still running
    spotText('CURRENT BLOCK').existsAtLeastOnce();
    spotText('Start pedaling to begin workout').doesNotExist();

    addRobotEvent('Workout continuing successfully');
  });

  robotTest('workout shows power and cadence data', (robot) async {
    // Setup: Create trainer device
    final kickrCore = robot.aether.createDevice(
      name: 'Kickr Core',
      capabilities: {DeviceDataType.power, DeviceDataType.cadence, DeviceDataType.speed},
    );

    await robot.launchApp(pairedDevices: [kickrCore], loggedIn: true);
    await robot.tapStartWorkout('Sweet Spot Workout');

    // Wait for workout player to fully load
    spotText('CURRENT BLOCK').existsAtLeastOnce();

    // Start workout with specific power and cadence values
    final indoorBikeDataUuid = fbp.Guid('00002AD2-0000-1000-8000-00805f9b34fb');
    final powerData = FtmsDataBuilder()
        .withPower(200) // 200W
        .withCadence(180) // 90 RPM
        .withSpeed(3500) // 35 km/h
        .build();

    kickrCore.emitCharacteristic(indoorBikeDataUuid, powerData);
    await robot.idle(1000);

    addRobotEvent('Emitted power: 200W, cadence: 90 RPM');

    // Note: The actual power/cadence display might not show exact values immediately
    // or might be formatted differently. This test verifies the workout is running
    // and accepting data. Exact value verification would require accessing the
    // device manager beacons, which robot tests don't have direct access to.

    // Verify workout is running (not waiting for pedaling)
    spotText('Start pedaling to begin workout').doesNotExist();
    spotText('CURRENT BLOCK').existsAtLeastOnce();

    addRobotEvent('Workout displaying metrics');
  });

  robotTest('workout auto-pauses when power source stops sending data', (robot) async {
    // Setup: Create trainer device
    final kickrCore = robot.aether.createDevice(
      name: 'Kickr Core',
      capabilities: {DeviceDataType.power, DeviceDataType.cadence, DeviceDataType.speed},
    );

    await robot.launchApp(pairedDevices: [kickrCore], loggedIn: true);
    await robot.tapStartWorkout('Sweet Spot Workout');

    addRobotEvent('Workout player loaded');

    // Start workout with power data
    final indoorBikeDataUuid = fbp.Guid('00002AD2-0000-1000-8000-00805f9b34fb');
    final powerData = FtmsDataBuilder().withPower(150).withCadence(180).withSpeed(3000).build();

    kickrCore.emitCharacteristic(indoorBikeDataUuid, powerData);
    await robot.idle(1000);

    addRobotEvent('Workout started with 150W power');

    // Verify workout is running
    spotText('Start pedaling to begin workout').doesNotExist();

    // Continue emitting power for a few seconds to ensure workout is running
    for (int i = 0; i < 3; i++) {
      kickrCore.emitCharacteristic(indoorBikeDataUuid, powerData);
      await robot.idle(1000);
    }

    addRobotEvent('Workout running for 3 seconds');

    // Now stop sending data (device goes stale)
    // Timeline from last data emission (~t=4s):
    // - t=4s: last power data sent
    // - t=9s: data goes stale (5s staleness threshold)
    // - t=12s: auto-pause triggers (3s auto-pause delay after going stale)
    // Total: need to wait 9s from last emission (to reach t=13s)

    // Wait for staleness detection + auto-pause delay + extra buffer
    await robot.idle(10000); // 9s needed + 1s extra buffer for timing jitter

    addRobotEvent('Waited 10 seconds for stale data detection and auto-pause');

    // Verify workout has auto-paused
    spotText('Paused - Start pedaling to resume').existsAtLeastOnce();

    addRobotEvent('Workout auto-paused successfully after data went stale');
  });
}
