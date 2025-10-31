import 'dart:developer' as developer;

import 'package:vekolo/ble/ble_scanner.dart';
import 'package:vekolo/ble/ble_transport.dart';

/// Registry entry for a transport implementation.
class TransportRegistration {
  const TransportRegistration({
    required this.name,
    required this.factory,
  });

  /// Human-readable name for this transport (e.g., "FTMS", "Heart Rate Service")
  final String name;

  /// Factory function to create instances of this transport.
  ///
  /// IMPORTANT: The factory should create lightweight instances that don't
  /// establish BLE connections. Connection happens when `connect()` is called.
  final TransportFactory factory;
}

/// Central registry for all available BLE protocol implementations (transports).
///
/// A transport IS a protocol (FTMS, Heart Rate, etc.). This registry maintains
/// a list of protocol factories and provides methods to:
/// - Register new protocol implementations
/// - Detect compatible protocols for a device
/// - Create protocol instances
///
/// Protocols are tested in registration order (first registered = first tested).
/// When multiple protocols support the same device, all compatible protocols
/// are returned and the device can use them simultaneously.
///
/// This is an instance class (not a singleton) to support:
/// - Dependency injection
/// - Easy testing with mock registries
/// - Multiple registries if needed
///
/// Example usage:
/// ```dart
/// // Create registry and register transports (typically at app startup)
/// final registry = TransportRegistry();
/// registry.register(ftmsRegistration);
/// registry.register(heartRateRegistration);
///
/// // Detect compatible transports for a device
/// final transports = registry.detectCompatibleTransports(
///   discovered,
///   deviceId: discovered.deviceId,
/// );
///
/// // Create device with transports
/// final device = BleDevice(transports: transports);
/// ```
class TransportRegistry {
  /// Creates a new transport registry.
  TransportRegistry();

  final List<TransportRegistration> _registrations = [];

  /// Register a new transport implementation.
  ///
  /// Transports are tested in registration order, so register more specific
  /// transports before more generic ones.
  ///
  /// Example:
  /// ```dart
  /// TransportRegistry.register(
  ///   TransportRegistration(
  ///     name: 'FTMS',
  ///     factory: (deviceId) => FtmsBleTransport(deviceId: deviceId),
  ///   ),
  /// );
  /// ```
  ///
  /// The transport's `canSupport()` method will be called during detection
  /// to check compatibility with discovered devices.
  void register(TransportRegistration registration) {
    developer.log(
      '[TransportRegistry] Registering transport: ${registration.name}',
      name: 'TransportRegistry',
    );
    _registrations.add(registration);
  }

  /// Unregister a transport by name.
  ///
  /// Useful for testing or dynamically enabling/disabling transports.
  void unregister(String name) {
    developer.log('[TransportRegistry] Unregistering transport: $name', name: 'TransportRegistry');
    _registrations.removeWhere((r) => r.name == name);
  }

  /// Clear all registered transports.
  ///
  /// Useful for testing.
  void clear() {
    developer.log('[TransportRegistry] Clearing all transports', name: 'TransportRegistry');
    _registrations.clear();
  }

  /// Get all registered transport names.
  List<String> get registeredTransportNames {
    return _registrations.map((r) => r.name).toList();
  }

  /// Detect all compatible transports for a discovered device.
  ///
  /// Creates lightweight transport instances and calls `canSupport()` on each
  /// to test compatibility using advertising data. Returns a list of transport
  /// instances for all compatible transports.
  ///
  /// **Note:** Transport instances are created but NOT connected. Connection
  /// happens later when the user selects the device and `connect()` is called.
  ///
  /// [discovered] - The discovered device to test
  /// [deviceId] - The BLE device ID to use for creating transport instances
  ///
  /// Returns empty list if no transports are compatible.
  ///
  /// Example:
  /// ```dart
  /// final transports = TransportRegistry.detectCompatibleTransports(
  ///   discovered,
  ///   deviceId: discovered.deviceId,
  /// );
  ///
  /// if (transports.isEmpty) {
  ///   throw UnsupportedDeviceException('No compatible transports found');
  /// }
  /// ```
  List<BleTransport> detectCompatibleTransports(
    DiscoveredDevice discovered, {
    required String deviceId,
  }) {
    developer.log(
      '[TransportRegistry] Detecting transports for device: ${discovered.name} (${discovered.deviceId})',
      name: 'TransportRegistry',
    );

    final compatibleTransports = <BleTransport>[];

    for (final registration in _registrations) {
      try {
        // Create lightweight transport instance (no BLE connection)
        final transport = registration.factory(deviceId);

        // Check compatibility using advertising data
        final isCompatible = transport.canSupport(discovered);

        if (isCompatible) {
          developer.log(
            '[TransportRegistry] ✓ ${registration.name} is compatible',
            name: 'TransportRegistry',
          );
          compatibleTransports.add(transport);
        } else {
          developer.log(
            '[TransportRegistry] ✗ ${registration.name} is not compatible',
            name: 'TransportRegistry',
          );
          // Dispose transport since we won't use it
          transport.dispose();
        }
      } catch (e, stackTrace) {
        developer.log(
          '[TransportRegistry] Error checking ${registration.name} compatibility: $e',
          name: 'TransportRegistry',
          error: e,
          stackTrace: stackTrace,
        );
      }
    }

    developer.log(
      '[TransportRegistry] Found ${compatibleTransports.length} compatible transport(s)',
      name: 'TransportRegistry',
    );

    return compatibleTransports;
  }

  /// Get a summary of the device's compatible transports.
  ///
  /// Returns a human-readable string describing which transports are compatible.
  ///
  /// Useful for debugging and logging.
  String getDeviceSummary(DiscoveredDevice discovered, {required String deviceId}) {
    final compatible = <String>[];
    final incompatible = <String>[];

    for (final registration in _registrations) {
      try {
        final transport = registration.factory(deviceId);
        if (transport.canSupport(discovered)) {
          compatible.add(registration.name);
        } else {
          incompatible.add(registration.name);
        }
        transport.dispose();
      } catch (e) {
        incompatible.add('${registration.name} (error: $e)');
      }
    }

    final buffer = StringBuffer();
    buffer.writeln('Device: ${discovered.name ?? 'Unknown'} (${discovered.deviceId})');
    buffer.writeln('Compatible transports (${compatible.length}): ${compatible.join(', ')}');
    buffer.writeln('Incompatible transports (${incompatible.length}): ${incompatible.join(', ')}');

    return buffer.toString();
  }
}
