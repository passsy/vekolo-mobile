import 'package:context_plus/context_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:vekolo/app/refs.dart';
import 'package:vekolo/pages/auth/login_page.dart';
import 'package:vekolo/pages/auth/signup_page.dart';
import 'package:vekolo/pages/devices_page.dart';
import 'package:vekolo/pages/home_page.dart';
import 'package:vekolo/pages/home_page_v2/home_page_v2.dart';
import 'package:vekolo/pages/profile_page.dart';
import 'package:vekolo/pages/scanner_page.dart';
import 'package:vekolo/pages/trainer_page.dart';
import 'package:vekolo/pages/unknown_device_report_page.dart';
import 'package:vekolo/pages/workout_player_page.dart';

class VekoloRouter extends StatefulWidget {
  const VekoloRouter({super.key, required this.builder});

  final Widget Function(BuildContext) builder;

  @override
  State<VekoloRouter> createState() => _VekoloRouterState();
}

class _VekoloRouterState extends State<VekoloRouter> {
  final _router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (context, state) => const HomePage()),
      GoRoute(path: '/home2', builder: (context, state) => const HomePage2()),
      GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
      GoRoute(path: '/signup', builder: (context, state) => const SignupPage()),
      GoRoute(path: '/profile', builder: (context, state) => const ProfilePage()),
      GoRoute(
        path: '/scanner',
        builder: (context, state) {
          final connectMode = state.uri.queryParameters['connectMode'] == 'true';
          return ScannerPage(connectMode: connectMode);
        },
      ),
      GoRoute(path: '/devices', builder: (context, state) => const DevicesPage()),
      GoRoute(
        path: '/trainer',
        builder: (context, state) {
          final deviceId = state.uri.queryParameters['deviceId'] ?? '';
          final deviceName = state.uri.queryParameters['deviceName'] ?? '';
          return TrainerPage(deviceId: deviceId, deviceName: deviceName);
        },
      ),
      GoRoute(path: '/unknown-device', builder: (context, state) => const UnknownDeviceReportPage()),
      GoRoute(
        path: '/workout-player',
        builder: (context, state) {
          final resuming = state.uri.queryParameters['resuming'] == 'true';
          return WorkoutPlayerPage(isResuming: resuming);
        },
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    Refs.router.bindValue(context, _router);
    return widget.builder(context);
  }
}
