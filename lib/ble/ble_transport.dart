import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;
import 'package:state_beacon/state_beacon.dart';
import 'package:vekolo/ble/ble_scanner.dart';
import 'package:vekolo/domain/models/device_info.dart';

/// Attachment state for BLE transports.
///
/// Represents whether a transport is attached to its BLE service on a connected device.
/// The physical device connection is managed by [BleDevice], while transports attach to
/// specific GATT services on the already-connected device.
enum TransportState { detached, attaching, attached }

/// Abstract interface for BLE protocol implementations.
///
/// A transport IS a protocol implementation (FTMS, Heart Rate, Cycling Power, etc.).
/// Multiple transports (protocols) can be active on the same physical device,
/// each handling communication with a specific Bluetooth service.
///
/// Each transport is responsible for:
/// - Detecting its own compatibility with devices
/// - Connecting to and communicating with its BLE service
/// - Parsing protocol-specific data
/// - Managing its own lifecycle
///
/// Transports implement capability interfaces (PowerProvider, CadenceProvider, etc.)
/// to expose their data streams. The implemented interfaces determine the transport's
/// possible capabilities.
///
/// Examples: FtmsBleTransport, HeartRateBleTransport, CyclingPowerBleTransport
///
/// See docs/BLE_DEVICE_ARCHITECTURE.md for detailed architecture documentation.
abstract interface class BleTransport {
  // ============================================================================
  // Transport Identification
  // ============================================================================

  /// Stable transport protocol identifier for persistence.
  ///
  /// This ID is used when saving device assignments to identify which protocol
  /// to use when reconnecting. Must be stable across app versions.
  ///
  /// Examples: "ftms", "heart-rate", "cycling-power", "cycling-speed-cadence"
  String get transportId;

  // ============================================================================
  // Compatibility Detection (Two-Phase)
  // ============================================================================

  /// **Phase 1: Fast compatibility check using only advertising data.**
  ///
  /// Called by BLE Scanner for every discovered device to determine if this
  /// device should be shown to the user as a compatible fitness device.
  ///
  /// **NO BLE CONNECTION REQUIRED** - only uses advertising data:
  /// - Service UUIDs in advertisement
  /// - Manufacturer ID and manufacturer data
  /// - Device name patterns
  /// - RSSI (if protocol requires minimum signal strength)
  ///
  /// Must be FAST (< 1ms) as it runs for every discovered device during scanning.
  ///
  /// Returns true if this transport can potentially work with the device.
  ///
  /// Example (simple case):
  /// ```dart
  /// @override
  /// bool canSupport(DiscoveredDevice device) {
  ///   return device.serviceUuids.contains(heartRateServiceUuid);
  /// }
  /// ```
  ///
  /// Example (complex case):
  /// ```dart
  /// @override
  /// bool canSupport(DiscoveredDevice device) {
  ///   // Check manufacturer ID and service UUID
  ///   return device.manufacturerId == wahooId &&
  ///          device.serviceUuids.contains(wahooServiceUuid);
  /// }
  /// ```
  bool canSupport(DiscoveredDevice device);

  /// **Phase 2: Deep compatibility check after connecting (optional).**
  ///
  /// Called AFTER device connection and service discovery, but BEFORE attach().
  /// Can perform checks that require reading characteristics:
  /// - Read firmware version to check protocol compatibility
  /// - Check protocol version
  /// - Verify required characteristics exist
  /// - Test read/write permissions
  /// - Validate device capabilities
  ///
  /// **REQUIRES BLE CONNECTION** - involves actual BLE communication.
  /// May take longer (100-500ms) as it reads from the device.
  ///
  /// The [device] is already connected and [services] have been discovered.
  /// Use these to perform deep compatibility checks before committing to attach().
  ///
  /// Returns true if device fully supports this transport, false otherwise.
  ///
  /// **Default implementation returns true** (no deep check needed).
  /// Most simple protocols only need `canSupport()` and can skip this.
  ///
  /// Example (when needed):
  /// ```dart
  /// @override
  /// Future<bool> verifyCompatibility({
  ///   required BluetoothDevice device,
  ///   required List<BluetoothService> services,
  /// }) async {
  ///   // Find firmware version characteristic
  ///   final fwChar = services
  ///       .expand((s) => s.characteristics)
  ///       .firstWhere((c) => c.uuid == firmwareVersionUuid);
  ///
  ///   // Read firmware version
  ///   final version = await fwChar.read();
  ///
  ///   // Check if version supports our protocol implementation
  ///   return parseFirmwareVersion(version) >= minimumSupportedVersion;
  /// }
  /// ```
  Future<bool> verifyCompatibility({
    required fbp.BluetoothDevice device,
    required List<fbp.BluetoothService> services,
  }) async =>
      true;

  // ============================================================================
  // Service Attachment
  // ============================================================================

  /// Attach to the BLE service on an already-connected device.
  ///
  /// The [device] must already be connected and [services] must be discovered
  /// by BleDevice before calling this method. BleDevice handles the physical
  /// connection and service discovery once, then passes them to all transports.
  ///
  /// The transport finds its specific service from [services], locates its
  /// characteristics, and subscribes to notifications.
  ///
  /// Throws exception if the required service or characteristics are not found.
  Future<void> attach({
    required fbp.BluetoothDevice device,
    required List<fbp.BluetoothService> services,
  });

  /// Detach from the BLE service.
  ///
  /// Unsubscribes from characteristics and cleans up service resources.
  /// Does not disconnect the physical device.
  Future<void> detach();

  /// Reactive beacon of transport attachment state.
  ///
  /// Provides [TransportState] updates as the transport attaches to its service,
  /// detaches, or encounters errors. The beacon always reflects the current
  /// state and notifies listeners of changes.
  ReadableBeacon<TransportState> get state;

  /// The last attachment error that occurred, if any.
  ///
  /// This is set when an attachment attempt fails and the transport returns to
  /// [TransportState.detached]. Check this after a failed attachment to understand
  /// what went wrong.
  ///
  /// Returns `null` if no error has occurred or if the last attachment was successful.
  ConnectionError? get lastAttachError;

  /// Current attachment state (convenience getter).
  ///
  /// Returns true if [state] is [TransportState.attached].
  bool get isAttached => state.value == TransportState.attached;

  // ============================================================================
  // Resource Management
  // ============================================================================

  /// Dispose of all resources including streams and controllers.
  ///
  /// Must be called when this transport is no longer needed to prevent memory leaks.
  /// After calling dispose, this transport instance should not be used anymore.
  Future<void> dispose();
}

/// Factory function type for creating transport instances.
///
/// Used by [TransportRegistry] to create transport instances.
///
/// IMPORTANT: The constructor should NOT establish a BLE connection.
/// Connection is established later when [BleTransport.connect] is called.
/// This allows creating lightweight instances for compatibility checking.
typedef TransportFactory = BleTransport Function(String deviceId);
