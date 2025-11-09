import 'package:flutter/widgets.dart';
import 'package:talker_flutter/talker_flutter.dart';

export 'package:talker/talker.dart' show LogLevel;

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

/// Tracks instances by class name using weak references.
/// Map structure: className -> (identityHashCode -> WeakReference)
final Map<String, Map<int, WeakReference<Object>>> _instanceTracker = {};

/// Function type for transforming an instance into a display name.
///
/// Return a non-null string to use that as the class name,
/// or null to try the next transformer.
typedef ClassNameTransformer = String? Function(Object instance);

/// Registry of class name transformers.
///
/// Transformers are applied in order until one returns a non-null value.
/// Register custom transformers using [registerClassNameTransformer].
final List<ClassNameTransformer> _classNameTransformers = [];

/// Register a custom class name transformer.
///
/// Transformers are applied in registration order. The first transformer
/// that returns a non-null value will be used. If all transformers return
/// null, the instance's runtimeType will be used.
///
/// Example - Custom class mapping:
/// ```dart
/// registerClassNameTransformer((instance) {
///   if (instance is MyCustomClass) {
///     return 'CustomName';
///   }
///   return null;
/// });
/// ```
///
/// Example - Extract provider type:
/// ```dart
/// registerClassNameTransformer((instance) {
///   if (instance is ChangeNotifier) {
///     return 'Provider<${instance.runtimeType}>';
///   }
///   return null;
/// });
/// ```
///
/// Note: The State → Widget transformer is registered by default.
void registerClassNameTransformer(ClassNameTransformer transformer) {
  _classNameTransformers.add(transformer);
}

/// Initialize default transformers.
void _initializeDefaultTransformers() {
  if (_classNameTransformers.isNotEmpty) return;

  // State → Widget$State transformer
  // Shows the widget type with the state type (e.g., "HomePage$_HomePageState")
  registerClassNameTransformer((instance) {
    if (instance is State) {
      // ignore: no_runtimetype_tostring
      final widgetName = instance.widget.runtimeType;
      final instanceType = instance.runtimeType;
      if ('$instanceType' == '_${widgetName}State') {
        return '$widgetName';
      }
      return '$instanceType';
    }
    return null;
  });

  registerClassNameTransformer((instance) {
    if (instance is BuildContext) {
      if (instance is StatelessElement) {
        final widgetName = instance.widget.runtimeType;
        return '$widgetName\$Element';
      }
    }
    return null;
  });
}

/// Get the display name for an instance by applying transformers.
String _getClassName(Object instance) {
  _initializeDefaultTransformers();

  // Try each transformer in order
  for (final transformer in _classNameTransformers) {
    final result = transformer(instance);
    if (result != null) return result;
  }

  // Fallback to runtimeType
  // ignore: no_runtimetype_tostring
  return instance.runtimeType.toString();
}

extension ClassLogger<T extends Object> on T {
  void logClass(Object? message, {Object? e, StackTrace? stack, LogLevel level = LogLevel.debug}) {
    final clazz = _getClassName(this);
    final instanceHash = identityHashCode(this);

    // Register this instance and clean up dead references
    final instances = _instanceTracker.putIfAbsent(clazz, () => {});
    instances[instanceHash] = WeakReference(this);

    // Clean up dead weak references
    instances.removeWhere((key, ref) => ref.target == null);

    // Always include instance hash for clarity
    final hashHex = instanceHash.toRadixString(16).padLeft(4, '0');
    final shortHash = hashHex.substring(hashHex.length - 4);
    final classLabel = '$clazz:$shortHash';

    // Generate readable color using HSL
    // - Hue varies by class name, avoiding red shades (reserved for errors)
    // - Hue range: 60° to 300° (yellow → green → cyan → blue → magenta, skipping red)
    // - Saturation fixed at 70% (vibrant but not oversaturated)
    // - Lightness fixed at 60% (readable on dark backgrounds)
    final hash = classLabel.hashCode;
    const minHue = 60.0; // Start at yellow
    const maxHue = 300.0; // End at magenta (before red)
    final hueRange = maxHue - minHue;
    final hueDegrees = minHue + (hash.abs() % hueRange.toInt());
    final hue = hueDegrees / 360.0; // Convert to 0.0 to 1.0
    const saturation = 0.7;
    const lightness = 0.6;

    final rgb = _hslToRgb(hue, saturation, lightness);

    final pen = AnsiPen()..rgb(r: rgb.$1, g: rgb.$2, b: rgb.$3);
    final entry = TalkerLog('[$classLabel] $message', pen: pen, exception: e, stackTrace: stack, logLevel: level);
    talker.logCustom(entry);
  }
}

/// Converts HSL color to RGB.
///
/// All values are in range 0.0 to 1.0.
/// Returns (r, g, b) tuple.
(double, double, double) _hslToRgb(double h, double s, double l) {
  if (s == 0.0) {
    // Achromatic (gray)
    return (l, l, l);
  }

  double hue2rgb(double p, double q, double t) {
    var t2 = t;
    if (t2 < 0) t2 += 1;
    if (t2 > 1) t2 -= 1;
    if (t2 < 1 / 6) return p + (q - p) * 6 * t2;
    if (t2 < 1 / 2) return q;
    if (t2 < 2 / 3) return p + (q - p) * (2 / 3 - t2) * 6;
    return p;
  }

  final q = l < 0.5 ? l * (1 + s) : l + s - l * s;
  final p = 2 * l - q;

  final r = hue2rgb(p, q, h + 1 / 3);
  final g = hue2rgb(p, q, h);
  final b = hue2rgb(p, q, h - 1 / 3);

  return (r, g, b);
}
