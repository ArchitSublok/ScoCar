import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ResidentDashboard extends StatelessWidget {
  const ResidentDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("RESIDENT PORTAL"), 
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_none_rounded),
            onPressed: () {},
          )
        ],
      ),
      body: Column(
        children: [
          _buildResidentProfileCard(),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              children: [
                Text("MY REGISTERED VEHICLES", 
                  style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2)),
              ],
            ),
          ),
          
          // 🔑 ONLY ONE INSTANCE OF THE EXTRACTED STREAMBUILDER LIST GOES HERE
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('vehicles')
                  .where('flatNumber', isEqualTo: 'B-402') 
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Text(
                      "No vehicles registered for Flat B-402.",
                      style: TextStyle(color: Colors.grey, fontSize: 16),
                    ),
                  );
                }

                final vehicleDocs = snapshot.data!.docs;

                return ListView.builder(
                  itemCount: vehicleDocs.length, 
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemBuilder: (context, i) {
                    final vehicle = vehicleDocs[i].data() as Map<String, dynamic>;
                    
                    final String plateNumber = vehicle['plateNumber'] ?? 'UNKNOWN';
                    final String ownerName = vehicle['ownerName'] ?? 'Resident';
                    final String status = vehicle['status'] ?? 'ACTIVE';

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      child: ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: Colors.blueAccent,
                          child: Icon(Icons.directions_car_filled_rounded, color: Colors.white),
                        ),
                        title: Text(
                          plateNumber, 
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text("Owner: $ownerName • $status"), 
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: status == 'ACTIVE' ? Colors.green.withOpacity(0.2) : Colors.red.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            status,
                            style: TextStyle(
                              color: status == 'ACTIVE' ? Colors.green : Colors.red,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
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
        onPressed: () => Navigator.pushNamed(context, '/add-vehicle'),
        icon: const Icon(Icons.add),
        label: const Text("ADD VEHICLE"),
        backgroundColor: Colors.blueAccent,
      ),
    );
  }

  Widget _buildResidentProfileCard() {
    return Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0D47A1), Colors.blueAccent],
        ),
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(color: Colors.blue.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 5))
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: Colors.white.withOpacity(0.2),
            child: const Icon(Icons.person_rounded, size: 35, color: Colors.white),
          ),
          const SizedBox(width: 20),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("John Doe", 
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                SizedBox(height: 4),
                Text("Apartment: B-402", 
                  style: TextStyle(color: Colors.white70, fontSize: 14)),
              ],
              ),
            ),
          ],
        ),
      );
    }
  }