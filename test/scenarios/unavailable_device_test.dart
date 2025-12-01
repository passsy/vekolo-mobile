import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spot/spot.dart';
import 'package:vekolo/domain/models/device_info.dart';
import 'package:vekolo/pages/devices_page.dart';

import '../robot/robot_kit.dart';

void main() {
  robotTest('show unavailable assigned device', (robot) async {
    final availableDevice = robot.aether.createDevice(
      name: 'Available Device',
      capabilities: {DeviceDataType.power, DeviceDataType.cadence},
    );
    final unavailableDevice = robot.aether.createDevice(
      name: 'Unavailable Device',
      capabilities: {DeviceDataType.heartRate},
    );

    await robot.launchApp(pairedDevices: [availableDevice, unavailableDevice], loggedIn: true);
    expect(availableDevice.isConnected, isTrue);
    expect(unavailableDevice.isConnected, isTrue);

    // Restart with one device unavailable
    await robot.closeApp();
    unavailableDevice.turnOff();
    await robot.launchApp(loggedIn: true);
    await robot.idle();
    expect(availableDevice.isConnected, isTrue);
    expect(unavailableDevice.isConnected, isFalse);

    await robot.openManageDevicesPage();
    await act.dragUntilVisible(dragStart: spotText('DATA SOURCES'), dragTarget: spotText('HEART RATE'));

    robot.verifyUnavailableDevice('HEART RATE', deviceName: 'Unavailable Device', deviceId: unavailableDevice.id);

    await robot.unassignUnavailableDevice('HEART RATE');
    robot.verifyUnavailableDevice('HEART RATE', exists: false);
  });

  robotTest('unassign unavailable device removes it from assignments', (robot) async {
    final device = robot.aether.createDevice(name: 'Test Device', capabilities: {DeviceDataType.power});

    await robot.launchApp(pairedDevices: [device], loggedIn: true);
    expect(device.isConnected, isTrue);

    // Restart with device unavailable
    await robot.closeApp();
    device.turnOff();
    await robot.launchApp(loggedIn: true);
    await robot.idle();
    expect(device.isConnected, isFalse);

    await robot.openManageDevicesPage();
    await act.dragUntilVisible(dragStart: spotText('DATA SOURCES'), dragTarget: spotText('HEART RATE'));

    // Unassign all unavailable device cards by tapping each unassign button
    final unassignButtons = spot<UnavailableDeviceCard>()
        .spot<OutlinedButton>()
        .withChild(spotText('Unassign'))
        .existsAtLeastOnce();
    for (final button in unassignButtons.widgets) {
      await act.tap(spotWidget(button));
      await robot.idle();
    }

    // Smart trainer may remain but data sources should be gone
    spot<UnavailableDeviceCard>().existsAtMostOnce();

    // Restart and verify unassignment persisted
    await robot.closeApp();
    await robot.launchApp(loggedIn: true);
    await robot.idle();
    await robot.openManageDevicesPage();

    spot<UnavailableDeviceCard>().existsAtMostOnce();
  });
}
