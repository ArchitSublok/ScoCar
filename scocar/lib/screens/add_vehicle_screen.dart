import 'dart:ui';
import 'package:flutter/material.dart';

class AddVehicleScreen extends StatefulWidget {
  const AddVehicleScreen({super.key});

  @override
  State<AddVehicleScreen> createState() => _AddVehicleScreenState();
}

class _AddVehicleScreenState extends State<AddVehicleScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1B),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          'ENTRY LOG',
          style: TextStyle(letterSpacing: 3, fontWeight: FontWeight.w900, fontSize: 14),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.cyanAccent,
      ),
      body: Stack(
        children: [
          // Background Aesthetic: Kinetic Orbs
          Positioned(
            top: -50,
            left: -50,
            child: _buildGlowOrb(Colors.blueAccent.withOpacity(0.1), 300),
          ),
          Positioned(
            bottom: 100,
            right: -100,
            child: _buildGlowOrb(Colors.cyanAccent.withOpacity(0.05), 400),
          ),

          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeaderSection(),
                  const SizedBox(height: 40),

                  // The Form "Glass" Container
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.03),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: Colors.white.withOpacity(0.05)),
                    ),
                    child: Column(
                      children: [
                        _buildAnimatedInput(
                          label: "LICENSE PLATE",
                          hint: "IND  MH 12 AB 1234",
                          icon: Icons.qr_code_scanner,
                          delay: 100,
                        ),
                        const SizedBox(height: 25),
                        _buildAnimatedInput(
                          label: "VEHICLE MODEL",
                          hint: "e.g. White Mahindra Thar",
                          icon: Icons.directions_car_filled,
                          delay: 300,
                        ),
                        const SizedBox(height: 25),
                        _buildAnimatedInput(
                          label: "OWNER/VISITOR NAME",
                          hint: "Enter Full Name",
                          icon: Icons.person_add_alt_1,
                          delay: 500,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 50),
                  _buildNeonSubmitButton(context),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlowOrb(Color color, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 70, sigmaY: 70),
        child: Container(),
      ),
    );
  }

  Widget _buildHeaderSection() {
    return TweenAnimationBuilder(
      duration: const Duration(milliseconds: 800),
      tween: Tween<double>(begin: 0, end: 1),
      builder: (context, double value, child) {
        return Opacity(
          opacity: value,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 4,
                    height: 24,
                    decoration: BoxDecoration(
                      color: Colors.cyanAccent,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [BoxShadow(color: Colors.cyanAccent.withOpacity(0.5), blurRadius: 10)],
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    "SECURITY CLEARANCE",
                    style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, letterSpacing: 2, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 15),
              const Text(
                "Register New Vehicle",
                style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAnimatedInput({required String label, required String hint, required IconData icon, required int delay}) {
    return TweenAnimationBuilder(
      duration: Duration(milliseconds: 600 + delay),
      tween: Tween<double>(begin: 0, end: 1),
      builder: (context, double value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(30 * (1 - value), 0), // Slides in from the side
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 8),
                  child: Text(
                    label,
                    style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.5),
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                  ),
                  child: TextField(
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                    decoration: InputDecoration(
                      hintText: hint,
                      hintStyle: TextStyle(color: Colors.white.withOpacity(0.15)),
                      prefixIcon: Icon(icon, color: Colors.cyanAccent, size: 20),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.all(20),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildNeonSubmitButton(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 65,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(colors: [Colors.cyanAccent, Colors.cyanAccent.withOpacity(0.7)]),
        boxShadow: [
          BoxShadow(
            color: Colors.cyanAccent.withOpacity(0.3),
            blurRadius: 25,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Colors.cyanAccent,
              behavior: SnackBarBehavior.floating,
              content: Text("SYSTEM LOG UPDATED", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          );
          Navigator.pop(context);
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              "CONFIRM ENTRY",
              style: TextStyle(color: Color(0xFF0D0D1B), fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 16),
            ),
            SizedBox(width: 10),
            Icon(Icons.shield_outlined, color: Color(0xFF0D0D1B)),
          ],
        ),
      ),
    );
  }
}