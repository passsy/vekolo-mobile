import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Vekolo'), backgroundColor: Theme.of(context).colorScheme.inversePrimary),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.bluetooth, size: 80, color: Colors.blue),
            const SizedBox(height: 32),
            const Text('Connect to your smart trainer', style: TextStyle(fontSize: 20)),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () => context.go('/scanner'),
              icon: const Icon(Icons.search),
              label: const Text('Scan for Trainer'),
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16)),
            ),
          ],
        ),
      ),
    );
  }
}
