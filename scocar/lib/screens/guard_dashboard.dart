import 'dart:ui';
import 'package:flutter/material.dart';

class GuardDashboard extends StatefulWidget {
  const GuardDashboard({super.key});

  @override
  State<GuardDashboard> createState() => _GuardDashboardState();
}

class _GuardDashboardState extends State<GuardDashboard> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1B),
      body: Stack(
        children: [
          // Background "Deep Space" Glow
          Positioned(
            bottom: -100,
            left: -50,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.blueAccent.withOpacity(0.1),
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 100, sigmaY: 100),
                child: Container(),
              ),
            ),
          ),
          
          CustomScrollView(
            slivers: [
              // 1. Futuristic Animated AppBar
              SliverAppBar(
                expandedHeight: 120.0,
                floating: true,
                backgroundColor: Colors.transparent,
                flexibleSpace: FlexibleSpaceBar(
                  title: const Text(
                    "COMMAND CENTER",
                    style: TextStyle(
                      letterSpacing: 3,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      color: Colors.cyanAccent,
                    ),
                  ),
                  centerTitle: true,
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.notifications_active_outlined, color: Colors.cyanAccent),
                    onPressed: () {},
                  ),
                ],
              ),

              // 2. Statistics/Status Row (Professional touch)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Row(
                    children: [
                      _buildStatusChip("SYSTEM: ACTIVE", Colors.greenAccent),
                      const SizedBox(width: 10),
                      _buildStatusChip("SCANS: 24", Colors.cyanAccent),
                    ],
                  ),
                ),
              ),

              // 3. The Animated List
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    return TweenAnimationBuilder(
                      duration: Duration(milliseconds: 400 + (index * 100)),
                      tween: Tween<double>(begin: 0, end: 1),
                      builder: (context, double value, child) {
                        return Transform.translate(
                          offset: Offset(0, 50 * (1 - value)),
                          child: Opacity(
                            opacity: value,
                            child: _buildScanCard(index),
                          ),
                        );
                      },
                    );
                  },
                  childCount: 8,
                ),
              ),
            ],
          ),
        ],
      ),
      
      // 4. Futuristic Floating Button
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.pushNamed(context, '/add-vehicle'),
        backgroundColor: Colors.cyanAccent,
        elevation: 10,
        icon: const Icon(Icons.qr_code_scanner, color: Color(0xFF0D0D1B)),
        label: const Text(
          "INITIATE SCAN",
          style: TextStyle(color: Color(0xFF0D0D1B), fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildStatusChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.5)),
        color: color.withOpacity(0.05),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildScanCard(int index) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.cyanAccent.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.directions_car_filled, color: Colors.cyanAccent),
        ),
        title: Text(
          "VEHICLE-ID: ${1000 + index}X",
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1),
        ),
        subtitle: Text(
          "TIMESTAMP: 08:${10 + index} PM",
          style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
        ),
        trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white24, size: 16),
      ),
    );
  }
}