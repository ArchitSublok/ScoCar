import 'package:flutter/material.dart';

class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // The AppBar gives the page a header
      appBar: AppBar(
        title: const Text('ScoCar Scanner'),
        centerTitle: true,
        backgroundColor: Colors.deepPurple,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.directions_car_filled,
              size: 100,
              color: Colors.deepPurple,
            ),
            const SizedBox(height: 20),
            const Text(
              'Welcome to ScoCar',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            const Text('Identify vehicles in seconds'),
            const SizedBox(height: 40),
            ElevatedButton.icon(
  onPressed: () {
    // This tells Flutter to look at the 'map' in main.dart and find '/login'
    Navigator.pushNamed(context, '/login'); 
  },
  icon: const Icon(Icons.camera_alt),
  label: const Text('START SCANNING'),
  style: ElevatedButton.styleFrom(
    padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
  ),
),
          ],
        ),
      ),
    );
  }
}