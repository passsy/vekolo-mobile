import 'package:talker_flutter/talker_flutter.dart';

/// Global Talker instance for logging throughout the app.
///
/// Initialize this early in main() before running the app.
/// Access it anywhere in the code without dependency injection.
final talker = TalkerFlutter.init(
  settings: TalkerSettings(
    
  ),
);
