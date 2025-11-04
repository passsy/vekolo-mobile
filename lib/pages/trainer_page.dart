import 'dart:async';
import 'package:vekolo/app/logger.dart';

import 'package:async/async.dart';
import 'package:context_plus/context_plus.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:vekolo/app/refs.dart';
import 'package:vekolo/domain/devices/device_manager.dart';
import 'package:vekolo/domain/devices/fitness_device.dart';
import 'package:vekolo/domain/models/device_info.dart' as device_info;
import 'package:vekolo/domain/models/fitness_data.dart';

/// Live trainer control with manual power target adjustment.
///
/// Connects to device on init, disconnects on dispose.
/// Auto-navigates home when connection is lost.
class TrainerPage extends StatefulWidget {
  final String deviceId;
  final String deviceName;

  const TrainerPage({super.key, required this.deviceId, required this.deviceName});

  @override
  State<TrainerPage> createState() => _TrainerPageState();
}

class _TrainerPageState extends State<TrainerPage> {
  late final DeviceManager _deviceManager;
  CancelableOperation<void>? _connectionOperation;
  FitnessDevice? _device;
  VoidCallback? _powerSubscription;
  VoidCallback? _cadenceSubscription;
  VoidCallback? _speedSubscription;
  VoidCallback? _connectionSubscription;

