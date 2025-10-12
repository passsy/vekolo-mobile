import 'package:context_plus/context_plus.dart';
import 'package:flutter/material.dart';
import 'package:vekolo/api/vekolo_api_client.dart';
import 'package:vekolo/config/api_config.dart';
import 'package:vekolo/domain/devices/device_manager.dart';
import 'package:vekolo/domain/mocks/device_simulator.dart';
import 'package:vekolo/router.dart';
import 'package:vekolo/services/auth_service.dart';
import 'package:vekolo/services/ble_manager.dart';
import 'package:vekolo/services/workout_sync_service.dart';
import 'package:vekolo/state/device_state.dart';
import 'package:vekolo/state/device_state_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize AuthService and load saved auth state
  final authService = AuthService();
  await authService.initialize();

  runApp(MyApp(authService: authService));
}

class MyApp extends StatefulWidget {
  final AuthService authService;

  const MyApp({super.key, required this.authService});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  DeviceStateManager? _deviceStateManager;

  @override
  void dispose() {
    _deviceStateManager?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ContextRef.root(
      child: Builder(
        builder: (context) {
          // Bind services
          bleManagerRef.bindLazy(context, () => BleManager());
          apiClientRef.bindLazy(
            context,
            () => VekoloApiClient(baseUrl: ApiConfig.baseUrl, tokenProvider: () => widget.authService.getAccessToken()),
          );
          authServiceRef.bindValue(context, widget.authService);

          // Initialize DeviceManager with mock devices for testing
          deviceManagerRef.bindLazy(context, () {
            final manager = DeviceManager();
            // Add mock devices for testing
            final trainer = DeviceSimulator.createRealisticTrainer(name: 'Wahoo KICKR');
            final hrm = DeviceSimulator.createHeartRateMonitor(name: 'Garmin HRM-Dual');
            final powerMeter = DeviceSimulator.createPowerMeter(name: 'Stages Power L');

            // Add devices asynchronously (not awaited to avoid blocking app startup)
            Future.microtask(() async {
              await manager.addDevice(trainer);
              await manager.addDevice(hrm);
              await manager.addDevice(powerMeter);
            });

            return manager;
          });

          // Initialize WorkoutSyncService with DeviceManager dependency
          workoutSyncServiceRef.bindLazy(context, () => WorkoutSyncService(deviceManagerRef.of(context)));

          // Initialize DeviceStateManager to bridge DeviceManager with UI state
          // This must happen after DeviceManager is set up but before the router
          if (_deviceStateManager == null) {
            final deviceManager = deviceManagerRef.of(context);
            _deviceStateManager = DeviceStateManager(deviceManager);
          }

          return MaterialApp.router(
            title: 'Vekolo',
            theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.orange)),
            routerConfig: router,
          );
        },
      ),
    );
  }
}
