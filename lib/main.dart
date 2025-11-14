import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vekolo/app/app.dart';
import 'package:vekolo/app/logger.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  initializeLogger();

  // Configure system UI for dark mode with edge-to-edge
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
      systemNavigationBarContrastEnforced: false,
    ),
  );

  // Important:
  // Don't put any initialization/setup code here, move it to _VekoloAppState._initialize

  runApp(VekoloApp());
}
