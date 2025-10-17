import 'dart:async';
import 'package:async/async.dart';
import 'package:context_plus/context_plus.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:vekolo/services/ble_manager.dart';
import 'dart:developer' as developer;

class TrainerPage extends StatefulWidget {
  final String deviceId;
  final String deviceName;

  const TrainerPage({super.key, required this.deviceId, required this.deviceName});

  @override
  State<TrainerPage> createState() => _TrainerPageState();
}

class _TrainerPageState extends State<TrainerPage> {
  late final BleManager _bleManager;
  CancelableOperation<void>? _connectionOperation;

  int? _currentPower;
  int? _currentCadence;
  double? _currentSpeed;
  bool _isConnecting = true;
  String? _errorMessage;
  int _targetPower = 150;
  bool _isDisposing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bleManager = bleManagerRef.of(context);
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
    _bleManager.disconnect();
    super.dispose();
  }

  Future<void> _connectToTrainer() async {
    setState(() {
      _isConnecting = true;
      _errorMessage = null;
    });

    _bleManager.onTrainerDataUpdate = (power, cadence, speed) {
      setState(() {
        _currentPower = power;
        _currentCadence = cadence;
        _currentSpeed = speed;
        _isConnecting = false;
      });
    };

    _bleManager.onError = (error) {
      developer.log('[TrainerPage] Error: $error');
      setState(() {
        _errorMessage = error;
        _isConnecting = false;
      });
    };

    _bleManager.onDisconnected = () {
      developer.log('[TrainerPage] Disconnected');
      // Only navigate if not already disposing (to avoid using context after disposal)
      if (mounted && !_isDisposing) {
        context.go('/');
      }
    };

    try {
      _connectionOperation = _bleManager.connectToDevice(widget.deviceId);
      await _connectionOperation!.value;
      developer.log('[TrainerPage] Device connected successfully, starting power updates');

      // Connection successful, start sending power commands
      _startPowerUpdates();
      setState(() {
        _isConnecting = false;
      });
    } catch (e, stackTrace) {
      developer.log('[TrainerPage] Connection failed: $e');
      print(stackTrace);
      if (mounted) {
        setState(() {
          _errorMessage = 'Connection failed: $e';
          _isConnecting = false;
        });
      }
    }
  }

  void _startPowerUpdates() {
    // Send initial power
    developer.log('[TrainerPage] Initial target power: ${_targetPower}W');
    _bleManager.setTargetPower(_targetPower);
  }

  void _updateTargetPower(double power) {
    setState(() {
      _targetPower = power.round();
    });
    developer.log('[TrainerPage] Setting target power to ${_targetPower}W');
    _bleManager.setTargetPower(_targetPower);
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
            _bleManager.disconnect();
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
                      _bleManager.disconnect();
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
                          onChanged: _updateTargetPower,
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
                      _bleManager.disconnect();
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
