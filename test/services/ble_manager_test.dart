import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vekolo/services/ble_manager.dart';

void main() {
  group('BleManager', () {
    late BleManager bleManager;

    setUp(() {
      bleManager = BleManager();
    });

    tearDown(() {
      bleManager.dispose();
    });

    group('Initial State', () {
      test('starts disconnected', () {
        expect(bleManager.isConnected, false);
        expect(bleManager.connectedDeviceId, null);
      });

      test('starts with null data values', () {
        expect(bleManager.currentPower, null);
        expect(bleManager.currentCadence, null);
        expect(bleManager.currentSpeed, null);
      });

      test('callbacks are null by default', () {
        expect(bleManager.onTrainerDataUpdate, null);
        expect(bleManager.onError, null);
        expect(bleManager.onDisconnected, null);
      });
    });

    group('Connection Lifecycle', () {
      test('sets isConnected flag appropriately', () {
        expect(bleManager.isConnected, false);

        // Note: We can't test actual connection without real BLE device
        // or dependency injection. This test documents current behavior.
      });

      test('disconnect clears connection state', () {
        bleManager.disconnect();

        expect(bleManager.isConnected, false);
        expect(bleManager.connectedDeviceId, null);
      });

      test('disconnect clears cached data', () {
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
        bool callbackCalled = false;
        bleManager.onDisconnected = () => callbackCalled = true;

        bleManager.disconnect();

        expect(callbackCalled, true);
      });
    });

    group('Target Power Control', () {
      test('setTargetPower is safe to call when disconnected', () {
        // Should not throw when called on disconnected manager
        expect(() => bleManager.setTargetPower(200), returnsNormally);
      });

      test('setTargetPower accepts valid power values', () {
        expect(() => bleManager.setTargetPower(0), returnsNormally);
        expect(() => bleManager.setTargetPower(100), returnsNormally);
        expect(() => bleManager.setTargetPower(500), returnsNormally);
      });
    });

    group('Disposal', () {
      test('dispose is safe to call', () {
        expect(() => bleManager.dispose(), returnsNormally);
      });

      test('dispose is safe to call multiple times', () {
        expect(() {
          bleManager.dispose();
          bleManager.dispose();
          bleManager.dispose();
        }, returnsNormally);
      });

      test('dispose calls disconnect', () {
        bool disconnectCallbackCalled = false;
        bleManager.onDisconnected = () => disconnectCallbackCalled = true;

        bleManager.dispose();

        expect(disconnectCallbackCalled, true);
        expect(bleManager.isConnected, false);
      });
    });

    group('Callback API', () {
      test('can set onTrainerDataUpdate callback', () {
        int callCount = 0;
        bleManager.onTrainerDataUpdate = (power, cadence, speed) {
          callCount++;
        };

        expect(bleManager.onTrainerDataUpdate, isNotNull);
      });

      test('can set onError callback', () {
        String? lastError;
        bleManager.onError = (error) {
          lastError = error;
        };

        expect(bleManager.onError, isNotNull);
      });

      test('can set onDisconnected callback', () {
        bool called = false;
        bleManager.onDisconnected = () {
          called = true;
        };

        expect(bleManager.onDisconnected, isNotNull);
      });

      test('callbacks can be cleared', () {
        bleManager.onTrainerDataUpdate = (power, cadence, speed) {};
        bleManager.onTrainerDataUpdate = null;

        expect(bleManager.onTrainerDataUpdate, null);
      });
    });

    group('Data Properties', () {
      test('currentPower can be read', () {
        expect(() => bleManager.currentPower, returnsNormally);
      });

      test('currentCadence can be read', () {
        expect(() => bleManager.currentCadence, returnsNormally);
      });

      test('currentSpeed can be read', () {
        expect(() => bleManager.currentSpeed, returnsNormally);
      });
    });
  });
}
