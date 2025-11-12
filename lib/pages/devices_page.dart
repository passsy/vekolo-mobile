import 'package:chirp/chirp.dart';

import 'package:context_plus/context_plus.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:state_beacon/state_beacon.dart';
import 'package:vekolo/app/refs.dart';
import 'package:vekolo/domain/devices/device_manager.dart';
import 'package:vekolo/domain/devices/fitness_device.dart';
import 'package:vekolo/domain/models/device_info.dart' as device_info;

/// Page for managing connected fitness devices and assigning them to data sources.
///
/// Allows users to:
/// - Scan for and connect to Bluetooth devices
/// - Assign devices to specific roles (power/cadence/HR/speed sources)
/// - View device connection status and capabilities
/// - Manage device connections (connect/disconnect)
///
/// The page shows separate sections for:
/// - Power Source (dedicated power meter)
/// - Cadence Source (dedicated cadence sensor)
/// - Heart Rate Source (dedicated HR monitor)
/// - Other Devices (unassigned devices available for assignment)
///
/// Used from anywhere in the app via go_router route '/devices'.
class DevicesPage extends StatelessWidget {
  const DevicesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final deviceManager = Refs.deviceManager.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Devices'),
        actions: [
          TextButton.icon(
            onPressed: () => context.push('/scanner?connectMode=true'),
            icon: const Icon(Icons.search),
            label: const Text('Scan'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildDataSourceSection(
            context,
            deviceManager,
            title: 'POWER SOURCE',
            icon: Icons.bolt,
            dataType: device_info.DeviceDataType.power,
          ),
          const SizedBox(height: 16),
          _buildDataSourceSection(
            context,
            deviceManager,
            title: 'CADENCE SOURCE',
            icon: Icons.refresh,
            dataType: device_info.DeviceDataType.cadence,
          ),
          const SizedBox(height: 16),
          _buildDataSourceSection(
            context,
            deviceManager,
            title: 'HEART RATE',
            icon: Icons.favorite,
            dataType: device_info.DeviceDataType.heartRate,
          ),
          const SizedBox(height: 16),
          _buildDataSourceSection(
            context,
            deviceManager,
            title: 'SPEED',
            icon: Icons.speed,
            dataType: device_info.DeviceDataType.speed,
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 24),
          _buildAllDevicesSection(context, deviceManager),
        ],
      ),
    );
  }

  Widget _buildDataSourceSection(
    BuildContext context,
    DeviceManager deviceManager, {
    required String title,
    required IconData icon,
    required device_info.DeviceDataType dataType,
  }) {
    return Builder(
      builder: (context) {
        final assignedDevice = switch (dataType) {
          device_info.DeviceDataType.power => deviceManager.powerSourceBeacon.watch(context),
          device_info.DeviceDataType.cadence => deviceManager.cadenceSourceBeacon.watch(context),
          device_info.DeviceDataType.speed => deviceManager.speedSourceBeacon.watch(context),
          device_info.DeviceDataType.heartRate => deviceManager.heartRateSourceBeacon.watch(context),
        };

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20),
                const SizedBox(width: 8),
                Text(title, style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold)),
                if (assignedDevice != null) ...[
                  const Spacer(),
                  Builder(
                    builder: (context) {
                      final connectedDevice = assignedDevice.connectedDevice;
                      final liveData = connectedDevice != null
                          ? _getLiveDataForDevice(context, connectedDevice, dataType)
                          : 'Not connected';
                      return Text(
                        liveData,
                        style: Theme.of(
                          context,
                        ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: Colors.blue[700]),
                      );
                    },
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            if (assignedDevice?.connectedDevice != null)
              _buildDeviceCard(
                context,
                device: assignedDevice!.connectedDevice!,
                onUnassign: () => _handleUnassignDataSource(context, dataType),
                onRemove: () => _handleRemove(context, assignedDevice.connectedDevice!),
              )
            else
              OutlinedButton.icon(
                onPressed: () => _showDeviceAssignmentDialog(context, deviceManager, dataType),
                icon: const Icon(Icons.add),
                label: const Text('Assign Device'),
              ),
          ],
        );
      },
    );
  }

  String _getLiveDataForDevice(BuildContext context, FitnessDevice device, device_info.DeviceDataType dataType) {
    switch (dataType) {
      case device_info.DeviceDataType.power:
        final powerData = device.powerStream?.watch(context);
        return powerData != null ? '${powerData.watts}W' : '--W';
      case device_info.DeviceDataType.cadence:
        final cadenceData = device.cadenceStream?.watch(context);
        return cadenceData != null ? '${cadenceData.rpm} RPM' : '-- RPM';
      case device_info.DeviceDataType.speed:
        final speedData = device.speedStream?.watch(context);
        return speedData != null ? '${speedData.kmh.toStringAsFixed(1)} km/h' : '-- km/h';
      case device_info.DeviceDataType.heartRate:
        final hrData = device.heartRateStream?.watch(context);
        return hrData != null ? '${hrData.bpm} BPM' : '-- BPM';
    }
  }

  Widget _buildAllDevicesSection(BuildContext context, DeviceManager deviceManager) {
    return Builder(
      builder: (context) {
        final allDevices = deviceManager.devicesBeacon.watch(context);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ALL DEVICES', style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            if (allDevices.isEmpty)
              _buildEmptyState(context, 'No devices found')
            else
              ...allDevices.map(
                (device) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _buildDeviceCard(
                    context,
                    device: device,
                    showAssignButtons: true,
                    onConnect: () => _handleConnect(context, device),
                    onDisconnect: () => _handleDisconnect(context, device),
                    onRemove: () => _handleRemove(context, device),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildDeviceCard(
    BuildContext context, {
    required FitnessDevice device,
    VoidCallback? onDisconnect,
    VoidCallback? onUnassign,
    VoidCallback? onConnect,
    VoidCallback? onRemove,
    bool showAssignButtons = false,
  }) {
    return Builder(
      builder: (context) {
        final connectionState = device.connectionState.watch(context);
        final isConnected = connectionState == device_info.ConnectionState.connected;
        final isConnecting = connectionState == device_info.ConnectionState.connecting;

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
                      if (device.capabilities.contains(device_info.DeviceDataType.heartRate))
                        OutlinedButton(
                          onPressed: () => _handleAssignHeartRate(context, device),
                          child: const Text('Assign to HR'),
                        ),
                      if (device.capabilities.contains(device_info.DeviceDataType.power))
                        OutlinedButton(
                          onPressed: () => _handleAssignPower(context, device),
                          child: const Text('Assign to Power'),
                        ),
                      if (device.capabilities.contains(device_info.DeviceDataType.cadence))
                        OutlinedButton(
                          onPressed: () => _handleAssignCadence(context, device),
                          child: const Text('Assign to Cadence'),
                        ),
                      if (device.capabilities.contains(device_info.DeviceDataType.speed))
                        OutlinedButton(
                          onPressed: () => _handleAssignSpeed(context, device),
                          child: const Text('Assign to Speed'),
                        ),
                      if (onConnect != null && !isConnected)
                        ElevatedButton(
                          onPressed: isConnecting ? null : onConnect,
                          child: Text(isConnecting ? 'Connecting...' : 'Connect'),
                        ),
                      if (isConnected && onDisconnect != null)
                        ElevatedButton.icon(
                          onPressed: onDisconnect,
                          icon: const Icon(Icons.bluetooth_disabled),
                          label: const Text('Disconnect'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red[50],
                            foregroundColor: Colors.red[900],
                          ),
                        ),
                      if (onRemove != null)
                        OutlinedButton.icon(
                          onPressed: onRemove,
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Remove'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red[900],
                            side: BorderSide(color: Colors.red[300]!),
                          ),
                        ),
                    ],
                  )
                else if (onUnassign != null)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (isConnected)
                        ElevatedButton.icon(
                          onPressed: onDisconnect,
                          icon: const Icon(Icons.bluetooth_disabled),
                          label: const Text('Disconnect'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red[50],
                            foregroundColor: Colors.red[900],
                          ),
                        )
                      else
                        ElevatedButton.icon(
                          onPressed: onConnect,
                          icon: const Icon(Icons.bluetooth_connected),
                          label: const Text('Connect'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue[50],
                            foregroundColor: Colors.blue[900],
                          ),
                        ),
                      OutlinedButton.icon(
                        onPressed: onUnassign,
                        icon: const Icon(Icons.link_off),
                        label: const Text('Unassign'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.orange[900],
                          side: BorderSide(color: Colors.orange[300]!),
                        ),
                      ),
                      if (onRemove != null)
                        OutlinedButton.icon(
                          onPressed: onRemove,
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Remove'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red[900],
                            side: BorderSide(color: Colors.red[300]!),
                          ),
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

  String _formatCapabilities(Set<device_info.DeviceDataType> capabilities) {
    if (capabilities.isEmpty) return 'No capabilities';

    final parts = <String>[];
    if (capabilities.contains(device_info.DeviceDataType.power)) parts.add('Power');
    if (capabilities.contains(device_info.DeviceDataType.cadence)) parts.add('Cadence');
    if (capabilities.contains(device_info.DeviceDataType.speed)) parts.add('Speed');
    if (capabilities.contains(device_info.DeviceDataType.heartRate)) parts.add('Heart Rate');

    return parts.join(' • ');
  }

  // ============================================================================
  // Action Handlers
  // ============================================================================

  Future<void> _handleConnect(BuildContext context, FitnessDevice device) async {
    final deviceManager = Refs.deviceManager.of(context);
    try {
      await deviceManager.connectDevice(device.id).value;
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${device.name} connected')));
    } catch (e, stackTrace) {
      Chirp.error('Error connecting to ${device.name}', error: e, stackTrace: stackTrace);
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to connect: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _handleDisconnect(BuildContext context, FitnessDevice device) async {
    final deviceManager = Refs.deviceManager.of(context);
    try {
      await deviceManager.disconnectDevice(device.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${device.name} disconnected')));
    } catch (e, stackTrace) {
      Chirp.error('Error disconnecting from ${device.name}', error: e, stackTrace: stackTrace);
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to disconnect: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _handleRemove(BuildContext context, FitnessDevice device) async {
    final deviceManager = Refs.deviceManager.of(context);
    try {
      await deviceManager.removeDevice(device.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${device.name} removed')));
    } catch (e, stackTrace) {
      Chirp.error('Error removing ${device.name}', error: e, stackTrace: stackTrace);
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to remove device: $e'), backgroundColor: Colors.red));
    }
  }

  void _handleAssignPower(BuildContext context, FitnessDevice device) {
    final deviceManager = Refs.deviceManager.of(context);
    try {
      deviceManager.assignPowerSource(device.id);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${device.name} assigned as power source')));
    } catch (e, stackTrace) {
      Chirp.error('Error assigning power source', error: e, stackTrace: stackTrace);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to assign: $e'), backgroundColor: Colors.red));
    }
  }

  void _handleAssignCadence(BuildContext context, FitnessDevice device) {
    final deviceManager = Refs.deviceManager.of(context);
    try {
      deviceManager.assignCadenceSource(device.id);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${device.name} assigned as cadence source')));
    } catch (e, stackTrace) {
      Chirp.error('Error assigning cadence source', error: e, stackTrace: stackTrace);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to assign: $e'), backgroundColor: Colors.red));
    }
  }

  void _handleAssignHeartRate(BuildContext context, FitnessDevice device) {
    final deviceManager = Refs.deviceManager.of(context);
    try {
      deviceManager.assignHeartRateSource(device.id);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${device.name} assigned as heart rate source')));
    } catch (e, stackTrace) {
      Chirp.error('Error assigning heart rate source', error: e, stackTrace: stackTrace);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to assign: $e'), backgroundColor: Colors.red));
    }
  }

  void _handleAssignSpeed(BuildContext context, FitnessDevice device) {
    final deviceManager = Refs.deviceManager.of(context);
    try {
      deviceManager.assignSpeedSource(device.id);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${device.name} assigned as speed source')));
    } catch (e, stackTrace) {
      Chirp.error('Error assigning speed source', error: e, stackTrace: stackTrace);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to assign: $e'), backgroundColor: Colors.red));
    }
  }

  void _handleUnassignDataSource(BuildContext context, device_info.DeviceDataType dataType) {
    final deviceManager = Refs.deviceManager.of(context);
    try {
      switch (dataType) {
        case device_info.DeviceDataType.power:
          deviceManager.assignPowerSource(null);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Power source unassigned')));
        case device_info.DeviceDataType.cadence:
          deviceManager.assignCadenceSource(null);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cadence source unassigned')));
        case device_info.DeviceDataType.heartRate:
          deviceManager.assignHeartRateSource(null);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Heart rate source unassigned')));
        case device_info.DeviceDataType.speed:
          deviceManager.assignSpeedSource(null);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Speed source unassigned')));
      }
    } catch (e, stackTrace) {
      Chirp.error('Error unassigning data source', error: e, stackTrace: stackTrace);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to unassign: $e'), backgroundColor: Colors.red));
    }
  }

  // ============================================================================
  // Device Assignment Dialog
  // ============================================================================

  void _showDeviceAssignmentDialog(
    BuildContext context,
    DeviceManager deviceManager,
    device_info.DeviceDataType dataType,
  ) {
    // Allow primary trainer to also be assigned as data source
    // (e.g., a KICKR CORE can control ERG mode AND provide power/cadence/speed data)
    // Allow same device to be assigned to multiple data sources (power, cadence, HR)

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final allDevices = deviceManager.devicesBeacon.watch(dialogContext);
        final eligibleDevices = allDevices.where((device) {
          return device.capabilities.contains(dataType);
        }).toList();

        final dataTypeName = switch (dataType) {
          device_info.DeviceDataType.power => 'Power',
          device_info.DeviceDataType.cadence => 'Cadence',
          device_info.DeviceDataType.speed => 'Speed',
          device_info.DeviceDataType.heartRate => 'Heart Rate',
        };

        return AlertDialog(
          title: Text('Assign $dataTypeName Source'),
          content: SizedBox(
            width: double.maxFinite,
            child: eligibleDevices.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.info_outline, size: 48, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text(
                          'No eligible devices found.\n\nMake sure you have devices that support $dataTypeName and are not already assigned to another role.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: () {
                            Navigator.of(dialogContext).pop();
                            context.push('/scanner?connectMode=true');
                          },
                          icon: const Icon(Icons.search),
                          label: const Text('Scan for Devices'),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: eligibleDevices.length,
                    itemBuilder: (context, index) {
                      final device = eligibleDevices[index];
                      return ListTile(
                        leading: const Icon(Icons.bluetooth),
                        title: Text(device.name),
                        subtitle: Text(_formatCapabilities(device.capabilities)),
                        trailing: const Icon(Icons.arrow_forward),
                        onTap: () {
                          Navigator.of(dialogContext).pop();
                          _assignDeviceToDataType(context, device, dataType);
                        },
                      );
                    },
                  ),
          ),
          actions: [TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel'))],
        );
      },
    );
  }

  void _assignDeviceToDataType(BuildContext context, FitnessDevice device, device_info.DeviceDataType dataType) {
    try {
      switch (dataType) {
        case device_info.DeviceDataType.power:
          _handleAssignPower(context, device);
        case device_info.DeviceDataType.cadence:
          _handleAssignCadence(context, device);
        case device_info.DeviceDataType.speed:
          _handleAssignSpeed(context, device);
        case device_info.DeviceDataType.heartRate:
          _handleAssignHeartRate(context, device);
      }
    } catch (e, stackTrace) {
      Chirp.error('Error assigning device', error: e, stackTrace: stackTrace);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to assign device: $e'), backgroundColor: Colors.red));
      }
    }
  }
}
