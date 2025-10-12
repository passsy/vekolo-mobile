import 'package:context_plus/context_plus.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:state_beacon/state_beacon.dart';
import 'package:vekolo/config/api_config.dart';
import 'package:vekolo/widgets/user_avatar.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = authServiceRef.of(context);
    final user = authService.currentUser.watch(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vekolo'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.devices),
            onPressed: () => context.push('/devices'),
            tooltip: 'Manage Devices',
          ),
          if (user != null)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: IconButton(
                icon: UserAvatar(
                  user: user,
                  backgroundColor: Colors.white,
                  foregroundColor: Theme.of(context).colorScheme.primary,
                ),
                onPressed: () => context.push('/profile'),
                tooltip: 'Profile',
              ),
            ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.directions_bike, size: 80, color: Colors.blue),
              const SizedBox(height: 32),
              if (user != null) ...[
                Text('Welcome, ${user.name}!', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
              ],
              const Text('Connect to your smart trainer', style: TextStyle(fontSize: 20)),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: () => context.push('/scanner'),
                icon: const Icon(Icons.search),
                label: const Text('Scan for Trainer'),
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16)),
              ),
              if (user == null) ...[
                const SizedBox(height: 48),
                const Divider(),
                const SizedBox(height: 16),
                const Text('Get started with Vekolo', style: TextStyle(fontSize: 18)),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlinedButton(onPressed: () => context.push('/login'), child: const Text('Login')),
                    const SizedBox(width: 16),
                    ElevatedButton(onPressed: () => context.push('/signup'), child: const Text('Sign Up')),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
