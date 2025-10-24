import 'package:flutter_blue_plus/flutter_blue_plus.dart';

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
/// - Receiving scan results as a stream
///
/// Note: This does NOT handle permissions. Permission checking is handled
/// by the separate BlePermissions abstraction since FlutterBluePlus doesn't
/// provide permission APIs.
abstract class BlePlatform {
  /// Stream of Bluetooth adapter state changes.
  ///
  /// Emits the current state immediately when subscribed, then emits whenever
  /// the adapter state changes (e.g., user turns Bluetooth on/off).
  ///
  /// Possible states:
  /// - BluetoothAdapterState.on: Bluetooth is powered on and ready
  /// - BluetoothAdapterState.off: Bluetooth is powered off
  /// - BluetoothAdapterState.unavailable: Device doesn't support Bluetooth
  /// - BluetoothAdapterState.turningOn: Bluetooth is currently turning on
  /// - BluetoothAdapterState.turningOff: Bluetooth is currently turning off
  /// - BluetoothAdapterState.unauthorized: App lacks Bluetooth permissions
  Stream<BluetoothAdapterState> get adapterStateStream;

  /// Stream of BLE scan results.
  ///
  /// Emits all currently discovered devices immediately when subscribed,
  /// then emits updated lists whenever new devices are discovered or existing
  /// devices send new advertisements.
  ///
  /// Each ScanResult contains:
  /// - device: The BluetoothDevice being advertised
  /// - rssi: Signal strength (more negative = weaker signal)
  /// - advertisementData: Service UUIDs, manufacturer data, device name, etc.
  /// - timeStamp: When this advertisement was received
  ///
  /// The stream continues emitting even when not actively scanning, allowing
  /// subscribers to see all devices that have been discovered.
  Stream<List<ScanResult>> get scanResultsStream;

  /// Start scanning for BLE devices.
  ///
  /// Scans for all BLE devices without filtering by service UUIDs. This allows
  /// discovering any nearby device regardless of what services it advertises.
  ///
  /// Scan results are delivered via [scanResultsStream]. Multiple calls to
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
  /// [scanResultsStream] continues to emit the most recently discovered
  /// devices, but no new devices will be discovered until [startScan]
  /// is called again.
  Future<void> stopScan();
}

/// Default implementation of [BlePlatform] that wraps FlutterBluePlus.
///
/// This implementation delegates all operations directly to FlutterBluePlus's
/// static API. It's a thin wrapper that exists solely to enable dependency
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
  @override
  Stream<BluetoothAdapterState> get adapterStateStream =>
      FlutterBluePlus.adapterState;

  @override
  Stream<List<ScanResult>> get scanResultsStream =>
      FlutterBluePlus.scanResults;

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
}
