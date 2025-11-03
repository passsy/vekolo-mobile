import 'package:flutter_test/flutter_test.dart';
import 'package:spot/spot.dart';
import 'package:vekolo/domain/models/device_info.dart';
import 'package:vekolo/pages/home_page.dart';

import '../robot/robot_test_fn.dart';

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
    await robot.startApp();
    // TODO: some waiting logic for scanner and ble connect
    await robot.tester.pumpAndSettle();
    expect(kickrCore.isConnected, isTrue);
    spot<HomePage>().existsOnce();

    await robot.openManageDevicesPage();
  });
}
