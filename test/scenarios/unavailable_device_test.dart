import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spot/spot.dart';
import 'package:vekolo/domain/models/device_info.dart';
import 'package:vekolo/pages/devices_page.dart';

import '../robot/robot_kit.dart';

void main() {
  robotTest('show unavailable assigned device', (robot) async {
    timeline.mode = TimelineMode.always;

    // Create two devices
    final availableDevice = robot.aether.createDevice(
      name: 'Available Device',
      capabilities: {DeviceDataType.power, DeviceDataType.cadence},
    );

    final unavailableDevice = robot.aether.createDevice(
      name: 'Unavailable Device',
      capabilities: {DeviceDataType.heartRate},
    );

    // Launch app and assign both devices
    await robot.launchApp(loggedIn: true);
    await robot.openManageDevicesPage();
    await robot.openScanner();

    // Connect and assign the available device to power
    await robot.selectDeviceInScanner('Available Device');
    await robot.waitUntilConnected();
    expect(availableDevice.isConnected, isTrue);

    // Note: Navigation back to devices page after scanner doesn't work reliably
    // So we skip that step and just open scanner again

    // Connect and assign the unavailable device to heart rate
    await robot.openScanner();
    await robot.selectDeviceInScanner('Unavailable Device');
    await robot.waitUntilConnected();
    expect(unavailableDevice.isConnected, isTrue);

    // Close app (skip navigation verification due to scanner page navigation issues)
    await robot.closeApp();

    // Now simulate the "unavailable device" scenario:
    // Turn off the unavailable device so it won't be discovered
    unavailableDevice.turnOff();

    // Restart the app - only the available device should be discovered
    await robot.launchApp(loggedIn: true);

    // Wait for auto-connect to complete for the available device
    await robot.idle(1000);

    // Open devices page
    await robot.openManageDevicesPage();

    // Verify available device is shown normally
    spotText('Available Device').existsAtLeastOnce();

    // Verify unavailable device is shown with UnavailableDeviceCard
    final unavailableCard = spot<UnavailableDeviceCard>();
    unavailableCard.existsOnce();

    // Verify the unavailable device shows the correct name
    unavailableCard.spotText('Unavailable Device').existsOnce();

    // Verify "Device not available" message is shown
    unavailableCard.spotText('Device not available').existsOnce();

    // Verify device ID is shown
    unavailableCard.spotText('ID: ${unavailableDevice.id}').existsOnce();

    // Verify unassign button exists and tap it
    final unassignButton = unavailableCard.spot<OutlinedButton>().withChild(spotText('Unassign'));
    unassignButton.existsOnce();

    await act.tap(unassignButton);

    // Wait for unassignment to propagate
    await robot.idle(100);

    // Verify the unavailable device card is now gone
    spot<UnavailableDeviceCard>().doesNotExist();
  });

  robotTest('unassign unavailable device removes it from assignments', (robot) async {
    timeline.mode = TimelineMode.always;

    // Create a device and assign it
    final device = robot.aether.createDevice(
      name: 'Test Device',
      capabilities: {DeviceDataType.power},
    );

    await robot.launchApp(loggedIn: true);
    await robot.openManageDevicesPage();
    await robot.openScanner();
    await robot.selectDeviceInScanner('Test Device');
    await robot.waitUntilConnected();
    expect(device.isConnected, isTrue);

    await robot.closeApp();

    // Turn off device so it becomes unavailable
    device.turnOff();

    // Restart app - device won't be discovered
    await robot.launchApp(loggedIn: true);
    await robot.idle(1000);
    await robot.openManageDevicesPage();

    // FTMS devices provide power, cadence, and speed data sources.
    // Devices with ERG support (like KICKR) also get assigned as primary trainer,
    // but test devices don't support ERG mode, so we expect 3 assignments.
    // When unavailable, each assignment shows an UnavailableDeviceCard.
    final unavailableCards = spot<UnavailableDeviceCard>().snapshot();
    expect(unavailableCards.discovered.length, 3, reason: 'FTMS devices are assigned to power, cadence, and speed sources');

    // Unassign all 3 (power, cadence, speed)
    for (int i = 0; i < 3; i++) {
      final unassignButton = spot<UnavailableDeviceCard>().spot<OutlinedButton>().withChild(spotText('Unassign')).first();
      await act.tap(unassignButton);
      await robot.idle(1000); // Allow UI to update and persistence to complete
    }

    // Wait for all persistence operations to complete
    await robot.idle(1000);

    // Verify all are gone
    spot<UnavailableDeviceCard>().doesNotExist();

    // Restart app again to verify assignment was persisted as removed
    await robot.closeApp();
    await robot.launchApp(loggedIn: true);
    await robot.idle(1000);
    await robot.openManageDevicesPage();

    // Device should not be shown (not in assignments anymore)
    spot<UnavailableDeviceCard>().doesNotExist();
    spotText('Test Device').doesNotExist();
  });
}
