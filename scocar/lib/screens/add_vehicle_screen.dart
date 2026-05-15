import 'package:flutter/material.dart';

class AddVehicleScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Register New Vehicle"), centerTitle: true),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(20),
        child: Column(
          children: [
            _buildInputField("Vehicle Number Plate", Icons.numbers),
            const SizedBox(height: 15),
            _buildInputField("Owner Name", Icons.person),
            const SizedBox(height: 15),
            _buildInputField("Owner Phone Number", Icons.phone),
            const SizedBox(height: 15),
            _buildInputField("Flat/Apartment Number", Icons.home),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green[600], shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Vehicle Added Successfully!"), backgroundColor: Colors.green));
                  Navigator.pop(context);
                },
                child: Text("Register & Grant Entry", style: TextStyle(fontSize: 18, color: Colors.white)),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildInputField(String hint, IconData icon) {
    return TextField(
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: Colors.blue[800]),
        hintText: hint,
        filled: true,
        fillColor: Colors.blue[50]!.withOpacity(0.3),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
      ),
    );
  }
}