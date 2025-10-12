import 'package:flutter/material.dart';
import 'package:vekolo/domain/models/device_info.dart';

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
class DevicesPage extends StatelessWidget {
  const DevicesPage({super.key});

  @override
  Widget build(BuildContext context) {
    // TODO: Access DeviceManager via context_plus when wired up
    // final deviceManager = deviceManagerRef.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Devices'),
        actions: [
          TextButton.icon(
            onPressed: () {
              // TODO: Phase 4.2 - Implement device scanning
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Device scanning coming in Phase 4.2')));
            },
            icon: const Icon(Icons.search),
            label: const Text('Scan'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildPrimaryTrainerSection(context),
          const SizedBox(height: 24),
          _buildDataSourceSection(context, title: 'POWER SOURCE', icon: Icons.bolt, assignedDevice: null),
          const SizedBox(height: 16),
          _buildDataSourceSection(context, title: 'CADENCE SOURCE', icon: Icons.refresh, assignedDevice: null),
          const SizedBox(height: 16),
          _buildDataSourceSection(context, title: 'HEART RATE', icon: Icons.favorite, assignedDevice: null),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 24),
          _buildOtherDevicesSection(context),
        ],
      ),
    );
  }

  Widget _buildPrimaryTrainerSection(BuildContext context) {
    // TODO: Get from DeviceManager.primaryTrainer
    const bool hasTrainer = false;

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
          _buildDeviceCard(
            context,
            deviceName: 'Wahoo KICKR',
            capabilities: {DataSource.power, DataSource.cadence},
            isConnected: true,
            batteryPercent: 95,
            signalStrength: -45,
            onDisconnect: () {
              // TODO: Implement disconnect
            },
          )
        else
          _buildEmptyState(context, 'No trainer assigned'),
      ],
    );
  }

  Widget _buildDataSourceSection(
    BuildContext context, {
    required String title,
    required IconData icon,
    required DeviceInfo? assignedDevice,
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
          _buildDeviceCard(
            context,
            deviceName: assignedDevice.name,
            capabilities: assignedDevice.capabilities,
            isConnected: true,
            onDisconnect: () {
              // TODO: Implement disconnect
            },
          )
        else
          OutlinedButton.icon(
            onPressed: () {
              // TODO: Show device picker dialog
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Device assignment coming in Phase 4.3')));
            },
            icon: const Icon(Icons.add),
            label: const Text('Assign Device'),
          ),
      ],
    );
  }

  Widget _buildOtherDevicesSection(BuildContext context) {
    // TODO: Get from DeviceManager.devices where device is not assigned
    final List<DeviceInfo> unassignedDevices = [];

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
                deviceName: device.name,
                capabilities: device.capabilities,
                isConnected: false,
                showAssignButtons: true,
                onConnect: () {
                  // TODO: Implement connect
                },
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildDeviceCard(
    BuildContext context, {
    required String deviceName,
    required Set<DataSource> capabilities,
    required bool isConnected,
    int? batteryPercent,
    int? signalStrength,
    VoidCallback? onDisconnect,
    VoidCallback? onConnect,
    bool showAssignButtons = false,
  }) {
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
                  child: Text(deviceName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _formatCapabilities(capabilities),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[700]),
            ),
            if (isConnected && (batteryPercent != null || signalStrength != null)) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  if (batteryPercent != null) ...[
                    const Icon(Icons.battery_full, size: 16, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text('$batteryPercent%', style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(width: 16),
                  ],
                  if (signalStrength != null) ...[
                    const Icon(Icons.signal_cellular_alt, size: 16, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text('${signalStrength}dBm', style: Theme.of(context).textTheme.bodySmall),
                  ],
                ],
              ),
            ],
            const SizedBox(height: 12),
            if (showAssignButtons)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (capabilities.contains(DataSource.heartRate))
                    OutlinedButton(
                      onPressed: () {
                        // TODO: Assign to HR source
                      },
                      child: const Text('Assign to HR'),
                    ),
                  if (capabilities.contains(DataSource.power))
                    OutlinedButton(
                      onPressed: () {
                        // TODO: Assign to Power source
                      },
                      child: const Text('Assign to Power'),
                    ),
                  if (capabilities.contains(DataSource.cadence))
                    OutlinedButton(
                      onPressed: () {
                        // TODO: Assign to Cadence source
                      },
                      child: const Text('Assign to Cadence'),
                    ),
                  if (onConnect != null) ElevatedButton(onPressed: onConnect, child: const Text('Connect')),
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

  String _formatCapabilities(Set<DataSource> capabilities) {
    if (capabilities.isEmpty) return 'No capabilities';

    final parts = <String>[];
    if (capabilities.contains(DataSource.power)) parts.add('Power');
    if (capabilities.contains(DataSource.cadence)) parts.add('Cadence');
    if (capabilities.contains(DataSource.heartRate)) parts.add('Heart Rate');

    return parts.join(' • ');
  }
}