  int? _currentPower;
  int? _currentCadence;
  double? _currentSpeed;
  bool _isConnecting = true;
  String? _errorMessage;
  int _targetPower = 150;
  bool _isDisposing = false;
  bool _supportsErgMode = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _deviceManager = Refs.deviceManager.of(context);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _connectToTrainer();
    });
  }

  @override
  void dispose() {
    _isDisposing = true;
    _connectionOperation?.cancel();
    _connectionSubscription?.call();
    _powerSubscription?.call();
    _cadenceSubscription?.call();
    _speedSubscription?.call();
    final device = _device;
    if (device != null) {
      unawaited(_deviceManager.disconnectDevice(device.id));
    }
    super.dispose();
  }

  Future<void> _connectToTrainer() async {
    setState(() {
      _isConnecting = true;
      _errorMessage = null;
    });

    try {
      final device = await _loadOrCreateDevice();
      _device = device;
      _subscribeToDevice(device);

      if (device.connectionState.value != device_info.ConnectionState.connected) {
        if (!mounted) return;
        final deviceManager = Refs.deviceManager.of(context);
        _connectionOperation = deviceManager.connectDevice(device.id);
        await _connectionOperation!.value;
      }

      talker.info('[TrainerPage] Device connected successfully, starting power updates');

      final supportsErgMode = device.supportsErgMode;

      setState(() {
        _isConnecting = false;
        _supportsErgMode = supportsErgMode;
      });

      if (supportsErgMode) {
        _sendTargetPower();
      }
    } catch (e, stackTrace) {
      talker.error('[TrainerPage] Connection failed', e, stackTrace);
      if (mounted) {
        setState(() {
          _errorMessage = 'Connection failed: $e';
          _isConnecting = false;
        });
      }
    }
  }

  /// Loads the device from DeviceManager.
  ///
  /// Throws [ArgumentError] if device is not found. Devices must be connected
  /// via DevicesPage before opening TrainerPage.
  Future<FitnessDevice> _loadOrCreateDevice() async {
    final device = _deviceManager.devices.where((d) => d.id == widget.deviceId).firstOrNull;
    if (device == null) {
      throw ArgumentError(
        'Device ${widget.deviceId} not found in DeviceManager. '
        'Please connect the device via the Devices page first.',
      );
    }
    return device;
  }

  void _subscribeToDevice(FitnessDevice device) {
    _connectionSubscription?.call();
    _connectionSubscription = device.connectionState.subscribe((state) {
      if (!mounted) return;
      if (state == device_info.ConnectionState.disconnected && !_isDisposing) {
        context.go('/');
      }
    });

    _powerSubscription?.call();
    _powerSubscription = device.powerStream?.subscribe((PowerData? data) {
      if (!mounted) return;
      setState(() {
        _currentPower = data?.watts;
        _maybeEstimateSpeed();
      });
    });

    _cadenceSubscription?.call();
    _cadenceSubscription = device.cadenceStream?.subscribe((CadenceData? data) {
      if (!mounted) return;
      setState(() {
        _currentCadence = data?.rpm;
        _maybeEstimateSpeed();
      });
    });

    _speedSubscription?.call();
    _speedSubscription = device.speedStream?.subscribe((SpeedData? data) {
      if (!mounted) return;
      setState(() {
        _currentSpeed = data?.kmh;
      });
    });
  }

  void _maybeEstimateSpeed() {
    if (_device?.speedStream != null) {
      return;
    }
    final cadence = _currentCadence;
    if (cadence == null) {
      _currentSpeed = null;
      return;
    }
    _currentSpeed = cadence * 0.3125;
  }

  void _sendTargetPower() {
    talker.info('[TrainerPage] Initial target power: ${_targetPower}W');
    unawaited(
      _device?.setTargetPower(_targetPower).catchError((Object error, StackTrace stackTrace) {
        talker.error('[TrainerPage] Failed to set target power', error, stackTrace);
        if (!mounted) return;
        setState(() {
          _errorMessage = 'Failed to set target power: $error';
        });
      }),
    );
  }

  void _updateTargetPower(double power) {
    setState(() {
      _targetPower = power.round();
    });
    talker.info('[TrainerPage] Setting target power to ${_targetPower}W');
    if (!_supportsErgMode) {
      return;
    }
    unawaited(
      _device?.setTargetPower(_targetPower).catchError((Object error, StackTrace stackTrace) {
        talker.error('[TrainerPage] Failed to set target power', error, stackTrace);
        if (!mounted) return;
        setState(() {
          _errorMessage = 'Failed to set target power: $error';
        });
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.deviceName.isEmpty ? 'Trainer' : widget.deviceName),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            final device = _device;
            if (device != null) {
              unawaited(device.disconnect());
            }
            context.go('/');
          },
        ),
      ),
      body: _isConnecting
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [CircularProgressIndicator(), SizedBox(height: 16), Text('Connecting to trainer...')],
              ),
            )
          : _errorMessage != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(
                    'Error: $_errorMessage',
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      final device = _device;
                      if (device != null) {
                        unawaited(device.disconnect());
                      }
                      context.go('/');
                    },
                    child: const Text('Go Back'),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  const SizedBox(height: 32),
                  const Text('Trainer Data', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.tune, color: Colors.orange),
                            const SizedBox(width: 12),
                            const Text('Target Power', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            const Spacer(),
                            Text(
                              '${_targetPower}W',
                              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.orange),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Slider(
                          value: _targetPower.toDouble(),
                          max: 300,
                          divisions: 60,
                          label: '${_targetPower}W',
                          activeColor: Colors.orange,
                          onChanged: _supportsErgMode ? _updateTargetPower : null,
                        ),
                        if (!_supportsErgMode)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              'ERG mode is unavailable for this device.',
                              style: TextStyle(color: Colors.orange[900]),
                            ),
                          ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('0W', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                            Text('300W', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  _buildDataCard(
                    icon: Icons.bolt,
                    label: 'Power',
                    value: _currentPower?.toString() ?? '--',
                    unit: 'W',
                    color: Colors.orange,
                  ),
                  const SizedBox(height: 16),
                  _buildDataCard(
                    icon: Icons.speed,
                    label: 'Cadence',
                    value: _currentCadence?.toString() ?? '--',
                    unit: 'RPM',
                    color: Colors.green,
                  ),
                  const SizedBox(height: 16),
                  _buildDataCard(
                    icon: Icons.directions_bike,
                    label: 'Speed',
                    value: _currentSpeed?.toStringAsFixed(1) ?? '--',
                    unit: 'km/h',
                    color: Colors.blue,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () {
                      final device = _device;
                      if (device != null) {
                        unawaited(device.disconnect());
                      }
                      context.go('/');
                    },
                    icon: const Icon(Icons.close),
                    label: const Text('Disconnect'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  Widget _buildDataCard({
    required IconData icon,
    required String label,
    required String value,
    required String unit,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 48, color: color),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 16, color: Colors.grey[600])),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      value,
                      style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: color),
                    ),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(unit, style: TextStyle(fontSize: 16, color: Colors.grey[600])),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
