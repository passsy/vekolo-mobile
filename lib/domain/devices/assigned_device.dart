import 'package:vekolo/domain/devices/fitness_device.dart';

/// Wrapper for a device assignment that may or may not have a connected device.
///
/// This class allows DeviceManager to represent "assigned but not connected" state,
/// which is necessary during initialization when assignments are loaded from
/// persistence before devices have connected.
///
/// The wrapper holds:
/// - Assignment data (deviceId, deviceName, transport) - always present
/// - Optional connected device reference - null when device is not connected
///
/// Example:
/// ```dart
/// // During initialization - device not connected yet
/// final assigned = AssignedDevice(
///   deviceId: "kickr-123",
///   deviceName: "KICKR CORE",
///   transport: "FTMS",
///   connectedDevice: null,
/// );
/// assigned.deviceId // "kickr-123"
/// assigned.connectedDevice // null
///
/// // After device connects
/// final updated = assigned.withConnectedDevice(device);
/// updated.connectedDevice // BleDevice instance
/// ```
class AssignedDevice {
  const AssignedDevice({
    required this.deviceId,
    required String deviceName,
    required this.transport,
    this.connectedDevice,
  }) : _storedDeviceName = deviceName;

  /// Creates an AssignedDevice from a connected device.
  ///
  /// Extracts the first transport ID to use for this assignment.
  /// Used when assigning a device that's already connected.
  factory AssignedDevice.fromDevice(FitnessDevice device) {
    final transport = device.transportIds.isNotEmpty ? device.transportIds.first : 'unknown';
    return AssignedDevice(
      deviceId: device.id,
      deviceName: device.name,
      transport: transport,
      connectedDevice: device,
    );
  }

  /// Device ID.
  ///
  /// This is always present, even when the device is not connected.
  final String deviceId;

  /// Stored device name from persistence.
  ///
  /// This is the name that was saved when the assignment was created.
  /// Use the [deviceName] getter to get the current name (from connected device if available).
  final String _storedDeviceName;

  /// Device name.
  ///
  /// Returns the name from the connected device if available, otherwise
  /// returns the stored name from persistence. This ensures the UI always
  /// shows the current device name.
  String get deviceName => connectedDevice?.name ?? _storedDeviceName;

  /// Transport ID.
  ///
  /// This is the transport that was used when this assignment was created.
  /// The connected device may have additional transports at runtime.
  final String transport;

  /// The connected device, or null if not currently connected.
  ///
  /// When connected, this device may have multiple transports at runtime,
  /// but the transport field specifies which transport was used for this
  /// specific role assignment.
  final FitnessDevice? connectedDevice;

  /// Creates a new AssignedDevice with the connected device updated.
  ///
  /// Used when a device connects and we need to update the assignment
  /// to reference the live device instance.
  AssignedDevice withConnectedDevice(FitnessDevice? device) {
    return AssignedDevice(
      deviceId: deviceId,
      deviceName: _storedDeviceName,
      transport: transport,
      connectedDevice: device,
    );
  }

  @override
  String toString() {
    return 'AssignedDevice(deviceId: $deviceId, deviceName: $deviceName, '
        'transport: $transport, connectedDevice: ${connectedDevice != null ? 'connected' : 'null'})';
  }
}
