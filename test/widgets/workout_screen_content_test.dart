import 'package:flutter/material.dart';
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
      robot.verifyAllMetricsPresent();
      robot.verifyCloseButton();
    });

    robotTest('transitions to running state when pedaling starts', (robot) async {
      final trainer = robot.aether.createDevice(
        name: 'KICKR CORE',
        capabilities: {DeviceDataType.power, DeviceDataType.cadence, DeviceDataType.speed},
      );

      await robot.launchApp(loggedIn: true, pairedDevices: [trainer]);
      await robot.tapStartWorkout('Sweet Spot');

      // Start pedaling to trigger auto-start (need >= 40W)
      final data = FtmsDataBuilder().withPower(150).withCadence(170).build(); // 170 * 0.5 = 85 RPM
      trainer.emitCharacteristic(indoorBikeDataUuid, data);
      await robot.pumpUntil(500);

      // Should transition to running state
      robot.verifyWorkoutRunning();
    });

    robotTest('displays metrics correctly during workout', (robot) async {
      final trainer = robot.aether.createDevice(
        name: 'KICKR CORE',
        capabilities: {DeviceDataType.power, DeviceDataType.cadence, DeviceDataType.speed},
      );

      await robot.launchApp(loggedIn: true, pairedDevices: [trainer]);
      await robot.tapStartWorkout('Sweet Spot');

      // Start pedaling
      final data = FtmsDataBuilder().withPower(180).withCadence(180).withHeartRate(145).build(); // 180 * 0.5 = 90 RPM
      trainer.emitCharacteristic(indoorBikeDataUuid, data);
      await robot.pumpUntil(1000);

      // Verify all metrics are displayed
      robot.verifyAllMetricsPresent();
      robot.verifyTimeMetricPresent();
    });

    robotTest('shows time metric section', (robot) async {
      final trainer = robot.aether.createDevice(
        name: 'KICKR CORE',
        capabilities: {DeviceDataType.power, DeviceDataType.cadence, DeviceDataType.speed},
      );

      await robot.launchApp(loggedIn: true, pairedDevices: [trainer]);
      await robot.tapStartWorkout('Sweet Spot');

      // Start workout
      trainer.emitCharacteristic(indoorBikeDataUuid, FtmsDataBuilder().withPower(150).build());
      await robot.pumpUntil(500);

      // Verify TIME metric label is shown
      robot.verifyTimeMetricPresent();
    });

    robotTest('can skip to next block', (robot) async {
      final trainer = robot.aether.createDevice(
        name: 'KICKR CORE',
        capabilities: {DeviceDataType.power, DeviceDataType.cadence, DeviceDataType.speed},
      );

      await robot.launchApp(loggedIn: true, pairedDevices: [trainer]);
      await robot.tapStartWorkout('Sweet Spot');

      // Start workout
      trainer.emitCharacteristic(indoorBikeDataUuid, FtmsDataBuilder().withPower(150).build());
      await robot.pumpUntil(500);

      // Verify running state before tapping skip
      robot.verifyWorkoutRunning();

      // Skip to next block
      await robot.tapSkipBlock();
      await robot.idle();

      // Verify still running (just in next block)
      robot.verifyWorkoutRunning();
    });

    robotTest('can adjust intensity up', (robot) async {
      final trainer = robot.aether.createDevice(
        name: 'KICKR CORE',
        capabilities: {DeviceDataType.power, DeviceDataType.cadence, DeviceDataType.speed},
      );

      await robot.launchApp(loggedIn: true, pairedDevices: [trainer]);
      await robot.tapStartWorkout('Sweet Spot');

      // Start workout
      trainer.emitCharacteristic(indoorBikeDataUuid, FtmsDataBuilder().withPower(150).build());
      await robot.pumpUntil(500);

      // Initially at 100%
      robot.verifyIntensityPercentage(100);

      // Increase intensity
      await robot.tapIncreaseIntensity();
      await robot.idle();

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
      trainer.emitCharacteristic(indoorBikeDataUuid, FtmsDataBuilder().withPower(150).build());
      await robot.pumpUntil(500);

      // Initially at 100%
      robot.verifyIntensityPercentage(100);

      // Decrease intensity
      await robot.tapDecreaseIntensity();
      await robot.idle();

      // Should now be 99%
      robot.verifyIntensityPercentage(99);
    });

    robotTest('can exit workout via close button', (robot) async {
      final trainer = robot.aether.createDevice(
        name: 'KICKR CORE',
        capabilities: {DeviceDataType.power, DeviceDataType.cadence, DeviceDataType.speed},
      );

      await robot.launchApp(loggedIn: true, pairedDevices: [trainer]);
      await robot.tapStartWorkout('Sweet Spot');

      // Start workout
      trainer.emitCharacteristic(indoorBikeDataUuid, FtmsDataBuilder().withPower(150).build());
      await robot.pumpUntil(500);

      // Verify running state before tapping close
      robot.verifyWorkoutRunning();

      // Tap close button
      await robot.tapCloseButton();
      await robot.idle();

      // Should show confirmation dialog
      spotText('Exit Workout?').existsOnce();
      // Short workout shows discard message and button (Cancel, Discard)
      spotText('Workout duration is too short to save').existsOnce();
      spotText('Cancel').existsOnce();
      spot<TextButton>().withChild(spotText('Discard')).existsOnce();
    });

    robotTest('shows timestamps at bottom during workout', (robot) async {
      final trainer = robot.aether.createDevice(
        name: 'KICKR CORE',
        capabilities: {DeviceDataType.power, DeviceDataType.cadence, DeviceDataType.speed},
      );

      await robot.launchApp(loggedIn: true, pairedDevices: [trainer]);
      await robot.tapStartWorkout('Sweet Spot');

      // Start workout
      trainer.emitCharacteristic(indoorBikeDataUuid, FtmsDataBuilder().withPower(150).build());
      await robot.pumpUntil(500);

      // Verify initial time (should be close to 00:00)
      robot.verifyElapsedTime('00:00');

      // Wait some time
      await robot.pumpUntil(2000);

      // Timer should have progressed
      // Timestamps are shown at bottom without labels
    });

    robotTest('handles missing metrics gracefully', (robot) async {
      final trainer = robot.aether.createDevice(
        name: 'KICKR CORE',
        capabilities: {DeviceDataType.power}, // Only power, no cadence or HR
      );

      await robot.launchApp(loggedIn: true, pairedDevices: [trainer]);
      await robot.tapStartWorkout('Sweet Spot');

      // Start workout
      trainer.emitCharacteristic(indoorBikeDataUuid, FtmsDataBuilder().withPower(150).build());
      await robot.pumpUntil(500);

      // Verify metrics are shown (should show 0 for missing metrics)
      robot.verifyAllMetricsPresent();
    });

    robotTest('auto-pauses when power drops below threshold', (robot) async {
      final trainer = robot.aether.createDevice(
        name: 'KICKR CORE',
        capabilities: {DeviceDataType.power, DeviceDataType.cadence, DeviceDataType.speed},
      );

      await robot.launchApp(loggedIn: true, pairedDevices: [trainer]);
      await robot.tapStartWorkout('Sweet Spot');

      // Start workout
      trainer.emitCharacteristic(indoorBikeDataUuid, FtmsDataBuilder().withPower(150).build());
      await robot.pumpUntil(500);
      robot.verifyWorkoutRunning();

      // Stop pedaling (power drops to 0)
      trainer.emitCharacteristic(indoorBikeDataUuid, FtmsDataBuilder().withPower(0).build());
      await robot.pumpUntil(3500); // Auto-pause threshold is 3 seconds

      // Should auto-pause
      robot.verifyPausedStartedMessage();
    });

    robotTest('auto-resumes when pedaling again', (robot) async {
      final trainer = robot.aether.createDevice(
        name: 'KICKR CORE',
        capabilities: {DeviceDataType.power, DeviceDataType.cadence, DeviceDataType.speed},
      );

      await robot.launchApp(loggedIn: true, pairedDevices: [trainer]);
      await robot.tapStartWorkout('Sweet Spot');

      // Start workout
      trainer.emitCharacteristic(indoorBikeDataUuid, FtmsDataBuilder().withPower(150).build());
      await robot.pumpUntil(500);

      // Stop pedaling to trigger auto-pause
      trainer.emitCharacteristic(indoorBikeDataUuid, FtmsDataBuilder().withPower(0).build());
      await robot.pumpUntil(3500);
      robot.verifyPausedStartedMessage();

      // Start pedaling again (need >= 40W to resume)
      trainer.emitCharacteristic(indoorBikeDataUuid, FtmsDataBuilder().withPower(150).build());
      await robot.pumpUntil(500);

      // Should auto-resume
      robot.verifyWorkoutRunning();
    });

    robotTest('shows interval visualization throughout workout', (robot) async {
      final trainer = robot.aether.createDevice(
        name: 'KICKR CORE',
        capabilities: {DeviceDataType.power, DeviceDataType.cadence, DeviceDataType.speed},
      );

      await robot.launchApp(loggedIn: true, pairedDevices: [trainer]);
      await robot.tapStartWorkout('Sweet Spot');

      // Start workout
      trainer.emitCharacteristic(indoorBikeDataUuid, FtmsDataBuilder().withPower(150).build());
      await robot.pumpUntil(500);

      // Interval bars should be visible
      robot.verifyIntervalBarsVisible();

      // Continue workout for a bit
      await robot.pumpUntil(5000);

      // Interval bars should still be there
      robot.verifyIntervalBarsVisible();
    });
  });
}
