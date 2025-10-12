/// Abstract interface for all fitness devices.
///
/// This is the core abstraction that separates domain logic from protocol
/// implementations and Bluetooth transport. All fitness devices (trainers,
/// power meters, cadence sensors, heart rate monitors) implement this interface.
///
/// Implementations exist for different protocols:
/// - FTMS (Fitness Machine Service) - most modern trainers
/// - Wahoo proprietary protocol - KICKR and CORE trainers
/// - Bluetooth Cycling Power Service - standalone power meters
/// - Bluetooth CSC Service - cadence/speed sensors
/// - Bluetooth Heart Rate Service - heart rate monitors
///
/// This interface contains NO Bluetooth code - all BLE details are isolated
/// in the transport layer. This enables full testability with mock devices
/// that behave realistically without requiring actual hardware.
library;

import 'package:vekolo/domain/models/device_info.dart';
import 'package:vekolo/domain/models/fitness_data.dart';

/// Core abstraction for all fitness devices.
///
/// Provides identity, connection management, data streams, and control
/// capabilities. Implementations handle protocol-specific behavior while
/// keeping domain logic clean and testable.
///
/// Used by [DeviceManager] to manage multiple devices and aggregate their
/// data streams into unified power/cadence/heart rate sources.
abstract class FitnessDevice {
  // ============================================================================
  // Identity Properties
  // ============================================================================

  /// Unique identifier for this device.
  ///
  /// Typically the Bluetooth device ID, but could be any unique string.
  /// Used by [DeviceManager] to track and reference specific devices.
  String get id;

  /// Human-readable device name displayed in the UI.
  ///
  /// Examples: "Wahoo KICKR", "Garmin HRM-Dual", "Stages Power L".
  String get name;

  /// Type of device determining its primary function.
  ///
  /// A [DeviceType.trainer] can be controlled and provides multiple data sources,
  /// while dedicated sensors provide only their specific measurement type.
  DeviceType get type;

  /// Set of data sources this device can provide.
  ///
  /// A trainer might provide both [DataSource.power] and [DataSource.cadence],
  /// while a heart rate monitor provides only [DataSource.heartRate].
  ///
  /// Used by [DeviceManager] to determine valid device assignments for each
  /// data source role (primary trainer, power source, cadence source, HR source).
  Set<DataSource> get capabilities;

  // ============================================================================
  // Connection Management
  // ============================================================================

  /// Stream of connection state changes.
  ///
  /// Emits [ConnectionState] updates as the device connects, disconnects,
  /// or encounters errors. UI can subscribe to show real-time connection status.
  ///
  /// The stream must emit the current state immediately upon subscription.
  Stream<ConnectionState> get connectionState;

  /// Initiates connection to the device.
  ///
  /// This method handles protocol-specific connection setup but delegates
  /// actual Bluetooth operations to the transport layer.
  ///
  /// Throws an exception if connection fails. Updates [connectionState] stream
  /// to reflect progress ([ConnectionState.connecting] → [ConnectionState.connected]
  /// or [ConnectionState.error]).
  Future<void> connect();

  /// Disconnects from the device.
  ///
  /// Cleanly tears down the connection and releases resources. Updates
  /// [connectionState] to [ConnectionState.disconnected].
  ///
  /// Safe to call even if already disconnected - should be idempotent.
  Future<void> disconnect();

  // ============================================================================
  // Data Streams
  // ============================================================================

  /// Stream of power measurements if this device provides power data.
  ///
  /// Returns `null` if [capabilities] does not include [DataSource.power].
  /// When non-null, emits [PowerData] updates at device-specific intervals
  /// (typically 1-4 Hz).
  ///
  /// The stream should emit data only while connected. It may complete or
  /// emit errors if the connection is lost.
  Stream<PowerData>? get powerStream;

  /// Stream of cadence measurements if this device provides cadence data.
  ///
  /// Returns `null` if [capabilities] does not include [DataSource.cadence].
  /// When non-null, emits [CadenceData] updates at device-specific intervals
  /// (typically 1-4 Hz).
  ///
  /// The stream should emit data only while connected. It may complete or
  /// emit errors if the connection is lost.
  Stream<CadenceData>? get cadenceStream;

  /// Stream of heart rate measurements if this device provides HR data.
  ///
  /// Returns `null` if [capabilities] does not include [DataSource.heartRate].
  /// When non-null, emits [HeartRateData] updates at device-specific intervals
  /// (typically 1 Hz for most HR monitors).
  ///
  /// The stream should emit data only while connected. It may complete or
  /// emit errors if the connection is lost.
  Stream<HeartRateData>? get heartRateStream;

  // ============================================================================
  // Control Capabilities (Trainers Only)
  // ============================================================================

  /// Whether this device supports ERG mode (target power control).
  ///
  /// Returns `true` only for smart trainers that can be controlled.
  /// Returns `false` for all sensors (power meters, cadence, HR monitors).
  ///
  /// When `true`, [setTargetPower] can be called to control resistance.
  /// Used by [WorkoutSyncService] to determine if ERG workout mode is available.
  bool get supportsErgMode;

  /// Sets the target power for ERG mode.
  ///
  /// Commands the trainer to adjust resistance so the rider maintains the
  /// specified power output (in watts) regardless of cadence within reasonable limits.
  ///
  /// Only valid when [supportsErgMode] is `true`. Throws an exception if
  /// called on a device that doesn't support ERG mode.
  ///
  /// The trainer typically takes 3-10 seconds to ramp to the target power,
  /// depending on the model and current vs target difference.
  ///
  /// For devices where [requiresContinuousRefresh] is `true`, this command
  /// must be periodically resent at [refreshInterval] to maintain the target.
  /// [WorkoutSyncService] handles this automatic refresh.
  ///
  /// Throws an exception if the device is not connected or if the command fails.
  Future<void> setTargetPower(int watts);

  // ============================================================================
  // Protocol-Specific Behavior
  // ============================================================================

  /// Whether this device requires continuous refresh of control commands.
  ///
  /// Some protocols (FTMS, ANT+ FE-C) may timeout if commands aren't periodically
  /// resent. When `true`, [WorkoutSyncService] will automatically re-send the
  /// last target power at [refreshInterval] to prevent timeouts.
  ///
  /// When `false`, commands are "set and forget" until changed.
  ///
  /// Conservative default: `true` for trainers to handle edge cases where
  /// the spec is unclear or devices behave inconsistently.
  bool get requiresContinuousRefresh;

  /// Interval at which to refresh control commands if [requiresContinuousRefresh] is `true`.
  ///
  /// Default recommendation: 2 seconds, which is:
  /// - Fast enough to prevent timeouts on devices that need it
  /// - Slow enough to avoid overwhelming the Bluetooth connection
  /// - Aligned with typical FTMS data rates (1-4 Hz)
  ///
  /// ANT+ FE-C typically uses 1 Hz for general settings, 2 Hz for FE data.
  /// FTMS doesn't clearly specify refresh requirements.
  ///
  /// Specific implementations may override based on protocol requirements.
  Duration get refreshInterval;
}
