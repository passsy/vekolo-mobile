import 'package:context_plus/context_plus.dart';
import 'package:flutter/material.dart';
import 'package:vekolo/api/pretty_log_interceptor.dart';
import 'package:vekolo/api/vekolo_api_client.dart';
import 'package:vekolo/config/api_config.dart';
import 'package:vekolo/domain/devices/device_manager.dart';
import 'package:vekolo/router.dart';
import 'package:vekolo/services/auth_service.dart';
import 'package:vekolo/services/ble_manager.dart';
import 'package:vekolo/services/workout_sync_service.dart';
import 'package:vekolo/state/device_state.dart';
import 'package:vekolo/state/device_state_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(VekoloApp());
}

class VekoloApp extends StatefulWidget {
  const VekoloApp({super.key});

  @override
  State<VekoloApp> createState() => _VekoloAppState();
}

class _VekoloAppState extends State<VekoloApp> {
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
          late final VekoloApiClient apiClient;
          final authService = authServiceRef.bindValue(context, AuthService(apiClient: () => apiClient));
          // TODO move in init method
          authService.initialize();

          // Bind services
          apiClient = apiClientRef.bindValue(
            context,
            VekoloApiClient(
              baseUrl: ApiConfig.baseUrl,
              interceptors: [
                PrettyLogInterceptor(logMode: LogMode.unexpectedResponses),
                authService.apiInterceptor,
              ],
              tokenProvider: () async {
                return await authService.getAccessToken();
              },
            ),
          );

          // Initialize DeviceManager
          bleManagerRef.bindLazy(context, () => BleManager());
          deviceManagerRef.bindLazy(context, () => DeviceManager());

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
