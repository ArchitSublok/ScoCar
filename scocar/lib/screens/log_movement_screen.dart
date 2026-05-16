import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class LogMovementScreen extends StatefulWidget {
  const LogMovementScreen({super.key});

  @override
  State<LogMovementScreen> createState() => _LogMovementScreenState();
}

class _LogMovementScreenState extends State<LogMovementScreen> {
  final _plateController = TextEditingController();
  bool _isEntry = true;
  bool _isSaving = false;

  void _submitLog() async {
    if (_plateController.text.trim().isEmpty) return;
    setState(() => _isSaving = true);

    try {
      // Writes to 'logs' collection. If it doesn't exist, Firestore builds it instantly!
      await FirebaseFirestore.instance.collection('logs').add({
        'plateNumber': _plateController.text.trim().toUpperCase(),
        'type': _isEntry ? 'ENTRY' : 'EXIT',
        'timestamp': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Log Registered!")));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("VEHICLE CHECKPOINT")),
      body: Padding(
        padding: const EdgeInsets.all(25.0),
        child: Column(
          children: [
            TextField(
              controller: _plateController,
              decoration: InputDecoration(
                labelText: "Type Plate Number",
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                prefixIcon: const Icon(Icons.pin_rounded, color: Colors.blueAccent),
              ),
            ),
            const SizedBox(height: 30),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ChoiceChip(
                  label: const Text("CHECK-IN"),
                  selected: _isEntry,
                  onSelected: (val) => setState(() => _isEntry = true),
                  selectedColor: Colors.green.withOpacity(0.3),
                ),
                const SizedBox(width: 20),
                ChoiceChip(
                  label: const Text("CHECK-OUT"),
                  selected: !_isEntry,
                  onSelected: (val) => setState(() => _isEntry = false),
                  selectedColor: Colors.red.withOpacity(0.3),
                ),
              ],
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 60,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _submitLog,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                child: _isSaving ? const CircularProgressIndicator() : const Text("SUBMIT MOVEMENT LOG", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            )
          ],
        ),
      ),
    );
  }
}