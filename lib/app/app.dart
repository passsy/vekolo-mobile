import 'package:chirp/chirp.dart';

import 'package:context_plus/context_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wiredash/wiredash.dart';
import 'package:vekolo/api/pretty_log_interceptor.dart';
import 'package:vekolo/api/vekolo_api_client.dart';
import 'package:vekolo/app/colors.dart';
import 'package:vekolo/app/refs.dart';
import 'package:vekolo/ble/ble_permissions.dart';
import 'package:vekolo/ble/ble_platform.dart' hide LogLevel;
import 'package:vekolo/ble/ble_scanner.dart';
import 'package:vekolo/ble/ftms_ble_transport.dart';
import 'package:vekolo/ble/heart_rate_ble_transport.dart';
import 'package:vekolo/ble/transport_registry.dart';
import 'package:vekolo/config/api_config.dart';
import 'package:vekolo/domain/devices/device_manager.dart';
import 'package:vekolo/app/router.dart';
import 'package:vekolo/services/auth_service.dart';
import 'package:vekolo/services/device_assignment_persistence.dart';
import 'package:vekolo/services/fresh_auth.dart';
import 'package:vekolo/services/notification_service.dart';
import 'package:vekolo/services/workout_session_persistence.dart';
import 'package:vekolo/services/workout_sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vekolo/widgets/initialization_error_screen.dart';
import 'package:vekolo/widgets/splash_screen.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp show LogLevel;

class VekoloApp extends StatefulWidget {
  const VekoloApp({super.key});

  @override
  State<VekoloApp> createState() => _VekoloAppState();
}

class _VekoloAppState extends State<VekoloApp> {
  bool _initialized = false;
  String? _initializationError;
  String? _initializationStackTrace;
  DateTime? _initializationStartTime;

