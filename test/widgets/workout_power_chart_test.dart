import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;
import 'package:flutter_test/flutter_test.dart';
import 'package:spot/spot.dart';
import 'package:vekolo/domain/models/device_info.dart';
import 'package:vekolo/pages/home_page_v2/widgets/workout_interval_bars.dart';
import 'package:vekolo/widgets/workout_screen_content.dart';

import '../helpers/ftms_data_builder.dart';
import '../robot/robot_kit.dart';

void main() {
  // FTMS Indoor Bike Data UUID
  final indoorBikeDataUuid = fbp.Guid('00002AD2-0000-1000-8000-00805f9b34fb');

  group('Workout Screen Visualization', () {
    robotTest('displays interval bars when workout is running', (robot) async {
      // Create a trainer device
      final trainer = robot.aether.createDevice(
        name: 'KICKR CORE',
        capabilities: {DeviceDataType.power, DeviceDataType.cadence, DeviceDataType.speed},
      );

      // Launch app with paired trainer
      await robot.launchApp(loggedIn: true, pairedDevices: [trainer]);

      // Start a workout
      await robot.tapStartWorkout('Sweet Spot');

      // Start pedaling to begin workout
      final data = FtmsDataBuilder().withPower(200).build();
      trainer.emitCharacteristic(indoorBikeDataUuid, data);
      await robot.idle();

      // Verify workout screen is visible with interval visualization
      spot<WorkoutScreenContent>().existsOnce();
      spot<WorkoutIntervalBars>().existsAtLeastOnce();
    });

    robotTest('shows start pedaling message when workout not started', (robot) async {
      // Create a trainer device
      final trainer = robot.aether.createDevice(
        name: 'KICKR CORE',
        capabilities: {DeviceDataType.power, DeviceDataType.cadence, DeviceDataType.speed},
      );

      // Launch app with paired trainer
      await robot.launchApp(loggedIn: true, pairedDevices: [trainer]);

      // Start a workout but don't pedal
      await robot.tapStartWorkout('Sweet Spot');

      // Verify waiting message is shown (no power data yet)
      spotText('Start pedaling to begin workout').existsOnce();
    });

    robotTest('displays power data when pedaling', (robot) async {
      // Create a trainer device
      final trainer = robot.aether.createDevice(
        name: 'KICKR CORE',
        capabilities: {DeviceDataType.power, DeviceDataType.cadence, DeviceDataType.speed},
      );

      // Launch app with paired trainer
      await robot.launchApp(loggedIn: true, pairedDevices: [trainer]);

      // Start a workout
      await robot.tapStartWorkout('Sweet Spot');

      // Start pedaling
      final data = FtmsDataBuilder().withPower(150).withCadence(170).build(); // 170 * 0.5 = 85 RPM
      trainer.emitCharacteristic(indoorBikeDataUuid, data);
      await robot.idle();

      // Verify workout screen is visible with interval visualization
      spot<WorkoutScreenContent>().existsOnce();
      spot<WorkoutIntervalBars>().existsAtLeastOnce();

      // Verify metrics labels are present
      spotText('WATT').existsAtLeastOnce();
      spotText('RPM').existsAtLeastOnce();
      spotText('HR').existsAtLeastOnce();
    });

    robotTest('updates display as power changes over time', (robot) async {
      // Create a trainer device
      final trainer = robot.aether.createDevice(
        name: 'KICKR CORE',
        capabilities: {DeviceDataType.power, DeviceDataType.cadence, DeviceDataType.speed},
      );

      // Launch app with paired trainer
      await robot.launchApp(loggedIn: true, pairedDevices: [trainer]);

      // Start a workout
      await robot.tapStartWorkout('Sweet Spot');

      // Start with low power
      var data = FtmsDataBuilder().withPower(100).build();
      trainer.emitCharacteristic(indoorBikeDataUuid, data);
      await robot.idle();
      spot<WorkoutScreenContent>().existsOnce();

      // Increase power gradually (simulating interval workout)
      for (var power = 150; power <= 250; power += 50) {
        data = FtmsDataBuilder().withPower(power).build();
        trainer.emitCharacteristic(indoorBikeDataUuid, data);
        await robot.idle();
      }

      // Workout screen should still be visible with interval bars
      spot<WorkoutScreenContent>().existsOnce();
      spot<WorkoutIntervalBars>().existsAtLeastOnce();
    });

    robotTest('shows workout with power zones visualization', (robot) async {
      // Create a trainer device
      final trainer = robot.aether.createDevice(
        name: 'KICKR CORE',
        capabilities: {DeviceDataType.power, DeviceDataType.cadence, DeviceDataType.speed},
      );

      // Launch app with paired trainer (user has FTP set via fake auth)
      await robot.launchApp(loggedIn: true, pairedDevices: [trainer]);

      // Start a workout
      await robot.tapStartWorkout('Sweet Spot');

      // Emit power at different zones
      // Recovery (< 55% FTP) - assuming FTP is 200
      var data = FtmsDataBuilder().withPower(100).build();
      trainer.emitCharacteristic(indoorBikeDataUuid, data);
      await robot.idle();

      // Endurance (55-75% FTP)
      data = FtmsDataBuilder().withPower(130).build();
      trainer.emitCharacteristic(indoorBikeDataUuid, data);
      await robot.idle();

      // Threshold (90-105% FTP)
      data = FtmsDataBuilder().withPower(200).build();
      trainer.emitCharacteristic(indoorBikeDataUuid, data);
      await robot.idle();

      // VO2max (105-120% FTP)
      data = FtmsDataBuilder().withPower(220).build();
      trainer.emitCharacteristic(indoorBikeDataUuid, data);
      await robot.idle();

      // Workout screen should show interval visualization
      spot<WorkoutScreenContent>().existsOnce();
      spot<WorkoutIntervalBars>().existsAtLeastOnce();
    });
  });
}
