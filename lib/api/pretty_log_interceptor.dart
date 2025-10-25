import 'dart:convert';
import 'dart:developer' as developer;
import 'package:dio/dio.dart';

/// Defines when the interceptor should log requests and responses
enum LogMode {
  /// Log all requests and responses
  all,

  /// Only log requests and responses that fail validateStatus (unexpected responses)
  unexpectedResponses,
}

/// A custom Dio interceptor that logs requests and responses with pretty-printed JSON
class PrettyLogInterceptor extends Interceptor {
  static const String _name = 'VekoloApiClient';
  static const JsonEncoder _prettyEncoder = JsonEncoder.withIndent('  ');

  final LogMode logMode;

  const PrettyLogInterceptor({this.logMode = LogMode.all});

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (logMode == LogMode.all) {
      final buffer = StringBuffer();
      buffer.writeln('┌─────────────────────────────────────────');
      buffer.writeln('│ *** REQUEST ***');
      buffer.writeln('├─────────────────────────────────────────');
      buffer.writeln('│ ${options.method} ${options.uri}');

      if (options.headers.isNotEmpty) {
        buffer.writeln('│ Headers:');
        for (final entry in options.headers.entries) {
          buffer.writeln('│   ${entry.key}: ${entry.value}');
        }
      }

      if (options.data != null) {
        buffer.writeln('│ Body:');
        try {
          final prettyJson = _prettyEncoder.convert(options.data);
          for (final line in prettyJson.split('\n')) {
            buffer.writeln('│   $line');
          }
        } catch (e) {
          buffer.writeln('│   ${options.data}');
        }
      }

      buffer.writeln('└─────────────────────────────────────────');
      developer.log(buffer.toString(), name: _name);
    }

    super.onRequest(options, handler);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (logMode == LogMode.all) {
      final buffer = StringBuffer();
      buffer.writeln('┌─────────────────────────────────────────');
      buffer.writeln('│ *** RESPONSE ***');
      buffer.writeln('├─────────────────────────────────────────');
      buffer.writeln('│ ${response.requestOptions.method} ${response.requestOptions.uri}');
      buffer.writeln('│ Status: ${response.statusCode} ${response.statusMessage ?? ''}');

      if (response.headers.map.isNotEmpty) {
        buffer.writeln('│ Headers:');
        for (final entry in response.headers.map.entries) {
          buffer.writeln('│   ${entry.key}: ${entry.value.join(', ')}');
        }
      }

      if (response.data != null) {
        buffer.writeln('│ Body:');
        try {
          final prettyJson = _prettyEncoder.convert(response.data);
          for (final line in prettyJson.split('\n')) {
            buffer.writeln('│   $line');
          }
        } catch (e) {
          buffer.writeln('│   ${response.data}');
        }
      }

      buffer.writeln('└─────────────────────────────────────────');
      developer.log(buffer.toString(), name: _name);
    }

    super.onResponse(response, handler);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    // In unexpectedResponses mode, only log badResponse errors (validateStatus failures)
    // In all mode, log all errors
    final shouldLog = logMode == LogMode.all || err.type == DioExceptionType.badResponse;

    if (shouldLog) {
      final buffer = StringBuffer();
      buffer.writeln('\n');
      buffer.writeln('┌───────────────────────────────────────────────────────────');
      final statusCode = err.response?.statusCode;
      buffer.writeln(
        '│ ERROR [${statusCode != null ? ' $statusCode'.trim() : ''}] ${err.requestOptions.method} ${err.requestOptions.path} ',
      );
      buffer.writeln('├───────────────────────────────────────────────────────────');

      // In unexpectedResponses mode, include full request details since we didn't log the request separately
      if (logMode == LogMode.unexpectedResponses) {
        if (err.requestOptions.headers.isNotEmpty) {
          buffer.writeln('│ Request Headers:');
          for (final entry in err.requestOptions.headers.entries) {
            buffer.writeln('│ ${entry.key}: ${entry.value}');
          }
        }

        if (err.requestOptions.data != null) {
          buffer.writeln('│ ');
          buffer.writeln('│ Request Body:');
          try {
            final prettyJson = _prettyEncoder.convert(err.requestOptions.data);
            for (final line in prettyJson.split('\n')) {
              buffer.writeln('│ $line');
            }
          } catch (e) {
            buffer.writeln('│ ${err.requestOptions.data}');
          }
        }
      }

      buffer.writeln('├───────────────────────────────────────────────────────────');
      // Handle multiline error messages
      final message = err.message ?? '';
      final messageLines = message.split('\n');
      buffer.writeln('│ ${err.type}: ${messageLines.first}');
      for (final line in messageLines.skip(1)) {
        buffer.writeln('│   $line');
      }

      if (err.response != null) {
        buffer.writeln('├───────────────────────────────────────────────────────────');
        buffer.writeln('│ Response status code: ${err.response?.statusCode}');
        buffer.writeln('├───────────────────────────────────────────────────────────');

        if (err.response!.headers.map.isNotEmpty) {
          buffer.writeln('│ Response Headers:');
          for (final entry in err.response!.headers.map.entries) {
            buffer.writeln('│ ${entry.key}: ${entry.value.join(', ')}');
          }
        }

        if (err.response?.data != null) {
          buffer.writeln('│ ');
          buffer.writeln('│ Response Body:');
          try {
            final prettyJson = _prettyEncoder.convert(err.response!.data);
            for (final line in prettyJson.split('\n')) {
              buffer.writeln('│ $line');
            }
          } catch (e) {
            buffer.writeln('│ ${err.response!.data}');
          }
        }
      }

      buffer.writeln('└───────────────────────────────────────────────────────────');
      developer.log(buffer.toString(), name: _name);
    }

    super.onError(err, handler);
  }
}