  /// Perform async initialization of services before mounting the main app / drawing the first frame
  Future<void> _initialize(BuildContext context) async {
    _initializationStartTime ??= DateTime.now();
    if (!mounted) return;

    // Configure system UI for dark mode with edge-to-edge
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarContrastEnforced: false,
      ),
    );
    try {
      // Initialize SharedPreferences first (required by other services)
      if (!mounted) return;

      // Disable verbose flutter_blue_plus logging
      Refs.blePlatform.of(context).setLogLevel(fbp.LogLevel.none);

      // Capture references before async operations
      final deviceManager = Refs.deviceManager.of(context);
      final authService = Refs.authService.of(context);

      // Initialize DeviceManager auto-connect
      try {
        await deviceManager.initialize();
      } catch (e, stackTrace) {
        chirp.error('Failed to initialize DeviceManager auto-connect', error: e, stackTrace: stackTrace);
      }

      // Run async initialization (load user from secure storage)
      await authService.initialize();
      try {
        await authService.refreshAccessToken();
      } catch (e, stack) {
        chirp.error('No valid refresh token found during initialization', error: e, stackTrace: stack);
      }

      // Ensure splash screen is shown for at least the animation duration
      final elapsedTime = DateTime.now().difference(_initializationStartTime!);
      final remainingTime = splashScreenAnimationDuration - elapsedTime;
      if (remainingTime.inMilliseconds > 0) {
        await Future<void>.delayed(remainingTime);
      }

      // Mark initialization as complete
      if (mounted) {
        setState(() {
          _initialized = true;
          _initializationError = null;
          _initializationStackTrace = null;
        });
      }
    } catch (e, stack) {
      chirp.error('Initialization failed', error: e, stackTrace: stack);
      if (mounted) {
        setState(() {
          _initializationError = e.toString();
          _initializationStackTrace = stack.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ContextPlus.root(
      child: AppRestart(
        onStop: () {
          setState(() {
            _initialized = false;
          });
        },
        builder: (context) {
          // Bind all services on every build (required by ContextRef)
          late final VekoloApiClient apiClient;
          VekoloApiClient apiClientProvider() => apiClient;

          // Create Fresh with lazy apiClient access
          final fresh = createFreshAuth(apiClient: apiClientProvider);
          final authService = Refs.authService.bindWhenUnbound(
            context,
            () => AuthService(fresh: fresh, apiClient: apiClientProvider),
            key: (apiClientProvider,),
          );

          final apiClientRef = Refs.apiClient.bindWhenUnbound(
            context,
            () => VekoloApiClient(
              baseUrl: ApiConfig.baseUrl,
              interceptors: [
                PrettyLogInterceptor(logMode: LogMode.unexpectedResponses),
                authService.apiInterceptor,
              ],
            ),
            key: (authService,),
          );
          apiClient = apiClientRef;

          final blePlatform = Refs.blePlatform.bindWhenUnbound(
            context,
            () => BlePlatformImpl(),
            dispose: (platform) => platform.dispose(),
          );
          final blePermissions = Refs.blePermissions.bindWhenUnbound(context, () => BlePermissionsImpl());

          // Initialize transport registry and register available transports
          final transportRegistry = Refs.transportRegistry.bindWhenUnbound(context, () {
            final registry = TransportRegistry();
            // Register transport implementations
            registry.register(ftmsTransportRegistration);
            registry.register(heartRateTransportRegistration);
            return registry;
          });

          // Initialize BLE services
          final scanner = Refs.bleScanner.bindWhenUnbound(
            context,
            () {
              final scanner = BleScanner(platform: blePlatform, permissions: blePermissions);
              scanner.initialize();
              return scanner;
            },
            dispose: (scanner) => scanner.dispose(),
            key: (blePlatform, blePermissions),
          );

          // Note: SharedPreferences must be initialized before this point
          // It's initialized in _initialize() method
          final persistence = Refs.deviceAssignmentPersistence.bindWhenUnbound(
            context,
            () => DeviceAssignmentPersistence(SharedPreferencesAsync()),
          );

          // Initialize WorkoutSessionPersistence
          Refs.workoutSessionPersistence.bindWhenUnbound(
            context,
            () => WorkoutSessionPersistence(prefs: SharedPreferencesAsync()),
          );

          // Initialize NotificationService
          Refs.notificationService.bindWhenUnbound(
            context,
            () => NotificationService(),
            dispose: (service) => service.dispose(),
          );

          // Initialize DeviceManager
          final deviceManager = Refs.deviceManager.bindWhenUnbound(
            context,
            () => DeviceManager(
              platform: blePlatform,
              scanner: scanner,
              transportRegistry: transportRegistry,
              persistence: persistence,
            ),
            dispose: (manager) => manager.dispose(),
            key: (blePlatform, scanner, transportRegistry, persistence),
          );

          // Initialize WorkoutSyncService with DeviceManager dependency
          Refs.workoutSyncService.bindWhenUnbound(
            context,
            () => WorkoutSyncService(deviceManager),
            dispose: (service) => service.dispose(),
            key: (deviceManager,),
          );

          // Show splash screen during initialization
          if (!_initialized) {
            // TODO handle when dependencies change to eventually call it again. Not required yet, but possible in the future
            if (_initializationError == null) {
              _initialize(context); // Fire and forget - setState will rebuild
            }

            return Wiredash(
              projectId: 'vekolo-6hc06gd',
              secret: 'gMdvLXLa3Xd8B6uXlpIr2uCmcUsflaOe',
              theme: WiredashThemeData.fromColor(primaryColor: VekoloColors.laser, brightness: Brightness.dark)
                  .copyWith(
                    primaryContainerColor: VekoloColors.calm,
                    secondaryContainerColor: VekoloColors.beige,
                    primaryBackgroundColor: VekoloColors.offBlack,
                    secondaryBackgroundColor: Colors.black,
                    textOnPrimaryContainerColor: VekoloColors.offWhite,
                    textOnSecondaryContainerColor: VekoloColors.offBlack,
                    firstPenColor: VekoloColors.firelineOrange,
                    secondPenColor: VekoloColors.limitBreakPink,
                    thirdPenColor: VekoloColors.vitalSurgeGreen,
                    fourthPenColor: VekoloColors.oxygenRushLightBlue,
                  ),
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                title: 'Vekolo',
                home: _initializationError != null
                    ? InitializationErrorScreen(
                        error: _initializationError!,
                        stackTrace: _initializationStackTrace,
                        onRetry: () {
                          setState(() {
                            _initializationError = null;
                            _initializationStackTrace = null;
                          });
                          _initialize(context);
                        },
                      )
                    : const SplashScreen(),
              ),
            );
          }

          // After initialization, render main app
          return Wiredash(
            projectId: 'vekolo-6hc06gd',
            secret: 'gMdvLXLa3Xd8B6uXlpIr2uCmcUsflaOe',
            theme: WiredashThemeData.fromColor(primaryColor: VekoloColors.laser, brightness: Brightness.dark).copyWith(
              primaryContainerColor: VekoloColors.calm,
              secondaryContainerColor: VekoloColors.beige,
              primaryBackgroundColor: VekoloColors.offBlack,
              secondaryBackgroundColor: Colors.black,
              textOnPrimaryContainerColor: VekoloColors.offWhite,
              textOnSecondaryContainerColor: VekoloColors.offBlack,
              firstPenColor: VekoloColors.firelineOrange,
              secondPenColor: VekoloColors.limitBreakPink,
              thirdPenColor: VekoloColors.vitalSurgeGreen,
              fourthPenColor: VekoloColors.oxygenRushLightBlue,
            ),
            child: VekoloRouter(
              builder: (context) {
                return MaterialApp.router(
                  title: 'Vekolo',
                  theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.orange)),
                  debugShowCheckedModeBanner: false,
                  routerConfig: Refs.router.of(context),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class AppRestart extends StatefulWidget {
  const AppRestart({super.key, required this.builder, this.onStop});

  final Widget Function(BuildContext context) builder;

  final void Function()? onStop;

  @override
  State<AppRestart> createState() => AppRestartState();
}

class AppRestartState extends State<AppRestart> {
  Key _key = UniqueKey();
  bool _isAppRunning = true;

  /// Forces the [widget.builder] to rebuild and lose all of its state
  void relaunch() {
    widget.onStop?.call();
    setState(() => _key = UniqueKey());
  }

  void stopApp() {
    widget.onStop?.call();
    setState(() => _isAppRunning = false);
  }

  void startApp() {
    setState(() => _isAppRunning = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAppRunning) {
      return const SizedBox.shrink();
    }
    return Builder(key: _key, builder: widget.builder);
  }
}
