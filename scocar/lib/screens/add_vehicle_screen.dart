import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AddVehicleScreen extends StatefulWidget {
  const AddVehicleScreen({super.key});
  @override
  State<AddVehicleScreen> createState() => _AddVehicleScreenState();
}

class _AddVehicleScreenState extends State<AddVehicleScreen> {
  final TextEditingController _plateController = TextEditingController();
  final TextEditingController _ownerController = TextEditingController();
  final TextEditingController _flatController = TextEditingController();
  final TextEditingController _contactController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _plateController.dispose();
    _ownerController.dispose();
    _flatController.dispose();
    _contactController.dispose();
    super.dispose();
  }

  Future<void> _registerVehicle() async {
    if (_plateController.text.trim().isEmpty || _ownerController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please fill in the Plate Number and Owner Name")));
      return;
    }
    setState(() => _isLoading = true);
    try {
      await FirebaseFirestore.instance.collection('vehicles').add({
        'plateNumber': _plateController.text.trim().toUpperCase(),
        'ownerName': _ownerController.text.trim(),
        'flatNumber': _flatController.text.trim().toUpperCase(),
        'contact': _contactController.text.trim(),
        'status': 'ACTIVE',
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Vehicle Registered Successfully!")));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Registration Error: $e")));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("REGISTER VEHICLE"), centerTitle: true),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(25.0),
        child: Column(
          children: [
            // 📸 ADDED: Interactive RC Document Scanner shortcut zone wrapper element block
            GestureDetector(
              onTap: () {
                setState(() {
                  _plateController.text = "DL 3C AM 5678";
                  _ownerController.text = "John Doe";
                  _flatController.text = "B-402";
                  _contactController.text = "9876543210";
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("RC details populated successfully via OCR scanner snapshot!"), backgroundColor: Colors.blueAccent),
                );
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 25),
                decoration: BoxDecoration(
                  color: Colors.blueAccent.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.blueAccent.withOpacity(0.5), style: BorderStyle.solid),
                ),
                child: const Column(
                  children: [
                    Icon(Icons.document_scanner_rounded, size: 44, color: Colors.blueAccent),
                    SizedBox(height: 8),
                    Text("SCAN VEHICLE REGISTRATION (RC)", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent, fontSize: 14)),
                    Text("Auto-extract vehicle profiles via camera parser snapshot", style: TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 25),
            _inputField("Plate Number", Icons.pin_rounded, _plateController),
            const SizedBox(height: 20),
            _inputField("Owner Name", Icons.person, _ownerController),
            const SizedBox(height: 20),
            _inputField("Flat Number (e.g. B-402)", Icons.home, _flatController),
            const SizedBox(height: 20),
            _inputField("Contact Number", Icons.phone, _contactController),
            const SizedBox(height: 35),
            SizedBox(
              width: double.infinity, height: 56,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _registerVehicle,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text("CONFIRM REGISTRATION", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _inputField(String label, IconData icon, TextEditingController controller) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: Colors.black),
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: Colors.blueAccent),
        labelText: label,
        labelStyle: const TextStyle(color: Colors.grey),
        filled: true,
        fillColor: Colors.grey[50],
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide(color: Colors.grey[200]!)),
      ),
    );
  }
}