import 'dart:async';
import 'package:clock/clock.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_blue_plus_platform_interface/flutter_blue_plus_platform_interface.dart';
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
  final WritableBeacon<BluetoothAdapterState> _adapterStateBeacon = Beacon.writable(BluetoothAdapterState.on);
  final WritableBeacon<List<ScanResult>> _scanResultsBeacon = Beacon.writable(<ScanResult>[]);

  final Map<String, FakeDevice> _devices = {};
  final Map<String, List<BluetoothService>> _deviceServices = {};
  final Set<String> _connectedDeviceIds = {};
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
    _connectedDeviceIds.add(deviceId);

    // Create and cache services based on the fake device's advertised service UUIDs
    // when the device connects, so they're ready when discoverServices() is called
    _populateServicesForDevice(deviceId);

    // Note: BluetoothCharacteristic.setNotifyValue() and write() will check if the device
    // is connected via FlutterBluePlus's platform interface. Since we're using real
    // BluetoothCharacteristic objects created via fromProto, they will try to communicate
    // with the platform.
    //
    // To make this work in tests, we would need to either:
    // 1. Override FlutterBluePlus's platform interface for tests
    // 2. Create custom characteristic wrappers that don't call the platform
    // 3. Ensure the device connection state is properly synchronized
    //
    // For now, the characteristics will fail with "device is not connected" errors.
    // This needs to be addressed by properly mocking the platform or characteristics.
  }

  /// Populate services for a fake device based on its advertised service UUIDs.
  void _populateServicesForDevice(String deviceId) {
    final fakeDevice = _devices[deviceId];
    if (fakeDevice == null || fakeDevice.services.isEmpty) {
      return;
    }

    final device = fakeDevice.bluetoothDevice;
    final services = <BluetoothService>[];

    for (final serviceUuid in fakeDevice.services) {
      // Create characteristics based on the service UUID
      final characteristics = _createCharacteristicsForService(serviceUuid, device.remoteId);

      // Create a BmBluetoothService proto object
      final bmService = BmBluetoothService(
        remoteId: device.remoteId,
        primaryServiceUuid: null, // Primary service
        serviceUuid: serviceUuid,
        characteristics: characteristics,
      );

      // Convert to BluetoothService using fromProto
      final bluetoothService = BluetoothService.fromProto(bmService);

      // Replace real characteristics with fake ones that don't call the platform
      final fakeCharacteristics = bluetoothService.characteristics.map((char) {
        return FakeBluetoothCharacteristic(uuid: char.uuid, properties: char.properties, device: device);
      }).toList();

      // Create a fake service with fake characteristics
      final fakeService = FakeBluetoothService(
        uuid: bluetoothService.uuid,
        remoteId: device.remoteId,
        characteristics: fakeCharacteristics,
      );

      services.add(fakeService);
    }

    // Cache the services
    _deviceServices[deviceId] = services;
  }

  /// Create characteristics for a given service UUID.
  ///
  /// Returns a list of BmBluetoothCharacteristic objects that match the
  /// expected characteristics for common BLE fitness services.
  List<BmBluetoothCharacteristic> _createCharacteristicsForService(Guid serviceUuid, DeviceIdentifier remoteId) {
    // FTMS Service UUID: 00001826-0000-1000-8000-00805f9b34fb
    final ftmsServiceUuid = Guid('00001826-0000-1000-8000-00805f9b34fb');
    // Indoor Bike Data Characteristic: 00002AD2-0000-1000-8000-00805f9b34fb
    final indoorBikeDataUuid = Guid('00002AD2-0000-1000-8000-00805f9b34fb');
    // Control Point Characteristic: 00002AD9-0000-1000-8000-00805f9b34fb
    final controlPointUuid = Guid('00002AD9-0000-1000-8000-00805f9b34fb');

    // Heart Rate Service UUID: 0000180d-0000-1000-8000-00805f9b34fb
    final heartRateServiceUuid = Guid('0000180d-0000-1000-8000-00805f9b34fb');
    // Heart Rate Measurement Characteristic: 00002a37-0000-1000-8000-00805f9b34fb
    final heartRateMeasurementUuid = Guid('00002a37-0000-1000-8000-00805f9b34fb');

    int instanceIdCounter = 0;

    if (serviceUuid == ftmsServiceUuid) {
      // FTMS service requires indoor bike data and control point characteristics
      return [
        BmBluetoothCharacteristic(
          remoteId: remoteId,
          serviceUuid: serviceUuid,
          characteristicUuid: indoorBikeDataUuid,
          instanceId: instanceIdCounter++,
          primaryServiceUuid: serviceUuid,
          descriptors: [],
          properties: BmCharacteristicProperties(
            read: false,
            write: false,
            writeWithoutResponse: false,
            notify: true,
            indicate: false,
            authenticatedSignedWrites: false,
            extendedProperties: false,
            broadcast: false,
            notifyEncryptionRequired: false,
            indicateEncryptionRequired: false,
          ),
        ),
        BmBluetoothCharacteristic(
          remoteId: remoteId,
          serviceUuid: serviceUuid,
          characteristicUuid: controlPointUuid,
          instanceId: instanceIdCounter++,
          primaryServiceUuid: serviceUuid,
          descriptors: [],
          properties: BmCharacteristicProperties(
            read: false,
            write: true,
            writeWithoutResponse: false,
            notify: true,
            indicate: false,
            authenticatedSignedWrites: false,
            extendedProperties: false,
            broadcast: false,
            notifyEncryptionRequired: false,
            indicateEncryptionRequired: false,
          ),
        ),
      ];
    } else if (serviceUuid == heartRateServiceUuid) {
      // Heart Rate service requires heart rate measurement characteristic
      return [
        BmBluetoothCharacteristic(
          remoteId: remoteId,
          serviceUuid: serviceUuid,
          characteristicUuid: heartRateMeasurementUuid,
          instanceId: instanceIdCounter++,
          primaryServiceUuid: serviceUuid,
          descriptors: [],
          properties: BmCharacteristicProperties(
            read: false,
            write: false,
            writeWithoutResponse: false,
            notify: true,
            indicate: false,
            authenticatedSignedWrites: false,
            extendedProperties: false,
            broadcast: false,
            notifyEncryptionRequired: false,
            indicateEncryptionRequired: false,
          ),
        ),
      ];
    }

    // Unknown service - return empty characteristics list
    return [];
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
    _connectedDeviceIds.remove(deviceId);

    // Disconnect the BluetoothDevice instance
    try {
      await device.bluetoothDevice.disconnect();
    } catch (_) {
      // Ignore errors during disconnect
    }
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
    // Initialize services cache - will be populated when discoverServices is called
    _deviceServices[id] = [];
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

  @override
  BluetoothDevice getDevice(String deviceId) {
    final fakeDevice = _devices[deviceId];
    if (fakeDevice == null) {
      throw Exception('Device not found: $deviceId');
    }

    // Ensure device is marked as connected if we think it's connected
    if (_connectedDeviceIds.contains(deviceId) && !fakeDevice._isConnected) {
      fakeDevice._isConnected = true;
    }

    // Return the BluetoothDevice instance stored in the fake device
    // This ensures the device object is linked to the fake device and its services
    return fakeDevice.bluetoothDevice;
  }

  @override
  Future<int> requestMtu(String deviceId, {int mtu = 512}) async {
    // In tests, just return the requested MTU
    // Real MTU negotiation would happen in production via FlutterBluePlus
    return mtu;
  }

  @override
  Future<List<BluetoothService>> discoverServices(String deviceId) async {
    final fakeDevice = _devices[deviceId];
    if (fakeDevice == null) {
      throw Exception('Device not found: $deviceId');
    }

    // Return cached services if available (created when device was connected)
    final cachedServices = _deviceServices[deviceId];
    if (cachedServices != null && cachedServices.isNotEmpty) {
      return cachedServices;
    }

    // Create BluetoothService objects based on the fake device's advertised service UUIDs
    // We use BluetoothService.fromProto() with BmBluetoothService objects
    final device = fakeDevice.bluetoothDevice;
    final services = <BluetoothService>[];

    for (final serviceUuid in fakeDevice.services) {
      // Create characteristics based on the service UUID
      final characteristics = _createCharacteristicsForService(serviceUuid, device.remoteId);

      // Create a BmBluetoothService proto object
      final bmService = BmBluetoothService(
        remoteId: device.remoteId,
        primaryServiceUuid: null, // Primary service
        serviceUuid: serviceUuid,
        characteristics: characteristics,
      );

      // Convert to BluetoothService using fromProto
      final bluetoothService = BluetoothService.fromProto(bmService);

      // Replace real characteristics with fake ones that don't call the platform
      final fakeCharacteristics = bluetoothService.characteristics.map((char) {
        return FakeBluetoothCharacteristic(uuid: char.uuid, properties: char.properties, device: device);
      }).toList();

      // Create a fake service with fake characteristics
      final fakeService = FakeBluetoothService(
        uuid: bluetoothService.uuid,
        remoteId: device.remoteId,
        characteristics: fakeCharacteristics,
      );

      services.add(fakeService);
    }

    // Cache the created services
    _deviceServices[deviceId] = services;
    return services;
  }

  @override
  Future<void> setLogLevel(LogLevel level, {bool color = true}) async {
    //noop
  }
}

