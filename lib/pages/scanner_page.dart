import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:go_router/go_router.dart';
import 'dart:async';
import 'dart:developer' as developer;

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  final _ble = FlutterReactiveBle();
  final _devices = <DiscoveredDevice>[];
  StreamSubscription<DiscoveredDevice>? _scanSubscription;
  StreamSubscription<BleStatus>? _bleStatusSubscription;
  bool _isScanning = false;
  BleStatus _bleStatus = BleStatus.unknown;

  // FTMS service UUID (Fitness Machine Service)
  static final _ftmsServiceUuid = Uuid.parse('00001826-0000-1000-8000-00805f9b34fb');

  @override
  void initState() {
    super.initState();
    developer.log('[ScannerPage] Initializing scanner page');

    // Listen to BLE status changes
    _bleStatusSubscription = _ble.statusStream.listen((status) {
      developer.log('[ScannerPage] BLE status changed to: $status');
      setState(() {
        _bleStatus = status;
      });

      // Auto-start scan when BLE becomes ready
      if (status == BleStatus.ready && !_isScanning && _devices.isEmpty) {
        developer.log('[ScannerPage] BLE is ready, auto-starting scan');
        _startScan();
      }
    });
  }

  @override
  void dispose() {
    developer.log('[ScannerPage] Disposing scanner page');
    _scanSubscription?.cancel();
    _bleStatusSubscription?.cancel();
    super.dispose();
  }

  void _startScan() {
    if (_bleStatus != BleStatus.ready) {
      developer.log('[ScannerPage] Cannot start scan, BLE status is: $_bleStatus');
      return;
    }

    developer.log('[ScannerPage] Starting BLE scan for FTMS devices');
    setState(() {
      _devices.clear();
      _isScanning = true;
    });

    _scanSubscription = _ble
        .scanForDevices(withServices: [_ftmsServiceUuid], scanMode: ScanMode.lowLatency)
        .listen(
          (device) {
            final index = _devices.indexWhere((d) => d.id == device.id);
            if (index >= 0) {
              developer.log('[ScannerPage] 🔄 Updated device: ${device.name.isEmpty ? device.id : device.name} (RSSI: ${device.rssi})');
              setState(() {
                _devices[index] = device;
              });
            } else {
              developer.log('[ScannerPage] 📱 Discovered new device: ${device.name.isEmpty ? device.id : device.name} (RSSI: ${device.rssi})');
              setState(() {
                _devices.add(device);
              });
            }
          },
          onError: (Object e, StackTrace stackTrace) {
            developer.log('[ScannerPage] Scan error: $e', error: e, stackTrace: stackTrace);
          },
        );
  }

  void _stopScan() {
    developer.log('[ScannerPage] Stopping BLE scan (found ${_devices.length} device(s))');
    _scanSubscription?.cancel();
    setState(() {
      _isScanning = false;
    });
  }

  String _getStatusMessage() {
    if (_bleStatus != BleStatus.ready) {
      return switch (_bleStatus) {
        BleStatus.unknown => 'Initializing Bluetooth...',
        BleStatus.unsupported => 'Bluetooth is not supported on this device',
        BleStatus.unauthorized => 'Bluetooth permission required.\nPlease grant permission in settings.',
        BleStatus.poweredOff => 'Bluetooth is turned off.\nPlease enable Bluetooth.',
        BleStatus.locationServicesDisabled => 'Location services required.\nPlease enable location services.',
        BleStatus.ready => 'Ready',
      };
    }
    return _isScanning ? 'Searching for trainers...' : 'No trainers found';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan for Trainers'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _isScanning ? 'Scanning...' : (_bleStatus == BleStatus.ready ? 'Ready to scan' : 'BLE not ready'),
                  style: const TextStyle(fontSize: 16),
                ),
                ElevatedButton(
                  onPressed: _isScanning ? _stopScan : (_bleStatus == BleStatus.ready ? _startScan : null),
                  child: Text(_isScanning ? 'Stop' : 'Scan'),
                ),
              ],
            ),
          ),
          Expanded(
            child: _devices.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _bleStatus == BleStatus.ready ? Icons.bluetooth_searching : Icons.bluetooth_disabled,
                          size: 64,
                          color: _bleStatus == BleStatus.ready ? Colors.grey[400] : Colors.red[300],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _getStatusMessage(),
                          style: TextStyle(
                            fontSize: 16,
                            color: _bleStatus == BleStatus.ready ? Colors.grey[600] : Colors.red[400],
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _devices.length,
                    itemBuilder: (context, index) {
                      final device = _devices[index];
                      return ListTile(
                        leading: const Icon(Icons.bluetooth),
                        title: Text(device.name.isEmpty ? 'Unknown Device' : device.name),
                        subtitle: Text('${device.id}\nRSSI: ${device.rssi}'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          developer.log(
                            '[ScannerPage] ✅ Selected device: ${device.name.isEmpty ? "Unknown" : device.name} '
                            '(ID: ${device.id}, RSSI: ${device.rssi})',
                          );
                          _stopScan();
                          context.go('/trainer?deviceId=${device.id}&deviceName=${device.name}');
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
