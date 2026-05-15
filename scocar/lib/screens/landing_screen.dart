import 'package:flutter/material.dart';

class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Standard professional dark theme
      backgroundColor: const Color(0xFF121212), 
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text("SCOCAR OS", style: TextStyle(letterSpacing: 1.2, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_pin, color: Colors.cyanAccent),
            onPressed: () => Navigator.pushNamed(context, '/login'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Main Menu",
              style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 5),
            Text(
              "Region: asia-south2 (Delhi)", // Based on your Firestore setup
              style: TextStyle(color: Colors.grey[500], fontSize: 14),
            ),
            const SizedBox(height: 30),

            // Standard Vertical Menu Buttons
            _buildNormalButton(
              context,
              title: "Vehicle Registry",
              subtitle: "Add or manage vehicle entries",
              icon: Icons.directions_car,
              color: Colors.blueAccent,
              // FIXED: Matching the hyphenated route in your main.dart
              route: '/add-vehicle', 
            ),
            
            _buildNormalButton(
              context,
              title: "Security Alerts",
              subtitle: "View active system warnings",
              icon: Icons.notifications_active,
              color: Colors.redAccent,
              route: '/alerts', // Ensure this exists in main.dart
            ),

            _buildNormalButton(
              context,
              title: "Guard Dashboard",
              subtitle: "Operator logs and status",
              icon: Icons.dashboard_customize,
              color: Colors.greenAccent,
              route: '/dashboard', // Matches your main.dart
            ),
            
            const SizedBox(height: 40),
            
            // Simple Status Card
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.cloud_done, color: Colors.cyanAccent, size: 20),
                  SizedBox(width: 10),
                  Text("System Online", style: TextStyle(color: Colors.white70)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNormalButton(BuildContext context, {
    required String title, 
    required String subtitle, 
    required IconData icon, 
    required Color color,
    required String route
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: ListTile(
        onTap: () => Navigator.pushNamed(context, route),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        tileColor: Colors.white.withOpacity(0.05),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        leading: Icon(icon, color: color, size: 30),
        title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 12)),
        trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white24, size: 16),
      ),
    );
  }
}