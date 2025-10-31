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

import 'package:async/async.dart';
import 'package:state_beacon/state_beacon.dart';
import 'package:vekolo/ble/transport_capabilities.dart';
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
  /// A trainer might provide both [DeviceDataType.power] and [DeviceDataType.cadence],
  /// while a heart rate monitor provides only [DeviceDataType.heartRate].
  ///
  /// Used by [DeviceManager] to determine valid device assignments for each
  /// data source role (primary trainer, power source, cadence source, HR source).
  Set<DeviceDataType> get capabilities;

  // ============================================================================
  // Connection Management
  // ============================================================================

  /// Reactive beacon of connection state.
  ///
  /// Provides [ConnectionState] updates as the device connects, disconnects,
  /// or encounters errors. UI can watch this to show real-time connection status.
  ///
  /// The beacon always reflects the current state and notifies listeners of changes.
  ReadableBeacon<ConnectionState> get connectionState;

  /// The last connection error that occurred, if any.
  ///
  /// This is set when a connection attempt fails and the device returns to
  /// [ConnectionState.disconnected]. Check this after a failed connection
  /// to understand what went wrong.
  ///
  /// Returns `null` if no error has occurred or if the last connection was successful.
  ConnectionError? get lastConnectionError;

  /// Initiates connection to the device.
  ///
  /// This method handles protocol-specific connection setup but delegates
  /// actual Bluetooth operations to the transport layer.
  ///
  /// Returns a [CancelableOperation] that can be cancelled during connection.
  /// Cancelling will stop the connection attempt and clean up resources.
  ///
  /// Throws an exception if connection fails. Updates [connectionState] stream
  /// to reflect progress ([ConnectionState.connecting] → [ConnectionState.connected]
  /// or back to [ConnectionState.disconnected] on failure).
  CancelableOperation<void> connect();

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

  /// Reactive beacon of power measurements if this device provides power data.
  ///
  /// Returns `null` if [capabilities] does not include [DeviceDataType.power].
  /// When non-null, provides [PowerData] updates at device-specific intervals
  /// (typically 1-4 Hz).
  ///
  /// The beacon updates only while connected. It may stop updating if the
  /// connection is lost.
  ReadableBeacon<PowerData?>? get powerStream;

  /// Reactive beacon of cadence measurements if this device provides cadence data.
  ///
  /// Returns `null` if [capabilities] does not include [DeviceDataType.cadence].
  /// When non-null, provides [CadenceData] updates at device-specific intervals
  /// (typically 1-4 Hz).
  ///
  /// The beacon updates only while connected. It may stop updating if the
  /// connection is lost.
  ReadableBeacon<CadenceData?>? get cadenceStream;

  /// Reactive beacon of speed measurements if this device provides speed data.
  ///
  /// Returns `null` if [capabilities] does not include [DeviceDataType.speed].
  /// When non-null, provides [SpeedData] updates at device-specific intervals
  /// (typically 1-4 Hz).
  ///
  /// The beacon updates only while connected. It may stop updating if the
  /// connection is lost.
  ReadableBeacon<SpeedData?>? get speedStream;

  /// Reactive beacon of heart rate measurements if this device provides HR data.
  ///
  /// Returns `null` if [capabilities] does not include [DeviceDataType.heartRate].
  /// When non-null, provides [HeartRateData] updates at device-specific intervals
  /// (typically 1 Hz for most HR monitors).
  ///
  /// The beacon updates only while connected. It may stop updating if the
  /// connection is lost.
  ReadableBeacon<HeartRateData?>? get heartRateStream;

  // ============================================================================
  // Control Capabilities (Trainers Only)
  // ============================================================================

  /// Whether this device supports ERG mode (target power control).
  ///
  /// Returns `true` only for smart trainers that can be controlled in ERG mode.
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

  /// Returns `true` only for smart trainers that support simulation mode.
  /// Returns `false` for all sensors and trainers without simulation support.
  ///
  /// When `true`, [setSimulationParameters] can be called to simulate road conditions.
  /// This is the "Free Ride" mode used by apps like Zwift to simulate virtual terrain.
  bool get supportsSimulationMode;

  /// Sets simulation parameters for realistic road feel.
  ///
  /// Commands the trainer to adjust resistance based on environmental factors
  /// (grade, wind, rolling resistance, wind resistance coefficient).
  /// The trainer calculates required resistance based on these parameters
  /// combined with the rider's current speed/cadence.
  ///
  /// Only valid when [supportsSimulationMode] is `true`. Throws an exception if
  /// called on a device that doesn't support simulation mode.
  ///
  /// Apps like Zwift send updates every ~2 seconds as terrain changes in the virtual world.
  ///
  /// For devices where [requiresContinuousRefresh] is `true`, this command
  /// must be periodically resent at [refreshInterval] to maintain the parameters.
  ///
  /// Throws an exception if the device is not connected or if the command fails.
  Future<void> setSimulationParameters(SimulationParameters parameters);

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
