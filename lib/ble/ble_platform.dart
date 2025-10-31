import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:state_beacon/state_beacon.dart';

export 'package:flutter_blue_plus/flutter_blue_plus.dart' show LogLevel;

/// Platform abstraction for BLE operations.
///
/// This abstraction wraps the flutter_blue_plus package to make the BLE
/// scanner fully testable without requiring real Bluetooth hardware.
/// Tests can provide a fake implementation that simulates device discovery,
/// adapter state changes, and error conditions.
///
/// The abstraction is intentionally minimal, exposing only the core BLE
/// operations needed by BleScanner:
/// - Monitoring Bluetooth adapter state (on/off/unavailable)
/// - Starting and stopping device scans
/// - Receiving scan results as beacons
///
/// Note: This does NOT handle permissions. Permission checking is handled
/// by the separate BlePermissions abstraction since FlutterBluePlus doesn't
/// provide permission APIs.
abstract class BlePlatform {
  /// Beacon of Bluetooth adapter state changes.
  ///
  /// Provides the current state immediately when accessed, then updates whenever
  /// the adapter state changes (e.g., user turns Bluetooth on/off).
  ///
  /// Possible states:
  /// - BluetoothAdapterState.on: Bluetooth is powered on and ready
  /// - BluetoothAdapterState.off: Bluetooth is powered off
  /// - BluetoothAdapterState.unavailable: Device doesn't support Bluetooth
  /// - BluetoothAdapterState.turningOn: Bluetooth is currently turning on
  /// - BluetoothAdapterState.turningOff: Bluetooth is currently turning off
  /// - BluetoothAdapterState.unauthorized: App lacks Bluetooth permissions
  ReadableBeacon<BluetoothAdapterState> get adapterState;

  /// Beacon of BLE scan results.
  ///
  /// Provides all currently discovered devices immediately when accessed,
  /// then updates whenever new devices are discovered or existing
  /// devices send new advertisements.
  ///
  /// Each ScanResult contains:
  /// - device: The BluetoothDevice being advertised
  /// - rssi: Signal strength (more negative = weaker signal)
  /// - advertisementData: Service UUIDs, manufacturer data, device name, etc.
  /// - timeStamp: When this advertisement was received
  ///
  /// The beacon continues updating even when not actively scanning, allowing
  /// subscribers to see all devices that have been discovered.
  ReadableBeacon<List<ScanResult>> get scanResults;

  /// Start scanning for BLE devices.
  ///
  /// Scans for all BLE devices without filtering by service UUIDs. This allows
  /// discovering any nearby device regardless of what services it advertises.
  ///
  /// Scan results are delivered via [scanResults]. Multiple calls to
  /// startScan() are safe - FlutterBluePlus handles this gracefully.
  ///
  /// The scan continues indefinitely until [stopScan] is called or the
  /// Bluetooth adapter is turned off.
  ///
  /// Throws if Bluetooth is off, unavailable, or lacks permissions.
  Future<void> startScan();

  /// Stop the active BLE scan.
  ///
  /// Safe to call even if no scan is active. After stopping, the
  /// [scanResults] beacon continues to emit the most recently discovered
  /// devices, but no new devices will be discovered until [startScan]
  /// is called again.
  Future<void> stopScan();

  /// Connect to a BLE device.
  ///
  /// Establishes a connection to the device with the given [deviceId].
  /// The device must have been discovered via scanning before connecting.
  ///
  /// Parameters:
  /// - [deviceId]: The unique identifier for the device (remoteId)
  /// - [timeout]: Optional connection timeout (defaults to 35 seconds)
  ///
  /// Throws if the device cannot be found or connection fails.
  Future<void> connect(String deviceId, {Duration timeout = const Duration(seconds: 35)});

  /// Disconnect from a BLE device.
  ///
  /// Closes the connection to the device with the given [deviceId].
  /// Safe to call even if not currently connected.
  ///
  /// Parameters:
  /// - [deviceId]: The unique identifier for the device (remoteId)
  Future<void> disconnect(String deviceId);

  /// Set the logging level for BLE operations.
  Future<void> setLogLevel(LogLevel level, {bool color = true});

  /// Clean up resources.
  ///
  /// Call this when done with the platform to prevent memory leaks.
  void dispose();
}

/// Default implementation of [BlePlatform] that wraps FlutterBluePlus.
///
/// This implementation wraps FlutterBluePlus streams in beacons and delegates
/// all operations to FlutterBluePlus's static API. It exists to enable dependency
/// injection and testing.
///
/// In production code, create this once and inject it into BleScanner:
/// ```dart
/// final scanner = BleScanner(
///   platform: BlePlatformImpl(),
///   permissions: BlePermissionsImpl(),
/// );
/// ```
///
/// In tests, inject a FakeBlePlatform instead to simulate BLE behavior
/// without requiring real hardware.
class BlePlatformImpl implements BlePlatform {
  final ReadableBeacon<BluetoothAdapterState> _adapterStateBeacon;
  final ReadableBeacon<List<ScanResult>> _scanResultsBeacon;

  BlePlatformImpl()
    : _adapterStateBeacon = Beacon.streamRaw(
        () => FlutterBluePlus.adapterState,
        initialValue: BluetoothAdapterState.unknown,
      ),
      _scanResultsBeacon = Beacon.streamRaw(() => FlutterBluePlus.scanResults, initialValue: <ScanResult>[]);

  @override
  ReadableBeacon<BluetoothAdapterState> get adapterState => _adapterStateBeacon;

  @override
  ReadableBeacon<List<ScanResult>> get scanResults => _scanResultsBeacon;

  @override
  Future<void> startScan() async {
    // Scan for all devices without service UUID filtering
    // Common errors:
    // - Bluetooth is off
    // - Missing permissions
    // - Platform-specific errors (Android location services, etc.)
    await FlutterBluePlus.startScan();
  }

  @override
  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
  }

  @override
  Future<void> connect(String deviceId, {Duration timeout = const Duration(seconds: 35)}) async {
    final device = BluetoothDevice(remoteId: DeviceIdentifier(deviceId));
    await device.connect(timeout: timeout);
  }

  @override
  Future<void> disconnect(String deviceId) async {
    final device = BluetoothDevice(remoteId: DeviceIdentifier(deviceId));
    await device.disconnect();
  }

  @override
  void dispose() {
    _adapterStateBeacon.dispose();
    _scanResultsBeacon.dispose();
  }

  @override
  Future<void> setLogLevel(LogLevel level, {bool color = true}) async {
    await FlutterBluePlus.setLogLevel(LogLevel.warning);
  }
}
