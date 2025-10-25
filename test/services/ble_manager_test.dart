import 'package:flutter_test/flutter_test.dart';
import 'package:vekolo/services/ble_manager.dart';

void main() {
  group('BleManager', () {
    BleManager createBleManager() {
      final bleManager = BleManager();
      addTearDown(() => bleManager.dispose());
      return bleManager;
    }

    group('Initial State', () {
      test('starts disconnected', () {
        final bleManager = createBleManager();
        expect(bleManager.isConnected, false);
        expect(bleManager.connectedDeviceId, null);
      });

      test('starts with null data values', () {
        final bleManager = createBleManager();
        expect(bleManager.currentPower, null);
        expect(bleManager.currentCadence, null);
        expect(bleManager.currentSpeed, null);
      });

      test('callbacks are null by default', () {
        final bleManager = createBleManager();
        expect(bleManager.onTrainerDataUpdate, null);
        expect(bleManager.onError, null);
        expect(bleManager.onDisconnected, null);
      });
    });

    group('Connection Lifecycle', () {
      test('sets isConnected flag appropriately', () {
        final bleManager = createBleManager();
        expect(bleManager.isConnected, false);

        // Note: We can't test actual connection without real BLE device
        // or dependency injection. This test documents current behavior.
      });

      test('disconnect clears connection state', () {
        final bleManager = createBleManager();
        bleManager.disconnect();

        expect(bleManager.isConnected, false);
        expect(bleManager.connectedDeviceId, null);
      });

      test('disconnect clears cached data', () {
        final bleManager = createBleManager();
        // Manually set some data to simulate connected state
        bleManager.currentPower = 150;
        bleManager.currentCadence = 90;
        bleManager.currentSpeed = 25.0;

        bleManager.disconnect();

        expect(bleManager.currentPower, null);
        expect(bleManager.currentCadence, null);
        expect(bleManager.currentSpeed, null);
      });

      test('disconnect calls onDisconnected callback', () {
        final bleManager = createBleManager();
        bool callbackCalled = false;
        bleManager.onDisconnected = () => callbackCalled = true;

        bleManager.disconnect();

        expect(callbackCalled, true);
      });
    });

    group('Target Power Control', () {
      test('setTargetPower is safe to call when disconnected', () {
        final bleManager = createBleManager();
        // Should not throw when called on disconnected manager
        expect(() => bleManager.setTargetPower(200), returnsNormally);
      });

      test('setTargetPower accepts valid power values', () {
        final bleManager = createBleManager();
        expect(() => bleManager.setTargetPower(0), returnsNormally);
        expect(() => bleManager.setTargetPower(100), returnsNormally);
        expect(() => bleManager.setTargetPower(500), returnsNormally);
      });
    });

    group('Disposal', () {
      test('dispose is safe to call', () {
        final bleManager = createBleManager();
        expect(() => bleManager.dispose(), returnsNormally);
      });

      test('dispose is safe to call multiple times', () {
        final bleManager = createBleManager();
        expect(() {
          bleManager.dispose();
          bleManager.dispose();
          bleManager.dispose();
        }, returnsNormally);
      });

      test('dispose calls disconnect', () {
        final bleManager = createBleManager();
        bool disconnectCallbackCalled = false;
        bleManager.onDisconnected = () => disconnectCallbackCalled = true;

        bleManager.dispose();

        expect(disconnectCallbackCalled, true);
        expect(bleManager.isConnected, false);
      });
    });

    group('Callback API', () {
      test('can set onTrainerDataUpdate callback', () {
        final bleManager = createBleManager();
        bleManager.onTrainerDataUpdate = (power, cadence, speed) {};

        expect(bleManager.onTrainerDataUpdate, isNotNull);
      });

      test('can set onError callback', () {
        final bleManager = createBleManager();
        bleManager.onError = (error) {};

        expect(bleManager.onError, isNotNull);
      });

      test('can set onDisconnected callback', () {
        final bleManager = createBleManager();
        bleManager.onDisconnected = () {};

        expect(bleManager.onDisconnected, isNotNull);
      });

      test('callbacks can be cleared', () {
        final bleManager = createBleManager();
        bleManager.onTrainerDataUpdate = (power, cadence, speed) {};
        bleManager.onTrainerDataUpdate = null;

        expect(bleManager.onTrainerDataUpdate, null);
      });
    });

    group('Data Properties', () {
      test('currentPower can be read', () {
        final bleManager = createBleManager();
        expect(() => bleManager.currentPower, returnsNormally);
      });

      test('currentCadence can be read', () {
        final bleManager = createBleManager();
        expect(() => bleManager.currentCadence, returnsNormally);
      });

      test('currentSpeed can be read', () {
        final bleManager = createBleManager();
        expect(() => bleManager.currentSpeed, returnsNormally);
      });
    });
  });
}
