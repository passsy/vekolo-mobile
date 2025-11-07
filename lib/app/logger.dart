import 'package:talker_flutter/talker_flutter.dart';

/// Custom formatter that displays only the message without underline/topline borders
class SimpleLoggerFormatter implements LoggerFormatter {
  const SimpleLoggerFormatter();

  @override
  String fmt(LogDetails details, TalkerLoggerSettings settings) {
    final msg = details.message?.toString() ?? '';

    // Parse and reformat the timestamp to align milliseconds
    final formattedMsg = _formatTimestamp(msg);

    final msgBorderedLines = formattedMsg.split('\n').map((e) => '│ $e');

    if (!settings.enableColors) {
      return msgBorderedLines.join('\n');
    }

    final coloredLines = msgBorderedLines.map((e) => details.pen.write(e));
    return coloredLines.join('\n');
  }

  /// Reformats timestamp to align milliseconds and log level
  /// Example: "[info] | 1:42:35 971ms" -> "[info ] | 1:42:35 971 ms"
  String _formatTimestamp(String msg) {
    // Pattern: [level] | H:MM:SS <1-3 digits>ms or HH:MM:SS
    final timestampPattern = RegExp(r'\[(.*?)](\s*\|\s*\d{1,2}:\d{2}:\d{2})\s+(\d{1,3})ms');

    return msg.replaceAllMapped(timestampPattern, (match) {
      final level = match.group(1)!;
      final timeAndSeparator = match.group(2)!;
      final milliseconds = match.group(3)!;

      // Pad log level to 5 characters (to accommodate "warning" or "critical")
      final paddedLevel = level.padRight(5);
      // Pad milliseconds to 3 characters (0-999)
      final paddedMs = milliseconds.padLeft(3);

      return '$paddedLevel$timeAndSeparator $paddedMs ms';
    });
  }
}

/// Global Talker instance for logging throughout the app.
///
/// Initialize this early in main() before running the app.
/// Access it anywhere in the code without dependency injection.
final talker = TalkerFlutter.init(
  settings: TalkerSettings(),
  logger: TalkerLogger(formatter: SimpleLoggerFormatter()),
);
