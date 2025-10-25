import 'dart:developer' as developer;

import 'package:clock/clock.dart';
import 'package:context_plus/context_plus.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:state_beacon/state_beacon.dart';
import 'package:vekolo/domain/devices/device_manager.dart';
import 'package:vekolo/domain/devices/fitness_device.dart';
import 'package:vekolo/domain/models/device_info.dart' as device_info;
import 'package:vekolo/domain/models/erg_command.dart';
import 'package:vekolo/domain/protocols/ftms_device.dart';
import 'package:vekolo/ble/ble_scanner.dart';
import 'package:vekolo/state/device_state.dart';
import 'package:vekolo/ble/ble_permissions.dart';

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
  double _targetPower = 100.0;

  @override
  Widget build(BuildContext context) {
    final deviceManager = deviceManagerRef.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Devices'),
        actions: [
          TextButton.icon(
            onPressed: () => _showScanDialog(context),
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
            assignedDevice: deviceManager.powerSource,
            dataType: device_info.DeviceDataType.power,
          ),
          const SizedBox(height: 16),
          _buildDataSourceSection(
            context,
            deviceManager,
            title: 'CADENCE SOURCE',
            icon: Icons.refresh,
            assignedDevice: deviceManager.cadenceSource,
            dataType: device_info.DeviceDataType.cadence,
          ),
          const SizedBox(height: 16),
          _buildDataSourceSection(
            context,
            deviceManager,
            title: 'HEART RATE',
            icon: Icons.favorite,
            assignedDevice: deviceManager.heartRateSource,
            dataType: device_info.DeviceDataType.heartRate,
          ),
          const SizedBox(height: 16),
          _buildDataSourceSection(
            context,
            deviceManager,
            title: 'SPEED',
            icon: Icons.speed,
            assignedDevice: deviceManager.speedSource,
            dataType: device_info.DeviceDataType.speed,
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 24),
          _buildErgControlTestSection(context),
          const SizedBox(height: 24),
          _buildWorkoutPlayerTestSection(context),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 24),
          _buildPrimaryTrainerSection(context, deviceManager),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 24),
          _buildOtherDevicesSection(context, deviceManager),
        ],
      ),
    );
  }

  Widget _buildErgControlTestSection(BuildContext context) {
    final syncService = workoutSyncServiceRef.of(context);
    final deviceManager = deviceManagerRef.of(context);

    return Builder(
      builder: (context) {
        final isSyncing = syncService.isSyncing.watch(context);
        final syncError = syncService.syncError.watch(context);
        final lastSyncTime = syncService.lastSyncTime.watch(context);
        final hasPrimaryTrainer = deviceManager.primaryTrainer != null;
        final supportsErg = deviceManager.primaryTrainer?.supportsErgMode ?? false;

        return Card(
          color: Colors.blue[50],
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.science, size: 20, color: Colors.blue),
                    const SizedBox(width: 8),
                    Text(
                      'ERG CONTROL TEST',
                      style: Theme.of(
                        context,
                      ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold, color: Colors.blue[900]),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Test the WorkoutSyncService by controlling the trainer ERG mode directly',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.blue[700]),
                ),
                const SizedBox(height: 16),
                if (!hasPrimaryTrainer)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.orange[100], borderRadius: BorderRadius.circular(8)),
                    child: Row(
                      children: [
                        Icon(Icons.warning, color: Colors.orange[900], size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'No primary trainer assigned. Assign a trainer below to test ERG control.',
                            style: TextStyle(color: Colors.orange[900]),
                          ),
                        ),
                      ],
                    ),
                  )
                else if (!supportsErg)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.orange[100], borderRadius: BorderRadius.circular(8)),
                    child: Row(
                      children: [
                        Icon(Icons.warning, color: Colors.orange[900], size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Primary trainer does not support ERG mode',
                            style: TextStyle(color: Colors.orange[900]),
                          ),
                        ),
                      ],
                    ),
                  )
                else ...[
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Target Power: ${_targetPower.toInt()}W',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            Slider(
                              value: _targetPower,
                              min: 50,
                              max: 400,
                              divisions: 35,
                              label: '${_targetPower.toInt()}W',
                              onChanged: (value) {
                                setState(() {
                                  _targetPower = value;
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ElevatedButton.icon(
                        onPressed: isSyncing
                            ? null
                            : () {
                                syncService.startSync();
                                syncService.currentTarget.value = ErgCommand(
                                  targetWatts: _targetPower.toInt(),
                                  timestamp: clock.now(),
                                );
                                ScaffoldMessenger.of(
                                  context,
                                ).showSnackBar(SnackBar(content: Text('Syncing target: ${_targetPower.toInt()}W')));
                              },
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Start Sync'),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                      ),
                      ElevatedButton.icon(
                        onPressed: isSyncing
                            ? () {
                                syncService.currentTarget.value = ErgCommand(
                                  targetWatts: _targetPower.toInt(),
                                  timestamp: clock.now(),
                                );
                                ScaffoldMessenger.of(
                                  context,
                                ).showSnackBar(SnackBar(content: Text('Updated target: ${_targetPower.toInt()}W')));
                              }
                            : null,
                        icon: const Icon(Icons.update),
                        label: const Text('Update Target'),
                      ),
                      ElevatedButton.icon(
                        onPressed: !isSyncing
                            ? null
                            : () {
                                syncService.stopSync();
                                ScaffoldMessenger.of(
                                  context,
                                ).showSnackBar(const SnackBar(content: Text('Sync stopped')));
                              },
                        icon: const Icon(Icons.stop),
                        label: const Text('Stop Sync'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red[700],
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue[200]!),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              isSyncing ? Icons.sync : Icons.sync_disabled,
                              size: 16,
                              color: isSyncing ? Colors.green : Colors.grey,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Status: ${isSyncing ? "Syncing" : "Not syncing"}',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        if (syncError != null) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(Icons.error, size: 16, color: Colors.red),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text('Error: $syncError', style: const TextStyle(color: Colors.red)),
                              ),
                            ],
                          ),
                        ],
                        if (lastSyncTime != null) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(Icons.access_time, size: 16, color: Colors.grey),
                              const SizedBox(width: 8),
                              Text(
                                'Last sync: ${_formatTime(lastSyncTime)}',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[700]),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatTime(DateTime time) {
    final now = clock.now();
    final diff = now.difference(time);
    if (diff.inSeconds < 60) {
      return '${diff.inSeconds}s ago';
    }
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    }
    return '${diff.inHours}h ago';
  }

  Widget _buildWorkoutPlayerTestSection(BuildContext context) {
    return Card(
      color: Colors.green[50],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.fitness_center, size: 20, color: Colors.green),
                const SizedBox(width: 8),
                Text(
                  'WORKOUT PLAYER TEST',
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold, color: Colors.green[900]),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Test the Workout Player by running a structured workout from save.json',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.green[700]),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => context.push('/workout-player'),
                icon: const Icon(Icons.play_circle_filled),
                label: const Text('Start Workout Player'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ],
        ),
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
          _buildDeviceCard(context, device: trainer, onUnassign: _handleUnassignPrimaryTrainer)
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
    required device_info.DeviceDataType dataType,
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
          _buildDeviceCard(context, device: assignedDevice, onUnassign: () => _handleUnassignDataSource(dataType))
        else
          OutlinedButton.icon(
            onPressed: () => _showDeviceAssignmentDialog(context, deviceManager, dataType),
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
      deviceManager.speedSource?.id,
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
    VoidCallback? onUnassign,
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
                      if (device.capabilities.contains(device_info.DeviceDataType.heartRate))
                        OutlinedButton(
                          onPressed: () => _handleAssignHeartRate(device),
                          child: const Text('Assign to HR'),
                        ),
                      if (device.capabilities.contains(device_info.DeviceDataType.power))
                        OutlinedButton(
                          onPressed: () => _handleAssignPower(device),
                          child: const Text('Assign to Power'),
                        ),
                      if (device.capabilities.contains(device_info.DeviceDataType.cadence))
                        OutlinedButton(
                          onPressed: () => _handleAssignCadence(device),
                          child: const Text('Assign to Cadence'),
                        ),
                      if (device.capabilities.contains(device_info.DeviceDataType.speed))
                        OutlinedButton(
                          onPressed: () => _handleAssignSpeed(device),
                          child: const Text('Assign to Speed'),
                        ),
                      if (onConnect != null && !isConnected)
                        ElevatedButton(
                          onPressed: isConnecting ? null : onConnect,
                          child: Text(isConnecting ? 'Connecting...' : 'Connect'),
                        ),
                    ],
                  )
                else if (onUnassign != null)
                  OutlinedButton.icon(
                    onPressed: onUnassign,
                    icon: const Icon(Icons.link_off),
                    label: const Text('Unassign'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.orange[900],
                      side: BorderSide(color: Colors.orange[300]!),
                    ),
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

  Future<void> _handleConnect(FitnessDevice device) async {
    setState(() {
      _isConnecting = true;
      _connectingDeviceId = device.id;
    });

    try {
      await device.connect().value;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${device.name} connected')));
    } catch (e, stackTrace) {
      developer.log('Error connecting to ${device.name}', name: 'DevicesPage', error: e, stackTrace: stackTrace);
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

  void _handleAssignPrimaryTrainer(FitnessDevice device) {
    final deviceManager = deviceManagerRef.of(context);
    try {
      deviceManager.assignPrimaryTrainer(device.id);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${device.name} assigned as primary trainer')));
      setState(() {}); // Refresh UI
    } catch (e, stackTrace) {
      developer.log('Error assigning primary trainer', name: 'DevicesPage', error: e, stackTrace: stackTrace);
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
      developer.log('Error assigning power source', name: 'DevicesPage', error: e, stackTrace: stackTrace);
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
      developer.log('Error assigning cadence source', name: 'DevicesPage', error: e, stackTrace: stackTrace);
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
      developer.log('Error assigning heart rate source', name: 'DevicesPage', error: e, stackTrace: stackTrace);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to assign: $e'), backgroundColor: Colors.red));
    }
  }

  void _handleAssignSpeed(FitnessDevice device) {
    final deviceManager = deviceManagerRef.of(context);
    try {
      deviceManager.assignSpeedSource(device.id);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${device.name} assigned as speed source')));
      setState(() {}); // Refresh UI
    } catch (e, stackTrace) {
      developer.log('Error assigning speed source', name: 'DevicesPage', error: e, stackTrace: stackTrace);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to assign: $e'), backgroundColor: Colors.red));
    }
  }

  void _handleUnassignPrimaryTrainer() {
    final deviceManager = deviceManagerRef.of(context);
    try {
      deviceManager.assignPrimaryTrainer(null);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Primary trainer unassigned')));
      setState(() {}); // Refresh UI
    } catch (e, stackTrace) {
      developer.log('Error unassigning primary trainer', name: 'DevicesPage', error: e, stackTrace: stackTrace);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to unassign: $e'), backgroundColor: Colors.red));
    }
  }

  void _handleUnassignDataSource(device_info.DeviceDataType dataType) {
    final deviceManager = deviceManagerRef.of(context);
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
      setState(() {}); // Refresh UI
    } catch (e, stackTrace) {
      developer.log('Error unassigning data source', name: 'DevicesPage', error: e, stackTrace: stackTrace);
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
    final allDevices = deviceManager.devices;
    // Only exclude primary trainer from data source assignments
    // Allow same device to be assigned to multiple data sources (power, cadence, HR)
    final primaryTrainerId = deviceManager.primaryTrainer?.id;

    final eligibleDevices = allDevices.where((device) {
      return device.id != primaryTrainerId && device.capabilities.contains(dataType);
    }).toList();

    final dataTypeName = switch (dataType) {
      device_info.DeviceDataType.power => 'Power',
      device_info.DeviceDataType.cadence => 'Cadence',
      device_info.DeviceDataType.speed => 'Speed',
      device_info.DeviceDataType.heartRate => 'Heart Rate',
    };

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
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
                        Navigator.of(ctx).pop();
                        _assignDeviceToDataType(device, dataType);
                      },
                    );
                  },
                ),
        ),
        actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel'))],
      ),
    );
  }

  void _assignDeviceToDataType(FitnessDevice device, device_info.DeviceDataType dataType) {
    try {
      switch (dataType) {
        case device_info.DeviceDataType.power:
          _handleAssignPower(device);
        case device_info.DeviceDataType.cadence:
          _handleAssignCadence(device);
        case device_info.DeviceDataType.speed:
          _handleAssignSpeed(device);
        case device_info.DeviceDataType.heartRate:
          _handleAssignHeartRate(device);
      }
    } catch (e, stackTrace) {
      developer.log('Error assigning device', name: 'DevicesPage', error: e, stackTrace: stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to assign device: $e'), backgroundColor: Colors.red));
      }
    }
  }

  // ============================================================================
  // BLE Scanning
  // ============================================================================

  void _showScanDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _BleScanDialog(
        onDeviceSelected: (device) async {
          Navigator.of(ctx).pop();
          await _handleDeviceSelected(device);
        },
      ),
    );
  }

  Future<void> _handleDeviceSelected(DiscoveredDevice device) async {
    final deviceName = device.name ?? '';
    final deviceId = device.deviceId;
    developer.log('[DevicesPage] Device selected: $deviceName ($deviceId)');

    try {
      final deviceManager = deviceManagerRef.of(context);

      // Create FTMS device from scanned device
      final newDevice = FtmsDevice(deviceId: deviceId, name: deviceName.isEmpty ? 'Unknown Device' : deviceName);

      // Add to device manager (or get existing if already exists)
      final ftmsDevice = await deviceManager.addOrGetExistingDevice(newDevice) as FtmsDevice;
      final isReconnect = ftmsDevice != newDevice;

      if (isReconnect) {
        developer.log('[DevicesPage] Device already exists in manager, reconnecting');
      }

      if (!mounted) return;

      // Auto-assign device to available data sources based on its capabilities (only for new devices)
      final autoAssignments = <String>[];

      if (!isReconnect) {
        // Check if device supports ERG mode and no trainer is assigned
        if (ftmsDevice.supportsErgMode && deviceManager.primaryTrainer == null) {
          deviceManager.assignPrimaryTrainer(ftmsDevice.id);
          autoAssignments.add('primary trainer');
        }

        // Auto-assign to data sources
        if (ftmsDevice.capabilities.contains(device_info.DeviceDataType.power) && deviceManager.powerSource == null) {
          deviceManager.assignPowerSource(ftmsDevice.id);
          autoAssignments.add('power source');
        }

        if (ftmsDevice.capabilities.contains(device_info.DeviceDataType.cadence) &&
            deviceManager.cadenceSource == null) {
          deviceManager.assignCadenceSource(ftmsDevice.id);
          autoAssignments.add('cadence source');
        }

        if (ftmsDevice.capabilities.contains(device_info.DeviceDataType.speed) && deviceManager.speedSource == null) {
          deviceManager.assignSpeedSource(ftmsDevice.id);
          autoAssignments.add('speed source');
        }

        if (ftmsDevice.capabilities.contains(device_info.DeviceDataType.heartRate) &&
            deviceManager.heartRateSource == null) {
          deviceManager.assignHeartRateSource(ftmsDevice.id);
          autoAssignments.add('heart rate source');
        }
      }

      // Connect the device automatically
      developer.log('[DevicesPage] ${isReconnect ? 'Reconnecting' : 'Auto-connecting'} device: ${ftmsDevice.name}');
      await ftmsDevice.connect().value;

      if (!mounted) return;

      final message = isReconnect
          ? '${ftmsDevice.name} reconnected'
          : autoAssignments.isEmpty
          ? '${ftmsDevice.name} added and connected'
          : '${ftmsDevice.name} connected and assigned as ${autoAssignments.join(', ')}';

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

      setState(() {}); // Refresh UI
    } catch (e, stackTrace) {
      developer.log('Error adding/connecting device', name: 'DevicesPage', error: e, stackTrace: stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to add/connect device: $e'), backgroundColor: Colors.red));
    }
  }
}

