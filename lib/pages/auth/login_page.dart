import 'package:context_plus/context_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:vekolo/config/api_config.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final form = FormGroup({
    'email': FormControl<String>(
      validators: [Validators.required, Validators.email],
      value: kDebugMode ? "pascal@phntm.xyz" : '',
    ),
    'code': FormControl<String>(),
  });

  bool _isLoading = false;
  bool _codeSent = false;
  String? _errorMessage;

  /// Extracts a user-friendly error message from a DioException
  String _extractErrorMessage(DioException error) {
    final statusCode = error.response?.statusCode;

    // Try to extract error message from API response
    if (error.response?.data != null && error.response!.data is Map) {
      final data = error.response!.data as Map<String, dynamic>;
      if (data['message'] != null) {
        final message = data['message'] as String;
        return 'Error ($statusCode): $message';
      }
    }

    // Fallback to generic error messages based on error type
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Connection timeout. Please check your internet connection.';
      case DioExceptionType.connectionError:
        return 'Unable to connect to the server. Please check your internet connection.';
      case DioExceptionType.badResponse:
        if (statusCode == 404) {
          return 'Error ($statusCode): Resource not found. Please try again later.';
        } else if (statusCode == 500) {
          return 'Error ($statusCode): Server error. Please try again later.';
        }
        return 'Error ($statusCode): An error occurred. Please try again.';
      case DioExceptionType.cancel:
        return 'Request cancelled.';
      case DioExceptionType.badCertificate:
        return 'Security error. Please check your connection.';
      case DioExceptionType.unknown:
      default:
        return 'An unexpected error occurred. Please try again.';
    }
  }

  Future<void> _requestCode() async {
    if (!form.valid) {
      form.markAllAsTouched();
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final client = apiClientRef.of(context);
      final response = await client.requestLoginCode(email: form.control('email').value as String);

      if (!mounted) return;

      if (response.success) {
        setState(() {
          _codeSent = true;
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(response.message)));
      } else {
        setState(() {
          _errorMessage = response.message;
          _isLoading = false;
        });
      }
    } catch (e, stackTrace) {
      if (!mounted) return;

      String errorMessage = 'Failed to send code';
      if (e is DioException) {
        errorMessage = _extractErrorMessage(e);
      }

      setState(() {
        _errorMessage = errorMessage;
        _isLoading = false;
      });
      debugPrint('Login error: $e');
      debugPrint('$stackTrace');
    }
  }

  Future<void> _verifyCode() async {
    final codeValue = form.control('code').value as String?;
    if (codeValue == null || codeValue.isEmpty) {
      setState(() => _errorMessage = 'Please enter the code');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final client = apiClientRef.of(context);
      final response = await client.redeemCode(
        email: form.control('email').value as String,
        code: codeValue,
        deviceInfo: 'Flutter App',
      );

      if (!mounted) return;

      // Store tokens
      final authService = authServiceRef.of(context);
      await authService.saveTokens(
        accessToken: response.accessToken,
        refreshToken: response.refreshToken,
        user: response.user,
      );

      if (!mounted) return;

      // Navigate to home
      context.go('/');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Welcome back, ${response.user.name}!')));
    } catch (e, stackTrace) {
      if (!mounted) return;

      String errorMessage = 'Invalid or expired code';
      if (e is DioException) {
        errorMessage = _extractErrorMessage(e);
      }

      setState(() {
        _errorMessage = errorMessage;
        _isLoading = false;
      });
      debugPrint('Code verification error: $e');
      debugPrint('$stackTrace');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login'), backgroundColor: Theme.of(context).colorScheme.inversePrimary),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: ReactiveForm(
            formGroup: form,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.login, size: 80, color: Colors.blue),
                const SizedBox(height: 32),
                const Text(
                  'Login to Vekolo',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                ReactiveTextField<String>(
                  formControlName: 'email',
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.email),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  readOnly: _codeSent || _isLoading,
                  validationMessages: {
                    ValidationMessage.required: (_) => 'Please enter your email',
                    ValidationMessage.email: (_) => 'Please enter a valid email',
                  },
                ),
                if (_codeSent) ...[
                  const SizedBox(height: 16),
                  ReactiveTextField<String>(
                    formControlName: 'code',
                    decoration: const InputDecoration(
                      labelText: 'Verification Code',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.lock),
                      helperText: 'Enter the 6-digit code from your email',
                    ),
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    readOnly: _isLoading,
                  ),
                ],
                if (_errorMessage != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 24),
                if (!_codeSent)
                  ElevatedButton(
                    onPressed: _isLoading ? null : _requestCode,
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                    child: _isLoading
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Send Code'),
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ElevatedButton(
                        onPressed: _isLoading ? null : _verifyCode,
                        style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                        child: _isLoading
                            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Verify Code'),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _isLoading
                            ? null
                            : () => setState(() {
                                _codeSent = false;
                                form.control('code').reset();
                                _errorMessage = null;
                              }),
                        child: const Text('Resend Code'),
                      ),
                    ],
                  ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => context.push('/signup'),
                  child: const Text("Don't have an account? Sign up"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
