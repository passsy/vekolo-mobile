import 'package:context_plus/context_plus.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:vekolo/ble/ble_scanner.dart';
import 'package:vekolo/config/ble_config.dart';
import 'dart:developer' as developer;

/// BLE device scanner with auto-start when Bluetooth is ready.
///
/// Keeps discovered devices visible after scan stops.
/// Navigates to TrainerPage on device selection.
class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  late final BleScanner _scanner;
  final _devices = <DiscoveredDevice>[];
  VoidCallback? _devicesUnsubscribe;
  VoidCallback? _bluetoothStateUnsubscribe;
  VoidCallback? _isScanningUnsubscribe;
  BluetoothState? _bluetoothState;
  bool _isScanning = false;
  ScanToken? _scanToken;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Get scanner from dependency injection
    _scanner = bleScannerRef.of(context);
  }

  @override
  void initState() {
    super.initState();
    developer.log('[ScannerPage] Initializing scanner page');

    // Note: _scanner will be initialized in didChangeDependencies
    // We set up listeners in a post-frame callback to ensure _scanner is ready
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupListeners();
    });
  }

  void _setupListeners() {
    // Listen to Bluetooth state
    _bluetoothStateUnsubscribe = _scanner.bluetoothState.subscribe((state) {
      if (!mounted) return;
      setState(() {
        _bluetoothState = state;
      });

      // Auto-start scan when ready (even if we have old devices from previous session)
      if (state.canScan && !_isScanning && _scanToken == null) {
        developer.log('[ScannerPage] Ready to scan, auto-starting');
        _startScan();
      }
    });

    // Listen to scanning state
    _isScanningUnsubscribe = _scanner.isScanning.subscribe((scanning) {
      if (!mounted) return;
      setState(() {
        _isScanning = scanning;
      });
    });

    // Listen to discovered devices
    _devicesUnsubscribe = _scanner.devices.subscribe((devices) {
      if (!mounted) return;
      setState(() {
        // If scanner's device list becomes empty, keep our local devices.
        // This handles:
        // 1. User stopping scan (scanner clears devices)
        // 2. Race condition where devices beacon fires before isScanning beacon
        // The devices will be shown with "Unknown" RSSI when not scanning.
        if (devices.isEmpty && _devices.isNotEmpty) {
          // Keep existing devices - don't clear them
          return;
        }

        // Update device list when:
        // - New devices discovered (devices.isNotEmpty)
        // - Initial state (both empty)
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
    // Don't dispose scanner - it's managed by the app's dependency injection
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
                      final rssi = device.rssi;
                      final rssiText = _isScanning
                          ? (rssi != null ? '$rssi' : 'No signal')
                          : 'Unknown';
                      final isActive = _isScanning && rssi != null;

                      return ListTile(
                        leading: Icon(
                          Icons.bluetooth,
                          color: isActive ? null : Colors.grey,
                        ),
                        title: Text(
                          deviceName.isEmpty ? 'Unknown Device' : deviceName,
                          style: TextStyle(
                            color: isActive ? null : Colors.grey[700],
                          ),
                        ),
                        subtitle: Text(
                          '$deviceId\nRSSI: $rssiText',
                          style: TextStyle(
                            color: isActive ? null : Colors.grey[600],
                          ),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          developer.log(
                            '[ScannerPage] ✅ Selected device: ${deviceName.isEmpty ? "Unknown" : deviceName} '
                            '(ID: $deviceId, RSSI: ${rssi ?? "unknown"})',
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
