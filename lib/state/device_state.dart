import 'package:context_plus/context_plus.dart';
import 'package:vekolo/domain/devices/device_manager.dart';

/// Ref for dependency injection of DeviceManager.
///
/// Used throughout the app to access the central device coordinator.
/// Initialize with mock devices for testing or leave empty for production.
final deviceManagerRef = Ref<DeviceManager>();
