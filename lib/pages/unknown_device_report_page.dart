import 'package:flutter/material.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'dart:developer' as developer;
import 'dart:io' show Platform;
import 'dart:async';
import 'package:clock/clock.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:context_plus/context_plus.dart';
import 'package:vekolo/config/api_config.dart';
import 'package:vekolo/models/user.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;

/// Page state enum for managing UI flow
enum UnknownDevicePageState { scanning, deviceList, connecting, review, success, error }

/// Simple device data structure for unknown device reporting
class _SimpleDevice {
  final String id;
  final String name;
  final int rssi;
  final List<fbp.Guid> serviceUuids;

  _SimpleDevice({
    required this.id,
    required this.name,
    required this.rssi,
    required this.serviceUuids,
  });
}

/// Collects device BLE data and generates email report for support.
///
/// Scans for all Bluetooth devices (no filter), connects to selected device,
/// reads services/characteristics, then opens email client with formatted report.
class UnknownDeviceReportPage extends StatefulWidget {
  const UnknownDeviceReportPage({super.key});

  @override
  State<UnknownDeviceReportPage> createState() => _UnknownDeviceReportPageState();
}

class _UnknownDeviceReportPageState extends State<UnknownDeviceReportPage> {
  UnknownDevicePageState _pageState = UnknownDevicePageState.scanning;

  // Real BLE devices - use a simple data class instead of the scanner's DiscoveredDevice
  final List<_SimpleDevice> _devices = [];
  _SimpleDevice? _selectedDevice;
  String _errorMessage = '';
  String _collectedData = '';

  // Store BLE device and services for report regeneration
  fbp.BluetoothDevice? _selectedBleDevice;
  List<fbp.BluetoothService>? _selectedDeviceServices;

  // Progress tracking for service reading
  int _currentServiceIndex = 0;
  int _totalServices = 0;

  // BLE scan subscription
  StreamSubscription<List<fbp.ScanResult>>? _scanSubscription;
  bool _isScanning = false;

  // Form for additional notes
  late FormGroup _form;

  @override
  void initState() {
    super.initState();
    developer.log('[UnknownDeviceReportPage] Initializing page');

    // Initialize form with notes field
    _form = FormGroup({'notes': FormControl<String>(value: '')});

    // Auto-start scan (stubbed)
    _startScan();
  }

  @override
  void dispose() {
    developer.log('[UnknownDeviceReportPage] Disposing page');
    _stopScan();
    super.dispose();
  }

  /// Starts real BLE scanning for all devices
  Future<void> _startScan() async {
    developer.log('[UnknownDeviceReportPage] Starting real BLE scan');

    setState(() {
      _pageState = UnknownDevicePageState.scanning;
      _devices.clear();
      _isScanning = true;
    });

    try {
      // Cancel any existing subscription
      await _scanSubscription?.cancel();

      // Stop any ongoing scan
      await fbp.FlutterBluePlus.stopScan();

      // Start scanning for ALL BLE devices (no service filter for unknown device reporting)
      await fbp.FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));

      // Map to track unique devices by ID
      final Map<String, _SimpleDevice> deviceMap = {};

      // Listen to scan results
      _scanSubscription = fbp.FlutterBluePlus.scanResults.listen(
        (results) {
          bool hasNewDevices = false;

          for (final result in results) {
            final deviceId = result.device.remoteId.str;

            // Check if this is a new device
            if (!deviceMap.containsKey(deviceId)) {
              hasNewDevices = true;

              // Convert to _SimpleDevice
              deviceMap[deviceId] = _SimpleDevice(
                id: deviceId,
                name: result.device.platformName,
                rssi: result.rssi,
                serviceUuids: result.advertisementData.serviceUuids,
              );
            }
          }

          if (hasNewDevices && mounted) {
            setState(() {
              _devices.clear();
              _devices.addAll(deviceMap.values);
              // Don't sort - show devices in the order they appear

              // Switch to device list state once we have at least one device
              if (_pageState == UnknownDevicePageState.scanning && _devices.isNotEmpty) {
                _pageState = UnknownDevicePageState.deviceList;
              }
            });
          }
        },
        onError: (Object e, StackTrace stackTrace) {
          developer.log('[UnknownDeviceReportPage] Scan error: $e', stackTrace: stackTrace);
          if (mounted) {
            setState(() {
              _errorMessage = 'Failed to scan for devices: $e';
              _pageState = UnknownDevicePageState.error;
            });
          }
        },
      );

