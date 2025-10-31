import 'dart:developer' as developer;

import 'package:clock/clock.dart';
import 'package:context_plus/context_plus.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:state_beacon/state_beacon.dart';
import 'package:vekolo/app/refs.dart';
import 'package:vekolo/domain/devices/device_manager.dart';
import 'package:vekolo/domain/devices/fitness_device.dart';
import 'package:vekolo/domain/models/device_info.dart' as device_info;
import 'package:vekolo/domain/models/erg_command.dart';

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
    final deviceManager = Refs.deviceManager.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Devices'),
        actions: [
          TextButton.icon(
            onPressed: () => context.push('/scanner?connectMode=true').then((_) {
              if (mounted) {
                setState(() {}); // Refresh UI after returning from scanner
              }
            }),
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
    final syncService = Refs.workoutSyncService.of(context);
    final deviceManager = Refs.deviceManager.of(context);

    return Builder(
      builder: (context) {
        final isSyncing = syncService.isSyncing.watch(context);
        final syncError = syncService.syncError.watch(context);
        final lastSyncTime = syncService.lastSyncTime.watch(context);
        final primaryTrainer = deviceManager.primaryTrainerBeacon.watch(context);
        final hasPrimaryTrainer = primaryTrainer != null;
        final supportsErg = primaryTrainer?.supportsErgMode ?? false;

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
    return Builder(
      builder: (context) {
        final trainer = deviceManager.primaryTrainerBeacon.watch(context);
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
              _buildDeviceCard(
                context,
                device: trainer,
                onUnassign: _handleUnassignPrimaryTrainer,
                onRemove: () => _handleRemove(trainer),
              )
            else
              _buildEmptyState(context, 'No trainer assigned'),
          ],
        );
      },
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
                      final liveData = _getLiveDataForDevice(context, assignedDevice, dataType);
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
            if (assignedDevice != null)
              _buildDeviceCard(
                context,
                device: assignedDevice,
                onUnassign: () => _handleUnassignDataSource(dataType),
                onRemove: () => _handleRemove(assignedDevice),
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

  Widget _buildOtherDevicesSection(BuildContext context, DeviceManager deviceManager) {
    return Builder(
      builder: (context) {
        final allDevices = deviceManager.devicesBeacon.watch(context);
        final primaryTrainer = deviceManager.primaryTrainerBeacon.watch(context);
        final powerSource = deviceManager.powerSourceBeacon.watch(context);
        final cadenceSource = deviceManager.cadenceSourceBeacon.watch(context);
        final speedSource = deviceManager.speedSourceBeacon.watch(context);
        final heartRateSource = deviceManager.heartRateSourceBeacon.watch(context);
        
        final assignedDeviceIds = {
          primaryTrainer?.id,
          powerSource?.id,
          cadenceSource?.id,
          speedSource?.id,
          heartRateSource?.id,
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
                    onDisconnect: () => _handleDisconnect(device),
                    onRemove: () => _handleRemove(device),
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
                      if (isConnected && onDisconnect != null)
                        ElevatedButton.icon(
                          onPressed: () => _handleDisconnect(device),
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
                          onPressed: () => _handleDisconnect(device),
                          icon: const Icon(Icons.bluetooth_disabled),
                          label: const Text('Disconnect'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red[50],
                            foregroundColor: Colors.red[900],
                          ),
                        )
                      else
                        ElevatedButton.icon(
                          onPressed: () => _handleConnect(device),
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

  Future<void> _handleDisconnect(FitnessDevice device) async {
    try {
      await device.disconnect();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${device.name} disconnected')));
      setState(() {}); // Refresh UI
    } catch (e, stackTrace) {
      developer.log('Error disconnecting from ${device.name}', name: 'DevicesPage', error: e, stackTrace: stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to disconnect: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _handleRemove(FitnessDevice device) async {
    final deviceManager = Refs.deviceManager.of(context);
    try {
      await device.disconnect();
      await deviceManager.removeDevice(device.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${device.name} removed')));
      setState(() {}); // Refresh UI
    } catch (e, stackTrace) {
      developer.log('Error removing ${device.name}', name: 'DevicesPage', error: e, stackTrace: stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to remove device: $e'), backgroundColor: Colors.red));
    }
  }

  void _handleAssignPrimaryTrainer(FitnessDevice device) {
    final deviceManager = Refs.deviceManager.of(context);
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
    final deviceManager = Refs.deviceManager.of(context);
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
    final deviceManager = Refs.deviceManager.of(context);
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
    final deviceManager = Refs.deviceManager.of(context);
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
    final deviceManager = Refs.deviceManager.of(context);
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
    final deviceManager = Refs.deviceManager.of(context);
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
                            context.push('/scanner?connectMode=true').then((_) {
                              if (mounted) {
                                setState(() {}); // Refresh UI after returning from scanner
                              }
                            });
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
                          _assignDeviceToDataType(device, dataType);
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

}
