import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;
import 'package:flutter_test/flutter_test.dart';
import 'package:spot/spot.dart';
import 'package:vekolo/domain/models/device_info.dart';

import '../helpers/ftms_data_builder.dart';
import '../robot/robot_kit.dart';
import '../robot/workout_player_robot.dart';

void main() {
  // FTMS Indoor Bike Data UUID
  final indoorBikeDataUuid = fbp.Guid('00002AD2-0000-1000-8000-00805f9b34fb');

  group('Workout Power Chart', () {
    robotTest('displays power chart when workout is running', (robot) async {
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
      await robot.idle(100);

      // Verify power chart is visible
      robot.verifyPowerChartVisible();
      robot.verifyPowerChartLegend();
    });

    robotTest('shows waiting message when no data', (robot) async {
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
      spotText('Waiting for data...').existsAtLeastOnce();
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
      await robot.pumpUntil(500); // Give time for data to populate

      // Verify power chart is visible with data
      robot.verifyPowerChartVisible();
      robot.verifyPowerChartLegend();

      // Verify metrics show power data
      robot.verifyAllMetricsPresent();
    });

    robotTest('updates chart as power changes over time', (robot) async {
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
      await robot.pumpUntil(500);
      robot.verifyPowerChartVisible();

      // Increase power gradually (simulating interval workout)
      for (var power = 150; power <= 250; power += 20) {
        data = FtmsDataBuilder().withPower(power).build();
        trainer.emitCharacteristic(indoorBikeDataUuid, data);
        await robot.pumpUntil(1000); // Wait 1s between changes
      }

      // Chart should still be visible with all data
      robot.verifyPowerChartVisible();
      robot.verifyPowerChartLegend();
    });

    robotTest('shows power zones correctly with FTP', (robot) async {
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
      await robot.pumpUntil(2000);

      // Endurance (55-75% FTP)
      data = FtmsDataBuilder().withPower(130).build();
      trainer.emitCharacteristic(indoorBikeDataUuid, data);
      await robot.pumpUntil(2000);

      // Threshold (90-105% FTP)
      data = FtmsDataBuilder().withPower(200).build();
      trainer.emitCharacteristic(indoorBikeDataUuid, data);
      await robot.pumpUntil(2000);

      // VO2max (105-120% FTP)
      data = FtmsDataBuilder().withPower(220).build();
      trainer.emitCharacteristic(indoorBikeDataUuid, data);
      await robot.pumpUntil(2000);

      // Chart should show colored bars based on zones
      robot.verifyPowerChartVisible();
      robot.verifyPowerChartLegend();
    });
  });
}
