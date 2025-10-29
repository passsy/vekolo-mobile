import 'package:context_plus/context_plus.dart';
import 'package:vekolo/api/vekolo_api_client.dart';
import 'package:vekolo/services/auth_service.dart';

abstract final class Refs {
  // Private constructor to prevent instantiation
  Refs._();

  static final apiClient = Ref<VekoloApiClient>();

  static final authService = Ref<AuthService>();
}