      developer.log('[UnknownDeviceReportPage] Scan started, waiting for devices...');
    } catch (e, stackTrace) {
      developer.log('[UnknownDeviceReportPage] Failed to start scan: $e', stackTrace: stackTrace);
      if (mounted) {
        setState(() {
          _errorMessage =
              'Failed to start Bluetooth scan.\nPlease ensure Bluetooth is enabled and permissions are granted.';
          _pageState = UnknownDevicePageState.error;
        });
      }
    }
  }

  /// Stops the current BLE scan
  Future<void> _stopScan() async {
    if (!_isScanning) return;

    developer.log('[UnknownDeviceReportPage] Stopping scan');
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    await fbp.FlutterBluePlus.stopScan();

    if (mounted) {
      setState(() {
        _isScanning = false;
      });
    }
  }

  /// Connects to device and collects data
  Future<void> _onDeviceSelected(_SimpleDevice device) async {
    developer.log('[UnknownDeviceReportPage] Device selected: ${device.id}');

    // Get current user from AuthService before async operations
    final authService = authServiceRef.of(context);
    final user = authService.currentUser.value;

    // Stop scanning when device is selected
    await _stopScan();

    setState(() {
      _selectedDevice = device;
      _pageState = UnknownDevicePageState.connecting;
      // Reset progress
      _currentServiceIndex = 0;
      _totalServices = 0;
    });

    try {
      // Find the BLE device
      final bleDevice = fbp.BluetoothDevice.fromId(device.id);

      // Wrap the connection process with a timeout
      await Future.any([
        Future<void>(() async {
          // Connect to the device
          await bleDevice.connect();

          developer.log('[UnknownDeviceReportPage] Connected to device: ${device.id}');

          // Discover services
          final services = await bleDevice.discoverServices();

          developer.log('[UnknownDeviceReportPage] Discovered ${services.length} services');

          // Store for later regeneration with user info
          _selectedBleDevice = bleDevice;
          _selectedDeviceServices = services;

          // Initialize progress tracking
          if (mounted) {
            setState(() {
              _totalServices = services.length;
              _currentServiceIndex = 0;
            });
          }

          // Collect device data with user info
          _collectedData = await _generateDeviceData(
            device,
            bleDevice,
            services,
            userInfo: user,
            onProgress: (current) {
              if (mounted) {
                setState(() {
                  _currentServiceIndex = current;
                });
              }
            },
          );

          // Disconnect from device
          await bleDevice.disconnect();

          if (mounted) {
            setState(() {
              _pageState = UnknownDevicePageState.review;
            });
          }
        }),
        Future.delayed(const Duration(seconds: 10), () {
          throw TimeoutException('Connection timed out after 10 seconds');
        }),
      ]);
    } on TimeoutException catch (e, stackTrace) {
      developer.log('[UnknownDeviceReportPage] Connection timeout: $e', stackTrace: stackTrace);

      if (mounted) {
        setState(() {
          _errorMessage = 'Connection timed out after 10 seconds.\nPlease try again or select a different device.';
          _pageState = UnknownDevicePageState.error;
        });
      }
    } catch (e, stackTrace) {
      developer.log('[UnknownDeviceReportPage] Connection error: $e', stackTrace: stackTrace);

      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to connect to device.\nError: $e\n\nPlease try again or select a different device.';
          _pageState = UnknownDevicePageState.error;
        });
      }
    }
  }

  /// Generates device data report from real BLE connection
  Future<String> _generateDeviceData(
    _SimpleDevice device,
    fbp.BluetoothDevice bleDevice,
    List<fbp.BluetoothService> services, {
    User? userInfo,
    void Function(int currentService)? onProgress,
  }) async {
    final now = clock.now();
    final buffer = StringBuffer();

    buffer.writeln('=== Vekolo Unknown Device Report ===');
    buffer.writeln('Generated: ${now.toIso8601String()}');
    buffer.writeln();

    buffer.writeln('User Information:');
    if (userInfo != null) {
      buffer.writeln('- User ID: ${userInfo.id}');
      buffer.writeln('- Name: ${userInfo.name}');
      buffer.writeln('- Email: ${userInfo.email}');
    } else {
      buffer.writeln('- Not available (user not logged in)');
    }
    buffer.writeln();

    buffer.writeln('Device Information:');
    buffer.writeln('- Device ID: ${device.id}');
    buffer.writeln('- Device Name: ${device.name.isEmpty ? "Unknown Device" : device.name}');
    buffer.writeln('- RSSI (Signal Strength): ${device.rssi} dBm');
    buffer.writeln('- Timestamp: ${now.toLocal()}');
    buffer.writeln();

    buffer.writeln('Discovered Services (${services.length} total):');
    for (var i = 0; i < services.length; i++) {
      final service = services[i];

      // Update progress
      onProgress?.call(i + 1);

      buffer.writeln('- Service UUID: ${service.uuid}');

      // List characteristics for each service
      if (service.characteristics.isNotEmpty) {
        for (final characteristic in service.characteristics) {
          buffer.writeln('  └─ Characteristic: ${characteristic.uuid}');
          buffer.writeln('     Properties: ${_formatCharacteristicProperties(characteristic)}');

          // Try to read characteristic value if readable
          if (characteristic.properties.read) {
            try {
              final value = await characteristic.read().timeout(const Duration(seconds: 2));
              if (value.isNotEmpty) {
                final hexValue = value.map((byte) => byte.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
                buffer.writeln('     Value: $hexValue (${value.length} bytes)');
              } else {
                buffer.writeln('     Value: (empty)');
              }
            } catch (e) {
              buffer.writeln('     Value: (read failed: $e)');
              developer.log('[UnknownDeviceReportPage] Failed to read characteristic ${characteristic.uuid}: $e');
            }
          }
        }
      }
    }
    buffer.writeln();

    // Try to get MTU if available
    try {
      final mtu = await bleDevice.mtu.first;
      buffer.writeln('Connection Parameters:');
      buffer.writeln('- MTU: $mtu bytes');
    } catch (e) {
      developer.log('[UnknownDeviceReportPage] Could not read MTU: $e');
    }
    buffer.writeln();

    buffer.writeln('Additional System Information:');
    buffer.writeln('- Platform: ${Platform.operatingSystem}');
    buffer.writeln('- App Version: 1.0.0');
    buffer.writeln('- Flutter Blue Plus Version: 1.36.8');
    buffer.writeln();

    buffer.writeln('End of Report');

    return buffer.toString();
  }

  /// Formats characteristic properties for display
  String _formatCharacteristicProperties(fbp.BluetoothCharacteristic characteristic) {
    final props = <String>[];
    if (characteristic.properties.read) props.add('Read');
    if (characteristic.properties.write) props.add('Write');
    if (characteristic.properties.writeWithoutResponse) props.add('WriteWithoutResponse');
    if (characteristic.properties.notify) props.add('Notify');
    if (characteristic.properties.indicate) props.add('Indicate');
    return props.isEmpty ? 'None' : props.join(', ');
  }

  /// Handles form submission - sends report via email
  Future<void> _submitReport() async {
    developer.log('[UnknownDeviceReportPage] Submitting report');

    try {
      // Get current user
      final authService = authServiceRef.of(context);
      final user = authService.currentUser.value;

      // Regenerate report with user information
      if (_selectedDevice != null && _selectedBleDevice != null && _selectedDeviceServices != null) {
        _collectedData = await _generateDeviceData(
          _selectedDevice!,
          _selectedBleDevice!,
          _selectedDeviceServices!,
          userInfo: user,
        );
      }

      final notes = _form.control('notes').value as String?;
      developer.log('[UnknownDeviceReportPage] Additional notes: ${notes ?? "(none)"}');

      // Build email content
      final emailBody = StringBuffer();
      emailBody.writeln(_collectedData);

      if (notes != null && notes.isNotEmpty) {
        emailBody.writeln('\n');
        emailBody.writeln('=== Additional Notes ===');
        emailBody.writeln(notes);
      }

      // Create mailto URL
      final emailAddress = 'support@vekolo.cc';
      final subject = Uri.encodeComponent('Unknown Device Report - ${_selectedDevice?.name ?? "Unknown Device"}');
      final body = Uri.encodeComponent(emailBody.toString());

      final mailtoUrl = Uri.parse('mailto:$emailAddress?subject=$subject&body=$body');

      developer.log('[UnknownDeviceReportPage] Opening email client with mailto URL');

      // Launch email client
      if (await canLaunchUrl(mailtoUrl)) {
        await launchUrl(mailtoUrl);

        // Show success state
        if (mounted) {
          setState(() {
            _pageState = UnknownDevicePageState.success;
          });
        }
      } else {
        throw Exception('Could not launch email client');
      }
    } catch (e, stackTrace) {
      developer.log('[UnknownDeviceReportPage] Error sending email: $e');
      developer.log(stackTrace.toString());

      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to open email client.\nPlease ensure you have a mail app configured.';
          _pageState = UnknownDevicePageState.error;
        });
      }
    }
  }

  /// Returns back to device list
  void _backToDeviceList() {
    setState(() {
      _selectedDevice = null;
      _errorMessage = '';
      _pageState = UnknownDevicePageState.deviceList;
      // Reset progress
      _currentServiceIndex = 0;
      _totalServices = 0;
    });
  }

  /// Retries connection to the same device
  void _retryConnection() {
    if (_selectedDevice != null) {
      _onDeviceSelected(_selectedDevice!);
    }
  }

  /// Builds RSSI indicator widget with icon and color
  Widget _buildRssiIndicator(int rssi) {
    // Convert RSSI to signal strength level and color using switch expression
    final (IconData icon, Color color, String strength) = switch (rssi) {
      >= -50 => (Icons.signal_cellular_4_bar, Colors.green, 'Excellent'),
      >= -60 => (Icons.signal_cellular_alt, Colors.lightGreen, 'Good'),
      >= -70 => (Icons.signal_cellular_alt_2_bar, Colors.orange, 'Fair'),
      >= -80 => (Icons.signal_cellular_alt_1_bar, Colors.deepOrange, 'Weak'),
      _ => (Icons.signal_cellular_0_bar, Colors.red, 'Poor'),
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(
          strength,
          style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500),
        ),
      ],
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
              const Text('Select a device to report', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
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
                      Text('No devices found', style: TextStyle(fontSize: 16, color: Colors.grey[600])),
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
                        title: Text(displayName, style: const TextStyle(fontWeight: FontWeight.w500)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Text(device.id, style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                _buildRssiIndicator(device.rssi),
                                const SizedBox(width: 8),
                                Text('${device.rssi} dBm', style: const TextStyle(fontSize: 12)),
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
            child: _isScanning
                ? OutlinedButton.icon(
                    onPressed: _stopScan,
                    icon: const Icon(Icons.stop),
                    label: const Text('Stop Scan'),
                  )
                : OutlinedButton.icon(
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
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32.0),
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
            if (_totalServices > 0) ...[
              const SizedBox(height: 24),
              LinearProgressIndicator(
                value: _currentServiceIndex / _totalServices,
                backgroundColor: Colors.grey[300],
                valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).colorScheme.primary),
              ),
              const SizedBox(height: 8),
              Text(
                'Reading service $_currentServiceIndex of $_totalServices',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ],
        ),
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
              const Text('Device information collected', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                'Successfully collected data from ${_selectedDevice?.name.isEmpty ?? true ? "Unknown Device" : _selectedDevice!.name}',
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
              const SizedBox(height: 24),
              const Text('Data Preview:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
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
                  child: SelectableText(_collectedData, style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
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
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(onPressed: _backToDeviceList, child: const Text('Back to Device List')),
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
            const Text('Connection Failed', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Text(_errorMessage, style: const TextStyle(fontSize: 16), textAlign: TextAlign.center),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _retryConnection,
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(onPressed: _backToDeviceList, child: const Text('Back to Device List')),
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
            const Text('Report Submitted', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
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
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
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
