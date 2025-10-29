import 'dart:async';
import 'package:clock/clock.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:state_beacon/state_beacon.dart';
import 'package:vekolo/ble/ble_platform.dart';

/// Fake implementation of [BlePlatform] for testing.
///
/// Uses the override pattern for methods while providing complete control
/// over BLE adapter state and device simulation without requiring real
/// Bluetooth hardware.
///
/// Example usage:
/// ```dart
/// final platform = FakeBlePlatform();
/// final scanner = BleScanner(platform: platform);
///
/// // Simulate Bluetooth turning on
/// platform.setAdapterState(BluetoothAdapterState.on);
///
/// // Add a device that advertises continuously
/// final device = platform.addDevice('D1', 'Heart Monitor', rssi: -60);
/// device.turnOn();
///
/// // Customize scan behavior for a specific test
/// platform.overrideStartScan = () async {
///   throw Exception('Scan failed');
/// };
/// ```
class FakeBlePlatform implements BlePlatform {
  final WritableBeacon<BluetoothAdapterState> _adapterStateBeacon = Beacon.writable(BluetoothAdapterState.off);
  final WritableBeacon<List<ScanResult>> _scanResultsBeacon = Beacon.writable(<ScanResult>[]);

  final Map<String, FakeDevice> _devices = {};
  bool _isScanning = false;
  Timer? _advertisingTimer;

  FakeBlePlatform() {
    // Start advertising loop that continuously emits active devices
    _startAdvertisingLoop();
  }

  @override
  ReadableBeacon<BluetoothAdapterState> get adapterState => _adapterStateBeacon;

  @override
  ReadableBeacon<List<ScanResult>> get scanResults => _scanResultsBeacon;

  Future<void> Function()? overrideStartScan;

  @override
  Future<void> startScan() async {
    if (overrideStartScan != null) {
      return overrideStartScan!();
    }
    // Default implementation
    if (_adapterStateBeacon.value != BluetoothAdapterState.on) {
      throw Exception('Bluetooth is not on');
    }
    _isScanning = true;
    _emitScanResults();
  }

  Future<void> Function()? overrideStopScan;

  @override
  Future<void> stopScan() async {
    if (overrideStopScan != null) {
      return overrideStopScan!();
    }
    // Default implementation
    _isScanning = false;
  }

  Future<void> Function(String deviceId, {Duration timeout})? overrideConnect;

  @override
  Future<void> connect(String deviceId, {Duration timeout = const Duration(seconds: 35)}) async {
    if (overrideConnect != null) {
      return overrideConnect!(deviceId, timeout: timeout);
    }
    // Default implementation
    final device = _devices[deviceId];
    if (device == null) {
      throw Exception('Device not found: $deviceId');
    }
    device._isConnected = true;
  }

  Future<void> Function(String deviceId)? overrideDisconnect;

  @override
  Future<void> disconnect(String deviceId) async {
    if (overrideDisconnect != null) {
      return overrideDisconnect!(deviceId);
    }
    // Default implementation
    final device = _devices[deviceId];
    if (device == null) {
      // Safe to call even if device doesn't exist
      return;
    }
    device._isConnected = false;
  }

  /// Change the Bluetooth adapter state.
  ///
  /// Updates the [adapterState] beacon. If the adapter is turned off
  /// while scanning, the scan automatically stops.
  void setAdapterState(BluetoothAdapterState state) {
    _adapterStateBeacon.value = state;

    if (state != BluetoothAdapterState.on && _isScanning) {
      _isScanning = false;
    }
  }

  /// Add a simulated BLE device.
  ///
  /// The device starts in an "off" state and won't appear in scan results
  /// until [FakeDevice.turnOn] is called. Once turned on, the device
  /// advertises continuously until turned off or removed.
  ///
  /// Parameters:
  /// - [id]: Unique device identifier (used as Bluetooth address)
  /// - [name]: Device name shown in advertisements
  /// - [rssi]: Signal strength, defaults to -50 (typical medium-range signal)
  /// - [services]: Optional list of advertised service UUIDs
  ///
  /// Returns a [FakeDevice] instance for controlling the device's behavior.
  FakeDevice addDevice(String id, String name, {int rssi = -50, List<Guid>? services}) {
    final device = FakeDevice._(id: id, name: name, rssi: rssi, services: services ?? [], platform: this);
    _devices[id] = device;
    return device;
  }

