// ─────────────────────────────────────────────────────────────────────────────
// AREA 7: CameraRegistrationScreen — Flutter UI
//
// Accessible by Admin/Guard role.
// Writes to Firestore `cameras` collection.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class CameraRegistrationScreen extends StatefulWidget {
  const CameraRegistrationScreen({super.key});

  @override
  State<CameraRegistrationScreen> createState() =>
      _CameraRegistrationScreenState();
}

class _CameraRegistrationScreenState extends State<CameraRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _ipController = TextEditingController();
  int _gateNo = 1;
  String _direction = 'IN';
  bool _isSaving = false;

  // ── Validate RTSP / HTTP camera URL ──────────────────────────────────────
  String? _validateUrl(String? value) {
    if (value == null || value.trim().isEmpty) return 'IP address / RTSP URL required';
    final v = value.trim().toLowerCase();
    if (v.startsWith('rtsp://') ||
        v.startsWith('http://') ||
        v.startsWith('https://') ||
        RegExp(r'^\d{1,3}(\.\d{1,3}){3}(:\d+)?').hasMatch(v)) {
      return null;
    }
    return 'Enter a valid RTSP URL or IP address (e.g. rtsp://admin:pass@192.168.1.108/stream1)';
  }

  // ── Save camera document to Firestore ────────────────────────────────────
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      await FirebaseFirestore.instance.collection('cameras').add({
        'cameraName': _nameController.text.trim(),
        'ipAddress': _ipController.text.trim(),
        'gateNo': _gateNo,
        'direction': _direction,
        'status': 'active',
        'addedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Camera registered successfully'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error saving camera: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A1A),
      appBar: AppBar(
        title: const Text('Register IP Camera',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF141428),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // ── Existing cameras list ──────────────────────────────────
            _SectionHeader('Registered Cameras'),
            _CameraList(),
            const SizedBox(height: 28),

            // ── Add new camera form ────────────────────────────────────
            _SectionHeader('Add New Camera'),
            const SizedBox(height: 12),

            _DarkField(
              controller: _nameController,
              label: 'Camera Name',
              hint: 'e.g. Main Gate Entry Cam',
              icon: Icons.videocam_rounded,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Camera name required' : null,
            ),
            const SizedBox(height: 14),

            _DarkField(
              controller: _ipController,
              label: 'RTSP / IP Address',
              hint: 'rtsp://admin:pass@192.168.1.108:554/stream1',
              icon: Icons.link_rounded,
              keyboardType: TextInputType.url,
              validator: _validateUrl,
            ),
            const SizedBox(height: 14),

            // ── Gate Number dropdown ────────────────────────────────────
            _DarkDropdown<int>(
              label: 'Gate Number',
              icon: Icons.door_front_door_rounded,
              value: _gateNo,
              items: List.generate(
                  6,
                  (i) => DropdownMenuItem(
                      value: i + 1, child: Text('Gate ${i + 1}'))),
              onChanged: (v) => setState(() => _gateNo = v ?? 1),
            ),
            const SizedBox(height: 14),

            // ── IN / OUT direction toggle ───────────────────────────────
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(children: [
                    Icon(Icons.swap_horiz_rounded,
                        color: Colors.cyanAccent, size: 18),
                    SizedBox(width: 8),
                    Text('Direction',
                        style: TextStyle(color: Colors.white70, fontSize: 13)),
                  ]),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: _DirectionToggle(
                        label: 'ENTRY (IN)',
                        icon: Icons.login_rounded,
                        selected: _direction == 'IN',
                        color: Colors.greenAccent,
                        onTap: () => setState(() => _direction = 'IN'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _DirectionToggle(
                        label: 'EXIT (OUT)',
                        icon: Icons.logout_rounded,
                        selected: _direction == 'OUT',
                        color: Colors.redAccent,
                        onTap: () => setState(() => _direction = 'OUT'),
                      ),
                    ),
                  ]),
                ],
              ),
            ),
            const SizedBox(height: 28),

            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.cyanAccent,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                onPressed: _isSaving ? null : _save,
                icon: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            color: Colors.black, strokeWidth: 2))
                    : const Icon(Icons.save_rounded),
                label: Text(
                    _isSaving ? 'Saving...' : 'REGISTER CAMERA',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, letterSpacing: 1)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Supporting widgets ────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          color: Colors.white70,
          fontWeight: FontWeight.bold,
          fontSize: 14,
          letterSpacing: 0.5));
}

class _DarkField extends StatelessWidget {
  final TextEditingController controller;
  final String label, hint;
  final IconData icon;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  const _DarkField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.keyboardType,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white),
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: Colors.white54),
        hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
        prefixIcon: Icon(icon, color: Colors.cyanAccent),
        filled: true,
        fillColor: Colors.white.withOpacity(0.05),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Colors.white12)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Colors.white12)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide:
                const BorderSide(color: Colors.cyanAccent, width: 1.5)),
        errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Colors.redAccent)),
      ),
    );
  }
}

class _DarkDropdown<T> extends StatelessWidget {
  final String label;
  final IconData icon;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final void Function(T?) onChanged;

  const _DarkDropdown({
    required this.label,
    required this.icon,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          items: items,
          onChanged: onChanged,
          dropdownColor: const Color(0xFF1C1C3A),
          style: const TextStyle(color: Colors.white),
          icon: const Icon(Icons.arrow_drop_down_rounded, color: Colors.white38),
        ),
      ),
    );
  }
}

class _DirectionToggle extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _DirectionToggle({
    required this.label,
    required this.icon,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: selected ? color : Colors.white24, width: 1.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                color: selected ? color : Colors.white38, size: 16),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    color: selected ? color : Colors.white38,
                    fontWeight: FontWeight.bold,
                    fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

// ── Live list of registered cameras ──────────────────────────────────────────
class _CameraList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('cameras')
          .orderBy('addedAt', descending: true)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData || snap.data!.docs.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text('No cameras registered yet.',
                style: TextStyle(color: Colors.white38)),
          );
        }
        return Column(
          children: snap.data!.docs.map((doc) {
            final d = doc.data() as Map<String, dynamic>;
            final bool isActive = d['status'] == 'active';
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF141428),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: isActive
                        ? Colors.greenAccent.withOpacity(0.3)
                        : Colors.white12),
              ),
              child: Row(children: [
                Icon(Icons.videocam_rounded,
                    color: isActive ? Colors.greenAccent : Colors.white38,
                    size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(d['cameraName'] ?? '—',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600)),
                      Text(
                          'Gate ${d['gateNo']} • ${d['direction']} • ${d['ipAddress'] ?? ''}',
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 11)),
                    ],
                  ),
                ),
                // Toggle active/inactive
                Switch(
                  value: isActive,
                  activeColor: Colors.greenAccent,
                  onChanged: (val) {
                    FirebaseFirestore.instance
                        .collection('cameras')
                        .doc(doc.id)
                        .update({'status': val ? 'active' : 'inactive'});
                  },
                ),
              ]),
            );
          }).toList(),
        );
      },
    );
  }
}