/// Dialog for scanning and selecting BLE devices.
class _BleScanDialog extends StatefulWidget {
  const _BleScanDialog({required this.onDeviceSelected});

  final void Function(DiscoveredDevice device) onDeviceSelected;

  @override
  State<_BleScanDialog> createState() => _BleScanDialogState();
}

class _BleScanDialogState extends State<_BleScanDialog> {
  late final BleScanner _scanner;
  List<DiscoveredDevice> _devices = [];
  BluetoothState? _bluetoothState;
  bool _isScanning = false;
  bool _isInitialized = false;
  ScanToken? _scanToken;
  VoidCallback? _devicesUnsubscribe;
  VoidCallback? _bluetoothStateUnsubscribe;
  VoidCallback? _isScanningUnsubscribe;

  @override
  void initState() {
    super.initState();
    _initializeScanner();
  }

  void _initializeScanner() {
    _scanner = BleScanner();

    // Listen to discovered devices
    _devicesUnsubscribe = _scanner.devices.subscribe((devices) {
      if (mounted) {
        setState(() {
          _devices = devices;
        });
      }
    });

    // Listen to Bluetooth state
    _bluetoothStateUnsubscribe = _scanner.bluetoothState.subscribe((state) {
      if (mounted) {
        setState(() {
          _bluetoothState = state;
        });

        // Auto-start scan if ready
        if (state.canScan && !_isScanning && _scanToken == null) {
          _handleScanButtonPressed();
        }
      }
    });

    // Listen to scanning state
    _isScanningUnsubscribe = _scanner.isScanning.subscribe((scanning) {
      if (mounted) {
        setState(() {
          _isScanning = scanning;
        });
      }
    });

    // Initialize scanner
    _scanner.initialize();
    setState(() {
      _isInitialized = true;
    });
  }

