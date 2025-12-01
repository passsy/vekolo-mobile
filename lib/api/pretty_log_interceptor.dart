import 'dart:convert';

import 'package:chirp/chirp.dart';
import 'package:dio/dio.dart';
import 'package:nanoid2/nanoid2.dart';

/// Defines when the interceptor should log requests and responses
enum LogMode {
  /// Log all requests and responses
  all,

  /// Only log requests and responses that fail validateStatus (unexpected responses)
  unexpectedResponses,
}

/// A custom Dio interceptor that logs requests and responses as curl commands
class PrettyLogInterceptor extends Interceptor {
  final LogMode logMode;

  PrettyLogInterceptor({this.logMode = LogMode.all});

  static final logger = ChirpLogger(name: 'dio');

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final traceId = nanoid(length: 8, alphabet: Alphabet.noDoppelganger);
    options.extra['trace-id'] = traceId;
    options.extra['start-time'] = DateTime.now();
    if (logMode == LogMode.all) {
      // Minimal single-line log for request (no body, no headers)
      logger.info('[$traceId] → ${options.method} ${options.uri}');
    }
    super.onRequest(options, handler);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (logMode == LogMode.all) {
      final buffer = StringBuffer();
      final traceId = response.requestOptions.extra['trace-id'] as String?;
      final duration = _calculateDuration(response.requestOptions);
      buffer.writeln(
        '[$traceId] ← ${response.statusCode} ${response.statusMessage ?? ''} '
        '${response.requestOptions.method} ${response.requestOptions.uri} (${duration}ms)',
      );
      buffer.writeln();
      buffer.writeln(_buildCurl(response.requestOptions));
      buffer.writeln();
      buffer.writeln('Response Headers:');
      buffer.writeln(_formatHeaders(response.headers.map));
      if (response.data != null) {
        buffer.writeln();
        buffer.writeln('Response Body:');
        try {
          buffer.writeln(_prettyJson(response.data));
        } catch (e, stackTrace) {
          buffer.writeln('${response.data}');
          logger.warning('Failed to encode response data', error: e, stackTrace: stackTrace);
        }
      }
      logger.info(buffer.toString());
    }
    super.onResponse(response, handler);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final shouldLog = logMode == LogMode.all || err.type == DioExceptionType.badResponse;

    if (shouldLog) {
      final buffer = StringBuffer();
      final traceId = err.requestOptions.extra['trace-id'] as String?;
      final duration = _calculateDuration(err.requestOptions);
      final statusCode = err.response?.statusCode;
      buffer.writeln(
        '[$traceId] ← ERROR ${statusCode ?? ''} ${err.requestOptions.method} ${err.requestOptions.uri} (${duration}ms)',
      );
      buffer.writeln('${err.type}: ${err.message ?? ''}');
      buffer.writeln();
      buffer.writeln(_buildCurl(err.requestOptions));

      if (err.response != null) {
        buffer.writeln();
        buffer.writeln('Response Headers:');
        buffer.writeln(_formatHeaders(err.response!.headers.map));
      }
      if (err.response?.data != null) {
        buffer.writeln();
        buffer.writeln('Response Body:');
        try {
          buffer.writeln(_prettyJson(err.response!.data));
        } catch (e, stackTrace) {
          buffer.writeln('${err.response!.data}');
          logger.warning('Failed to encode error response data', error: e, stackTrace: stackTrace);
        }
      }
      logger.warning(buffer.toString(), error: err, stackTrace: err.stackTrace);
    }

    super.onError(err, handler);
  }

  int _calculateDuration(RequestOptions options) {
    final startTime = options.extra['start-time'] as DateTime?;
    if (startTime == null) return -1;
    return DateTime.now().difference(startTime).inMilliseconds;
  }

  String _formatHeaders(Map<String, List<String>> headers) {
    final buffer = StringBuffer();
    for (final entry in headers.entries) {
      final value = entry.value.length == 1 ? entry.value.first : entry.value.toString();
      buffer.writeln('  ${entry.key}: $value');
    }
    return buffer.toString().trimRight();
  }

  String _buildCurl(RequestOptions options) {
    final parts = <String>['curl'];

    // Method (skip for GET as it's the default)
    if (options.method != 'GET') {
      parts.add('-X ${options.method}');
    }

    // Headers
    for (final entry in options.headers.entries) {
      final value = _shellEscape('${entry.value}');
      parts.add("-H '${entry.key}: $value'");
    }

    // Body
    if (options.data != null) {
      try {
        final json = jsonEncode(options.data);
        parts.add("-d '${_shellEscape(json)}'");
      } catch (e, stackTrace) {
        parts.add("-d '${_shellEscape('${options.data}')}'");
        logger.warning('Failed to encode request data for curl', error: e, stackTrace: stackTrace);
      }
    }

    // URL (always last)
    parts.add("'${options.uri}'");

    return parts.join(' \\\n  ');
  }
}

String _shellEscape(String value) {
  return value.replaceAll("'", r"'\''");
}

String _prettyJson(Object? data) {
  const encoder = JsonEncoder.withIndent('  ');
  return encoder.convert(_truncateForLog(data));
}

/// Recursively truncates data for logging:
/// - Strings longer than 256 chars are trimmed
/// - Lists longer than 10 elements are trimmed
Object? _truncateForLog(Object? value) {
  const maxStringLength = 256;
  const maxListLength = 10;

  if (value == null) return null;

  if (value is String) {
    if (value.length > maxStringLength) {
      return '${value.substring(0, maxStringLength)}... (${value.length} chars)';
    }
    return value;
  }

  if (value is List) {
    final truncatedList = value.take(maxListLength).map(_truncateForLog).toList();
    if (value.length > maxListLength) {
      truncatedList.add('... (${value.length - maxListLength} more items)');
    }
    return truncatedList;
  }

  if (value is Map) {
    return value.map((key, v) => MapEntry(key, _truncateForLog(v)));
  }

  return value;
}
