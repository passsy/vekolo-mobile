import 'package:flutter/material.dart';
import 'package:vekolo/app/app.dart';
import 'package:vekolo/app/logger.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  initializeLogger();

  // Important:
  // Don't put any initialization/setup code here, move it to _VekoloAppState._initialize

  runApp(VekoloApp());
}