/// Fake implementation of BluetoothCharacteristic for testing.
///
/// This class mocks BluetoothCharacteristic methods without calling the
/// FlutterBluePlus platform, allowing tests to run without real BLE hardware.
class FakeBluetoothCharacteristic implements BluetoothCharacteristic {
  FakeBluetoothCharacteristic({required this.uuid, required this.properties, required BluetoothDevice device})
    : _device = device,
      _isNotifying = false,
      _valueController = StreamController<List<int>>.broadcast();

  @override
  final Guid uuid;

  @override
  final CharacteristicProperties properties;

  final BluetoothDevice _device;
  bool _isNotifying;
  final StreamController<List<int>> _valueController;
  List<int> _lastValue = [];

  @override
  Guid get characteristicUuid => uuid;

  @override
  List<BluetoothDescriptor> get descriptors => [];

  @override
  BluetoothDevice get device => _device;

  @override
  DeviceIdentifier get deviceId => _device.remoteId;

  @override
  int get instanceId => 0;

  @override
  Stream<List<int>> get onValueChangedStream => _valueController.stream;

  @override
  Guid? get primaryServiceUuid => null;

  @override
  DeviceIdentifier get remoteId => _device.remoteId;

  @override
  Guid get serviceUuid => uuid; // Characteristic belongs to its service

