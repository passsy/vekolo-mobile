import 'package:context_plus/context_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:vekolo/api/vekolo_api_client.dart';
import 'package:vekolo/ble/ble_permissions.dart';
import 'package:vekolo/ble/ble_platform.dart';
import 'package:vekolo/ble/ble_scanner.dart';
import 'package:vekolo/ble/transport_registry.dart';
import 'package:vekolo/domain/devices/device_manager.dart';
import 'package:vekolo/services/auth_service.dart';
import 'package:vekolo/services/device_assignment_persistence.dart';
import 'package:vekolo/services/notification_service.dart';
import 'package:vekolo/services/workout_player_service.dart';
import 'package:vekolo/services/workout_recording_service.dart';
import 'package:vekolo/services/workout_session_persistence.dart';
import 'package:vekolo/services/workout_sync_service.dart';

abstract final class Refs {
  Refs._();

  static final apiClient = Ref<VekoloApiClient>();
  static final authService = Ref<AuthService>();
  static final blePlatform = Ref<BlePlatform>();
  static final blePermissions = Ref<BlePermissions>();
  static final bleScanner = Ref<BleScanner>();
  static final transportRegistry = Ref<TransportRegistry>();
  static final deviceAssignmentPersistence = Ref<DeviceAssignmentPersistence>();
  static final workoutSessionPersistence = Ref<WorkoutSessionPersistence>();
  static final deviceManager = Ref<DeviceManager>();
  static final workoutSyncService = Ref<WorkoutSyncService>();
  static final notificationService = Ref<NotificationService>();
  static final router = Ref<GoRouter>();
  static final workoutPlayerService = Ref<WorkoutPlayerService>();
  static final workoutRecordingService = Ref<WorkoutRecordingService>();
}

extension BindUnboundRef<T> on Ref<T> {
  /// Binds the Ref if it is not already bound to [context], otherwise returns the existing value from [context].
  ///
  /// Always calls [bind] to ensure the [dispose] callback is set/updated, even if the ref is already bound.
  T bindWhenUnbound(BuildContext context, T Function() create, {void Function(T value)? dispose, Object? key}) {
    final T? found = maybeOf(context);
    if (found == null) {
      // If the Ref is not bound, bind it now
      return bind(context, create, dispose: dispose, key: key);
    }
    return found;
  }
}
