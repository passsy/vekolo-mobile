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
}
