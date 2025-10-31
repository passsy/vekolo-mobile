import 'package:flutter_test/flutter_test.dart';
import 'package:vekolo/domain/mocks/device_simulator.dart';
import 'package:vekolo/domain/models/device_info.dart';

void main() {
  group('DeviceSimulator', () {
    test('createRealisticTrainer creates trainer with correct properties', () {
      final trainer = DeviceSimulator.createRealisticTrainer(ftpWatts: 250, variability: 0.08);

      expect(trainer.type, DeviceType.trainer);
      expect(trainer.supportsErgMode, true);
      expect(trainer.capabilities, {DeviceDataType.power, DeviceDataType.cadence, DeviceDataType.speed});
      expect(trainer.requiresContinuousRefresh, false);
    });

    test('createHighEndTrainer creates fast responding trainer', () {
      final trainer = DeviceSimulator.createHighEndTrainer();

      expect(trainer.type, DeviceType.trainer);
      expect(trainer.supportsErgMode, true);
      expect(trainer.requiresContinuousRefresh, false);
    });

    test('createMidRangeTrainer creates trainer with refresh requirement', () {
      final trainer = DeviceSimulator.createMidRangeTrainer();

      expect(trainer.type, DeviceType.trainer);
      expect(trainer.supportsErgMode, true);
      expect(trainer.requiresContinuousRefresh, true);
      expect(trainer.refreshInterval, const Duration(seconds: 2));
    });

    test('createBudgetTrainer creates slower responding trainer', () {
      final trainer = DeviceSimulator.createBudgetTrainer();

      expect(trainer.type, DeviceType.trainer);
      expect(trainer.supportsErgMode, true);
      expect(trainer.requiresContinuousRefresh, true);
      expect(trainer.refreshInterval, const Duration(seconds: 3));
    });

    test('createPowerMeter creates power-only device', () {
      final powerMeter = DeviceSimulator.createPowerMeter();

      expect(powerMeter.type, DeviceType.powerMeter);
      expect(powerMeter.supportsErgMode, false);
      expect(powerMeter.capabilities, {DeviceDataType.power});
      expect(powerMeter.powerStream, isNotNull);
      expect(powerMeter.cadenceStream, isNull);
      expect(powerMeter.heartRateStream, isNull);
    });

    test('createCadenceSensor creates cadence-only device', () {
      final cadenceSensor = DeviceSimulator.createCadenceSensor();

      expect(cadenceSensor.type, DeviceType.cadenceSensor);
      expect(cadenceSensor.supportsErgMode, false);
      expect(cadenceSensor.capabilities, {DeviceDataType.cadence});
      expect(cadenceSensor.powerStream, isNull);
      expect(cadenceSensor.cadenceStream, isNotNull);
      expect(cadenceSensor.heartRateStream, isNull);
    });

    test('createHeartRateMonitor creates HR-only device', () {
      final hrm = DeviceSimulator.createHeartRateMonitor();

      expect(hrm.type, DeviceType.heartRateMonitor);
      expect(hrm.supportsErgMode, false);
      expect(hrm.capabilities, {DeviceDataType.heartRate});
      expect(hrm.powerStream, isNull);
      expect(hrm.cadenceStream, isNull);
      expect(hrm.heartRateStream, isNotNull);
    });

    test('power meter connects and emits data', () async {
      final powerMeter = DeviceSimulator.createPowerMeter();

      await powerMeter.connect().value;

      // Wait for beacon to emit data
      await Future.delayed(const Duration(milliseconds: 600));
      final powerData = powerMeter.powerStream!.value;
      expect(powerData, isNotNull);
      expect(powerData!.watts, greaterThan(0));

      await powerMeter.disconnect();
    });

    test('cadence sensor connects and emits data', () async {
      final cadenceSensor = DeviceSimulator.createCadenceSensor();

      await cadenceSensor.connect().value;

      // Wait for beacon to emit data
      await Future.delayed(const Duration(milliseconds: 600));
      final cadenceData = cadenceSensor.cadenceStream!.value;
      expect(cadenceData, isNotNull);
      expect(cadenceData!.rpm, greaterThan(0));

      await cadenceSensor.disconnect();
    });

    test('heart rate monitor connects and emits data', () async {
      final hrm = DeviceSimulator.createHeartRateMonitor();

      await hrm.connect().value;

      // Wait for beacon to emit data
      await Future.delayed(const Duration(seconds: 1, milliseconds: 100));
      final hrData = hrm.heartRateStream!.value;
      expect(hrData, isNotNull);
      expect(hrData!.bpm, greaterThanOrEqualTo(60));
      expect(hrData.bpm, lessThanOrEqualTo(180));

      await hrm.disconnect();
    });

    test('power meter throws when setting target power', () async {
      final powerMeter = DeviceSimulator.createPowerMeter();
      await powerMeter.connect().value;

      expect(() => powerMeter.setTargetPower(100), throwsA(isA<UnsupportedError>()));

      await powerMeter.disconnect();
    });

    test('cadence sensor throws when setting target power', () async {
      final cadenceSensor = DeviceSimulator.createCadenceSensor();
      await cadenceSensor.connect().value;

      expect(() => cadenceSensor.setTargetPower(100), throwsA(isA<UnsupportedError>()));

      await cadenceSensor.disconnect();
    });

    test('heart rate monitor throws when setting target power', () async {
      final hrm = DeviceSimulator.createHeartRateMonitor();
      await hrm.connect().value;

      expect(() => hrm.setTargetPower(100), throwsA(isA<UnsupportedError>()));

      await hrm.disconnect();
    });

    test('each device gets unique ID', () async {
      final trainer1 = DeviceSimulator.createRealisticTrainer();
      // Wait a bit to ensure different timestamp
      await Future.delayed(const Duration(milliseconds: 2));
      final trainer2 = DeviceSimulator.createRealisticTrainer();

      expect(trainer1.id, isNot(trainer2.id));
    });

    test('custom names are applied', () {
      final trainer = DeviceSimulator.createRealisticTrainer(name: 'Custom Trainer Name');

      expect(trainer.name, 'Custom Trainer Name');
    });
  });
}
