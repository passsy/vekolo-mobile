import 'package:flutter/material.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:vekolo/infrastructure/ble/ble_scanner.dart';
import 'dart:developer' as developer;

/// Page state enum for managing UI flow
enum UnknownDevicePageState {
  scanning,
  deviceList,
  connecting,
  review,
  success,
  error,
}

class UnknownDeviceReportPage extends StatefulWidget {
  const UnknownDeviceReportPage({super.key});

  @override
  State<UnknownDeviceReportPage> createState() => _UnknownDeviceReportPageState();
}

class _UnknownDeviceReportPageState extends State<UnknownDeviceReportPage> {
  UnknownDevicePageState _pageState = UnknownDevicePageState.scanning;

  // Fake devices for UI demonstration
  final List<DiscoveredDevice> _devices = [];
  DiscoveredDevice? _selectedDevice;
  String _errorMessage = '';
  String _collectedData = '';

  // Form for additional notes
  late FormGroup _form;

  @override
  void initState() {
    super.initState();
    developer.log('[UnknownDeviceReportPage] Initializing page');

    // Initialize form with notes field
    _form = FormGroup({
      'notes': FormControl<String>(value: ''),
    });

    // Auto-start scan (stubbed)
    _startScan();
  }

  @override
  void dispose() {
    developer.log('[UnknownDeviceReportPage] Disposing page');
    super.dispose();
  }

