import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AddVehicleScreen extends StatefulWidget {
  const AddVehicleScreen({super.key});

  @override
  State<AddVehicleScreen> createState() => _AddVehicleScreenState();
}

class _AddVehicleScreenState extends State<AddVehicleScreen> {
  // Text controllers to capture data
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please fill in the Plate Number and Owner Name")),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Pushing payload straight to your Firestore 'vehicles' collection
      await FirebaseFirestore.instance.collection('vehicles').add({
        'plateNumber': _plateController.text.trim().toUpperCase(),
        'ownerName': _ownerController.text.trim(),
        'flatNumber': _flatController.text.trim().toUpperCase().replaceAll(' ', ''),
        'contactNumber': _contactController.text.trim(),
        'status': 'ACTIVE',
        'registeredAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Vehicle Registered Successfully"), backgroundColor: Colors.green),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Firestore Error: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Register Vehicle")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(25),
        child: Column(
          children: [
            // Responsive License Plate Window View
            ListenableBuilder(
              listenable: _plateController,
              builder: (context, child) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.yellow, width: 3),
                  ),
                  child: Center(
                    child: Text(
                      _plateController.text.isEmpty ? "DL 01 AA 0000" : _plateController.text.toUpperCase(), 
                      style: const TextStyle(color: Colors.yellow, fontSize: 35, fontWeight: FontWeight.bold, letterSpacing: 5),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 40),
            _inputField("Vehicle Plate Number", Icons.numbers, _plateController),
            const SizedBox(height: 20),
            _inputField("Owner Name", Icons.person, _ownerController),
            const SizedBox(height: 20),
            _inputField("Flat Number (e.g. B-402)", Icons.home, _flatController),
            const SizedBox(height: 20),
            _inputField("Contact Number", Icons.phone, _contactController),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 60,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _registerVehicle,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                child: _isLoading 
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text("CONFIRM REGISTRATION", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: Colors.blueAccent),
        labelText: label,
        filled: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
      ),
    );
  }
}