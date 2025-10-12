
import 'package:flutter_test/flutter_test.dart';
import 'package:vekolo/domain/mocks/mock_trainer.dart';
import 'package:vekolo/domain/models/device_info.dart';
import 'package:vekolo/domain/models/fitness_data.dart';

void main() {
  group('MockTrainer', () {
    late MockTrainer trainer;

    setUp(() {
      trainer = MockTrainer(
        id: 'test-001',
        name: 'Test Trainer',
      );
    });

    tearDown(() {
      trainer.dispose();
    });

    test('has correct identity properties', () {
      expect(trainer.id, 'test-001');
      expect(trainer.name, 'Test Trainer');
      expect(trainer.type, DeviceType.trainer);
      expect(trainer.capabilities, {DataSource.power, DataSource.cadence});
    });

    test('supports ERG mode', () {
      expect(trainer.supportsErgMode, true);
    });

    test('starts disconnected', () async {
      final states = <ConnectionState>[];
      final subscription = trainer.connectionState.listen(states.add);

      await Future.delayed(const Duration(milliseconds: 50));
      expect(states, isEmpty);

      await subscription.cancel();
    });

    test('connects successfully', () async {
      final states = <ConnectionState>[];
      final subscription = trainer.connectionState.listen(states.add);

      await trainer.connect();

      // Give time for all state transitions
      await Future.delayed(const Duration(milliseconds: 100));

      expect(states, [
        ConnectionState.connecting,
        ConnectionState.connected,
      ]);

      await subscription.cancel();
    });

    test('disconnects successfully', () async {
      await trainer.connect();

      final states = <ConnectionState>[];
      final subscription = trainer.connectionState.listen(states.add);

      await trainer.disconnect();

      expect(states, [ConnectionState.disconnected]);

      await subscription.cancel();
    });

    test('setTargetPower fails when disconnected', () async {
      expect(
        () => trainer.setTargetPower(200),
        throwsA(isA<StateError>()),
      );
    });

    test('setTargetPower rejects negative power', () async {
      await trainer.connect();

      expect(
        () => trainer.setTargetPower(-50),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('setTargetPower rejects excessive power', () async {
      await trainer.connect();

      expect(
        () => trainer.setTargetPower(2000),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('emits power data when target is set', () async {
      await trainer.connect();

      final powerData = <PowerData>[];
      final subscription = trainer.powerStream!.listen(powerData.add);

      await trainer.setTargetPower(100);

      // Wait for some power updates
      await Future.delayed(const Duration(milliseconds: 500));

      expect(powerData, isNotEmpty);
      expect(powerData.last.watts, greaterThan(0));

      await subscription.cancel();
    });

    test('power ramps gradually to target', () async {
      await trainer.connect();

      final powerData = <PowerData>[];
      final subscription = trainer.powerStream!.listen(powerData.add);

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

      await subscription.cancel();
    });

    test('emits cadence data when connected', () async {
      await trainer.connect();

      final cadenceData = <CadenceData>[];
      final subscription = trainer.cadenceStream!.listen(cadenceData.add);

      await trainer.setTargetPower(100);

      // Wait for cadence updates
      await Future.delayed(const Duration(seconds: 1));

      expect(cadenceData, isNotEmpty);
      expect(cadenceData.last.rpm, greaterThanOrEqualTo(0));

      await subscription.cancel();
    });

    test('cadence correlates with power', () async {
      await trainer.connect();

      final cadenceData = <CadenceData>[];
      final subscription = trainer.cadenceStream!.listen(cadenceData.add);

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

      await subscription.cancel();
    });

    test('power stops when disconnected', () async {
      await trainer.connect();

      final powerData = <PowerData>[];
      final subscription = trainer.powerStream!.listen(powerData.add);

      await trainer.setTargetPower(100);
      await Future.delayed(const Duration(milliseconds: 500));

      final countBeforeDisconnect = powerData.length;

      await trainer.disconnect();
      await Future.delayed(const Duration(milliseconds: 500));

      // No new data should be emitted after disconnect
      expect(powerData.length, countBeforeDisconnect);

      await subscription.cancel();
    });

    test('can reconnect after disconnect', () async {
      await trainer.connect();
      await trainer.disconnect();

      final states = <ConnectionState>[];
      final subscription = trainer.connectionState.listen(states.add);

      await trainer.connect();

      // Give time for all state transitions
      await Future.delayed(const Duration(milliseconds: 100));

      expect(states, [
        ConnectionState.connecting,
        ConnectionState.connected,
      ]);

      await subscription.cancel();
    });

    test('configurable continuous refresh requirement', () {
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
      await trainer.connect();
      trainer.dispose();

      expect(
        () => trainer.connect(),
        throwsA(isA<StateError>()),
      );
    });
  });
}
