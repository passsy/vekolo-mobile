import 'package:context_plus/context_plus.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:state_beacon/state_beacon.dart';
import 'package:vekolo/app/refs.dart';
import 'package:vekolo/utils/dio_error_handler.dart';
import 'package:vekolo/widgets/user_avatar.dart';

/// User profile with editable FTP and weight.
///
/// Only sends changed fields to the server on save.
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  FormGroup? _form;
  bool _isEditing = false;
  bool _isSaving = false;
  String? _errorMessage;

  // Store original values to detect changes
  int? _originalFtp;
  int? _originalWeight;

  FormGroup get form => _form!;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Initialize form only once
    if (_form == null) {
      final authService = Refs.authService.of(context);
      final user = authService.currentUser.value;

      _originalFtp = user?.ftp;
      _originalWeight = user?.weight;

      _form = FormGroup({
        'ftp': FormControl<int>(
          value: user?.ftp,
          validators: [Validators.required, Validators.min(50), Validators.max(500)],
        ),
        'weight': FormControl<int>(
          value: user?.weight,
          validators: [Validators.required, Validators.min(30), Validators.max(200)],
        ),
      });
    }
  }

  Future<void> _saveChanges() async {
    if (!form.valid) {
      form.markAllAsTouched();
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final authService = Refs.authService.of(context);
      final apiClient = Refs.apiClient.of(context);
      final messenger = ScaffoldMessenger.of(context);
      final refreshToken = await authService.getRefreshToken();
      final accessToken = await authService.getAccessToken();
      await authService.saveTokens(accessToken: accessToken!, refreshToken: refreshToken!);
      final user = authService.currentUser.value;

      if (user == null) {
        throw Exception('No user logged in');
      }

      // Get current form values
      final currentFtp = form.control('ftp').value as int?;
      final currentWeight = form.control('weight').value as int?;

      // Only send fields that have changed
      final response = await apiClient.updateProfile(
        ftp: currentFtp != _originalFtp ? currentFtp : null,
        weight: currentWeight != _originalWeight ? currentWeight : null,
      );

      if (!mounted) return;

      // Update the user in both storage and beacon
      await authService.updateUser(response.user);

      // Update original values to new values
      _originalFtp = response.user.ftp;
      _originalWeight = response.user.weight;

      setState(() {
        _isSaving = false;
        _isEditing = false;
      });

      messenger.showSnackBar(const SnackBar(content: Text('Profile updated successfully')));
    } catch (e, stackTrace) {
      if (!mounted) return;

      final errorMessage = extractDioErrorMessage(
        e as Exception,
        fallbackMessage: 'Failed to update profile',
        customMessage: (e) {
          final statusCode = e.response?.statusCode;
          if (statusCode == 401) return 'Error ($statusCode): Session expired. Please log in again.';
          if (statusCode == 403) return 'Error ($statusCode): You do not have permission to update this profile.';
          return '';
        },
      );

      setState(() {
        _errorMessage = errorMessage;
        _isSaving = false;
      });
      debugPrint('Profile update error: $e');
      debugPrint('$stackTrace');
    }
  }

  Future<void> _logout() async {
    final authService = Refs.authService.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);

    await authService.clearAuth();

    if (!mounted) return;

    router.go('/');
    messenger.showSnackBar(const SnackBar(content: Text('Logged out successfully')));
  }

  @override
  Widget build(BuildContext context) {
    final authService = Refs.authService.of(context);
    final user = authService.currentUser.watch(context);

    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Profile'), backgroundColor: Theme.of(context).colorScheme.inversePrimary),
        body: const Center(child: Text('Not logged in')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (_isEditing)
            TextButton(
              onPressed: () {
                setState(() {
                  _isEditing = false;
                  // Reset form to original values
                  form.control('ftp').value = user.ftp;
                  form.control('weight').value = user.weight;
                  _errorMessage = null;
                });
              },
              child: const Text('Cancel', style: TextStyle(color: Colors.white)),
            )
          else
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => setState(() => _isEditing = true),
              tooltip: 'Edit Profile',
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              // Avatar
              UserAvatar(user: user, radius: 60),
              const SizedBox(height: 24),
              Text(user.name, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(user.email, style: TextStyle(fontSize: 16, color: Colors.grey[600])),
              const SizedBox(height: 12),
              // Plan badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: user.plan == 'pro' ? Colors.amber.withValues(alpha: 0.2) : Colors.grey.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: user.plan == 'pro' ? Colors.amber : Colors.grey, width: 1.5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      user.plan == 'pro' ? Icons.workspace_premium : Icons.person,
                      size: 16,
                      color: user.plan == 'pro' ? Colors.amber[700] : Colors.grey[700],
                    ),
                    const SizedBox(width: 6),
                    Text(
                      user.plan.toUpperCase(),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: user.plan == 'pro' ? Colors.amber[700] : Colors.grey[700],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 36),

              // Stats Cards
              ReactiveForm(
                formGroup: form,
                child: Column(
                  children: [
                    _buildStatCard(
                      icon: Icons.bolt,
                      label: 'FTP (watts)',
                      formControlName: 'ftp',
                      color: Colors.orange,
                      readOnly: !_isEditing,
                    ),
                    const SizedBox(height: 16),
                    _buildStatCard(
                      icon: Icons.monitor_weight,
                      label: 'Weight (kg)',
                      formControlName: 'weight',
                      color: Colors.blue,
                      readOnly: !_isEditing,
                    ),
                  ],
                ),
              ),

              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              ],

              if (_isEditing) ...[
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _isSaving ? null : _saveChanges,
                  icon: _isSaving
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save),
                  label: Text(_isSaving ? 'Saving...' : 'Save Changes'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],

              const SizedBox(height: 48),
              const Divider(),
              const SizedBox(height: 16),

              // Logout Button
              ElevatedButton.icon(
                onPressed: _logout,
                icon: const Icon(Icons.logout),
                label: const Text('Logout'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String formControlName,
    required Color color,
    required bool readOnly,
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 48, color: color),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 16, color: Colors.grey[600])),
                const SizedBox(height: 8),
                if (readOnly)
                  ReactiveValueListenableBuilder<int>(
                    formControlName: formControlName,
                    builder: (context, control, child) {
                      return Text(
                        control.value?.toString() ?? '--',
                        style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: color),
                      );
                    },
                  )
                else
                  ReactiveTextField<int>(
                    formControlName: formControlName,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color),
                    validationMessages: {
                      ValidationMessage.required: (_) => 'Required',
                      ValidationMessage.min: (_) => 'Too low',
                      ValidationMessage.max: (_) => 'Too high',
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
