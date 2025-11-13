import 'package:flutter_test/flutter_test.dart';

import 'fake_ble_platform.dart';

void main() {
  group('FakeBlePlatform connect/disconnect', () {
    late FakeBlePlatform platform;

    setUp(() {
      platform = FakeBlePlatform();
    });

    tearDown(() {
      platform.dispose();
    });

    test('device starts disconnected', () {
      final device = platform.addDevice('D1', 'Test Device');
      expect(device.isConnected, isFalse);
    });

    test('can connect to advertising device', () async {
      final device = platform.addDevice('D1', 'Test Device');
      device.turnOn();

      expect(device.isConnected, isFalse);

      await device.connect();

      expect(device.isConnected, isTrue);
    });

    test('cannot connect to non-advertising device', () {
      final device = platform.addDevice('D1', 'Test Device');
      // Device is not turned on (not advertising)

      expect(
        () => device.connect(),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Cannot connect to device that is not advertising'),
          ),
        ),
      );

      expect(device.isConnected, isFalse);
    });

    test('can disconnect from connected device', () async {
      final device = platform.addDevice('D1', 'Test Device');
      device.turnOn();

      await device.connect();
      expect(device.isConnected, isTrue);

      await device.disconnect();
      expect(device.isConnected, isFalse);
    });

    test('disconnect is safe to call when not connected', () async {
      final device = platform.addDevice('D1', 'Test Device');
      device.turnOn();

      expect(device.isConnected, isFalse);

      // Should not throw
      await device.disconnect();

      expect(device.isConnected, isFalse);
    });

    test('connect via platform with device ID', () async {
      final device = platform.addDevice('D1', 'Test Device');
      device.turnOn();

      await platform.connect('D1');

      expect(device.isConnected, isTrue);
    });

    test('disconnect via platform with device ID', () async {
      final device = platform.addDevice('D1', 'Test Device');
      device.turnOn();

      await device.connect();
      expect(device.isConnected, isTrue);

      await platform.disconnect('D1');
      expect(device.isConnected, isFalse);
    });

    test('connect throws if device not found', () {
      expect(
        () => platform.connect('NONEXISTENT'),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('Device not found'))),
      );
    });

    test('disconnect is safe when device not found', () async {
      // Should not throw
      await platform.disconnect('NONEXISTENT');
    });

    test('can override connect behavior', () {
      final device = platform.addDevice('D1', 'Test Device');
      device.turnOn();

      platform.overrideConnect = (deviceId, {timeout = const Duration(seconds: 35)}) {
        throw Exception('Connection failed');
      };

      expect(
        () => device.connect(),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('Connection failed'))),
      );

      expect(device.isConnected, isFalse);
    });

    test('can override disconnect behavior', () async {
      final device = platform.addDevice('D1', 'Test Device');
      device.turnOn();
      await device.connect();

      bool disconnectCalled = false;
      platform.overrideDisconnect = (deviceId) async {
        disconnectCalled = true;
        // Don't actually disconnect in the override
      };

      await device.disconnect();

      expect(disconnectCalled, isTrue);
      // Device stays connected because override didn't change state
      expect(device.isConnected, isTrue);
    });

    test('multiple devices can connect independently', () async {
      final device1 = platform.addDevice('D1', 'Device 1');
      final device2 = platform.addDevice('D2', 'Device 2');

      device1.turnOn();
      device2.turnOn();

      await device1.connect();

      expect(device1.isConnected, isTrue);
      expect(device2.isConnected, isFalse);

      await device2.connect();

      expect(device1.isConnected, isTrue);
      expect(device2.isConnected, isTrue);

      await device1.disconnect();

      expect(device1.isConnected, isFalse);
      expect(device2.isConnected, isTrue);
    });

    test('turnOff disconnects the device', () async {
      final device = platform.addDevice('D1', 'Test Device');
      device.turnOn();

      await device.connect();
      expect(device.isConnected, isTrue);

      // Turn off device (simulate hardware power-off)
      await device.turnOff();

      // Device should be disconnected
      expect(device.isConnected, isFalse);
    });
  });
}
