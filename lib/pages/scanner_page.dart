import 'package:chirp/chirp.dart';

import 'package:context_plus/context_plus.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:vekolo/app/refs.dart';
import 'package:vekolo/ble/ble_device.dart';
import 'package:vekolo/ble/ble_scanner.dart';
import 'package:vekolo/ble/transport_capabilities.dart';
import 'package:vekolo/domain/devices/fitness_device.dart';
import 'package:vekolo/domain/models/device_info.dart' as device_info;
import 'package:visibility_detector/visibility_detector.dart';

/// BLE device scanner with auto-start when Bluetooth is ready.
///
/// Keeps discovered devices visible after scan stops.
/// If [connectMode] is true, connects device via DeviceManager before navigation.
/// Otherwise, navigates directly to TrainerPage.
class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key, this.connectMode = false});

  final bool connectMode;

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
    _scanner = Refs.bleScanner.of(context);
  }

  @override
  void initState() {
    super.initState();
    Chirp.info('Initializing scanner page');

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupListeners();
    });
  }

  void _setupListeners() {
    _bluetoothStateUnsubscribe = _scanner.bluetoothState.subscribe((state) {
      if (!mounted) return;
      setState(() {
        _bluetoothState = state;
      });

      if (state.canScan && !_isScanning && _scanToken == null) {
        Chirp.info('Ready to scan, auto-starting');
        _startScan();
      }
    });

    _isScanningUnsubscribe = _scanner.isScanning.subscribe((scanning) {
      if (!mounted) return;
      setState(() {
        _isScanning = scanning;
      });
    });

    _devicesUnsubscribe = _scanner.devices.subscribe((devices) {
      if (!mounted) return;
      setState(() {
        if (devices.isEmpty && _devices.isNotEmpty) {
          return;
        }

        _devices.clear();
        _devices.addAll(devices);
      });
    });
  }

  @override
  void dispose() {
    Chirp.info('Disposing scanner page');
    if (_scanToken != null) {
      _scanner.stopScan(_scanToken!);
    }
    _devicesUnsubscribe?.call();
    _bluetoothStateUnsubscribe?.call();
    _isScanningUnsubscribe?.call();
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

  void _onVisibilityChanged(VisibilityInfo info) {
    if (!mounted) return;

    if (info.visibleFraction == 0) {
      Chirp.info('Page hidden, stopping scan');
      _stopScan();
    } else if (info.visibleFraction > 0) {
      final bluetoothState = _bluetoothState;
      if (bluetoothState != null && bluetoothState.canScan && !_isScanning && _scanToken == null) {
        Chirp.info('Page visible again, restarting scan');
        _startScan();
      }
    }
  }

  Future<void> _showConnectingDialog(BuildContext context, DiscoveredDevice device) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _DeviceConnectingDialog(
        device: device,
        onConnect: (fitnessDevice, autoAssignments, isReconnect) {
          final message = isReconnect
              ? '${fitnessDevice.name} reconnected'
              : (autoAssignments.isEmpty
                    ? '${fitnessDevice.name} added and connected'
                    : '${fitnessDevice.name} connected and assigned as ${autoAssignments.join(', ')}');

          scaffoldMessenger.showSnackBar(SnackBar(content: Text(message)));
        },
      ),
    );
  }

  String _getStatusMessage(BluetoothState? state) {
    if (state == null) return 'Initializing...';
    if (!state.isBluetoothOn) return 'Please turn on Bluetooth';
    if (!state.hasPermission) return 'Bluetooth permissions required';
    if (!state.isLocationServiceEnabled) return 'Location services required';
    if (state.canScan && _devices.isEmpty) return 'No devices found yet. Press Scan to start.';
    return 'Ready to scan';
  }

  Set<device_info.DeviceDataType> _detectCapabilities(BuildContext context, DiscoveredDevice device) {
    try {
      final transportRegistry = Refs.transportRegistry.of(context);
      final transports = transportRegistry.detectCompatibleTransports(device, deviceId: device.deviceId);

      final capabilities = <device_info.DeviceDataType>{};

      for (final transport in transports) {
        if (transport is PowerSource) capabilities.add(device_info.DeviceDataType.power);
        if (transport is CadenceSource) capabilities.add(device_info.DeviceDataType.cadence);
        if (transport is SpeedSource) capabilities.add(device_info.DeviceDataType.speed);
        if (transport is HeartRateSource) capabilities.add(device_info.DeviceDataType.heartRate);
      }

      // Dispose transports since we only needed them for capability detection
      for (final transport in transports) {
        transport.dispose();
      }

      return capabilities;
    } catch (e) {
      Chirp.info('Error detecting capabilities: $e');
      return {};
    }
  }

  @override
  Widget build(BuildContext context) {
    final bluetoothState = _bluetoothState;
    final isScanning = _isScanning;
    final canScan = bluetoothState?.canScan ?? false;
    final statusMessage = _getStatusMessage(bluetoothState);

    return VisibilityDetector(
      key: const Key('scanner-page-visibility'),
      onVisibilityChanged: _onVisibilityChanged,
      child: Scaffold(
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
                            style: TextStyle(fontSize: 16, color: canScan ? Colors.grey[600] : Colors.red[400]),
                            textAlign: TextAlign.center,
                          ),
                          if (!canScan && bluetoothState?.needsPermission == true) ...[
                            const SizedBox(height: 24),
                            ElevatedButton.icon(
                              onPressed: () {
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
                  : Builder(
                      builder: (context) {
                        final deviceManager = Refs.deviceManager.of(context);
                        final managedDevices = deviceManager.devicesBeacon.value;
                        final connectedDeviceIds = <String>{};
                        for (final managedDevice in managedDevices) {
                          if (managedDevice.connectionState.value == device_info.ConnectionState.connected) {
                            connectedDeviceIds.add(managedDevice.id);
                          }
                        }

                        return ListView.builder(
                          itemCount: _devices.length,
                          itemBuilder: (context, index) {
                            final device = _devices[index];
                            final capabilities = _detectCapabilities(context, device);
                            final isAlreadyConnected = connectedDeviceIds.contains(device.deviceId);

                            return _DeviceListTile(
                              device: device,
                              isScanning: _isScanning,
                              isAlreadyConnected: isAlreadyConnected,
                              capabilities: capabilities,
                              connectMode: widget.connectMode,
                              onTap: () async {
                                Chirp.info(
                                  '✅ Selected device: ${device.name?.isEmpty ?? true ? "Unknown" : device.name} '
                                  '(ID: ${device.deviceId}, RSSI: ${device.rssi ?? "unknown"})',
                                );
                                _stopScan();

                                if (widget.connectMode) {
                                  if (context.mounted) {
                                    final navigator = Navigator.of(context);
                                    final parentContext = navigator.context;
                                    navigator.pop();
                                    await Future.delayed(const Duration(milliseconds: 100));
                                    if (parentContext.mounted) {
                                      await _showConnectingDialog(parentContext, device);
                                    }
                                  }
                                } else {
                                  if (context.mounted) {
                                    final deviceName = device.name ?? '';
                                    context.push('/trainer?deviceId=${device.deviceId}&deviceName=$deviceName');
                                  }
                                }
                              },
                            );
                          },
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: OutlinedButton.icon(
                onPressed: () {
                  Chirp.info('Navigating to unknown device report page');
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
      ),
    );
  }
}

class _DeviceListTile extends StatelessWidget {
  const _DeviceListTile({
    required this.device,
    required this.isScanning,
    required this.isAlreadyConnected,
    required this.capabilities,
    required this.connectMode,
    required this.onTap,
  });

  final DiscoveredDevice device;
  final bool isScanning;
  final bool isAlreadyConnected;
  final Set<device_info.DeviceDataType> capabilities;
  final bool connectMode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final deviceName = device.name ?? '';
    final deviceId = device.deviceId;
    final rssi = device.rssi;
    final isActive = isScanning && rssi != null;

    final leadingIcon = isAlreadyConnected ? Icons.check_circle : Icons.bluetooth;
    final leadingColor = isAlreadyConnected ? Colors.green : (isActive ? null : Colors.grey);

    final displayName = deviceName.isEmpty ? 'Unknown Device' : deviceName;
    final titleColor = isAlreadyConnected ? Colors.green[700] : (isActive ? null : Colors.grey[700]);

    final subtitleColor = isAlreadyConnected ? Colors.green[600] : (isActive ? null : Colors.grey[600]);

    final trailingIcon = isAlreadyConnected
        ? const Icon(Icons.check, color: Colors.green)
        : const Icon(Icons.chevron_right);

    final isTapDisabled = isAlreadyConnected && connectMode;

    return ListTile(
      leading: Icon(leadingIcon, color: leadingColor),
      title: Text(displayName, style: TextStyle(color: titleColor)),
      subtitle: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  isAlreadyConnected ? '$deviceId\nAlready connected' : deviceId,
                  style: TextStyle(color: subtitleColor),
                ),
              ),
              if (!isAlreadyConnected && isScanning && rssi != null)
                _buildSignalStrengthIcon(rssi)
              else if (!isAlreadyConnected && isScanning)
                Icon(Icons.signal_cellular_off, size: 24, color: Colors.grey[400])
              else if (!isAlreadyConnected)
                Icon(Icons.signal_cellular_off, size: 24, color: Colors.grey[300]),
            ],
          ),
          if (capabilities.isNotEmpty) ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                if (capabilities.contains(device_info.DeviceDataType.power))
                  _buildCapabilityChip(context, 'Power', Icons.bolt),
                if (capabilities.contains(device_info.DeviceDataType.cadence))
                  _buildCapabilityChip(context, 'Cadence', Icons.refresh),
                if (capabilities.contains(device_info.DeviceDataType.speed))
                  _buildCapabilityChip(context, 'Speed', Icons.speed),
                if (capabilities.contains(device_info.DeviceDataType.heartRate))
                  _buildCapabilityChip(context, 'HR', Icons.favorite),
              ],
            ),
          ],
        ],
      ),
      trailing: trailingIcon,
      enabled: !isAlreadyConnected || !connectMode,
      onTap: isTapDisabled ? null : onTap,
    );
  }

  Widget _buildCapabilityChip(BuildContext context, String label, IconData icon) {
    return Chip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      ),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      labelPadding: const EdgeInsets.symmetric(horizontal: 6),
    );
  }

  Widget _buildSignalStrengthIcon(int rssi) {
    IconData icon;
    Color color;

    if (rssi >= -50) {
      icon = Icons.signal_cellular_4_bar;
      color = Colors.green;
    } else if (rssi >= -70) {
      icon = Icons.signal_cellular_4_bar;
      color = Colors.lightGreen;
    } else if (rssi >= -80) {
      icon = Icons.signal_cellular_alt;
      color = Colors.yellow[700]!;
    } else if (rssi >= -90) {
      icon = Icons.signal_cellular_alt_2_bar;
      color = Colors.orange[700]!;
    } else if (rssi >= -100) {
      icon = Icons.signal_cellular_alt_1_bar;
      color = Colors.red[700]!;
    } else {
      icon = Icons.signal_cellular_off;
      color = Colors.red[900]!;
    }

    return Icon(icon, size: 24, color: color);
  }
}

