import 'dart:developer' as developer;

import 'package:context_plus/context_plus.dart';
import 'package:flutter/material.dart';
import 'package:vekolo/domain/devices/device_manager.dart';
import 'package:vekolo/domain/devices/fitness_device.dart';
import 'package:vekolo/domain/models/device_info.dart' as device_info;
import 'package:vekolo/state/device_state.dart';

/// Page for managing connected fitness devices and assigning them to data sources.
///
/// Allows users to:
/// - Scan for and connect to Bluetooth devices
/// - Assign devices to specific roles (primary trainer, power/cadence/HR sources)
/// - View device connection status and capabilities
/// - Manage device connections (connect/disconnect)
///
/// The page shows separate sections for:
/// - Primary Trainer (ERG control + can provide data)
/// - Power Source (dedicated power meter)
/// - Cadence Source (dedicated cadence sensor)
/// - Heart Rate Source (dedicated HR monitor)
/// - Other Devices (unassigned devices available for assignment)
///
/// Used from anywhere in the app via go_router route '/devices'.
class DevicesPage extends StatefulWidget {
  const DevicesPage({super.key});

  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  bool _isConnecting = false;
  String? _connectingDeviceId;

  @override
  Widget build(BuildContext context) {
    final deviceManager = deviceManagerRef.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Devices'),
        actions: [
          TextButton.icon(
            onPressed: () {
              // TODO: Phase 4.2 - Implement device scanning
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Device scanning will be implemented with BLE scanner')));
            },
            icon: const Icon(Icons.search),
            label: const Text('Scan'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildPrimaryTrainerSection(context, deviceManager),
          const SizedBox(height: 24),
          _buildDataSourceSection(
            context,
            deviceManager,
            title: 'POWER SOURCE',
            icon: Icons.bolt,
            assignedDevice: deviceManager.powerSource,
          ),
          const SizedBox(height: 16),
          _buildDataSourceSection(
            context,
            deviceManager,
            title: 'CADENCE SOURCE',
            icon: Icons.refresh,
            assignedDevice: deviceManager.cadenceSource,
          ),
          const SizedBox(height: 16),
          _buildDataSourceSection(
            context,
            deviceManager,
            title: 'HEART RATE',
            icon: Icons.favorite,
            assignedDevice: deviceManager.heartRateSource,
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 24),
          _buildOtherDevicesSection(context, deviceManager),
        ],
      ),
    );
  }

