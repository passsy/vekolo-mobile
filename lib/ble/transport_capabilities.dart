import 'package:state_beacon/state_beacon.dart';
import 'package:vekolo/domain/models/fitness_data.dart';

/// Interface for transports that are a source of power data.
///
/// Implement this interface if your transport can measure or calculate power output.
/// The powerStream beacon should update with PowerData whenever new measurements arrive.
abstract interface class PowerSource {
  /// Reactive beacon of power measurements.
  ///
  /// Updates at device-specific intervals (typically 1-4 Hz).
  /// The beacon updates only while connected.
  ReadableBeacon<PowerData?> get powerStream;
}

/// Interface for transports that are a source of cadence data.
///
/// Implement this interface if your transport can measure pedaling cadence (RPM).
/// The cadenceStream beacon should update with CadenceData whenever new measurements arrive.
abstract interface class CadenceSource {
  /// Reactive beacon of cadence measurements.
  ///
  /// Updates at device-specific intervals (typically 1-4 Hz).
  /// The beacon updates only while connected.
  ReadableBeacon<CadenceData?> get cadenceStream;
}

/// Interface for transports that are a source of speed data.
///
/// Implement this interface if your transport can measure speed.
/// The speedStream beacon should update with SpeedData whenever new measurements arrive.
abstract interface class SpeedSource {
  /// Reactive beacon of speed measurements.
  ///
  /// Updates at device-specific intervals (typically 1-4 Hz).
  /// The beacon updates only while connected.
  ReadableBeacon<SpeedData?> get speedStream;
}

/// Interface for transports that are a source of heart rate data.
///
/// Implement this interface if your transport can measure heart rate.
/// The heartRateStream beacon should update with HeartRateData whenever new measurements arrive.
abstract interface class HeartRateSource {
  /// Reactive beacon of heart rate measurements.
  ///
  /// Updates at device-specific intervals (typically 1 Hz for most HR monitors).
  /// The beacon updates only while connected.
  ReadableBeacon<HeartRateData?> get heartRateStream;
}

/// Interface for transports that support ERG mode (target power control).
///
/// Implement this interface if your transport can control resistance to maintain
/// a target power output. Only smart trainers typically support this capability.
abstract interface class ErgModeControl {
  /// Sets the target power for ERG mode.
  ///
  /// Commands the trainer to adjust resistance so the rider maintains the
  /// specified power output (in watts) regardless of cadence within reasonable limits.
  ///
  /// The transport handles any necessary continuous refresh internally.
  Future<void> setTargetPower(int watts);
}

/// Parameters for indoor bike simulation mode.
///
/// These parameters allow apps like Zwift to simulate realistic road conditions
/// by controlling the trainer's resistance based on environmental factors.
///
/// Used with the FTMS "Set Indoor Bike Simulation Parameters" command (Op Code 0x11).
class SimulationParameters {
  /// Creates simulation parameters for indoor bike training.
  const SimulationParameters({
    required this.windSpeed,
    required this.grade,
    required this.rollingResistance,
    required this.windResistanceCoefficient,
  });

  /// Wind speed in meters per second (m/s).
  ///
  /// - Positive values: Headwind (increases resistance)
  /// - Negative values: Tailwind (decreases resistance)
  /// - Zero: No wind
  ///
  /// Typical range: -20.0 to +20.0 m/s
  final double windSpeed;

  /// Road grade (incline/decline) as a percentage.
  ///
  /// - Positive values: Uphill (increases resistance)
  /// - Negative values: Downhill (decreases resistance)
  /// - Zero: Flat road
  ///
  /// Typical range: -40.0% to +40.0%
  /// Example: 5.0 = 5% uphill grade
  final double grade;

  /// Coefficient of rolling resistance (Crr).
  ///
  /// Represents the friction between tires and road surface.
  /// Dimensionless coefficient, typically:
  /// - 0.0020 - 0.0030: Smooth asphalt
  /// - 0.0040 - 0.0050: Rough asphalt
  /// - 0.0080 - 0.0120: Gravel
  ///
  /// Higher values = more resistance
  final double rollingResistance;

  /// Wind resistance coefficient (Cw) in kg/m.
  ///
  /// Represents aerodynamic drag, depends on:
  /// - Rider position (aero vs upright)
  /// - Bike type (TT bike vs road bike)
  /// - Rider size
  ///
  /// Typical range: 0.3 - 0.8 kg/m
  /// Example: 0.51 = typical road bike in normal position
  final double windResistanceCoefficient;

  /// Creates a copy with optional field replacements.
  SimulationParameters copyWith({
    double? windSpeed,
    double? grade,
    double? rollingResistance,
    double? windResistanceCoefficient,
  }) {
    return SimulationParameters(
      windSpeed: windSpeed ?? this.windSpeed,
      grade: grade ?? this.grade,
      rollingResistance: rollingResistance ?? this.rollingResistance,
      windResistanceCoefficient: windResistanceCoefficient ?? this.windResistanceCoefficient,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is SimulationParameters &&
        other.windSpeed == windSpeed &&
        other.grade == grade &&
        other.rollingResistance == rollingResistance &&
        other.windResistanceCoefficient == windResistanceCoefficient;
  }

  @override
  int get hashCode => Object.hash(
        windSpeed,
        grade,
        rollingResistance,
        windResistanceCoefficient,
      );

  @override
  String toString() {
    return 'SimulationParameters('
        'windSpeed: ${windSpeed}m/s, '
        'grade: ${grade}%, '
        'rollingResistance: $rollingResistance, '
        'windResistanceCoefficient: ${windResistanceCoefficient}kg/m)';
  }
}

/// Interface for transports that support simulation mode (road condition simulation).
///
/// Implement this interface if your transport can control resistance based on
/// simulated environmental factors (grade, wind, rolling resistance).
/// Only smart trainers typically support this capability.
///
/// This is the "Free Ride" mode used by apps like Zwift to simulate virtual terrain.
abstract interface class SimulationModeControl {
  /// Sets the simulation parameters for realistic road feel.
  ///
  /// Commands the trainer to adjust resistance based on environmental factors:
  /// - **Grade**: Simulates hills (uphill = more resistance)
  /// - **Wind**: Simulates headwind/tailwind
  /// - **Rolling Resistance**: Simulates surface friction
  /// - **Wind Resistance**: Simulates aerodynamic drag
  ///
  /// The trainer calculates required resistance based on these parameters
  /// combined with the rider's current speed/cadence.
  ///
  /// Apps like Zwift send updates every ~2 seconds as terrain changes.
  /// The transport handles any necessary continuous refresh internally.
  ///
  /// Example:
  /// ```dart
  /// await transport.setSimulationParameters(SimulationParameters(
  ///   windSpeed: 0.0,      // No wind
  ///   grade: 5.0,          // 5% uphill
  ///   rollingResistance: 0.004,  // Typical asphalt
  ///   windResistanceCoefficient: 0.51,  // Road bike position
  /// ));
  /// ```
  Future<void> setSimulationParameters(SimulationParameters parameters);
}
