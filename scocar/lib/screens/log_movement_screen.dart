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
  String _selectedDeliveryCompany = ""; // Tracks if Zomato/Swiggy is active

  @override
  void dispose() {
    _plateController.dispose();
    super.dispose();
  }

  void _submitLog() async {
    if (_plateController.text.trim().isEmpty) return;
    setState(() => _isSaving = true);

    try {
      await FirebaseFirestore.instance.collection('logs').add({
        'plateNumber': _plateController.text.trim().toUpperCase(),
        'type': _isEntry ? 'ENTRY' : 'EXIT',
        'company': _selectedDeliveryCompany.isNotEmpty ? _selectedDeliveryCompany : 'GENERAL',
        'timestamp': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Log Registered!")));
        Navigator.pop(context); // Closes the bottom sheet smoothly
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24, // Adapts safely to keyboard entry
        top: 16,
        left: 24,
        right: 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Drag handle decoration
          Container(
            width: 45,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            "Log Vehicle Movement",
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black),
          ),
          const SizedBox(height: 20),

          // 🛵 FIXED: Uses Wrap instead of Row to gracefully flow layout lines without clipping
          Wrap(
            spacing: 10.0, // Horizontal space between chips
            runSpacing: 10.0, // Vertical space between wrapped chip rows
            alignment: WrapAlignment.center,
            children: [
              ActionChip(
                avatar: const Icon(Icons.fastfood_rounded, color: Colors.white, size: 16),
                backgroundColor: Colors.redAccent,
                side: BorderSide.none,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                label: const Text("Zomato", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                onPressed: () {
                  setState(() {
                    _selectedDeliveryCompany = "ZOMATO";
                    _plateController.text = "ZOMATO - ";
                  });
                },
              ),
              ActionChip(
                avatar: const Icon(Icons.delivery_dining_rounded, color: Colors.white, size: 16),
                backgroundColor: Colors.orangeAccent,
                side: BorderSide.none,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                label: const Text("Swiggy", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                onPressed: () {
                  setState(() {
                    _selectedDeliveryCompany = "SWIGGY";
                    _plateController.text = "SWIGGY - ";
                  });
                },
              ),
              ActionChip(
                avatar: Icon(Icons.refresh_rounded, color: Colors.grey[700], size: 16),
                backgroundColor: Colors.grey[200],
                side: BorderSide.none,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                label: Text("Clear Tag", style: TextStyle(color: Colors.grey[800], fontWeight: FontWeight.w500)),
                onPressed: () {
                  setState(() {
                    _selectedDeliveryCompany = "";
                    _plateController.clear();
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 24),
          
          // Input row field setup
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: TextField(
                  controller: _plateController,
                  textCapitalization: TextCapitalization.characters,
                  style: const TextStyle(color: Colors.black),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.pin_rounded, color: Colors.blueAccent),
                    labelText: "Number Plate / Info",
                    hintText: "e.g. MH 12 AB 1234",
                    filled: true,
                    fillColor: Colors.grey[50],
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                height: 56,
                width: 56,
                child: IconButton.filledTonal(
                  icon: const Icon(Icons.qr_code_scanner_rounded, size: 24),
                  color: Colors.blueAccent,
                  style: IconButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  ),
                  onPressed: () {
                    setState(() {
                      String prefix = _selectedDeliveryCompany.isNotEmpty ? "$_selectedDeliveryCompany - " : "";
                      _plateController.text = "${prefix}MH 12 AB 1234";
                    });
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          
          // Operational Choice Chips layout
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ChoiceChip(
                label: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: Text("CHECK-IN", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                selected: _isEntry,
                selectedColor: Colors.green.withOpacity(0.15),
                checkmarkColor: Colors.green,
                labelStyle: TextStyle(color: _isEntry ? Colors.green : Colors.grey[600]),
                onSelected: (val) => setState(() => _isEntry = true),
              ),
              const SizedBox(width: 16),
              ChoiceChip(
                label: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: Text("CHECK-OUT", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                selected: !_isEntry,
                selectedColor: Colors.red.withOpacity(0.15),
                checkmarkColor: Colors.red,
                labelStyle: TextStyle(color: !_isEntry ? Colors.red : Colors.grey[600]),
                onSelected: (val) => setState(() => _isEntry = false),
              ),
            ],
          ),
          const SizedBox(height: 32),
          
          // Operational dispatch button
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _submitLog,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                elevation: 0,
              ),
              child: _isSaving
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text(
                      "SUBMIT MOVEMENT LOG",
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}