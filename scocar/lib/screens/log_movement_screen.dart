import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class LogMovementScreen extends StatefulWidget {
  const LogMovementScreen({super.key});

  @override
  State<LogMovementScreen> createState() => _LogMovementScreenState();
}

class _LogMovementScreenState extends State<LogMovementScreen> {
  final _plateController = TextEditingController();
  final _flatController = TextEditingController(); // 🔑 NEW: Controls destination apartment number input
  bool _isEntry = true;
  bool _isSaving = false;
  String _selectedDeliveryCompany = ""; 

  @override
  void dispose() {
    _plateController.dispose();
    _flatController.dispose(); // 🔑 Clean up controller resource allocation
    super.dispose();
  }

  void _submitLog() async {
    final String plateText = _plateController.text.trim().toUpperCase();
    final String targetFlat = _flatController.text.trim().toUpperCase();
    String currentCompany = _selectedDeliveryCompany.isNotEmpty ? _selectedDeliveryCompany : 'GENERAL';

    if (plateText.isEmpty) {
      _showSnackbar("Please enter a valid number plate or tracking info.", Colors.orange);
      return;
    }

    // 🚨 ENFORCE CRITICAL RULE: Delivery tags must have a designated apartment block destination
    if (currentCompany != 'GENERAL' && _isEntry && targetFlat.isEmpty) {
      _showSnackbar("A target Flat Number is required for delivery authorizations!", Colors.redAccent);
      return;
    }

    setState(() => _isSaving = true);

    try {
      // Simulating AI vehicle attribute identification variations based on tags
      String mockModel = "Unknown Vehicle Type";
      if (currentCompany == 'ZOMATO' || currentCompany == 'SWIGGY') {
        mockModel = "Delivery Motorcycle";
      } else {
        mockModel = "Standard Sedan (Verified)";
      }

      // 1. Log overall checkpoint movement history record
      await FirebaseFirestore.instance.collection('logs').add({
        'plateNumber': plateText,
        'type': _isEntry ? 'ENTRY' : 'EXIT',
        'company': currentCompany,
        'detectedVehicleModel': mockModel,
        'guardOnDuty': 'Guard Supervisor Ram',
        'flatNumber': targetFlat.isNotEmpty ? targetFlat : 'N/A', // Attach destination flat if provided
        'timestamp': FieldValue.serverTimestamp(),
      });

      // 2. 🚀 LIVE ROUTING DYNAMICALLY CHOSEN BY GUARD: 
      // Drop an interactive request entry matching the target flat number field input
      if (currentCompany != 'GENERAL' && _isEntry) {
        await FirebaseFirestore.instance.collection('approvals').add({
          'company': currentCompany,
          'flatNumber': targetFlat, // 🔑 FIXED: No longer hardcoded to B-402! Uses input text directly.
          'status': 'PENDING',
          'timestamp': FieldValue.serverTimestamp(),
          'visitorPhotoUrl': currentCompany == 'ZOMATO' 
              ? 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=150' 
              : 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=150',
        });
      }

      if (mounted) {
        _showSnackbar(
          currentCompany != 'GENERAL' 
              ? "Log saved & instant Approval request broadcasted to Flat $targetFlat!" 
              : "Movement Log Registered Successfully!", 
          Colors.green
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) _showSnackbar("Database write fault: $e", Colors.red);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showSnackbar(String text, Color bgColor) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: bgColor),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24, 
        top: 16,
        left: 24,
        right: 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
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

          // Vendor Selection Quick Tags
          Wrap(
            spacing: 10.0, 
            runSpacing: 10.0, 
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
          
          // Number Plate Entry Row
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
          const SizedBox(height: 16),

          // 🔑 NEW: Dynamic Destination Apartment Field UI
          TextField(
            controller: _flatController,
            textCapitalization: TextCapitalization.characters,
            style: const TextStyle(color: Colors.black),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.home_work_rounded, color: Colors.blueAccent),
              labelText: "Destination Flat Number",
              hintText: "e.g. B-402, A-101",
              filled: true,
              fillColor: Colors.grey[50],
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
              helperText: _selectedDeliveryCompany.isNotEmpty && _isEntry
                  ? "Required to route this delivery alert to the correct resident."
                  : "Optional for regular non-delivery entry logs.",
            ),
          ),
          const SizedBox(height: 20),
          
          // Gate Direction Choice Chips
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
          const SizedBox(height: 24),
          
          // Submit Action Button
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