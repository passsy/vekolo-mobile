import 'package:context_plus/context_plus.dart';
import 'package:flutter/material.dart';
import 'package:vekolo/api/vekolo_api_client.dart';
import 'package:vekolo/config/api_config.dart';
import 'package:vekolo/router.dart';
import 'package:vekolo/services/auth_service.dart';
import 'package:vekolo/services/ble_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize AuthService and load saved auth state
  final authService = AuthService();
  await authService.initialize();

  runApp(MyApp(authService: authService));
}

class MyApp extends StatelessWidget {
  final AuthService authService;

  const MyApp({super.key, required this.authService});

  @override
  Widget build(BuildContext context) {
    return ContextRef.root(
      child: Builder(
        builder: (context) {
          // Bind services
          bleManagerRef.bindLazy(context, () => BleManager());
          apiClientRef.bindLazy(
            context,
            () => VekoloApiClient(baseUrl: ApiConfig.baseUrl, tokenProvider: () => authService.getAccessToken()),
          );
          authServiceRef.bindValue(context, authService);

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