  Widget _buildPrimaryTrainerSection(BuildContext context, DeviceManager deviceManager) {
    final trainer = deviceManager.primaryTrainer;
    final hasTrainer = trainer != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.directions_bike, size: 20),
            const SizedBox(width: 8),
            Text(
              'PRIMARY TRAINER',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (hasTrainer)
          _buildDeviceCard(context, device: trainer, onDisconnect: () => _handleDisconnect(trainer))
        else
          _buildEmptyState(context, 'No trainer assigned'),
      ],
    );
  }

  Widget _buildDataSourceSection(
    BuildContext context,
    DeviceManager deviceManager, {
    required String title,
    required IconData icon,
    required FitnessDevice? assignedDevice,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 8),
            Text(title, style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 12),
        if (assignedDevice != null)
          _buildDeviceCard(context, device: assignedDevice, onDisconnect: () => _handleDisconnect(assignedDevice))
        else
          OutlinedButton.icon(
            onPressed: () {
              // TODO: Show device picker dialog
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Device assignment coming in Phase 4.4')));
            },
            icon: const Icon(Icons.add),
            label: const Text('Assign Device'),
          ),
      ],
    );
  }

  Widget _buildOtherDevicesSection(BuildContext context, DeviceManager deviceManager) {
    // Get unassigned devices
    final allDevices = deviceManager.devices;
    final assignedDeviceIds = {
      deviceManager.primaryTrainer?.id,
      deviceManager.powerSource?.id,
      deviceManager.cadenceSource?.id,
      deviceManager.heartRateSource?.id,
    }.whereType<String>().toSet();

    final unassignedDevices = allDevices.where((device) => !assignedDeviceIds.contains(device.id)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('OTHER DEVICES', style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        if (unassignedDevices.isEmpty)
          _buildEmptyState(context, 'No other devices found')
        else
          ...unassignedDevices.map(
            (device) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildDeviceCard(
                context,
                device: device,
                showAssignButtons: true,
                onConnect: () => _handleConnect(device),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildDeviceCard(
    BuildContext context, {
    required FitnessDevice device,
    VoidCallback? onDisconnect,
    VoidCallback? onConnect,
    bool showAssignButtons = false,
  }) {
    return StreamBuilder<device_info.ConnectionState>(
      stream: device.connectionState,
      initialData: device_info.ConnectionState.disconnected,
      builder: (context, snapshot) {
        final connectionState = snapshot.data ?? device_info.ConnectionState.disconnected;
        final isConnected = connectionState == device_info.ConnectionState.connected;
        final isConnecting = _isConnecting && _connectingDeviceId == device.id;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      isConnected ? Icons.link : Icons.link_off,
                      size: 20,
                      color: isConnected ? Colors.green : Colors.grey,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(device.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _formatCapabilities(device.capabilities),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[700]),
                ),
                const SizedBox(height: 12),
                if (showAssignButtons)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (device.supportsErgMode)
                        OutlinedButton(
                          onPressed: () => _handleAssignPrimaryTrainer(device),
                          child: const Text('Assign as Trainer'),
                        ),
                      if (device.capabilities.contains(device_info.DataSource.heartRate))
                        OutlinedButton(
                          onPressed: () => _handleAssignHeartRate(device),
                          child: const Text('Assign to HR'),
                        ),
                      if (device.capabilities.contains(device_info.DataSource.power))
                        OutlinedButton(
                          onPressed: () => _handleAssignPower(device),
                          child: const Text('Assign to Power'),
                        ),
                      if (device.capabilities.contains(device_info.DataSource.cadence))
                        OutlinedButton(
                          onPressed: () => _handleAssignCadence(device),
                          child: const Text('Assign to Cadence'),
                        ),
                      if (onConnect != null && !isConnected)
                        ElevatedButton(
                          onPressed: isConnecting ? null : onConnect,
                          child: Text(isConnecting ? 'Connecting...' : 'Connect'),
                        ),
                    ],
                  )
                else if (onDisconnect != null)
                  ElevatedButton(
                    onPressed: onDisconnect,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red[50], foregroundColor: Colors.red[900]),
                    child: const Text('Disconnect'),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context, String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        children: [
          Icon(Icons.bluetooth_disabled, size: 48, color: Colors.grey[400]),
          const SizedBox(height: 12),
          Text(message, style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.grey[600])),
        ],
      ),
    );
  }

  String _formatCapabilities(Set<device_info.DataSource> capabilities) {
    if (capabilities.isEmpty) return 'No capabilities';

    final parts = <String>[];
    if (capabilities.contains(device_info.DataSource.power)) parts.add('Power');
    if (capabilities.contains(device_info.DataSource.cadence)) parts.add('Cadence');
    if (capabilities.contains(device_info.DataSource.heartRate)) parts.add('Heart Rate');

    return parts.join(' • ');
  }

  // ============================================================================
  // Action Handlers
  // ============================================================================

  Future<void> _handleConnect(FitnessDevice device) async {
    setState(() {
      _isConnecting = true;
      _connectingDeviceId = device.id;
    });

    try {
      await device.connect();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${device.name} connected')));
    } catch (e, stackTrace) {
      developer.log(
        'Error connecting to ${device.name}',
        name: 'DevicesPage',
        error: e,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to connect: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) {
        setState(() {
          _isConnecting = false;
          _connectingDeviceId = null;
        });
      }
    }
  }

  Future<void> _handleDisconnect(FitnessDevice device) async {
    try {
      await device.disconnect();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${device.name} disconnected')));
      setState(() {}); // Refresh UI
    } catch (e, stackTrace) {
      developer.log(
        'Error disconnecting from ${device.name}',
        name: 'DevicesPage',
        error: e,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to disconnect: $e'), backgroundColor: Colors.red));
    }
  }

  void _handleAssignPrimaryTrainer(FitnessDevice device) {
    final deviceManager = deviceManagerRef.of(context);
    try {
      deviceManager.assignPrimaryTrainer(device.id);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${device.name} assigned as primary trainer')));
      setState(() {}); // Refresh UI
    } catch (e, stackTrace) {
      developer.log(
        'Error assigning primary trainer',
        name: 'DevicesPage',
        error: e,
        stackTrace: stackTrace,
      );
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to assign: $e'), backgroundColor: Colors.red));
    }
  }

  void _handleAssignPower(FitnessDevice device) {
    final deviceManager = deviceManagerRef.of(context);
    try {
      deviceManager.assignPowerSource(device.id);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${device.name} assigned as power source')));
      setState(() {}); // Refresh UI
    } catch (e, stackTrace) {
      developer.log(
        'Error assigning power source',
        name: 'DevicesPage',
        error: e,
        stackTrace: stackTrace,
      );
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to assign: $e'), backgroundColor: Colors.red));
    }
  }

  void _handleAssignCadence(FitnessDevice device) {
    final deviceManager = deviceManagerRef.of(context);
    try {
      deviceManager.assignCadenceSource(device.id);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${device.name} assigned as cadence source')));
      setState(() {}); // Refresh UI
    } catch (e, stackTrace) {
      developer.log(
        'Error assigning cadence source',
        name: 'DevicesPage',
        error: e,
        stackTrace: stackTrace,
      );
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to assign: $e'), backgroundColor: Colors.red));
    }
  }

  void _handleAssignHeartRate(FitnessDevice device) {
    final deviceManager = deviceManagerRef.of(context);
    try {
      deviceManager.assignHeartRateSource(device.id);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${device.name} assigned as heart rate source')));
      setState(() {}); // Refresh UI
    } catch (e, stackTrace) {
      developer.log(
        'Error assigning heart rate source',
        name: 'DevicesPage',
        error: e,
        stackTrace: stackTrace,
      );
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to assign: $e'), backgroundColor: Colors.red));
    }
  }
}
