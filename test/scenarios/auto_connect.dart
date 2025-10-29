import 'package:flutter_test/flutter_test.dart';

import '../robot/robot_test_fn.dart';

void main() {
  robotTest('auto connect to device on app start', (robot) async {
    // Do initial pairing
    final kickrCore = robot.aether.createDevice(name: 'Kickr Core', protocols: ['ftms']);
    await robot.launchApp(loggedIn: true);

    // TODO Pair kickr and bind it as Wattage device

    expect(kickrCore.isConnected, isTrue);
    await robot.closeApp();
    expect(kickrCore.isConnected, isFalse);

    // On app start, known devices should automatically reconnect
    await robot.launchApp(loggedIn: true);
    // TODO: some waiting logic for scanner and ble connect

    expect(kickrCore.isConnected, isTrue);
  });
}
