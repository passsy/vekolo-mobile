import 'package:flutter/widgets.dart';
import 'package:talker_flutter/talker_flutter.dart';

export 'package:talker_flutter/talker_flutter.dart' show LogLevel;

final Map<String, WeakReference<ColumnFormattedLog>> _messagesCache = {};

/// Custom TalkerLog that formats messages with equally spaced columns.
class ColumnFormattedLog extends TalkerLog {
  ColumnFormattedLog(
    super.message, {
    this.classLabel,
    TimeFormat? timeFormat,
    super.key,
    super.title,
    super.exception,
    super.error,
    super.stackTrace,
    super.time,
    super.pen,
    super.logLevel,
  }) : _timeFormat = timeFormat;

  final String? classLabel;

  TimeFormat? _timeFormat;
  TimeFormat? get timeFormat => _timeFormat;

  @override
  String generateTextMessage({TimeFormat timeFormat = TimeFormat.timeAndSeconds}) {
    _timeFormat = timeFormat;
    final lookupKey = (time, message).toString();
    _messagesCache.putIfAbsent(lookupKey, () => WeakReference(this));
    return lookupKey;
  }
}

/// Custom formatter that displays only the message without underline/topline borders
class SimpleLoggerFormatter implements LoggerFormatter {
  const SimpleLoggerFormatter();

  @override
  String fmt(LogDetails details, TalkerLoggerSettings settings) {
    final msg = _messagesCache[details.message]?.target;
    if (msg == null) {
      return details.message?.toString() ?? '';
    }

    final String formattedTime;
    if (msg.timeFormat == TimeFormat.timeAndSeconds) {
      final hour = msg.time.hour.toString().padLeft(2, '0');
      final minute = msg.time.minute.toString().padLeft(2, '0');
      final second = msg.time.second.toString().padLeft(2, '0');
      final ms = msg.time.millisecond.toString().padLeft(3, '0');
      formattedTime = '$hour:$minute:$second.$ms';
    } else {
      final year = msg.time.year.toString().padLeft(4);
      final month = msg.time.month.toString().padLeft(2, '0');
      final day = msg.time.day.toString().padLeft(2, '0');
      final hour = msg.time.hour.toString().padLeft(2, '0');
      final minute = msg.time.minute.toString().padLeft(2, '0');
      final second = msg.time.second.toString().padLeft(2, '0');
      final ms = msg.time.millisecond.toString().padLeft(3, '0');
      formattedTime = '$year:$month:$day $hour:$minute:$second.${ms}';
    }

    const metaWidth = 60;
    final justText = '$formattedTime [${msg.logLevel?.name}] ${msg.classLabel}';
    final remaining = metaWidth - justText.length;
    final meta = '$formattedTime [${msg.logLevel?.name}] ${"".padRight(remaining, '=')} ${msg.classLabel}';

    final message = msg.displayMessage;
    final messageLines = message.split('\n');

    final errorOnNewLine = msg.error == null ? "" : "\n${msg.error}";
    final exceptionOnNewLine = msg.exception == null ? "" : "\n${msg.exception}";
    final stacktraceOnNewLine = msg.stackTrace == null ? "" : "\n${msg.stackTrace}";
    final newLineThings = "${errorOnNewLine}${exceptionOnNewLine}${stacktraceOnNewLine}";

    String color(String msg) {
      if (settings.enableColors) {
        return details.pen.write(msg);
      }
      return msg;
    }

    final colorNewLineThings = newLineThings.split('\n').map(color).join('\n');
    if (messageLines.length <= 1) {
      return color('$meta │ $message') + colorNewLineThings;
    } else {
      final lines = messageLines.map(color);
      return '${color(meta)} │ \n${lines.map(color).join('\n')}${colorNewLineThings}';
    }
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

    // Always include instance hash for clarity
    final hashHex = instanceHash.toRadixString(16).padLeft(4, '0');
    final shortHash = hashHex.substring(hashHex.length - 4);
    final classLabel = '$clazz:$shortHash';

    // Generate readable color using HSL
    final double hue;
    const saturation = 0.7;
    const lightness = 0.6;

    if (e != null) {
      // Use red color for errors/exceptions
      hue = 0.0; // Red
    } else {
      // - Hue varies by class name, avoiding red shades (reserved for errors)
      // - Hue range: 60° to 300° (yellow → green → cyan → blue → magenta, skipping red)
      // - Saturation fixed at 70% (vibrant but not oversaturated)
      // - Lightness fixed at 60% (readable on dark backgrounds)
      final hash = clazz.hashCode;
      const minHue = 60.0; // Start at yellow
      const maxHue = 300.0; // End at magenta (before red)
      final hueRange = maxHue - minHue;
      final hueDegrees = minHue + (hash.abs() % hueRange.toInt());
      hue = hueDegrees / 360.0; // Convert to 0.0 to 1.0
    }

    final rgb = _hslToRgb(hue, saturation, lightness);

    final pen = AnsiPen()..rgb(r: rgb.$1, g: rgb.$2, b: rgb.$3);
    final entry = ColumnFormattedLog(
      '$message',
      classLabel: classLabel,
      pen: pen,
      exception: e,
      stackTrace: stack,
      logLevel: level,
    );
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