  /// STUB: Simulates BLE scanning with fake devices
  void _startScan() {
    developer.log('[UnknownDeviceReportPage] Starting scan (STUB)');

    setState(() {
      _pageState = UnknownDevicePageState.scanning;
      _devices.clear();
    });

    // Simulate discovering devices after a delay
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;

      // Generate fake devices for demonstration
      final fakeDevices = [
        _createFakeDevice('Wahoo KICKR 1234', 'AA:BB:CC:DD:EE:01', -45),
        _createFakeDevice('', 'AA:BB:CC:DD:EE:02', -67),
        _createFakeDevice('Garmin Edge', 'AA:BB:CC:DD:EE:03', -52),
        _createFakeDevice('Unknown BLE Device', 'AA:BB:CC:DD:EE:04', -78),
        _createFakeDevice('', 'AA:BB:CC:DD:EE:05', -89),
        _createFakeDevice('Polar H10', 'AA:BB:CC:DD:EE:06', -41),
      ];

      setState(() {
        _devices.addAll(fakeDevices);
        _devices.sort((a, b) => b.rssi.compareTo(a.rssi)); // Sort by signal strength
        _pageState = UnknownDevicePageState.deviceList;
      });
    });
  }

  /// STUB: Creates a fake DiscoveredDevice for demonstration
  DiscoveredDevice _createFakeDevice(String name, String id, int rssi) {
    return DiscoveredDevice(
      id: id,
      name: name,
      rssi: rssi,
      serviceUuids: const [],
    );
  }

  /// STUB: Simulates device connection and data collection
  void _onDeviceSelected(DiscoveredDevice device) {
    developer.log('[UnknownDeviceReportPage] Device selected (STUB): ${device.id}');

    setState(() {
      _selectedDevice = device;
      _pageState = UnknownDevicePageState.connecting;
    });

    // Simulate connection and data collection
    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;

      // Randomly simulate success or failure (80% success rate)
      final success = DateTime.now().second % 5 != 0;

      if (success) {
        // Generate fake collected data
        _collectedData = _generateFakeDeviceData(device);

        setState(() {
          _pageState = UnknownDevicePageState.review;
        });
      } else {
        // Simulate connection failure
        setState(() {
          _errorMessage = 'Failed to connect to device.\nPlease try again or select a different device.';
          _pageState = UnknownDevicePageState.error;
        });
      }
    });
  }

  /// STUB: Generates fake device data in TXT format
  String _generateFakeDeviceData(DiscoveredDevice device) {
    final now = DateTime.now();
    return '''
=== Vekolo Unknown Device Report ===
Generated: ${now.toIso8601String()}

Device Information:
- Device ID: ${device.id}
- Device Name: ${device.name.isEmpty ? "Unknown Device" : device.name}
- RSSI (Signal Strength): ${device.rssi} dBm
- Timestamp: ${now.toLocal()}

Discovered Services:
- Service UUID: 00001800-0000-1000-8000-00805f9b34fb (Generic Access)
- Service UUID: 00001801-0000-1000-8000-00805f9b34fb (Generic Attribute)
- Service UUID: 0000180a-0000-1000-8000-00805f9b34fb (Device Information)

Manufacturer Data:
- Data Length: 12 bytes
- Raw Data: 4C 00 02 15 A1 B2 C3 D4 E5 F6 07 08

Service Data:
- No service data available

Connection Parameters:
- Connection Interval: 7.5-15ms
- MTU: 185 bytes
- Latency: 0
- Supervision Timeout: 4000ms

Additional System Information:
- Platform: iOS 17.0.0
- App Version: 1.0.0
- Flutter Reactive BLE Version: 5.x.x

End of Report
''';
  }

  /// STUB: Handles form submission
  void _submitReport() {
    developer.log('[UnknownDeviceReportPage] Submitting report (STUB)');

    final notes = _form.control('notes').value as String?;
    developer.log('[UnknownDeviceReportPage] Additional notes: ${notes ?? "(none)"}');
    developer.log('[UnknownDeviceReportPage] Data length: ${_collectedData.length} characters');

    setState(() {
      _pageState = UnknownDevicePageState.success;
    });
  }

  /// Returns back to device list
  void _backToDeviceList() {
    setState(() {
      _selectedDevice = null;
      _errorMessage = '';
      _pageState = UnknownDevicePageState.deviceList;
    });
  }

  /// Retries connection to the same device
  void _retryConnection() {
    if (_selectedDevice != null) {
      _onDeviceSelected(_selectedDevice!);
    }
  }

  /// Builds RSSI indicator widget
  Widget _buildRssiIndicator(int rssi) {
    // Convert RSSI to signal strength (0-4 bars)
    int bars;
    Color color;

    if (rssi >= -50) {
      bars = 4;
      color = Colors.green;
    } else if (rssi >= -60) {
      bars = 3;
      color = Colors.lightGreen;
    } else if (rssi >= -70) {
      bars = 2;
      color = Colors.orange;
    } else if (rssi >= -80) {
      bars = 1;
      color = Colors.deepOrange;
    } else {
      bars = 1;
      color = Colors.red;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(4, (index) {
        return Container(
          width: 4,
          height: 8 + (index * 3),
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            color: index < bars ? color : Colors.grey[300],
            borderRadius: BorderRadius.circular(1),
          ),
        );
      }),
    );
  }

  /// Builds the scanning state UI
  Widget _buildScanningState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 24),
          const Text(
            'Scanning for all Bluetooth devices...',
            style: TextStyle(fontSize: 16),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'This may take a few moments',
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  /// Builds the device list state UI
  Widget _buildDeviceListState() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Select a device to report',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              Text(
                'Found ${_devices.length} device(s) nearby',
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
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
                      Icon(Icons.bluetooth_searching, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        'No devices found',
                        style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: _startScan,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Scan Again'),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _devices.length,
                  itemBuilder: (context, index) {
                    final device = _devices[index];
                    final displayName = device.name.isEmpty ? 'Unknown Device' : device.name;

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: ListTile(
                        leading: const Icon(Icons.bluetooth, size: 32),
                        title: Text(
                          displayName,
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Text(
                              device.id,
                              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                _buildRssiIndicator(device.rssi),
                                const SizedBox(width: 8),
                                Text(
                                  '${device.rssi} dBm',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ],
                            ),
                          ],
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _onDeviceSelected(device),
                      ),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _startScan,
              icon: const Icon(Icons.refresh),
              label: const Text('Scan Again'),
            ),
          ),
        ),
      ],
    );
  }

  /// Builds the connecting state UI
  Widget _buildConnectingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 24),
          const Text(
            'Connecting and collecting\ndevice information...',
            style: TextStyle(fontSize: 16),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          if (_selectedDevice != null) ...[
            Text(
              _selectedDevice!.name.isEmpty ? 'Unknown Device' : _selectedDevice!.name,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            Text(
              _selectedDevice!.id,
              style: TextStyle(fontSize: 12, color: Colors.grey[600], fontFamily: 'monospace'),
            ),
          ],
        ],
      ),
    );
  }

  /// Builds the review state UI
  Widget _buildReviewState() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ReactiveForm(
          formGroup: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.check_circle, size: 64, color: Colors.green),
              const SizedBox(height: 16),
              const Text(
                'Device information collected',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Successfully collected data from ${_selectedDevice?.name.isEmpty ?? true ? "Unknown Device" : _selectedDevice!.name}',
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
              const SizedBox(height: 24),
              const Text(
                'Data Preview:',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                height: 300,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    _collectedData,
                    style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Additional Information (optional):',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              ReactiveTextField(
                formControlName: 'notes',
                decoration: const InputDecoration(
                  hintText: 'Add brand, model, or any other notes...',
                  border: OutlineInputBorder(),
                  helperText: 'e.g., "Wahoo KICKR Core 2020 model"',
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _submitReport,
                  icon: const Icon(Icons.send),
                  label: const Text('Submit Report'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _backToDeviceList,
                  child: const Text('Back to Device List'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds the error state UI
  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 24),
            const Text(
              'Connection Failed',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage,
              style: const TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _retryConnection,
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _backToDeviceList,
                child: const Text('Back to Device List'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds the success state UI
  Widget _buildSuccessState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle_outline, size: 80, color: Colors.green),
            const SizedBox(height: 24),
            const Text(
              'Report Submitted',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Text(
              'Thank you for contributing to Vekolo!\n\nYour device report will help us improve support for more trainers.',
              style: TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  // Reset to initial state
                  setState(() {
                    _selectedDevice = null;
                    _errorMessage = '';
                    _collectedData = '';
                    _form.control('notes').value = '';
                  });
                  _startScan();
                },
                icon: const Icon(Icons.add),
                label: const Text('Report Another Device'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Report Unknown Device'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: switch (_pageState) {
        UnknownDevicePageState.scanning => _buildScanningState(),
        UnknownDevicePageState.deviceList => _buildDeviceListState(),
        UnknownDevicePageState.connecting => _buildConnectingState(),
        UnknownDevicePageState.review => _buildReviewState(),
        UnknownDevicePageState.error => _buildErrorState(),
        UnknownDevicePageState.success => _buildSuccessState(),
      },
    );
  }
}
