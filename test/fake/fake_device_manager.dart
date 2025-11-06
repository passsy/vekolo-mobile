import 'package:clock/clock.dart';
import 'package:state_beacon/state_beacon.dart';
import 'package:vekolo/domain/devices/assigned_device.dart';
import 'package:vekolo/domain/devices/device_manager.dart';
import 'package:vekolo/domain/models/fitness_data.dart';

/// Fake implementation of DeviceManager for testing.
///
/// Allows control over device data streams for testing workout recording.
class FakeDeviceManager implements DeviceManager {
  FakeDeviceManager({Clock? clock}) : _clock = clock ?? const Clock();

  final Clock _clock;

  // Data storage
  PowerData? _powerData;
  CadenceData? _cadenceData;
  SpeedData? _speedData;
  HeartRateData? _heartRateData;

  // Beacons
  final WritableBeacon<PowerData?> _powerBeacon = Beacon.writable(null);
  final WritableBeacon<CadenceData?> _cadenceBeacon = Beacon.writable(null);
  final WritableBeacon<SpeedData?> _speedBeacon = Beacon.writable(null);
  final WritableBeacon<HeartRateData?> _heartRateBeacon = Beacon.writable(null);

  @override
  ReadableBeacon<PowerData?> get powerStream => _powerBeacon;

  @override
  ReadableBeacon<CadenceData?> get cadenceStream => _cadenceBeacon;

  @override
  ReadableBeacon<SpeedData?> get speedStream => _speedBeacon;

  @override
  ReadableBeacon<HeartRateData?> get heartRateStream => _heartRateBeacon;

  // Stub for primaryTrainerBeacon (required by WorkoutSyncService)
  @override
  ReadableBeacon<AssignedDevice?> get primaryTrainerBeacon => Beacon.writable(null);

  // Test control methods

  /// Set power value (null to clear).
  void setPower(int? watts) {
    if (watts == null) {
      _powerData = null;
      _powerBeacon.value = null;
    } else {
      _powerData = PowerData(watts: watts, timestamp: _clock.now());
      _powerBeacon.value = _powerData;
    }
  }

  /// Set cadence value (null to clear).
  void setCadence(int? rpm) {
    if (rpm == null) {
      _cadenceData = null;
      _cadenceBeacon.value = null;
    } else {
      _cadenceData = CadenceData(rpm: rpm, timestamp: _clock.now());
      _cadenceBeacon.value = _cadenceData;
    }
  }

  /// Set speed value (null to clear).
  void setSpeed(double? kmh) {
    if (kmh == null) {
      _speedData = null;
      _speedBeacon.value = null;
    } else {
      _speedData = SpeedData(kmh: kmh, timestamp: _clock.now());
      _speedBeacon.value = _speedData;
    }
  }

  /// Set heart rate value (null to clear).
  void setHeartRate(int? bpm) {
    if (bpm == null) {
      _heartRateData = null;
      _heartRateBeacon.value = null;
    } else {
      _heartRateData = HeartRateData(bpm: bpm, timestamp: _clock.now());
      _heartRateBeacon.value = _heartRateData;
    }
  }

  /// Clear all device data.
  void clearAll() {
    setPower(null);
    setCadence(null);
    setSpeed(null);
    setHeartRate(null);
  }

  // Unimplemented DeviceManager methods (not needed for recording tests)

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnimplementedError('${invocation.memberName} not implemented in FakeDeviceManager');
  }
}
