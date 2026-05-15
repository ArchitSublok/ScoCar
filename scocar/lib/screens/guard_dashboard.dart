import 'package:flutter/material.dart';

class GuardDashboard extends StatelessWidget {
  const GuardDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("SECURE LOGS"), centerTitle: true),
      body: Column(
        children: [
          _buildLiveStats(),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(children: [Text("RECENT ACTIVITY", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2))]),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: 8,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemBuilder: (context, i) => Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                child: ListTile(
                  leading: const CircleAvatar(backgroundColor: Colors.blueGrey, child: Icon(Icons.directions_car, color: Colors.white)),
                  title: Text("PB 01 BK ${2024 + i}", style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(i % 2 == 0 ? "Entry • 10:20 AM" : "Exit • 09:45 AM"),
                  trailing: Icon(i % 2 == 0 ? Icons.arrow_downward : Icons.arrow_upward, color: i % 2 == 0 ? Colors.green : Colors.red),
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.pushNamed(context, '/add-vehicle'),
        icon: const Icon(Icons.add),
        label: const Text("NEW REGISTRATION"),
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
        boxShadow: [BoxShadow(color: Colors.blue.withOpacity(0.4), blurRadius: 10, offset: const Offset(0, 5))],
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
        Text(value, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white)),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ],
    );
  }
}