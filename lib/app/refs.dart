import 'package:context_plus/context_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:vekolo/api/vekolo_api_client.dart';
import 'package:vekolo/ble/ble_permissions.dart';
import 'package:vekolo/ble/ble_platform.dart';
import 'package:vekolo/ble/ble_scanner.dart';
import 'package:vekolo/domain/devices/device_manager.dart';
import 'package:vekolo/services/auth_service.dart';
import 'package:vekolo/services/workout_sync_service.dart';
import 'package:vekolo/state/device_state.dart';
import 'package:vekolo/state/device_state_manager.dart';

abstract final class Refs {
  Refs._();

  static final apiClient = Ref<VekoloApiClient>();
  static final authService = Ref<AuthService>();
  static final blePlatform = Ref<BlePlatform>();
  static final blePermissions = Ref<BlePermissions>();
  static final bleScanner = Ref<BleScanner>();
  static final deviceManager = Ref<DeviceManager>();
  static final workoutSyncService = Ref<WorkoutSyncService>();
  static final connectedDevices = Ref<ConnectedDevices>();
  static final liveTelemetry = Ref<LiveTelemetry>();
  static final workoutSyncState = Ref<WorkoutSyncState>();
  static final deviceStateManager = Ref<DeviceStateManager>();
}

extension BindUnboundRef<T> on Ref<T> {
  /// Binds the Ref if it is not already bound to [context], otherwise returns the existing value from [context].
  T bindWhenUnbound(BuildContext context, T Function() create, {void Function(T value)? dispose, Object? key}) {
    final T? found = maybeOf(context);
    if (found == null) {
      // If the Ref is not bound, bind it now
      return bind(context, create, dispose: dispose, key: key);
    }
    return found;
  }
}
