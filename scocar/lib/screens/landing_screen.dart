import 'package:flutter/material.dart';
import 'package:animate_do/animate_do.dart';
import 'login_screen.dart';

class LandingScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FadeInDown(
                duration: Duration(milliseconds: 800),
                child: Icon(Icons.security_rounded, size: 100, color: Colors.blue[800]),
              ),
              const SizedBox(height: 20),
              FadeInUp(
                delay: Duration(milliseconds: 500),
                child: Text(
                  "SECURE GATE",
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.blue[900], letterSpacing: 2),
                ),
              ),
              FadeInUp(
                delay: Duration(milliseconds: 800),
                child: Text(
                  "Digitalizing Society Management",
                  style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                ),
              ),
              const SizedBox(height: 50),
              FadeIn(
                delay: Duration(seconds: 1),
                child: ElevatedButton(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => LoginScreen())),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[800],
                    padding: EdgeInsets.symmetric(horizontal: 50, vertical: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  ),
                  child: Text("Get Started", style: TextStyle(color: Colors.white, fontSize: 18)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}