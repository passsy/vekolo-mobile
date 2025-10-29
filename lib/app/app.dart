import 'dart:developer' as devloper;

import 'package:context_plus/context_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:vekolo/api/pretty_log_interceptor.dart';
import 'package:vekolo/api/vekolo_api_client.dart';
import 'package:vekolo/app/refs.dart';
import 'package:vekolo/ble/ble_scanner.dart';
import 'package:vekolo/config/api_config.dart';
import 'package:vekolo/config/ble_config.dart';
import 'package:vekolo/domain/devices/device_manager.dart';
import 'package:vekolo/app/router.dart';
import 'package:vekolo/services/auth_service.dart';
import 'package:vekolo/services/ble_manager.dart';
import 'package:vekolo/services/fresh_auth.dart';
import 'package:vekolo/services/workout_sync_service.dart';
import 'package:vekolo/state/device_state.dart';
import 'package:vekolo/state/device_state_manager.dart';
import 'package:vekolo/widgets/splash_screen.dart';

class VekoloApp extends StatefulWidget {
  const VekoloApp({super.key});

  @override
  State<VekoloApp> createState() => _VekoloAppState();
}

class _VekoloAppState extends State<VekoloApp> {
  bool _initialized = false;

  /// Perform async initialization of services before mounting the main app / drawing the first frame
  Future<void> _initialize(BuildContext context) async {
    // Disable verbose flutter_blue_plus logging
    FlutterBluePlus.setLogLevel(LogLevel.warning);

    // Initialize DeviceStateManager to start streaming device data to UI beacons
    // Must be done before any async operations to avoid BuildContext issues
    deviceStateManagerRef.of(context);
    devloper.log('[VekoloApp] DeviceStateManager initialized');

    // Run async initialization (load user from secure storage)
    final authService = Refs.authService.of(context);
    await authService.initialize();
    try {
      await authService.refreshAccessToken();
    } catch (e, stack) {
      devloper.log('[VekoloApp] No valid refresh token found during initialization', error: e, stackTrace: stack);
    }

    // Mark initialization as complete
    if (mounted) {
      setState(() => _initialized = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ContextRef.root(
      child: Builder(
        builder: (context) {
          // Bind all services on every build (required by ContextRef)
          late final VekoloApiClient apiClient;

          // Create Fresh with lazy apiClient access
          final fresh = createFreshAuth(apiClient: () => apiClient);
          final authService = Refs.authService.bind(
            context,
            () => AuthService(fresh: fresh, apiClient: () => apiClient),
          );

          apiClient = Refs.apiClient.bind(
            context,
            () => VekoloApiClient(
              baseUrl: ApiConfig.baseUrl,
              interceptors: [
                PrettyLogInterceptor(logMode: LogMode.unexpectedResponses),
                authService.apiInterceptor,
              ],
            ),
          );

          // Initialize BLE services
          bleScannerRef.bindLazy(context, () {
            final scanner = BleScanner();
            scanner.initialize();
            return scanner;
          });
          bleManagerRef.bindLazy(context, () => BleManager());

          // Initialize DeviceManager
          deviceManagerRef.bindLazy(context, () => DeviceManager());

          // Initialize WorkoutSyncService with DeviceManager dependency
          workoutSyncServiceRef.bindLazy(context, () => WorkoutSyncService(deviceManagerRef.of(context)));

          // Initialize DeviceStateManager to bridge DeviceManager with UI state
          deviceStateManagerRef.bindLazy(context, () => DeviceStateManager(deviceManagerRef.of(context)));

          // Show splash screen during initialization
          if (!_initialized) {
            _initialize(context); // Fire and forget - setState will rebuild

            return MaterialApp(debugShowCheckedModeBanner: false, title: 'Vekolo', home: SplashScreen());
          }

          // After initialization, render main app
          return MaterialApp.router(
            title: 'Vekolo',
            theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.orange)),
            debugShowCheckedModeBanner: false,
            routerConfig: router,
          );
        },
      ),
    );
  }
}
