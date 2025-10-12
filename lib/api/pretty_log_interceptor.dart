import 'dart:convert';
import 'dart:developer' as developer;
import 'package:dio/dio.dart';

/// A custom Dio interceptor that logs requests and responses with pretty-printed JSON
class PrettyLogInterceptor extends Interceptor {
  static const String _name = 'VekoloApiClient';
  static const JsonEncoder _prettyEncoder = JsonEncoder.withIndent('  ');

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final buffer = StringBuffer();
    buffer.writeln('┌─────────────────────────────────────────');
    buffer.writeln('│ *** REQUEST ***');
    buffer.writeln('├─────────────────────────────────────────');
    buffer.writeln('│ ${options.method} ${options.uri}');

    if (options.headers.isNotEmpty) {
      buffer.writeln('│ Headers:');
      options.headers.forEach((key, value) {
        buffer.writeln('│   $key: $value');
      });
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

    super.onRequest(options, handler);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final buffer = StringBuffer();
    buffer.writeln('┌─────────────────────────────────────────');
    buffer.writeln('│ *** RESPONSE ***');
    buffer.writeln('├─────────────────────────────────────────');
    buffer.writeln('│ ${response.requestOptions.method} ${response.requestOptions.uri}');
    buffer.writeln('│ Status: ${response.statusCode} ${response.statusMessage ?? ''}');

    if (response.headers.map.isNotEmpty) {
      buffer.writeln('│ Headers:');
      response.headers.map.forEach((key, value) {
        buffer.writeln('│   $key: ${value.join(', ')}');
      });
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

    super.onResponse(response, handler);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final buffer = StringBuffer();
    buffer.writeln('┌─────────────────────────────────────────');
    buffer.writeln('│ *** ERROR ***');
    buffer.writeln('├─────────────────────────────────────────');
    buffer.writeln('│ ${err.requestOptions.method} ${err.requestOptions.uri}');
    buffer.writeln('│ ${err.type}: ${err.message}');

    if (err.response != null) {
      buffer.writeln('│ Status: ${err.response?.statusCode}');
      if (err.response?.data != null) {
        buffer.writeln('│ Response:');
        try {
          final prettyJson = _prettyEncoder.convert(err.response!.data);
          for (final line in prettyJson.split('\n')) {
            buffer.writeln('│   $line');
          }
        } catch (e) {
          buffer.writeln('│   ${err.response!.data}');
        }
      }
    }

    buffer.writeln('└─────────────────────────────────────────');
    developer.log(buffer.toString(), name: _name);

    super.onError(err, handler);
  }
}
