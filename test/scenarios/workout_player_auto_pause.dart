import 'package:spot/spot.dart';
import 'package:vekolo/domain/models/device_info.dart';

import '../robot/robot_test_fn.dart';

void main() {
  // Note: These tests verify UI state and basic interactions.
  // Full auto-pause/resume behavior requires power data simulation which
  // is not yet implemented in the test infrastructure (FakeDevice.setPower).
  // The auto-pause logic is tested through manual testing and the implementation
  // is documented in lib/pages/workout_player_page.dart lines 111-200.

  robotTest('workout player shows initial state correctly', (robot) async {
    timeline.mode = TimelineMode.always;

    // Setup: Create trainer device and launch app with it pre-paired
    final kickrCore = robot.aether.createDevice(
      name: 'Kickr Core',
      capabilities: {DeviceDataType.power, DeviceDataType.cadence, DeviceDataType.speed},
    );

    await robot.launchApp(pairedDevices: [kickrCore], loggedIn: true);

    // Tap "Start Workout" button on home page
    await act.tap(spotText('Start Workout'));
    await robot.idle(500);

    // Verify workout player page loaded
    spotText('CURRENT BLOCK').existsAtLeastOnce();

    // Initially, workout should not be started (waiting for pedaling)
    spotText('Start pedaling to begin workout').existsAtLeastOnce();

    addRobotEvent('Workout player loaded with correct initial state');
  });

  // Note: Manual pause/resume testing requires the workout to be running,
  // which requires power simulation (FakeDevice.setPower) that isn't implemented yet.
  // The pause/resume functionality is covered by manual testing.
}
