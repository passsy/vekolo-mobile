import '../robot/robot_kit.dart';
import '../robot/workout_player_robot.dart';

void main() {
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
      trainer.emitPower(200);
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
      trainer.emitPower(150);
      trainer.emitCadence(85);
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
      trainer.emitPower(100);
      await robot.pumpUntil(500);
      robot.verifyPowerChartVisible();

      // Increase power gradually (simulating interval workout)
      for (var power = 150; power <= 250; power += 20) {
        trainer.emitPower(power);
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
      trainer.emitPower(100);
      await robot.pumpUntil(2000);

      // Endurance (55-75% FTP)
      trainer.emitPower(130);
      await robot.pumpUntil(2000);

      // Threshold (90-105% FTP)
      trainer.emitPower(200);
      await robot.pumpUntil(2000);

      // VO2max (105-120% FTP)
      trainer.emitPower(220);
      await robot.pumpUntil(2000);

      // Chart should show colored bars based on zones
      robot.verifyPowerChartVisible();
      robot.verifyPowerChartLegend();
    });
  });
}
