import 'package:context_plus/context_plus.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:vekolo/config/api_config.dart';
import 'package:vekolo/utils/dio_error_handler.dart';

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final form = FormGroup({
    'email': FormControl<String>(validators: [Validators.required, Validators.email]),
    'name': FormControl<String>(),
    'sex': FormControl<String>(validators: [Validators.required]),
    'weight': FormControl<int>(),
    'ftp': FormControl<int>(),
    'code': FormControl<String>(),
  });

  bool _isLoading = false;
  bool _codeSent = false;
  String? _errorMessage;

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
      final response = await client.requestSignupCode(
        email: form.control('email').value as String,
        name: form.control('name').value as String?,
        sex: form.control('sex').value as String?,
        weight: form.control('weight').value as int?,
        ftp: form.control('ftp').value as int?,
      );

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

      final errorMessage = extractDioErrorMessage(
        e as Exception,
        fallbackMessage: 'Could not create account',
        customMessage: (e) {
          if (e.response?.statusCode == 409) {
            return 'Error (409): An account with this email already exists';
          }
          return '';
        },
      );

      setState(() {
        _errorMessage = errorMessage;
        _isLoading = false;
      });
      debugPrint('Signup error: $e');
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
      await authService.saveTokens(accessToken: response.accessToken, refreshToken: response.refreshToken);

      if (!mounted) return;

      // Navigate to home
      context.go('/');

      final user = response.accessToken.parseUser();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Welcome, ${user.name}!')));
    } catch (e, stackTrace) {
      if (!mounted) return;

      final errorMessage = extractDioErrorMessage(
        e as Exception,
        fallbackMessage: 'Invalid or expired code',
        customMessage: (e) {
          final statusCode = e.response?.statusCode;
          if (statusCode == 401) return 'Error ($statusCode): Invalid or expired code';
          if (statusCode == 400) return 'Error ($statusCode): Invalid verification code format';
          return '';
        },
      );

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
      appBar: AppBar(title: const Text('Sign Up'), backgroundColor: Theme.of(context).colorScheme.inversePrimary),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: ReactiveForm(
            formGroup: form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.person_add, size: 80, color: Colors.blue),
                const SizedBox(height: 32),
                const Text(
                  'Create Account',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                ReactiveTextField<String>(
                  formControlName: 'email',
                  decoration: const InputDecoration(
                    labelText: 'Email *',
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
                const SizedBox(height: 16),
                ReactiveTextField<String>(
                  formControlName: 'name',
                  decoration: const InputDecoration(
                    labelText: 'Name (optional)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person),
                  ),
                  readOnly: _codeSent || _isLoading,
                ),
                const SizedBox(height: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Gender *', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 8),
                    ReactiveValueListenableBuilder<String>(
                      formControlName: 'sex',
                      builder: (context, control, child) {
                        final hasError = control.invalid && control.touched;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: (_codeSent || _isLoading) ? null : () => control.value = 'm',
                                    icon: Icon(control.value == 'm' ? Icons.check_circle : Icons.circle_outlined),
                                    label: const Text('Male'),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      backgroundColor: control.value == 'm' ? Colors.blue.withValues(alpha: 0.1) : null,
                                      side: BorderSide(
                                        color: hasError
                                            ? Colors.red
                                            : (control.value == 'm' ? Colors.blue : Colors.grey),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: (_codeSent || _isLoading) ? null : () => control.value = 'f',
                                    icon: Icon(control.value == 'f' ? Icons.check_circle : Icons.circle_outlined),
                                    label: const Text('Female'),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      backgroundColor: control.value == 'f' ? Colors.pink.withValues(alpha: 0.1) : null,
                                      side: BorderSide(
                                        color: hasError
                                            ? Colors.red
                                            : (control.value == 'f' ? Colors.pink : Colors.grey),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: (_codeSent || _isLoading) ? null : () => control.value = 'd',
                                    icon: Icon(control.value == 'd' ? Icons.check_circle : Icons.circle_outlined),
                                    label: const Text('Diverse'),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      backgroundColor: control.value == 'd'
                                          ? Colors.purple.withValues(alpha: 0.1)
                                          : null,
                                      side: BorderSide(
                                        color: hasError
                                            ? Colors.red
                                            : (control.value == 'd' ? Colors.purple : Colors.grey),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (hasError)
                              Padding(
                                padding: const EdgeInsets.only(top: 8, left: 12),
                                child: Text(
                                  'Please select your gender',
                                  style: TextStyle(color: Colors.red[700], fontSize: 12),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ReactiveTextField<int>(
                        formControlName: 'weight',
                        decoration: const InputDecoration(
                          labelText: 'Weight (kg)',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.monitor_weight),
                        ),
                        keyboardType: TextInputType.number,
                        readOnly: _codeSent || _isLoading,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ReactiveTextField<int>(
                        formControlName: 'ftp',
                        decoration: const InputDecoration(
                          labelText: 'FTP (watts)',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.bolt),
                        ),
                        keyboardType: TextInputType.number,
                        readOnly: _codeSent || _isLoading,
                      ),
                    ),
                  ],
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
                  onPressed: () => context.push('/login'),
                  child: const Text('Already have an account? Login'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
