import 'package:flutter_test/flutter_test.dart';
import 'package:spot/spot.dart';
import 'package:vekolo/domain/models/device_info.dart';

import '../robot/robot_kit.dart';

void main() {
  robotTest('auto connect to device on app start', (robot) async {
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
    robot.verifyDeviceState('POWER SOURCE', disconnectButtonEnabled: true);

    // Simulate device powering off (disconnect and stop advertising)
    await kickrCore.turnOff();

    // Wait for disconnection to propagate through connection state stream
    await robot.idle(100);

    expect(kickrCore.isConnected, isFalse);
    robot.verifyDeviceState('POWER SOURCE', disconnectButtonVisible: false, connectButtonVisible: true);

    // Wait some time to simulate device being off
    await robot.idle(2000);
    robot.verifyDeviceState('POWER SOURCE', disconnectButtonVisible: false, connectButtonVisible: true);

    // Simulate device powering back on (start advertising again)
    kickrCore.turnOn();

    // Wait for device to be rediscovered and auto-reconnect
    await robot.idle(500);

    expect(kickrCore.isConnected, isTrue);
    robot.verifyDeviceState('POWER SOURCE', disconnectButtonEnabled: true);
  });

  robotTest('manual disconnect prevents auto-reconnect', (robot) async {
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
    robot.verifyDeviceState('POWER SOURCE', disconnectButtonEnabled: true);

    // User manually clicks disconnect button
    await robot.tapDisconnectButton();

    // Wait for disconnection to propagate
    await robot.idle(100);

    expect(kickrCore.isConnected, isFalse);
    robot.verifyDeviceState(
      'POWER SOURCE',
      disconnectButtonVisible: false,
      connectButtonVisible: true,
      connectButtonEnabled: true,
    );

    // Simulate device going away and coming back (e.g., user walks away and comes back)
    await kickrCore.turnOff();
    await robot.idle(100);
    kickrCore.turnOn();

    // Wait for device to be rediscovered - it should NOT auto-reconnect
    await robot.idle(500);

    expect(kickrCore.isConnected, isFalse, reason: 'Device should NOT auto-reconnect after manual disconnect');
    robot.verifyDeviceState(
      'POWER SOURCE',
      disconnectButtonVisible: false,
      connectButtonVisible: true,
      connectButtonEnabled: true,
    );

    // User manually clicks connect button to reconnect
    await robot.tapConnectButton();

    // Wait for connection to complete
    await robot.idle(100);
    expect(kickrCore.isConnected, isTrue);
    robot.verifyDeviceState('POWER SOURCE', disconnectButtonEnabled: true);

    // Now test that auto-reconnect is re-enabled after manual reconnect
    // Simulate device powering off (unexpected disconnect)
    await kickrCore.turnOff();

    // Wait for disconnection
    await robot.idle(100);
    expect(kickrCore.isConnected, isFalse);
    robot.verifyDeviceState('POWER SOURCE', disconnectButtonVisible: false, connectButtonVisible: true);

    // Simulate device powering back on
    kickrCore.turnOn();

    // Wait for device to be rediscovered and auto-reconnect
    await robot.pumpUntil(500);
    expect(kickrCore.isConnected, isTrue);
    robot.verifyDeviceState('POWER SOURCE', disconnectButtonEnabled: true);
  });
}
