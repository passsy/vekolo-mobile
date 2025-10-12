import 'package:context_plus/context_plus.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:vekolo/config/api_config.dart';

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final form = FormGroup({
    'email': FormControl<String>(validators: [Validators.required, Validators.email]),
    'name': FormControl<String>(),
    'sex': FormControl<String>(value: 'm'),
    'weight': FormControl<int>(),
    'ftp': FormControl<int>(),
    'code': FormControl<String>(),
  });

  bool _isLoading = false;
  bool _codeSent = false;
  String? _errorMessage;

  Future<void> _requestCode() async {
    if (!form.control('email').valid) {
      form.control('email').markAsTouched();
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
      setState(() {
        _errorMessage = 'Failed to send code: $e';
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
      await authService.saveTokens(
        accessToken: response.accessToken,
        refreshToken: response.refreshToken,
        user: response.user,
      );

      if (!mounted) return;

      // Navigate to home
      context.go('/');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Welcome, ${response.user.name}!')));
    } catch (e, stackTrace) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Invalid or expired code';
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
                ReactiveDropdownField<String>(
                  formControlName: 'sex',
                  decoration: const InputDecoration(
                    labelText: 'Gender',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.wc),
                  ),
                  readOnly: _codeSent || _isLoading,
                  items: const [
                    DropdownMenuItem(value: 'm', child: Text('Male')),
                    DropdownMenuItem(value: 'f', child: Text('Female')),
                    DropdownMenuItem(value: 'd', child: Text('Diverse')),
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
