import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class GuardDashboard extends StatelessWidget {
  const GuardDashboard({super.key});

  // 🔑 Function to automatically create mock logs in Firestore
  Future<void> _createMockData(BuildContext context) async {
    final collection = FirebaseFirestore.instance.collection('logs');
    
    try {
      // 1. Create an ENTRY log
      await collection.add({
        'plateNumber': 'HR 26 BR 9911',
        'type': 'ENTRY',
        'timestamp': FieldValue.serverTimestamp(),
      });

      // 2. Create an EXIT log
      await collection.add({
        'plateNumber': 'DL 03 CA 1234',
        'type': 'EXIT',
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
          // 🔑 This button will inject the entry/exit data into your dashboard immediately
          IconButton(
            icon: const Icon(Icons.analytics_outlined, color: Colors.blueAccent),
            tooltip: "Generate Mock Logs",
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
                Text(
                  "RECENT ACTIVITY", 
                  style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2),
                )
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('logs')
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                
                if (snapshot.hasError) {
                  return Center(child: Text("Error fetching data: ${snapshot.error}"));
                }

                if (!snapshot.hasData || snapshot.data == null || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(20.0),
                      child: Text(
                        "No vehicle movements logged today.",
                        style: TextStyle(color: Colors.grey, fontSize: 16),
                      ),
                    ),
                  );
                }

                final logDocs = snapshot.data!.docs;

                return ListView.builder(
                  itemCount: logDocs.length,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemBuilder: (context, i) {
                    final log = logDocs[i].data() as Map<String, dynamic>;
                    
                    // Uses corrected lowercase keys to read seamlessly
                    final String plate = log['plateNumber'] ?? 'UNKNOWN';
                    final String movementType = log['type'] ?? 'ENTRY';
                    
                    final Timestamp? timestamp = log['timestamp'] as Timestamp?;
                    String timeString = "Recent";
                    if (timestamp != null) {
                      final DateTime dt = timestamp.toDate();
                      timeString = "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
                    }

                    final bool isEntry = movementType.toUpperCase() == 'ENTRY';

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isEntry ? Colors.green.withOpacity(0.2) : Colors.red.withOpacity(0.2), 
                          child: Icon(Icons.directions_car, color: isEntry ? Colors.green : Colors.red),
                        ),
                        title: Text(plate, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text("$movementType • $timeString"),
                        trailing: Icon(
                          isEntry ? Icons.arrow_downward : Icons.arrow_upward,
                          color: isEntry ? Colors.green : Colors.red,
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
        onPressed: () => Navigator.pushNamed(context, '/log-movement'), 
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
        boxShadow: [
          BoxShadow(color: Colors.blue.withOpacity(0.4), blurRadius: 10, offset: const Offset(0, 5))
        ],
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
        Text(
          value,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        const SizedBox(height: 5),
        Text(
          label,
          style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.8)),
        ),
      ],
    );
  }
}