  @override
  void dispose() {
    if (_scanToken != null) {
      _scanner.stopScan(_scanToken!);
    }
    _devicesUnsubscribe?.call();
    _bluetoothStateUnsubscribe?.call();
    _isScanningUnsubscribe?.call();
    _scanner.dispose();
    super.dispose();
  }

  void _handleScanButtonPressed() {
    if (_isScanning) {
      if (_scanToken != null) {
        _scanner.stopScan(_scanToken!);
        _scanToken = null;
      }
    } else {
      _scanToken = _scanner.startScan();
    }
  }

  @override
  Widget build(BuildContext context) {
    final canScan = _bluetoothState?.canScan ?? false;
    final isScanning = _isScanning;
    final statusMessage = _getStatusMessage(_bluetoothState);

    return AlertDialog(
      title: const Text('Scan for Devices'),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Text(statusMessage, style: Theme.of(context).textTheme.bodyMedium)),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _isInitialized && (canScan || isScanning) ? _handleScanButtonPressed : null,
                  child: Text(isScanning ? 'Stop' : 'Scan'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
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
                            isScanning ? 'Searching for devices...' : 'No devices found',
                            style: TextStyle(fontSize: 16, color: canScan ? Colors.grey[600] : Colors.red[400]),
                          ),
                          if (!canScan && _bluetoothState != null) ...[
                            const SizedBox(height: 16),
                            if (_bluetoothState!.needsPermission)
                              ElevatedButton.icon(
                                onPressed: () async {
                                  final messenger = ScaffoldMessenger.of(context);
                                  final permissions = BlePermissionsImpl();
                                  final granted = await permissions.request();
                                  if (granted && mounted) {
                                    _handleScanButtonPressed();
                                  } else {
                                    final permanentlyDenied = await permissions.isPermanentlyDenied();
                                    if (permanentlyDenied && mounted) {
                                      messenger.showSnackBar(
                                        SnackBar(
                                          content: const Text('Please enable permissions in app settings'),
                                          action: SnackBarAction(
                                            label: 'Settings',
                                            onPressed: () => permissions.openSettings(),
                                          ),
                                        ),
                                      );
                                    }
                                  }
                                },
                                icon: const Icon(Icons.security),
                                label: const Text('Grant Permissions'),
                              )
                            else if (!_bluetoothState!.isBluetoothOn)
                              const Text('Please turn on Bluetooth', style: TextStyle(color: Colors.red)),
                          ],
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _devices.length,
                      itemBuilder: (context, index) {
                        final device = _devices[index];
                        final deviceName = device.name ?? '';
                        return ListTile(
                          leading: const Icon(Icons.bluetooth),
                          title: Text(deviceName.isEmpty ? 'Unknown Device' : deviceName),
                          subtitle: Text('${device.deviceId}\nRSSI: ${device.rssi}'),
                          trailing: const Icon(Icons.arrow_forward),
                          onTap: () => widget.onDeviceSelected(device),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))],
    );
  }

  String _getStatusMessage(BluetoothState? state) {
    if (state == null) return 'Initializing...';
    if (!state.isBluetoothOn) return 'Bluetooth is off';
    if (!state.hasPermission) return 'Bluetooth permissions required';
    if (!state.isLocationServiceEnabled) return 'Location services required';
    if (_isScanning) return 'Scanning for devices...';
    return 'Ready to scan';
  }
}
