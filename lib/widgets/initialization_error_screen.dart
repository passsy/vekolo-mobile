import 'package:flutter/material.dart';

/// Shown when app initialization fails.
class InitializationErrorScreen extends StatelessWidget {
  const InitializationErrorScreen({
    super.key,
    required this.error,
    this.stackTrace,
    this.onRetry,
  });

  final String error;
  final String? stackTrace;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FlutterLogo(size: 100), // TODO: Replace with Vekolo logo
              const SizedBox(height: 24),
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 24),
              const Text(
                'Initialization Failed',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red[200]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      error,
                      style: TextStyle(color: Colors.red[900], fontSize: 13),
                      textAlign: TextAlign.left,
                    ),
                    if (stackTrace != null) ...[
                      const SizedBox(height: 12),
                      const Divider(color: Colors.red, height: 1),
                      const SizedBox(height: 8),
                      const Text(
                        'Stack Trace:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        stackTrace!,
                        style: TextStyle(color: Colors.red[700], fontSize: 11),
                        textAlign: TextAlign.left,
                      ),
                    ],
                  ],
                ),
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

