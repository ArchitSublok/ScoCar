import 'package:flutter/material.dart';
import 'add_vehicle_screen.dart';

class GuardDashboard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Guard Dashboard", style: TextStyle(color: Colors.blue[900], fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [IconButton(onPressed: () {}, icon: Icon(Icons.dark_mode, color: Colors.blue))],
      ),
      body: Column(
        children: [
          _buildSummaryHeader(),
          Expanded(
            child: ListView.builder(
              itemCount: 10,
              padding: EdgeInsets.all(16),
              itemBuilder: (context, index) => _vehicleLogCard(index),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => AddVehicleScreen())),
        label: Text("Add Vehicle"),
        icon: Icon(Icons.add),
        backgroundColor: Colors.blue[800],
      ),
    );
  }

  Widget _buildSummaryHeader() {
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.blue[800], borderRadius: BorderRadius.only(bottomLeft: Radius.circular(30), bottomRight: Radius.circular(30))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _statItem("24", "In Today"),
          _statItem("12", "Out Today"),
          _statItem("150", "Total Registered"),
        ],
      ),
    );
  }

  Widget _statItem(String value, String label) {
    return Column(children: [
      Text(value, style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
      Text(label, style: TextStyle(color: Colors.white70, fontSize: 12)),
    ]);
  }

  Widget _vehicleLogCard(int index) {
    return Card(
      margin: EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: ListTile(
        leading: CircleAvatar(backgroundColor: Colors.blue[50], child: Icon(Icons.directions_car, color: Colors.blue[800])),
        title: Text(
  "PB-01-AX-123$index", 
  style: TextStyle(fontWeight: FontWeight.bold), // Corrected line
),
        subtitle: Text("Entry: 10:30 AM | Owner: Flat 40$index"),
        trailing: Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
      ),
    );
  }
}