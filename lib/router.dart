import 'package:go_router/go_router.dart';
import 'package:vekolo/pages/home_page.dart';
import 'package:vekolo/pages/scanner_page.dart';
import 'package:vekolo/pages/trainer_page.dart';

final router = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (context, state) => const HomePage()),
    GoRoute(path: '/scanner', builder: (context, state) => const ScannerPage()),
    GoRoute(
      path: '/trainer',
      builder: (context, state) {
        final deviceId = state.uri.queryParameters['deviceId'] ?? '';
        final deviceName = state.uri.queryParameters['deviceName'] ?? '';
        return TrainerPage(deviceId: deviceId, deviceName: deviceName);
      },
    ),
  ],
);
