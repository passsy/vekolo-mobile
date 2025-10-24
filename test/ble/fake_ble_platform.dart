import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:vekolo/ble/ble_platform.dart';

/// Fake implementation of [BlePlatform] for testing.
///
/// Provides complete control over BLE adapter state and device simulation
/// without requiring real Bluetooth hardware. Devices continue advertising
/// until explicitly turned off, matching real BLE behavior.
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
/// // Start scanning to see the device
/// await platform.startScan();
///
/// // Device appears in scan results
/// await platform.scanResultsStream.first; // Contains device
///
/// // Update signal strength
/// device.updateRssi(-70);
///
/// // Stop device advertising
/// device.turnOff();
/// ```
class FakeBlePlatform implements BlePlatform {
  final _adapterStateController = StreamController<BluetoothAdapterState>.broadcast();
  final _scanResultsController = StreamController<List<ScanResult>>.broadcast();

  final Map<String, FakeDevice> _devices = {};
  BluetoothAdapterState _currentAdapterState = BluetoothAdapterState.off;
  bool _isScanning = false;
  Timer? _advertisingTimer;

  FakeBlePlatform() {
    // Emit initial adapter state
    _adapterStateController.add(_currentAdapterState);

    // Start advertising loop that continuously emits active devices
    _startAdvertisingLoop();
  }

  @override
  Stream<BluetoothAdapterState> get adapterStateStream => _adapterStateController.stream;

  @override
  Stream<List<ScanResult>> get scanResultsStream => _scanResultsController.stream;

  @override
  Future<void> startScan() async {
    if (_currentAdapterState != BluetoothAdapterState.on) {
      throw Exception('Bluetooth is not on');
    }
    _isScanning = true;
    _emitScanResults();
  }

  @override
  Future<void> stopScan() async {
    _isScanning = false;
  }

  /// Change the Bluetooth adapter state.
  ///
  /// Emits the new state on [adapterStateStream]. If the adapter is turned off
  /// while scanning, the scan automatically stops.
  void setAdapterState(BluetoothAdapterState state) {
    _currentAdapterState = state;
    _adapterStateController.add(state);

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
  void dispose() {
    _advertisingTimer?.cancel();
    _adapterStateController.close();
    _scanResultsController.close();
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

    _scanResultsController.add(activeDevices);
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
  DateTime _lastUpdate = DateTime.now();

  FakeDevice._({
    required this.id,
    required this.name,
    required int rssi,
    required this.services,
    required this.platform,
  }) : _rssi = rssi;

  /// Start advertising this device.
  ///
  /// The device will appear in scan results on the next advertising cycle
  /// (typically within 100ms). The device continues advertising until
  /// [turnOff] is called.
  void turnOn() {
    _isAdvertising = true;
    _lastUpdate = DateTime.now();
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
    _lastUpdate = DateTime.now();
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
