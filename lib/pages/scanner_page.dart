import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:vekolo/ble/ble_scanner.dart';
import 'dart:developer' as developer;

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  final _scanner = BleScanner();
  final _devices = <DiscoveredDevice>[];
  VoidCallback? _devicesUnsubscribe;
  VoidCallback? _bluetoothStateUnsubscribe;
  VoidCallback? _isScanningUnsubscribe;
  BluetoothState? _bluetoothState;
  bool _isScanning = false;
  ScanToken? _scanToken;

  @override
  void initState() {
    super.initState();
    developer.log('[ScannerPage] Initializing scanner page');

    // Initialize scanner
    _scanner.initialize();

    // Listen to Bluetooth state
    _bluetoothStateUnsubscribe = _scanner.bluetoothState.subscribe((state) {
      setState(() {
        _bluetoothState = state;
      });

      // Auto-start scan when ready
      if (state.canScan && !_isScanning && _devices.isEmpty && _scanToken == null) {
        developer.log('[ScannerPage] Ready to scan, auto-starting');
        _startScan();
      }
    });

    // Listen to scanning state
    _isScanningUnsubscribe = _scanner.isScanning.subscribe((scanning) {
      setState(() {
        _isScanning = scanning;
      });
    });

    // Listen to discovered devices
    _devicesUnsubscribe = _scanner.devices.subscribe((devices) {
      setState(() {
        if (devices.isEmpty && !_isScanning) {
          // Scanner stopped - keep existing devices, we'll show them with unknown RSSI
          return;
        }
        _devices.clear();
        _devices.addAll(devices);
      });
    });
  }

  @override
  void dispose() {
    developer.log('[ScannerPage] Disposing scanner page');
    if (_scanToken != null) {
      _scanner.stopScan(_scanToken!);
    }
    _devicesUnsubscribe?.call();
    _bluetoothStateUnsubscribe?.call();
    _isScanningUnsubscribe?.call();
    _scanner.dispose();
    super.dispose();
  }

  void _startScan() {
    _scanToken = _scanner.startScan();
  }

  void _stopScan() {
    if (_scanToken != null) {
      _scanner.stopScan(_scanToken!);
      _scanToken = null;
    }
  }

  String _getStatusMessage(BluetoothState? state) {
    if (state == null) return 'Initializing...';
    if (!state.isBluetoothOn) return 'Please turn on Bluetooth';
    if (!state.hasPermission) return 'Bluetooth permissions required';
    if (!state.isLocationServiceEnabled) return 'Location services required';
    if (state.canScan && _devices.isEmpty) return 'No devices found yet. Press Scan to start.';
    return 'Ready to scan';
  }

  @override
  Widget build(BuildContext context) {
    final bluetoothState = _bluetoothState;
    final isScanning = _isScanning;
    final canScan = bluetoothState?.canScan ?? false;
    final statusMessage = _getStatusMessage(bluetoothState);

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
                        if (!canScan && bluetoothState?.needsPermission == true) ...[
                          const SizedBox(height: 24),
                          ElevatedButton.icon(
                            onPressed: () {
                              // Permissions are checked automatically by the scanner
                              // Just trigger a state update
                              setState(() {});
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
                      final deviceName = device.name ?? '';
                      final deviceId = device.deviceId;
                      final rssiText = _isScanning ? '${device.rssi}' : 'Unknown';
                      return ListTile(
                        leading: Icon(
                          Icons.bluetooth,
                          color: _isScanning ? null : Colors.grey,
                        ),
                        title: Text(
                          deviceName.isEmpty ? 'Unknown Device' : deviceName,
                          style: TextStyle(
                            color: _isScanning ? null : Colors.grey[700],
                          ),
                        ),
                        subtitle: Text(
                          '$deviceId\nRSSI: $rssiText',
                          style: TextStyle(
                            color: _isScanning ? null : Colors.grey[600],
                          ),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          developer.log(
                            '[ScannerPage] ✅ Selected device: ${deviceName.isEmpty ? "Unknown" : deviceName} '
                            '(ID: $deviceId, RSSI: ${device.rssi})',
                          );
                          _stopScan();
                          context.push('/trainer?deviceId=$deviceId&deviceName=$deviceName');
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
