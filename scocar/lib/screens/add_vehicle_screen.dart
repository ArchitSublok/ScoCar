import 'package:flutter/material.dart';

class AddVehicleScreen extends StatelessWidget {
  const AddVehicleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Register Vehicle")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(25),
        child: Column(
          children: [
            // Visual License Plate Preview
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.yellow, width: 3),
              ),
              child: const Center(
                child: Text("DL 01 AA 0000", 
                  style: TextStyle(color: Colors.yellow, fontSize: 35, fontWeight: FontWeight.bold, letterSpacing: 5)),
              ),
            ),
            const SizedBox(height: 40),
            _inputField("Vehicle Plate Number", Icons.numbers),
            const SizedBox(height: 20),
            _inputField("Owner Name", Icons.person),
            const SizedBox(height: 20),
            _inputField("Flat Number (e.g. B-402)", Icons.home),
            const SizedBox(height: 20),
            _inputField("Contact Number", Icons.phone),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 60,
              child: ElevatedButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Vehicle Registered Successfully")));
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                child: const Text("CONFIRM REGISTRATION", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _inputField(String label, IconData icon) {
    return TextField(
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: Colors.blueAccent),
        labelText: label,
        filled: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
      ),
    );
  }
}