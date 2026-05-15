import 'dart:ui';
import 'package:flutter/material.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isVisible = false;

  @override
  void initState() {
    super.initState();
    // Trigger the entrance animation as soon as the page loads
    Future.delayed(const Duration(milliseconds: 300), () {
      setState(() {
        _isVisible = true;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Cyberpunk Dark Gradient Background
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF0D0D1B), Color(0xFF1B1B2F)],
              ),
            ),
          ),
          
          // Animated Ambient "Glow"
          AnimatedPositioned(
            duration: const Duration(seconds: 2),
            top: _isVisible ? -50 : -150,
            right: _isVisible ? -50 : -150,
            child: Container(
              width: 350,
              height: 350,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.cyanAccent.withOpacity(0.15),
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
                child: Container(),
              ),
            ),
          ),

          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(30),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 800),
                  opacity: _isVisible ? 1.0 : 0.0,
                  child: Column(
                    children: [
                      // Animated Logo Header
                      _buildAnimatedHeader(),
                      const SizedBox(height: 50),

                      // Glassmorphic Form Fields
                      _buildGlassField(label: "Operator ID", icon: Icons.badge_outlined),
                      const SizedBox(height: 20),
                      _buildGlassField(label: "Access Code", icon: Icons.lock_open_rounded, isPassword: true),
                      
                      const SizedBox(height: 40),

                      // High-Glow Action Button
                      _buildNeonButton(context),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnimatedHeader() {
    return Column(
      children: [
        TweenAnimationBuilder(
          tween: Tween<double>(begin: 0, end: 1),
          duration: const Duration(seconds: 1),
          builder: (context, double value, child) {
            return Transform.scale(
              scale: value,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.cyanAccent.withOpacity(0.5), width: 2),
                  boxShadow: [
                    BoxShadow(color: Colors.cyanAccent.withOpacity(0.2 * value), blurRadius: 20),
                  ],
                ),
                child: const Icon(Icons.qr_code_scanner_rounded, size: 60, color: Colors.cyanAccent),
              ),
            );
          },
        ),
        const SizedBox(height: 20),
        const Text(
          "SCOCAR OS",
          style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: 4),
        ),
      ],
    );
  }

  Widget _buildGlassField({required String label, required IconData icon, bool isPassword = false}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
            borderRadius: BorderRadius.circular(20),
          ),
          child: TextField(
            obscureText: isPassword,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              prefixIcon: Icon(icon, color: Colors.cyanAccent),
              labelText: label,
              labelStyle: const TextStyle(color: Colors.white60),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNeonButton(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.pushReplacementNamed(context, '/dashboard'),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(colors: [Colors.cyanAccent, Colors.blueAccent]),
          boxShadow: [
            BoxShadow(color: Colors.cyanAccent.withOpacity(0.4), blurRadius: 15, offset: const Offset(0, 8)),
          ],
        ),
        child: const Center(
          child: Text(
            "INITIALIZE SYSTEM",
            style: TextStyle(color: Color(0xFF0D0D1B), fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 2),
          ),
        ),
      ),
    );
  }
}