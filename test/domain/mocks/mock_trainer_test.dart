import 'package:flutter_test/flutter_test.dart';
import 'package:vekolo/domain/mocks/mock_trainer.dart';
import 'package:vekolo/domain/models/device_info.dart';
import 'package:vekolo/domain/models/fitness_data.dart';

void main() {
  group('MockTrainer', () {
    MockTrainer createTrainer() {
      final trainer = MockTrainer(id: 'test-001', name: 'Test Trainer');
      addTearDown(() => trainer.dispose());
      return trainer;
    }

    test('has correct identity properties', () {
      final trainer = createTrainer();
      expect(trainer.id, 'test-001');
      expect(trainer.name, 'Test Trainer');
      expect(trainer.type, DeviceType.trainer);
      expect(trainer.capabilities, {DeviceDataType.power, DeviceDataType.cadence, DeviceDataType.speed});
    });

    test('supports ERG mode', () {
      final trainer = createTrainer();

      expect(trainer.supportsErgMode, true);
    });

    test('starts disconnected', () async {
      final trainer = createTrainer();

      final states = <ConnectionState>[];
      final unsubscribe = trainer.connectionState.subscribe(states.add);

      // Beacons emit their initial value immediately upon subscription
      await Future.delayed(const Duration(milliseconds: 50));
      expect(states, [ConnectionState.disconnected]);

      unsubscribe();
    });

    test('connects successfully', () async {
      final trainer = createTrainer();

      final states = <ConnectionState>[];
      final unsubscribe = trainer.connectionState.subscribe(states.add);

      await trainer.connect().value;

      // Give time for all state transitions
      await Future.delayed(const Duration(milliseconds: 100));

      expect(states, [ConnectionState.connecting, ConnectionState.connected]);

      unsubscribe();
    });

    test('disconnects successfully', () async {
      final trainer = createTrainer();

      await trainer.connect().value;

      final states = <ConnectionState>[];
      final unsubscribe = trainer.connectionState.subscribe(states.add);

      await trainer.disconnect();

      expect(states, [ConnectionState.disconnected]);

      unsubscribe();
    });

    test('setTargetPower fails when disconnected', () {
      final trainer = createTrainer();

      expect(() => trainer.setTargetPower(200), throwsA(isA<StateError>()));
    });

    test('setTargetPower rejects negative power', () async {
      final trainer = createTrainer();

      await trainer.connect().value;

      expect(() => trainer.setTargetPower(-50), throwsA(isA<ArgumentError>()));
    });

    test('setTargetPower rejects excessive power', () async {
      final trainer = createTrainer();

      await trainer.connect().value;

      expect(() => trainer.setTargetPower(2000), throwsA(isA<ArgumentError>()));
    });

    test('emits power data when target is set', () async {
      final trainer = createTrainer();

      await trainer.connect().value;

      final powerData = <PowerData>[];
      final unsubscribe = trainer.powerStream!.subscribe((data) {
        if (data != null) powerData.add(data);
      });

      await trainer.setTargetPower(100);

      // Wait for some power updates
      await Future.delayed(const Duration(milliseconds: 500));

      expect(powerData, isNotEmpty);
      expect(powerData.last.watts, greaterThan(0));

      unsubscribe();
    });

    test('power ramps gradually to target', () async {
      final trainer = createTrainer();

      await trainer.connect().value;

      final powerData = <PowerData>[];
      final unsubscribe = trainer.powerStream!.subscribe((data) {
        if (data != null) powerData.add(data);
      });

      await trainer.setTargetPower(200);

      // Wait for ramp to complete (ramp is 5W/200ms = 25W/sec, so 200W takes 8 seconds)
      await Future.delayed(const Duration(seconds: 9));

      expect(powerData.length, greaterThan(10));

      // Check that power increased gradually - check average of last few readings
      final firstPower = powerData.first.watts;
      final recentPowers = powerData.skip(powerData.length - 5).map((d) => d.watts);
      final avgRecentPower = recentPowers.reduce((a, b) => a + b) / recentPowers.length;
      expect(firstPower, lessThan(avgRecentPower));
      expect(avgRecentPower, closeTo(200, 15)); // Within 15W of target (with fluctuations)

      unsubscribe();
    });

    test('emits cadence data when connected', () async {
      final trainer = createTrainer();

      await trainer.connect().value;

      final cadenceData = <CadenceData>[];
      final unsubscribe = trainer.cadenceStream!.subscribe((data) {
        if (data != null) cadenceData.add(data);
      });

      await trainer.setTargetPower(100);

      // Wait for cadence updates
      await Future.delayed(const Duration(seconds: 1));

      expect(cadenceData, isNotEmpty);
      expect(cadenceData.last.rpm, greaterThanOrEqualTo(0));

      unsubscribe();
    });

    test('cadence correlates with power', () async {
      final trainer = createTrainer();

      await trainer.connect().value;

      final cadenceData = <CadenceData>[];
      final unsubscribe = trainer.cadenceStream!.subscribe((data) {
        if (data != null) cadenceData.add(data);
      });

      // Set low power
      await trainer.setTargetPower(50);
      await Future.delayed(const Duration(seconds: 1));
      final lowPowerCadence = cadenceData.last.rpm;

      // Set high power
      await trainer.setTargetPower(250);
      await Future.delayed(const Duration(seconds: 5));
      final highPowerCadence = cadenceData.last.rpm;

      // Higher power should generally have higher cadence
      expect(highPowerCadence, greaterThanOrEqualTo(lowPowerCadence - 5));

      unsubscribe();
    });

    test('power stops when disconnected', () async {
      final trainer = createTrainer();

      await trainer.connect().value;

      final powerData = <PowerData>[];
      final unsubscribe = trainer.powerStream!.subscribe((data) {
        if (data != null) powerData.add(data);
      });

      await trainer.setTargetPower(100);
      await Future.delayed(const Duration(milliseconds: 500));

      final countBeforeDisconnect = powerData.length;

      await trainer.disconnect();
      await Future.delayed(const Duration(milliseconds: 500));

      // No new data should be emitted after disconnect
      expect(powerData.length, countBeforeDisconnect);

      unsubscribe();
    });

    test('can reconnect after disconnect', () async {
      final trainer = createTrainer();

      await trainer.connect().value;
      await trainer.disconnect();

      final states = <ConnectionState>[];
      final unsubscribe = trainer.connectionState.subscribe(states.add);

      await trainer.connect().value;

      // Give time for all state transitions
      await Future.delayed(const Duration(milliseconds: 100));

      expect(states, [ConnectionState.connecting, ConnectionState.connected]);

      unsubscribe();
    });

    test('configurable continuous refresh requirement', () {
      createTrainer();

      final refreshTrainer = MockTrainer(
        id: 'test-002',
        name: 'Refresh Trainer',
        requiresContinuousRefresh: true,
        refreshInterval: const Duration(seconds: 3),
      );

      expect(refreshTrainer.requiresContinuousRefresh, true);
      expect(refreshTrainer.refreshInterval, const Duration(seconds: 3));

      refreshTrainer.dispose();
    });

    test('dispose prevents further operations', () async {
      final trainer = createTrainer();

      await trainer.connect().value;
      trainer.dispose();

      expect(() => trainer.connect().value, throwsA(isA<StateError>()));
    });
  });
}