/// Dialog shown while connecting to a selected device.
class _DeviceConnectingDialog extends StatefulWidget {
  const _DeviceConnectingDialog({required this.device, required this.onConnect});

  final DiscoveredDevice device;
  final void Function(FitnessDevice fitnessDevice, List<String> autoAssignments, bool isReconnect) onConnect;

  @override
  State<_DeviceConnectingDialog> createState() => _DeviceConnectingDialogState();
}

class _DeviceConnectingDialogState extends State<_DeviceConnectingDialog> {
  _DialogConnectionState _state = _DialogConnectionState.connecting;
  String? _errorMessage;
  String _statusMessage = 'Initializing...';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _connectToDevice();
    });
  }

  Future<void> _connectToDevice() async {
    if (!mounted) return;

    setState(() {
      _state = _DialogConnectionState.connecting;
      _errorMessage = null;
      _statusMessage = 'Initializing device...';
    });

    try {
      final deviceManager = Refs.deviceManager.of(context);

      // Check if device already exists in manager (reconnection scenario)
      final existingDevice = deviceManager.devices.where((d) => d.id == widget.device.deviceId).firstOrNull;
      final isReconnect = existingDevice != null;

      FitnessDevice fitnessDevice;
      BleDevice? newDevice; // Only created for new devices, before adding to manager

      if (isReconnect) {
        Chirp.info('Device already exists in manager, reconnecting');
        fitnessDevice = existingDevice;
      } else {
        setState(() => _statusMessage = 'Detecting device type...');
        final transportRegistry = Refs.transportRegistry.of(context);

        final transports = transportRegistry.detectCompatibleTransports(
          widget.device,
          deviceId: widget.device.deviceId,
        );

        Chirp.info('Found ${transports.length} compatible transport(s)');

        if (transports.isEmpty) {
          throw Exception(
            'Device does not advertise any recognized fitness services. '
            'Advertised services: ${widget.device.serviceUuids.map((uuid) => uuid.toString()).join(', ')}',
          );
        }

        setState(() => _statusMessage = 'Creating device profile...');
        final blePlatform = Refs.blePlatform.of(context);
        newDevice = BleDevice(
          id: widget.device.deviceId,
          name: widget.device.name ?? 'Unknown Device',
          transports: transports,
          platform: blePlatform,
          discoveredDevice: widget.device,
        );
        fitnessDevice = newDevice; // Use temporarily for connection
      }

      if (!mounted) return;

      // Add device to manager first (for new devices)
      if (!isReconnect && newDevice != null) {
        setState(() => _statusMessage = 'Registering device...');
        fitnessDevice = await deviceManager.addOrGetExistingDevice(newDevice);
      }

      if (!mounted) return;

      setState(() => _statusMessage = 'Establishing Bluetooth connection...');
      Chirp.info(
        '${isReconnect ? 'Reconnecting' : 'Connecting'} device: ${fitnessDevice.name}',
      );
      await deviceManager.connectDevice(fitnessDevice.id).value;

      if (!mounted) return;

      setState(() => _statusMessage = 'Configuring device assignments...');
      final autoAssignments = <String>[];

      // Auto-assign all capabilities that are not already assigned
      // Check after connection so supportsErgMode and capabilities are accurate
      if (fitnessDevice.supportsErgMode && deviceManager.primaryTrainerBeacon.value == null) {
        deviceManager.assignPrimaryTrainer(fitnessDevice.id);
        autoAssignments.add('primary trainer');
      }

      if (fitnessDevice.capabilities.contains(device_info.DeviceDataType.power) &&
          deviceManager.powerSourceBeacon.value == null) {
        deviceManager.assignPowerSource(fitnessDevice.id);
        autoAssignments.add('power source');
      }

      if (fitnessDevice.capabilities.contains(device_info.DeviceDataType.cadence) &&
          deviceManager.cadenceSourceBeacon.value == null) {
        deviceManager.assignCadenceSource(fitnessDevice.id);
        autoAssignments.add('cadence source');
      }

      if (fitnessDevice.capabilities.contains(device_info.DeviceDataType.speed) &&
          deviceManager.speedSourceBeacon.value == null) {
        deviceManager.assignSpeedSource(fitnessDevice.id);
        autoAssignments.add('speed source');
      }

      if (fitnessDevice.capabilities.contains(device_info.DeviceDataType.heartRate) &&
          deviceManager.heartRateSourceBeacon.value == null) {
        deviceManager.assignHeartRateSource(fitnessDevice.id);
        autoAssignments.add('heart rate source');
      }

      if (!mounted) return;

      setState(() {
        _statusMessage = 'Connection established!';
        _state = _DialogConnectionState.connected;
      });

      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;

      Navigator.of(context).pop();
      if (!mounted) return;

      widget.onConnect(fitnessDevice, autoAssignments, isReconnect);
    } catch (e, stackTrace) {
      Chirp.error('Error connecting to device', error: e, stackTrace: stackTrace);

      if (!mounted) return;

      setState(() {
        _state = _DialogConnectionState.error;
        _errorMessage = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final deviceName = widget.device.name ?? 'Unknown Device';

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            _state == _DialogConnectionState.connecting
                ? Icons.bluetooth_searching
                : _state == _DialogConnectionState.connected
                ? Icons.check_circle
                : Icons.error,
            color: _state == _DialogConnectionState.connecting
                ? Colors.blue
                : _state == _DialogConnectionState.connected
                ? Colors.green
                : Colors.red,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _state == _DialogConnectionState.connecting
                  ? 'Connecting...'
                  : _state == _DialogConnectionState.connected
                  ? 'Connected!'
                  : 'Connection Failed',
              style: TextStyle(color: _state == _DialogConnectionState.error ? Colors.red : null),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Device: $deviceName', style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          if (_state == _DialogConnectionState.connecting) ...[
            Center(
              child: Column(
                children: [const CircularProgressIndicator(), const SizedBox(height: 16), Text(_statusMessage)],
              ),
            ),
          ] else if (_state == _DialogConnectionState.connected) ...[
            const Row(
              children: [
                Icon(Icons.check, color: Colors.green),
                SizedBox(width: 8),
                Text('Successfully connected!'),
              ],
            ),
          ] else if (_state == _DialogConnectionState.error) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.error, color: Colors.red, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Error',
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _errorMessage ?? 'Unknown error occurred',
                    style: TextStyle(color: Colors.red[900], fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
      actions: [
        if (_state == _DialogConnectionState.error) ...[
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          ElevatedButton.icon(onPressed: _connectToDevice, icon: const Icon(Icons.refresh), label: const Text('Retry')),
        ] else if (_state == _DialogConnectionState.connecting)
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
      ],
    );
  }
}

enum _DialogConnectionState { connecting, connected, error }
