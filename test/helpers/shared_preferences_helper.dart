import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';

/// Creates a properly initialized SharedPreferencesAsync instance for testing.
///
/// This helper ensures the platform instance is set before creating the async
/// preferences object, preventing "SharedPreferencesAsyncPlatform instance must be set" errors.
SharedPreferencesAsync createTestSharedPreferencesAsync() {
  if (SharedPreferencesAsyncPlatform.instance == null) {
    final empty = InMemorySharedPreferencesAsync.empty();
    SharedPreferencesAsyncPlatform.instance = empty;

    addTearDown(() {
      if (SharedPreferencesAsyncPlatform.instance == empty) {
        SharedPreferencesAsyncPlatform.instance = null;
      }
    });
  }
  return SharedPreferencesAsync();
}
