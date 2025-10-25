/// Device metadata, types, and connection state information.
///
/// These types define device capabilities and states for multi-device
/// fitness data collection and trainer control.
library;

/// Type of fitness device determining its capabilities.
enum DeviceType {
  /// Smart trainer that can be controlled and provides multiple data sources.
  trainer,

  /// Dedicated power meter providing power data only.
  powerMeter,

  /// Cadence sensor providing RPM data only.
  cadenceSensor,

  /// Heart rate monitor providing BPM data only.
  heartRateMonitor,
}

/// Current connection state of a device.
enum ConnectionState {
  /// Device is not connected.
  disconnected,

  /// Currently attempting to connect.
  connecting,

  /// Successfully connected and ready.
  connected,
}

/// Information about a connection error.
///
/// Stores details about connection failures separately from the connection state.
/// This allows tracking error history while keeping the state machine simple
/// (disconnected, connecting, connected).
class ConnectionError {
  /// Creates a connection error record.
  const ConnectionError({required this.message, required this.timestamp, this.error, this.stackTrace});

  /// Human-readable error message describing what went wrong.
  final String message;

  /// When the error occurred.
  final DateTime timestamp;

  /// The underlying error object, if available.
  final Object? error;

  /// Stack trace for debugging, if available.
  final StackTrace? stackTrace;

  @override
  String toString() {
    return 'ConnectionError(message: $message, timestamp: $timestamp)';
  }
}

/// Type of fitness data a device can provide.
///
/// Represents the specific measurements a device is capable of producing.
/// Used by [DeviceInfo] to indicate device capabilities and by [DeviceManager]
/// to assign devices to specific data source roles.
enum DeviceDataType {
  /// Power measurement in watts.
  power,

  /// Cadence measurement in RPM.
  cadence,

  /// Speed measurement in km/h.
  speed,

  /// Heart rate measurement in BPM.
  heartRate,
}

/// Metadata about a fitness device including its capabilities.
///
/// Used by [DeviceManager] to track connected devices and assign them
/// to specific data sources (power, cadence, heart rate).
class DeviceInfo {
  /// Creates device metadata.
  const DeviceInfo({required this.id, required this.name, required this.type, required this.capabilities});

  /// Unique identifier for this device (typically Bluetooth device ID).
  final String id;

  /// Human-readable device name (e.g., "Wahoo KICKR", "Garmin HRM-Dual").
  final String name;

  /// Type of device determining primary function.
  final DeviceType type;

  /// Set of data sources this device can provide.
  ///
  /// A trainer might provide [DeviceDataType.power] and [DeviceDataType.cadence],
  /// while a heart rate monitor provides only [DeviceDataType.heartRate].
  final Set<DeviceDataType> capabilities;

  /// Creates a copy with optional field replacements.
  DeviceInfo copyWith({String? id, String? name, DeviceType? type, Set<DeviceDataType>? capabilities}) {
    return DeviceInfo(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      capabilities: capabilities ?? this.capabilities,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is DeviceInfo &&
        other.id == id &&
        other.name == name &&
        other.type == type &&
        _setEquals(other.capabilities, capabilities);
  }

  @override
  int get hashCode => Object.hash(id, name, type, Object.hashAll(capabilities));

  @override
  String toString() {
    return 'DeviceInfo(id: $id, name: $name, type: $type, '
        'capabilities: $capabilities)';
  }
}

/// Helper for set equality comparison.
bool _setEquals<T>(Set<T> a, Set<T> b) {
  if (a.length != b.length) return false;
  return a.every((element) => b.contains(element));
}
