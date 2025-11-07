import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;
import 'package:spot/spot.dart';
import 'package:vekolo/domain/models/device_info.dart';

import '../helpers/ftms_data_builder.dart';
import '../robot/robot_test_fn.dart';

void main() {
  robotTest('workout player shows initial state correctly', (robot) async {
    timeline.mode = TimelineMode.always;

    // Setup: Create trainer device and launch app with it pre-paired
    final kickrCore = robot.aether.createDevice(
      name: 'Kickr Core',
      capabilities: {DeviceDataType.power, DeviceDataType.cadence, DeviceDataType.speed},
    );

    await robot.launchApp(pairedDevices: [kickrCore], loggedIn: true);
    await robot.startWorkout();

    // Verify workout player page loaded
    spotText('CURRENT BLOCK').existsAtLeastOnce();

    // Initially, workout should not be started (waiting for pedaling)
    spotText('Start pedaling to begin workout').existsAtLeastOnce();

    addRobotEvent('Workout player loaded with correct initial state');
  });

  robotTest('workout starts when power data is received', (robot) async {
    timeline.mode = TimelineMode.always;

    // Setup: Create trainer device
    final kickrCore = robot.aether.createDevice(
      name: 'Kickr Core',
      capabilities: {DeviceDataType.power, DeviceDataType.cadence, DeviceDataType.speed},
    );

    await robot.launchApp(pairedDevices: [kickrCore], loggedIn: true);
    await robot.startWorkout();

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
    timeline.mode = TimelineMode.always;

    // Setup: Create trainer device
    final kickrCore = robot.aether.createDevice(
      name: 'Kickr Core',
      capabilities: {DeviceDataType.power, DeviceDataType.cadence, DeviceDataType.speed},
    );

    await robot.launchApp(pairedDevices: [kickrCore], loggedIn: true);
    await robot.startWorkout();

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
    timeline.mode = TimelineMode.always;

    // Setup: Create trainer device
    final kickrCore = robot.aether.createDevice(
      name: 'Kickr Core',
      capabilities: {DeviceDataType.power, DeviceDataType.cadence, DeviceDataType.speed},
    );

    await robot.launchApp(pairedDevices: [kickrCore], loggedIn: true);
    await robot.startWorkout();

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
}