  @override
  Stream<List<int>> get value => _valueController.stream;

  @override
  bool get isNotifying => _isNotifying;

  @override
  Stream<List<int>> get lastValueStream => _valueController.stream;

  @override
  Stream<List<int>> get onValueReceived => _valueController.stream;

  @override
  List<int> get lastValue => _lastValue;

  @override
  Future<List<int>> read({int timeout = 15}) async {
    // Return the last written value or empty list
    return List<int>.from(_lastValue);
  }

  @override
  Future<void> write(
    List<int> value, {
    bool allowLongWrite = false,
    int timeout = 15,
    bool withoutResponse = false,
  }) async {
    // Store the written value
    _lastValue = List<int>.from(value);
    // Emit the value on the stream
    _valueController.add(_lastValue);
  }

  @override
  Future<bool> setNotifyValue(bool notify, {bool forceIndications = false, int timeout = 15}) async {
    _isNotifying = notify;
    // In real BLE, notifications would start arriving from the device
    // For tests, we can simulate this by emitting values if needed
    return notify;
  }

  /// Simulate receiving a notification value from the device.
  ///
  /// Call this in tests to simulate the device sending data.
  void simulateValueReceived(List<int> value) {
    _lastValue = List<int>.from(value);
    _valueController.add(_lastValue);
  }

  void dispose() {
    _valueController.close();
  }
}

/// Fake implementation of BluetoothService for testing.
///
/// This class wraps BluetoothService functionality but uses fake characteristics
/// that don't call the FlutterBluePlus platform.
class FakeBluetoothService implements BluetoothService {
  FakeBluetoothService({required this.uuid, required DeviceIdentifier remoteId, required this.characteristics})
    : _remoteId = remoteId;

  @override
  final Guid uuid;

  @override
  final List<BluetoothCharacteristic> characteristics;

  final DeviceIdentifier _remoteId;

  @override
  DeviceIdentifier get deviceId => _remoteId;

  @override
  List<BluetoothService> get includedServices => [];

  @override
  bool get isPrimary => true;

  @override
  bool get isSecondary => false;

  @override
  BluetoothService? get primaryService => null;

  @override
  Guid? get primaryServiceUuid => null;

  @override
  DeviceIdentifier get remoteId => _remoteId;

  @override
  Guid get serviceUuid => uuid;
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

  /// The BluetoothDevice instance linked to this fake device.
  /// This ensures that when getDevice() is called, it returns a device
  /// that's connected to this fake device and can discover its services.
  final BluetoothDevice bluetoothDevice;

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
  }) : _rssi = rssi,
       bluetoothDevice = BluetoothDevice(remoteId: DeviceIdentifier(id));

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
    _isConnected = false;
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
    _isConnected = false;
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
