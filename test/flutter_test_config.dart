import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

/// Test configuration to setup Google Fonts for testing.
///
/// Google Fonts are bundled in assets/fonts/ and will be loaded from there
/// instead of being fetched over HTTP during tests.
///
/// This file is automatically loaded by Flutter before running any tests.
/// See: https://api.flutter.dev/flutter/flutter_test/flutter_test-library.html
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // Prevent Google Fonts from making HTTP requests during tests
  // (fonts will be loaded from assets/fonts/ instead)
  GoogleFonts.config.allowRuntimeFetching = false;

  setUpAll(() {
    // Ensure the binding is initialized before tests run
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  return testMain();
}
