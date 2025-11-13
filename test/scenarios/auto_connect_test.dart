import 'package:flutter_test/flutter_test.dart';
import 'package:spot/spot.dart';
import 'package:vekolo/domain/models/device_info.dart';

import '../robot/robot_kit.dart';

void main() {
  robotTest('auto connect to device on app start', (robot) async {
    timeline.mode = TimelineMode.always;
    // Do initial pairing
    final kickrCore = robot.aether.createDevice(
      name: 'Kickr Core',
      capabilities: {DeviceDataType.power, DeviceDataType.cadence, DeviceDataType.speed},
    );
    await robot.launchApp(loggedIn: true);
    await robot.openManageDevicesPage();
    await robot.openScanner();
    await robot.selectDeviceInScanner('Kickr Core');
    await robot.waitUntilConnected();

    expect(kickrCore.isConnected, isTrue);
    await robot.closeApp();
    expect(kickrCore.isConnected, isFalse);

    // On app start, known devices should automatically reconnect
    await robot.launchApp(loggedIn: true);
    expect(robot.aether.devices, contains(kickrCore));
    expect(kickrCore.isConnected, isTrue);

    await robot.openManageDevicesPage();
    spotText('Kickr Core').existsAtLeastOnce();
  });

  robotTest('auto reconnect when device turns off and back on', (robot) async {
    timeline.mode = TimelineMode.always;
    // Do initial pairing
    final kickrCore = robot.aether.createDevice(
      name: 'Kickr Core',
      capabilities: {DeviceDataType.power, DeviceDataType.cadence, DeviceDataType.speed},
    );
    await robot.launchApp(loggedIn: true);
    await robot.openManageDevicesPage();
    await robot.openScanner();
    await robot.selectDeviceInScanner('Kickr Core');
    await robot.waitUntilConnected();

    expect(kickrCore.isConnected, isTrue);

    // Stay on devices page
    spotText('Kickr Core').existsAtLeastOnce();
    robot.verifyDisconnectButtonEnabled();

    // Simulate device powering off (disconnect and stop advertising)
    await kickrCore.turnOff();

    // Wait for disconnection to propagate through connection state stream
    await robot.pumpUntil(5000);
    await robot.idle(1000); // Extra time for stream callbacks to process

    expect(kickrCore.isConnected, isFalse);
    robot.verifyDisconnectButtonDisabled();

    // Wait some time to simulate device being off
    await robot.idle(2000);
    robot.verifyDisconnectButtonDisabled();

    // Simulate device powering back on (start advertising again)
    kickrCore.turnOn();

    // Wait for device to be rediscovered and auto-reconnect
    await robot.pumpUntil(10000);
    await robot.idle(1000);

    expect(kickrCore.isConnected, isTrue);
    robot.verifyDisconnectButtonEnabled();
  });
}
