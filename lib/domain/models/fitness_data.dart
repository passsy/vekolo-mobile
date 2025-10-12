/// Fitness data models with timestamps for various metrics.
///
/// These immutable classes represent timestamped fitness data from devices.
/// Used by [DeviceManager] to aggregate data from multiple sources.
library;

/// Power measurement in watts from a trainer or power meter.
class PowerData {
  /// Creates a power data point.
  const PowerData({required this.watts, required this.timestamp});

  /// Power output in watts.
  final int watts;

  /// Time when this measurement was taken.
  final DateTime timestamp;

  /// Creates a copy with optional field replacements.
  PowerData copyWith({int? watts, DateTime? timestamp}) {
    return PowerData(watts: watts ?? this.watts, timestamp: timestamp ?? this.timestamp);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is PowerData && other.watts == watts && other.timestamp == timestamp;
  }

  @override
  int get hashCode => Object.hash(watts, timestamp);

  @override
  String toString() => 'PowerData(watts: $watts, timestamp: $timestamp)';
}

/// Cadence measurement in RPM from a trainer or cadence sensor.
class CadenceData {
  /// Creates a cadence data point.
  const CadenceData({required this.rpm, required this.timestamp});

  /// Pedaling cadence in revolutions per minute.
  final int rpm;

  /// Time when this measurement was taken.
  final DateTime timestamp;

  /// Creates a copy with optional field replacements.
  CadenceData copyWith({int? rpm, DateTime? timestamp}) {
    return CadenceData(rpm: rpm ?? this.rpm, timestamp: timestamp ?? this.timestamp);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is CadenceData && other.rpm == rpm && other.timestamp == timestamp;
  }

  @override
  int get hashCode => Object.hash(rpm, timestamp);

  @override
  String toString() => 'CadenceData(rpm: $rpm, timestamp: $timestamp)';
}

/// Heart rate measurement in BPM from a heart rate monitor.
class HeartRateData {
  /// Creates a heart rate data point.
  const HeartRateData({required this.bpm, required this.timestamp});

  /// Heart rate in beats per minute.
  final int bpm;

  /// Time when this measurement was taken.
  final DateTime timestamp;

  /// Creates a copy with optional field replacements.
  HeartRateData copyWith({int? bpm, DateTime? timestamp}) {
    return HeartRateData(bpm: bpm ?? this.bpm, timestamp: timestamp ?? this.timestamp);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is HeartRateData && other.bpm == bpm && other.timestamp == timestamp;
  }

  @override
  int get hashCode => Object.hash(bpm, timestamp);

  @override
  String toString() => 'HeartRateData(bpm: $bpm, timestamp: $timestamp)';
}
