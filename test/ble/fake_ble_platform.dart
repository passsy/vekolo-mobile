// ignore_for_file: unnecessary_async

import 'dart:async';
import 'dart:typed_data';

import 'package:chirp/chirp.dart';
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

  /// All simulated devices, including those that are turned off.
  List<FakeDevice> get devices => _devices.values.toList();

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
    // Clear scan results when scanning stops
    _scanResultsBeacon.value = [];
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
    if (!device.isAdvertising) {
      await Future.delayed(Duration(milliseconds: 200));
      throw Exception('Cannot connect to device that is not advertising: ${device.name}');
    }
    device._isConnected = true;
    _connectedDeviceIds.add(deviceId);

    // Update connection state beacon
    device._connectionStateBeacon.value = BluetoothConnectionState.connected;

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
    final controlPointUuid = Guid('00002AD9-0000-1000-8000-00805f9b34fb');

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
        // For control point characteristic, add callback to intercept writes
        void Function(List<int>)? onWrite;
        if (char.uuid == controlPointUuid) {
          onWrite = fakeDevice._handleControlPointWrite;
        }

        final fakeChar = FakeBluetoothCharacteristic(
          uuid: char.uuid,
          properties: char.properties,
          device: device,
          onWrite: onWrite,
        );
        // Register characteristic with device for emitCharacteristic() access
        fakeDevice._characteristics[char.uuid] = fakeChar;
        return fakeChar;
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

    // Update connection state beacon
    device._connectionStateBeacon.value = BluetoothConnectionState.disconnected;
  }

  /// Change the Bluetooth adapter state.
  ///
  /// Updates the [adapterState] beacon. If the adapter is turned off
  /// while scanning, the scan automatically stops and scan results are cleared.
  void setAdapterState(BluetoothAdapterState state) {
    _adapterStateBeacon.value = state;

    if (state != BluetoothAdapterState.on && _isScanning) {
      _isScanning = false;
      // Clear scan results when Bluetooth turns off
      _scanResultsBeacon.value = [];
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
  /// Only emits results when actively scanning. Only includes devices that
  /// are turned on.
  void _emitScanResults() {
    // Only emit scan results when actively scanning
    if (!_isScanning) {
      return;
    }

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
    final controlPointUuid = Guid('00002AD9-0000-1000-8000-00805f9b34fb');

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
        // For control point characteristic, add callback to intercept writes
        void Function(List<int>)? onWrite;
        if (char.uuid == controlPointUuid) {
          onWrite = fakeDevice._handleControlPointWrite;
        }

        final fakeChar = FakeBluetoothCharacteristic(
          uuid: char.uuid,
          properties: char.properties,
          device: device,
          onWrite: onWrite,
        );
        // Register characteristic with device for emitCharacteristic() access
        fakeDevice._characteristics[char.uuid] = fakeChar;
        return fakeChar;
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
  FakeBluetoothCharacteristic({
    required this.uuid,
    required this.properties,
    required BluetoothDevice device,
    this.onWrite,
  }) : _device = device,
       _isNotifying = false,
       // sync: true ensures events are delivered synchronously during fake time jumps.
       // Processing thousands of events is fast; only pumping (drawing frames) is expensive in real time.
       // Without sync: true, stream events are batched as microtasks and delivered after pump() completes.
       _valueController = StreamController<List<int>>.broadcast(sync: true);

  /// Callback invoked when data is written to this characteristic.
  /// Used by FakeDevice to intercept control point commands.
  final void Function(List<int> value)? onWrite;

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
    // Notify callback if present
    onWrite?.call(value);
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
    if (!_valueController.isClosed) {
      _lastValue = List<int>.from(value);
      _valueController.add(_lastValue);
    }
  }

  void dispose() {
    _valueController.close();
  }
}

/// Wrapper for BluetoothDevice that provides fake connection state.
///
/// This allows tests to control the connection state stream independently
/// of the real flutter_blue_plus implementation.
// ignore: avoid_implementing_value_types
class FakeBluetoothDeviceWrapper implements BluetoothDevice {
  FakeBluetoothDeviceWrapper({
    required DeviceIdentifier remoteId,
    required WritableBeacon<BluetoothConnectionState> connectionStateBeacon,
  }) : _remoteId = remoteId,
       _connectionStateBeacon = connectionStateBeacon;

  final DeviceIdentifier _remoteId;
  final WritableBeacon<BluetoothConnectionState> _connectionStateBeacon;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FakeBluetoothDeviceWrapper && other._remoteId == _remoteId;
  }

  @override
  int get hashCode => _remoteId.hashCode;

  @override
  DeviceIdentifier get remoteId => _remoteId;

  @override
  Stream<BluetoothConnectionState> get connectionState => _connectionStateBeacon.toStream();

  // Delegate all other methods to a real BluetoothDevice instance
  // Most of these won't be called in tests, but implement them for completeness

  @override
  Future<void> connect({Duration timeout = const Duration(seconds: 35), int? mtu, bool autoConnect = false}) async {
    // Connection is managed via FakeDevice/FakeBlePlatform, not through this wrapper
    throw UnimplementedError('Use FakeDevice.connect() instead');
  }

  @override
  Future<void> disconnect({int timeout = 35, int androidDelay = 0, bool queue = true}) async {
    // Disconnection is managed via FakeDevice/FakeBlePlatform, not through this wrapper
    throw UnimplementedError('Use FakeDevice.disconnect() instead');
  }

  @override
  Future<List<BluetoothService>> discoverServices({int timeout = 15, bool subscribeToServicesChanged = true}) async {
    // Service discovery is managed via FakeBlePlatform, not through this wrapper
    throw UnimplementedError('Use FakeBlePlatform.discoverServices() instead');
  }

  @override
  Future<int> requestMtu(int desiredMtu, {int timeout = 15, double predelay = 0.0}) async {
    // MTU request is managed via FakeBlePlatform, not through this wrapper
    throw UnimplementedError('Use FakeBlePlatform.requestMtu() instead');
  }

  // Other properties/methods that are unlikely to be used in tests
  @override
  String get advName => '';

  @override
  String get platformName => '';

  @override
  String get localName => '';

  @override
  String get name => '';

  @override
  DeviceIdentifier get id => _remoteId;

  @override
  bool get isAutoConnectEnabled => false;

  @override
  bool get isConnected => false;

  @override
  bool get isDisconnected => true;

  @override
  Stream<BluetoothConnectionState> get state => connectionState;

  @override
  BluetoothBondState get prevBondState => BluetoothBondState.none;

  @override
  int get mtuNow => 512;

  @override
  Stream<bool> get isDiscoveringServices => Stream.value(false);

  @override
  Stream<int> get mtu => Stream.value(512);

  @override
  Stream<List<BluetoothService>> get servicesStream => Stream.value([]);

  @override
  Stream<List<BluetoothService>> get services => Stream.value([]);

  @override
  List<BluetoothService> get servicesList => [];

  @override
  DisconnectReason? get disconnectReason => null;

  @override
  Future<void> clearGattCache() async {}

  @override
  Future<int> readRssi({int timeout = 15}) async => -50;

  @override
  Future<void> requestConnectionPriority({required ConnectionPriority connectionPriorityRequest}) async {}

  @override
  Future<void> setPreferredPhy({required int txPhy, required int rxPhy, required PhyCoding option}) async {}

  @override
  Future<void> createBond({int timeout = 90, Uint8List? pin}) async {}

  @override
  Future<void> removeBond({int timeout = 30}) async {}

  @override
  Future<void> pair({int timeout = 90, Uint8List? pin}) async {}

  @override
  Stream<BluetoothBondState> get bondState => Stream.value(BluetoothBondState.none);

  @override
  Stream<List<BluetoothService>> get onServicesReset => Stream.value([]);

  @override
  void cancelWhenDisconnected(StreamSubscription subscription, {bool delayed = false, bool next = false}) {
    // In tests, we don't need to do anything here
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
  late final BluetoothDevice bluetoothDevice;

  /// Connection state beacon for this device.
  ///
  /// This controls the connection state stream exposed by bluetoothDevice.connectionState.
  /// Tests can use this to simulate connection state changes.
  late final WritableBeacon<BluetoothConnectionState> _connectionStateBeacon;

  int _rssi;
  bool _isAdvertising = false;
  bool _isConnected = false;
  DateTime _lastUpdate = clock.now();

  /// Cache of characteristics for this device, keyed by UUID.
  final Map<Guid, FakeBluetoothCharacteristic> _characteristics = {};

  /// Timer for continuous riding simulation
  Timer? _ridingTimer;

  /// Whether the device is currently simulating riding
  bool get isRiding => _ridingTimer != null;

  /// Current target power set by the app (from control point writes)
  int? _targetPower;

  /// Fixed cadence and speed for riding simulation
  int _ridingCadence = 90;
  int _ridingSpeed = 30;

  FakeDevice._({
    required this.id,
    required this.name,
    required int rssi,
    required this.services,
    required this.platform,
  }) : _rssi = rssi {
    _connectionStateBeacon = Beacon.writable(BluetoothConnectionState.disconnected);
    bluetoothDevice = FakeBluetoothDeviceWrapper(
      remoteId: DeviceIdentifier(id),
      connectionStateBeacon: _connectionStateBeacon,
    );
  }

  /// Whether this device is currently connected.
  ///
  /// This simulates the connection state. Use [connect] and [disconnect]
  /// to change the state (to be implemented when auto-connect is added).
  bool get isConnected => _isConnected;

  bool get isAdvertising => _isAdvertising;

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

  /// Turn off this device (simulate hardware power-off).
  ///
  /// The device immediately stops advertising and disconnects from the platform.
  /// This simulates the device being powered off or battery dying.
  /// In reality, the BLE stack may take some time to detect the disconnection,
  /// but for testing purposes we disconnect immediately.
  Future<void> turnOff() async {
    _isAdvertising = false;
    platform._emitScanResults();

    // Disconnect if connected (simulates power off)
    if (_isConnected) {
      await platform.disconnect(id);
    }
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
  /// Note: If the platform has an override for disconnect that doesn't change
  /// the connection state, this device's state will also remain unchanged.
  Future<void> disconnect() async {
    final wasConnected = _isConnected;
    await platform.disconnect(id);
    // Only update state if platform actually disconnected
    // (check if platform removed from connected set)
    if (wasConnected && !platform._connectedDeviceIds.contains(id)) {
      _isConnected = false;
    }
  }

  /// Handle control point characteristic writes from the app.
  ///
  /// Intercepts FTMS Control Point commands and updates internal state.
  /// Op Code 0x05 = Set Target Power (ERG mode)
  void _handleControlPointWrite(List<int> data) {
    if (data.isEmpty) return;

    final opCode = data[0];

    // Op Code 0x00 = Request Control (acknowledge it)
    if (opCode == 0x00) {
      chirp.debug('Control point: Request Control received');
      return;
    }

    // Op Code 0x05 = Set Target Power
    if (opCode == 0x05 && data.length >= 3) {
      _targetPower = data[1] | (data[2] << 8);
      chirp.debug('Control point: Target power set to ${_targetPower}W');
    }
  }

  /// Start continuously emitting FTMS Indoor Bike Data, simulating a real ride.
  ///
  /// This method starts a timer that emits power data at 1Hz (once per second),
  /// mimicking how a real smart trainer streams data while someone is riding.
  /// The simulation continues until [stopRiding] is called or the device is
  /// disconnected/turned off.
  ///
  /// **Smart ERG Mode**: When the app sends target power commands to the control
  /// point characteristic, this simulation automatically uses that target power
  /// as the actual power output, just like a real smart trainer in ERG mode.
  ///
  /// Parameters:
  /// - [cadenceRpm]: Instantaneous cadence in RPM (default: 90 RPM)
  /// - [speedKmh]: Instantaneous speed in km/h (default: 30 km/h)
  ///
  /// Example:
  /// ```dart
  /// // Start riding - power will automatically match whatever the app requests
  /// kickrCore.startRiding();
  ///
  /// // Let the workout run for 10 seconds
  /// await robot.pumpUntil(10000);
  ///
  /// // Stop riding
  /// kickrCore.stopRiding();
  /// ```
  void startRiding({int cadenceRpm = 90, int speedKmh = 30}) {
    // Stop any existing riding simulation
    stopRiding();

    _ridingCadence = cadenceRpm;
    _ridingSpeed = speedKmh;

    chirp.info('Starting riding simulation: ${cadenceRpm}RPM, ${speedKmh}km/h (power from ERG control)');

    // Emit immediately with current target power (or default), then every second
    final power = _targetPower ?? 150;
    emitIndoorBikeData(powerWatts: power, cadenceRpm: cadenceRpm, speedKmh: speedKmh);

    _ridingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      // Use target power from control point, or default to 150W
      final power = _targetPower ?? 150;
      emitIndoorBikeData(powerWatts: power, cadenceRpm: _ridingCadence, speedKmh: _ridingSpeed);
    });
  }

  /// Stop the continuous riding simulation.
  ///
  /// Safe to call even if not currently riding.
  void stopRiding() {
    if (_ridingTimer != null) {
      chirp.info('Stopping riding simulation');
      _ridingTimer?.cancel();
      _ridingTimer = null;
    }
  }

  /// Emit FTMS Indoor Bike Data with the specified power, cadence, and speed.
  ///
  /// This is a convenience method for emitting realistic FTMS data without
  /// having to construct the binary packet manually.
  ///
  /// Parameters:
  /// - [powerWatts]: Instantaneous power in watts (e.g., 150 = 150W)
  /// - [cadenceRpm]: Instantaneous cadence in RPM (e.g., 90 = 90 RPM)
  /// - [speedKmh]: Instantaneous speed in km/h (e.g., 30 = 30 km/h)
  ///
  /// Example:
  /// ```dart
  /// kickrCore.emitIndoorBikeData(powerWatts: 150, cadenceRpm: 90, speedKmh: 30);
  /// ```
  void emitIndoorBikeData({int? powerWatts, int? cadenceRpm, int? speedKmh}) {
    // Indoor Bike Data UUID: 00002AD2-0000-1000-8000-00805f9b34fb
    final indoorBikeDataUuid = Guid('00002AD2-0000-1000-8000-00805f9b34fb');

    // Build FTMS Indoor Bike Data packet
    // Calculate flags based on what data we're including
    int flags = 0x0000;

    // Bit 0: More Data (0 = speed present, 1 = speed not present)
    if (speedKmh == null) {
      flags |= 1 << 0;
    }

    // Bit 2: Instantaneous Cadence Present
    if (cadenceRpm != null) {
      flags |= 1 << 2;
    }

    // Bit 6: Instantaneous Power Present
    if (powerWatts != null) {
      flags |= 1 << 6;
    }

    // Build the packet
    final buffer = <int>[];

    // Add flags (uint16, little endian)
    buffer.add(flags & 0xFF);
    buffer.add((flags >> 8) & 0xFF);

    // Add speed if present (uint16, resolution 0.01 km/h)
    if (speedKmh != null) {
      final speedX100 = (speedKmh * 100).round();
      buffer.add(speedX100 & 0xFF);
      buffer.add((speedX100 >> 8) & 0xFF);
    }

    // Add cadence if present (uint16, resolution 0.5 RPM)
    if (cadenceRpm != null) {
      final cadenceX2 = (cadenceRpm * 2).round();
      buffer.add(cadenceX2 & 0xFF);
      buffer.add((cadenceX2 >> 8) & 0xFF);
    }

    // Add power if present (sint16)
    if (powerWatts != null) {
      buffer.add(powerWatts & 0xFF);
      buffer.add((powerWatts >> 8) & 0xFF);
    }

    emitCharacteristic(indoorBikeDataUuid, buffer);
  }

  /// Emit a BLE characteristic notification with the given data.
  ///
  /// This simulates the device sending data to subscribed characteristics.
  /// The characteristic must exist (be discovered) and have notifications enabled
  /// via setNotifyValue(true) before calling this.
  ///
  /// Example:
  /// ```dart
  /// // Create device and connect
  /// final kickr = robot.aether.createDevice(...);
  /// await kickr.connect();
  ///
  /// // Discover services (populates characteristics)
  /// await platform.discoverServices(kickr.id);
  ///
  /// // Subscribe to characteristic
  /// final char = await getCharacteristic(...);
  /// await char.setNotifyValue(true);
  ///
  /// // Emit power data
  /// final indoorBikeDataUuid = Guid('00002AD2-0000-1000-8000-00805f9b34fb');
  /// kickr.emitCharacteristic(indoorBikeDataUuid, [0x44, 0x02, 0x00, 0x00, 0x96, 0x00]);
  /// ```
  void emitCharacteristic(Guid characteristicUuid, List<int> data) {
    // Silently ignore emissions when disconnected to prevent race conditions
    // during app disposal when beacons may already be disposed
    if (!_isConnected) {
      return;
    }

    final char = _characteristics[characteristicUuid];
    if (char == null) {
      throw Exception(
        'Characteristic $characteristicUuid not found on device $name. '
        'Ensure services have been discovered and the characteristic exists.',
      );
    }

    if (!char.isNotifying) {
      throw Exception(
        'Characteristic $characteristicUuid on device $name is not notifying. '
        'Call setNotifyValue(true) before emitting data.',
      );
    }

    final hexValue = data.map((byte) => byte.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
    chirp.debug('Sending Notification to $characteristicUuid: ${hexValue}');
    char.simulateValueReceived(data);

    // Flush beacon updates after stream processing completes.
    // The Future() schedules this as a microtask that runs after the current
    // synchronous processing, ensuring derived beacons see the new values.
    Future(() => BeaconScheduler.flush());
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
