import 'dart:typed_data';

/// Helper for building FTMS Indoor Bike Data characteristic packets.
///
/// FTMS Indoor Bike Data format (GATT Specification Supplement, Part B, Section 4.16):
/// - Bytes 0-1: Flags (uint16, little endian)
/// - Followed by optional data fields based on flags
///
/// This builder makes it easy to create realistic BLE packets for testing.
///
/// Example:
/// ```dart
/// final data = FtmsDataBuilder()
///   .withPower(150)
///   .withCadence(90)
///   .withHeartRate(145)
///   .build();
/// device.emitCharacteristic(indoorBikeDataUuid, data);
/// ```
class FtmsDataBuilder {
  int? _instantaneousSpeed;
  int? _instantaneousCadence;
  int? _instantaneousPower;
  int? _heartRate;

  /// Set instantaneous speed in km/h * 100.
  ///
  /// Example: `withSpeed(2500)` = 25.00 km/h
  FtmsDataBuilder withSpeed(int speedX100) {
    _instantaneousSpeed = speedX100;
    return this;
  }

  /// Set instantaneous cadence in RPM * 2.
  ///
  /// Example: `withCadence(180)` = 90.0 RPM
  FtmsDataBuilder withCadence(int cadenceX2) {
    _instantaneousCadence = cadenceX2;
    return this;
  }

  /// Set instantaneous power in watts.
  ///
  /// Example: `withPower(150)` = 150W
  FtmsDataBuilder withPower(int watts) {
    _instantaneousPower = watts;
    return this;
  }

  /// Set heart rate in BPM.
  ///
  /// Example: `withHeartRate(145)` = 145 BPM
  FtmsDataBuilder withHeartRate(int bpm) {
    _heartRate = bpm;
    return this;
  }

  /// Build the FTMS Indoor Bike Data packet.
  List<int> build() {
    // Calculate flags based on what data we're including
    int flags = 0x0000;

    // Bit 0: More Data (0 = speed present, 1 = speed not present)
    if (_instantaneousSpeed == null) {
      flags |= (1 << 0);
    }

    // Bit 2: Instantaneous Cadence Present
    if (_instantaneousCadence != null) {
      flags |= (1 << 2);
    }

    // Bit 6: Instantaneous Power Present
    if (_instantaneousPower != null) {
      flags |= (1 << 6);
    }

    // Bit 9: Heart Rate Present
    if (_heartRate != null) {
      flags |= (1 << 9);
    }

    // Build the packet
    final buffer = BytesBuilder();
    final flagsBytes = ByteData(2);
    flagsBytes.setUint16(0, flags, Endian.little);
    buffer.add(flagsBytes.buffer.asUint8List());

    // Add speed if present (uint16, resolution 0.01 km/h)
    if (_instantaneousSpeed != null) {
      final speedBytes = ByteData(2);
      speedBytes.setUint16(0, _instantaneousSpeed!, Endian.little);
      buffer.add(speedBytes.buffer.asUint8List());
    }

    // Add cadence if present (uint16, resolution 0.5 RPM)
    if (_instantaneousCadence != null) {
      final cadenceBytes = ByteData(2);
      cadenceBytes.setUint16(0, _instantaneousCadence!, Endian.little);
      buffer.add(cadenceBytes.buffer.asUint8List());
    }

    // Add power if present (sint16)
    if (_instantaneousPower != null) {
      final powerBytes = ByteData(2);
      powerBytes.setInt16(0, _instantaneousPower!, Endian.little);
      buffer.add(powerBytes.buffer.asUint8List());
    }

    // Add heart rate if present (uint8)
    if (_heartRate != null) {
      buffer.addByte(_heartRate!);
    }

    return buffer.toBytes();
  }
}
