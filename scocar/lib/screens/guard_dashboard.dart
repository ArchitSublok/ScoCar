import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'log_movement_screen.dart'; // Handles the checkpoint form overlay card

class GuardDashboard extends StatelessWidget {
  const GuardDashboard({super.key});

  // 🧪 UPDATED: Generates mock entries representing specialized service partners
  Future<void> _createMockData(BuildContext context) async {
    final collection = FirebaseFirestore.instance.collection('logs');
    try {
      // 1. Standard Entry Log
      await collection.add({
        'plateNumber': 'HR 26 BR 9911',
        'type': 'ENTRY',
        'company': 'GENERAL',
        'timestamp': FieldValue.serverTimestamp(),
      });
      
      // 2. Specialized Zomato Delivery Entry Log
      await collection.add({
        'plateNumber': 'ZOMATO - 4821',
        'type': 'ENTRY',
        'company': 'ZOMATO',
        'timestamp': FieldValue.serverTimestamp(),
      });

      // 3. Specialized Swiggy Delivery Exit Log
      await collection.add({
        'plateNumber': 'SWIGGY - 9302',
        'type': 'EXIT',
        'company': 'SWIGGY',
        'timestamp': FieldValue.serverTimestamp(),
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Mock Data Added Successfully!"), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error inserting data: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("SECURE LOGS"), 
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.gpp_maybe_rounded, color: Colors.redAccent, size: 28),
            tooltip: "EMERGENCY PANIC",
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("🚨 EMERGENCY ALARM TRIGGERED!"), backgroundColor: Colors.red),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.analytics_outlined, color: Colors.blueAccent),
            onPressed: () => _createMockData(context),
          )
        ],
      ),
      body: Column(
        children: [
          _buildLiveStats(),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              children: [
                Text("RECENT ACTIVITY", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2))
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('logs').orderBy('timestamp', descending: true).snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text("Error fetching data: ${snapshot.error}"));
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Text("No vehicle movements logged today.", style: TextStyle(color: Colors.grey, fontSize: 16)),
                  );
                }

                final logDocs = snapshot.data!.docs;
                return ListView.builder(
  itemCount: logDocs.length,
  padding: const EdgeInsets.symmetric(horizontal: 16),
  itemBuilder: (context, i) {
    final log = logDocs[i].data() as Map<String, dynamic>;
    
    final String plate = log['plateNumber'] ?? 'UNKNOWN';
    final String movementType = log['type'] ?? 'ENTRY';
    final String company = log['company'] ?? 'GENERAL'; 
    
    final Timestamp? timestamp = log['timestamp'] as Timestamp?;
    String timeString = "Recent";
    if (timestamp != null) {
      final DateTime dt = timestamp.toDate();
      timeString = "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
    }
    final bool isEntry = movementType.toUpperCase() == 'ENTRY';

    // 🎨 Custom icons/colors for delivery companies
    Color avatarBg = isEntry ? Colors.green.withOpacity(0.15) : Colors.red.withOpacity(0.15);
    Color iconColor = isEntry ? Colors.green : Colors.red;
    IconData leadingIcon = Icons.directions_car_filled_rounded;

    if (company == 'ZOMATO') {
      avatarBg = Colors.red.shade900;
      iconColor = Colors.white;
      leadingIcon = Icons.fastfood_rounded;
    } else if (company == 'SWIGGY') {
      avatarBg = Colors.orange.shade800;
      iconColor = Colors.white;
      leadingIcon = Icons.delivery_dining_rounded;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.0), // Adds internal breathing room
        child: ListTile(
          isThreeLine: company != 'GENERAL', // 🔑 FIX: Tells Flutter to allocate extra height for delivery text
          leading: CircleAvatar(
            backgroundColor: avatarBg, 
            child: Icon(leadingIcon, color: iconColor, size: 20),
          ),
          title: Text(
            plate, 
            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black, fontSize: 16),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4.0), // Keeps subtitle from bumping into title
            child: Text(
              company != 'GENERAL' ? "$company SERVICE\n$movementType • $timeString" : "$movementType • $timeString",
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12, height: 1.3),
            ),
          ),
          trailing: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: isEntry ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isEntry ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded, 
              color: isEntry ? Colors.green : Colors.red,
              size: 20,
            ),
          ),
        ),
      ),
    );
  },
);
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            backgroundColor: Colors.transparent,
            builder: (context) => const LogMovementScreen(),
          );
        }, 
        icon: const Icon(Icons.swap_vert_rounded),
        label: const Text("LOG ENTRY / EXIT"),
        backgroundColor: Colors.blueAccent,
      ),
    );
  }

  Widget _buildLiveStats() {
    return Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Colors.blueAccent, Colors.blue]),
        borderRadius: BorderRadius.circular(25),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _StatTile(value: "42", label: "In Society"),
          _StatTile(value: "128", label: "Daily Total"),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String value, label;
  const _StatTile({required this.value, required this.label});
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
        const SizedBox(height: 5),
        Text(label, style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.8))),
      ],
    );
  }
}