  /// Remove a simulated device.
  ///
  /// The device immediately stops advertising and is removed from all future
  /// scan results.
  void removeDevice(String id) {
    _devices.remove(id);
    _emitScanResults();
  }

  /// Clean up resources.
  ///
  /// Call this when done with the fake platform to prevent memory leaks.
  @override
  void dispose() {
    _advertisingTimer?.cancel();
    _adapterStateBeacon.dispose();
    _scanResultsBeacon.dispose();
  }

  /// Start the advertising loop that simulates continuous BLE advertisements.
  ///
  /// Real BLE devices continuously broadcast advertisements. This timer
  /// simulates that behavior by periodically emitting scan results for all
  /// active (turned on) devices.
  void _startAdvertisingLoop() {
    _advertisingTimer = Timer.periodic(const Duration(milliseconds: 100), (_) => _emitScanResults());
  }

  /// Emit current scan results for all advertising devices.
  ///
  /// Only includes devices that are turned on. Devices continue to appear
  /// in results even when not actively scanning (matching FlutterBluePlus
  /// behavior which caches discovered devices).
  void _emitScanResults() {
    final activeDevices = _devices.values
        .where((device) => device._isAdvertising)
        .map((device) => device._toScanResult())
        .toList();

    _scanResultsBeacon.value = activeDevices;
  }
}

/// A simulated BLE device that can be controlled in tests.
///
/// Devices start in an "off" state (not advertising). Call [turnOn] to make
/// the device appear in scan results, and [turnOff] to stop advertising.
/// Signal strength can be updated dynamically with [updateRssi].
class FakeDevice {
  final String id;
  final String name;
  final List<Guid> services;
  final FakeBlePlatform platform;

  int _rssi;
  bool _isAdvertising = false;
  bool _isConnected = false;
  DateTime _lastUpdate = clock.now();

  FakeDevice._({
    required this.id,
    required this.name,
    required int rssi,
    required this.services,
    required this.platform,
  }) : _rssi = rssi;

  /// Whether this device is currently connected.
  ///
  /// This simulates the connection state. Use [connect] and [disconnect]
  /// to change the state (to be implemented when auto-connect is added).
  bool get isConnected => _isConnected;

  /// Start advertising this device.
  ///
  /// The device will appear in scan results on the next advertising cycle
  /// (typically within 100ms). The device continues advertising until
  /// [turnOff] is called.
  void turnOn() {
    _isAdvertising = true;
    _lastUpdate = clock.now();
    platform._emitScanResults();
  }

  /// Stop advertising this device.
  ///
  /// The device immediately disappears from scan results.
  void turnOff() {
    _isAdvertising = false;
    platform._emitScanResults();
  }

  /// Update the device's signal strength.
  ///
  /// Changes take effect immediately in the next scan result emission.
  /// More negative values = weaker signal (e.g., -90 is very weak, -30 is strong).
  void updateRssi(int rssi) {
    _rssi = rssi;
    _lastUpdate = clock.now();
  }

  /// Connect to this device.
  ///
  /// Sets [isConnected] to true. The device must be turned on (advertising)
  /// before it can be connected to.
  ///
  /// Throws if the device is not advertising.
  Future<void> connect({Duration timeout = const Duration(seconds: 35)}) async {
    if (!_isAdvertising) {
      throw Exception('Cannot connect to device that is not advertising: $name');
    }
    await platform.connect(id, timeout: timeout);
  }

  /// Disconnect from this device.
  ///
  /// Sets [isConnected] to false. Safe to call even if not currently connected.
  Future<void> disconnect() async {
    await platform.disconnect(id);
  }

  /// Convert this fake device to a FlutterBluePlus ScanResult.
  ///
  /// Creates a realistic ScanResult with all expected fields populated.
  ScanResult _toScanResult() {
    final device = BluetoothDevice(remoteId: DeviceIdentifier(id));

    final advertisementData = AdvertisementData(
      advName: name,
      txPowerLevel: null,
      appearance: null,
      connectable: true,
      manufacturerData: {},
      serviceData: {},
      serviceUuids: services,
    );

    return ScanResult(device: device, advertisementData: advertisementData, rssi: _rssi, timeStamp: _lastUpdate);
  }
}
