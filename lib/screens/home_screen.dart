import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final email = AuthService().currentUser?.email ?? 'User';

    return Scaffold(
      appBar: AppBar(
        title: const Text('GigsCourt'),
        actions: [
          IconButton(
            onPressed: () async {
              await AuthService().signOut();
              if (context.mounted) {
                Navigator.pushReplacementNamed(context, '/auth');
              }
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle, size: 64, color: Color(0xFF4CAF50)),
            const SizedBox(height: 16),
            const Text(
              'Auth is working!',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Signed in as $email',
              style: const TextStyle(color: Color(0xFF6B7280)),
            ),
          ],
        ),
      ),
    );
  }
}
