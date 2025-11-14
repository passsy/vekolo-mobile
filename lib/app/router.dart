import 'package:context_plus/context_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:vekolo/app/refs.dart';
import 'package:vekolo/domain/models/workout/workout_models.dart';
import 'package:vekolo/models/activity.dart';
import 'package:vekolo/pages/activity_detail_page.dart';
import 'package:vekolo/pages/auth/login_page.dart';
import 'package:vekolo/pages/auth/signup_page.dart';
import 'package:vekolo/pages/devices_page.dart';
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
      GoRoute(path: '/', builder: (context, state) => const HomePage2()),
      GoRoute(
        path: '/activity/:id',
        builder: (context, state) {
          final activity = state.extra! as Activity;
          return ActivityDetailPage(activity: activity);
        },
      ),
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

          // Extract workout plan and name from extra data
          WorkoutPlan? workoutPlan;
          String? workoutName;

          if (state.extra is Map) {
            final extra = state.extra! as Map;
            workoutPlan = extra['plan'] as WorkoutPlan?;
            workoutName = extra['name'] as String?;
          } else if (state.extra is WorkoutPlan) {
            // Legacy support for direct WorkoutPlan passing
            workoutPlan = state.extra! as WorkoutPlan;
          }

          return WorkoutPlayerPage(isResuming: resuming, workoutPlan: workoutPlan, workoutName: workoutName);
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
