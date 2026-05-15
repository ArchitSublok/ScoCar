import 'package:flutter/material.dart';
import 'guard_dashboard.dart';

class LoginScreen extends StatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  String selectedRole = 'Owner';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0, iconTheme: IconThemeData(color: Colors.blue)),
      body: Padding(
        padding: const EdgeInsets.all(25.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Welcome Back", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.blue[900])),
            Text("Please select your role to continue", style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 30),
            Row(
              children: [
                _roleCard("Owner", Icons.home_work, selectedRole == 'Owner'),
                const SizedBox(width: 20),
                _roleCard("Guard", Icons.shield, selectedRole == 'Guard'),
              ],
            ),
            const SizedBox(height: 30),
            TextField(decoration: InputDecoration(labelText: "Email/Username", border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
            const SizedBox(height: 20),
            TextField(obscureText: true, decoration: InputDecoration(labelText: "Password", border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => GuardDashboard())),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue[800], shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: Text("Login", style: TextStyle(fontSize: 18, color: Colors.white)),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _roleCard(String title, IconData icon, bool isSelected) {
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => selectedRole = title),
        child: Container(
          padding: EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isSelected ? Colors.blue[800] : Colors.white,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: Colors.blue[800]!),
            boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)],
          ),
          child: Column(
            children: [
              Icon(icon, color: isSelected ? Colors.white : Colors.blue[800], size: 40),
              const SizedBox(height: 10),
              Text(title, style: TextStyle(color: isSelected ? Colors.white : Colors.blue[800], fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }
}