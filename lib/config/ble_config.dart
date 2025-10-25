import 'package:context_plus/context_plus.dart' as context_plus;
import 'package:vekolo/ble/ble_scanner.dart';

/// Global reference for dependency injection of BleScanner
final bleScannerRef = context_plus.Ref<BleScanner>();
