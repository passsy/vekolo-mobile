import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:vekolo/infrastructure/ble/ble_scanner.dart';
import 'dart:async';
import 'dart:developer' as developer;

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  final _scanner = BleScanner();
  final _devices = <DiscoveredDevice>[];
  StreamSubscription<List<DiscoveredDevice>>? _devicesSubscription;
  StreamSubscription<ScanState>? _scanStateSubscription;
  ScanState? _scanState;

  @override
  void initState() {
    super.initState();
    developer.log('[ScannerPage] Initializing scanner page');

    // Initialize scanner and listen to state changes
    _scanner.initialize();

    // Listen to scan state
    _scanStateSubscription = _scanner.scanState.listen((state) {
      setState(() {
        _scanState = state;
      });

      // Auto-start scan when ready
      if (state.canScan && !state.isScanning && _devices.isEmpty) {
        developer.log('[ScannerPage] Ready to scan, auto-starting');
        _startScan();
      }
    });

    // Listen to discovered devices
    _devicesSubscription = _scanner.discoveredDevices.listen((devices) {
      setState(() {
        _devices.clear();
        _devices.addAll(devices);
      });
    });
  }

  @override
  void dispose() {
    developer.log('[ScannerPage] Disposing scanner page');
    _devicesSubscription?.cancel();
    _scanStateSubscription?.cancel();
    _scanner.dispose();
    super.dispose();
  }

  Future<void> _startScan() async {
    await _scanner.startScan();
  }

  void _stopScan() {
    _scanner.stopScan();
  }

  @override
  Widget build(BuildContext context) {
    final scanState = _scanState;
    final isScanning = scanState?.isScanning ?? false;
    final canScan = scanState?.canScan ?? false;
    final statusMessage = scanState?.statusMessage ?? 'Initializing...';

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
                  isScanning ? 'Scanning...' : (canScan ? 'Ready to scan' : 'BLE not ready'),
                  style: const TextStyle(fontSize: 16),
                ),
                ElevatedButton(
                  onPressed: isScanning ? _stopScan : (canScan ? _startScan : null),
                  child: Text(isScanning ? 'Stop' : 'Scan'),
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
                          canScan ? Icons.bluetooth_searching : Icons.bluetooth_disabled,
                          size: 64,
                          color: canScan ? Colors.grey[400] : Colors.red[300],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          statusMessage,
                          style: TextStyle(
                            fontSize: 16,
                            color: canScan ? Colors.grey[600] : Colors.red[400],
                          ),
                          textAlign: TextAlign.center,
                        ),
                        if (!canScan && scanState?.permissionsGranted == false) ...[
                          const SizedBox(height: 24),
                          ElevatedButton.icon(
                            onPressed: () async {
                              await _scanner.checkAndRequestPermissions();
                            },
                            icon: const Icon(Icons.security),
                            label: const Text('Grant Permissions'),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            ),
                          ),
                        ],
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
                          context.push('/trainer?deviceId=${device.id}&deviceName=${device.name}');
                        },
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: OutlinedButton.icon(
              onPressed: () {
                developer.log('[ScannerPage] Navigating to unknown device report page');
                context.push('/unknown-device');
              },
              icon: const Icon(Icons.help_outline),
              label: const Text('My device is not listed'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
