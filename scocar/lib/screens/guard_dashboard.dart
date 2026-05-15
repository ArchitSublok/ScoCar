import 'package:flutter/material.dart';

class GuardDashboard extends StatelessWidget {
  const GuardDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Guard Dashboard')),
      body: const Center(child: Text('List of Recent Scans will go here')),
      // Inside guard_dashboard.dart
floatingActionButton: FloatingActionButton(
  onPressed: () {
    // Navigate to the add vehicle screen
    Navigator.pushNamed(context, '/add-vehicle');
  },
  child: const Icon(Icons.add),
),
    );
  }
}