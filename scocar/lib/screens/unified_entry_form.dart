import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

// ---------------------------------------------------------------------------
// Entry type enum
// ---------------------------------------------------------------------------

enum EntryType { delivery, visitor, generalMovement }

extension EntryTypeExtension on EntryType {
  String get label {
    switch (this) {
      case EntryType.delivery:
        return 'DELIVERY';
      case EntryType.visitor:
        return 'VISITOR';
      case EntryType.generalMovement:
        return 'MOVEMENT';
    }
  }

  String get displayName {
    switch (this) {
      case EntryType.delivery:
        return 'Delivery';
      case EntryType.visitor:
        return 'Visitor';
      case EntryType.generalMovement:
        return 'General Movement';
    }
  }

  IconData get icon {
    switch (this) {
      case EntryType.delivery:
        return Icons.local_shipping_rounded;
      case EntryType.visitor:
        return Icons.person_rounded;
      case EntryType.generalMovement:
        return Icons.swap_vert_rounded;
    }
  }
}

// ---------------------------------------------------------------------------
// Public API — call UnifiedEntryForm.show(context, guardId: ...)
// ---------------------------------------------------------------------------

class UnifiedEntryForm extends StatefulWidget {
  final String? guardId;

  const UnifiedEntryForm({super.key, this.guardId});

  /// Show the form as a full-screen-height bottom sheet.
  static Future<void> show(
    BuildContext context, {
    String? guardId,
    EntryType initialType = EntryType.delivery,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => UnifiedEntryForm(guardId: guardId),
    );
  }

  @override
  State<UnifiedEntryForm> createState() => _UnifiedEntryFormState();
}

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

class _UnifiedEntryFormState extends State<UnifiedEntryForm>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final _nameCtrl = TextEditingController();
  final _plateCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  // Focus nodes
  final _nameFocus = FocusNode();
  final _plateFocus = FocusNode();
  final _notesFocus = FocusNode();

  // State
  EntryType _entryType = EntryType.delivery;
  bool _isScanning = false;
  bool _isSubmitting = false;
  File? _scannedImage;

  // Animation controller for the submit button
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  // ─── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(begin: 1.0, end: 1.03).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    // Auto-focus name field once sheet is open
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusScope.of(context).requestFocus(_nameFocus);
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _plateCtrl.dispose();
    _notesCtrl.dispose();
    _nameFocus.dispose();
    _plateFocus.dispose();
    _notesFocus.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  // ─── OCR / Scan ─────────────────────────────────────────────────────────────

  Future<void> _scanNumberPlate() async {
    setState(() => _isScanning = true);

    try {
      final picker = ImagePicker();
      final XFile? photo = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 90,
        preferredCameraDevice: CameraDevice.rear,
      );

      if (photo == null) return; // user cancelled

      _scannedImage = File(photo.path);

      final inputImage = InputImage.fromFile(_scannedImage!);
      final recognizer =
          TextRecognizer(script: TextRecognitionScript.latin);
      final RecognizedText result =
          await recognizer.processImage(inputImage);
      await recognizer.close();

      final detected = _extractNumberPlate(result.text);

      if (!mounted) return;

      if (detected != null) {
        setState(() => _plateCtrl.text = detected);
        _showSnack('✅ Number plate detected — verify if needed.',
            Colors.green.shade700);
      } else {
        // Fall back to raw OCR text so guard can edit it
        final raw = result.text
            .replaceAll('\n', ' ')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim()
            .toUpperCase();
        if (raw.isNotEmpty) setState(() => _plateCtrl.text = raw);
        _showSnack(
            '⚠️  Plate not recognised — please verify manually.',
            Colors.orange.shade700);
      }

      // Move focus to notes after successful scan
      FocusScope.of(context).requestFocus(_notesFocus);
    } catch (e) {
      if (mounted) {
        _showSnack('Camera error: ${e.toString()}', Colors.red.shade700);
      }
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  /// Regex patterns for Indian number plates.
  ///   Standard  : MH12AB1234
  ///   BH series : 22BH1234AB
  ///   Old 2-col  : MH12 1234
  String? _extractNumberPlate(String raw) {
    final text = raw.toUpperCase().replaceAll(RegExp(r'\s+'), '');

    final patterns = [
      // Standard 4-letter suffix: MH12AB1234
      RegExp(r'[A-Z]{2}\d{2}[A-Z]{1,3}\d{4}'),
      // BH series: 22BH1234AB
      RegExp(r'\d{2}BH\d{4}[A-Z]{1,2}'),
      // Old 2-column: MH121234 (state + 2 digits + 4 digits)
      RegExp(r'[A-Z]{2}\d{2}\d{4}'),
    ];

    for (final p in patterns) {
      final m = p.firstMatch(text);
      if (m != null) return m.group(0);
    }
    return null;
  }

  // ─── Submit ──────────────────────────────────────────────────────────────────

  Future<void> _submitEntry() async {
    // Close keyboard
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      await FirebaseFirestore.instance.collection('logs').add({
        'type': 'ENTRY',
        'entryType': _entryType.displayName,     // "Delivery" / "Visitor" / "General Movement"
        'company': _nameCtrl.text.trim(),
        'plateNumber': _plateCtrl.text.trim().toUpperCase(),
        'notes': _notesCtrl.text.trim(),
        'guardId': widget.guardId ?? 'GUARD',
        'scannedImagePath': _scannedImage?.path,  // for optional image storage in logs
        'timestamp': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded,
                  color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${_entryType.displayName} entry logged successfully.',
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, color: Colors.white),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
          margin:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (mounted) {
        _showSnack('Submission failed: $e', Colors.red.shade700);
        setState(() => _isSubmitting = false);
      }
    }
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────────

  void _showSnack(String msg, Color bg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: bg,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }

  InputDecoration _inputDec({
    required String hint,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF3A3A5C), fontSize: 14),
      prefixIcon: Icon(icon, color: const Color(0xFF4A4A7A), size: 20),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: const Color(0xFF13132A),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF2A2A4A)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF2A2A4A)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide:
            const BorderSide(color: Colors.cyanAccent, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
      ),
      errorStyle:
          const TextStyle(color: Colors.redAccent, fontSize: 11),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text,
          style: const TextStyle(
            color: Color(0xFF7A7AAA),
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
      );

  // ─── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // Dismiss keyboard on tap outside
      onTap: () => FocusScope.of(context).unfocus(),
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0A0A1A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          border: Border(
            top: BorderSide(color: Color(0xFF1E1E3A), width: 1),
          ),
        ),
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 28,
        ),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Handle bar ────────────────────────────────────────────
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A2A4A),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),

                // ── Header ────────────────────────────────────────────────
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.cyanAccent.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.add_circle_outline_rounded,
                          color: Colors.cyanAccent, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'NEW ENTRY LOG',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                          ),
                        ),
                        Text(
                          'Fill details or scan number plate',
                          style: TextStyle(
                            color: Color(0xFF5A5A8A),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 24),
                const Divider(color: Color(0xFF1A1A3A), height: 1),
                const SizedBox(height: 20),

                // ── 1. Entry Type Selector ────────────────────────────────
                _label('ENTRY TYPE'),
                _EntryTypeSelector(
                  selected: _entryType,
                  onChanged: (t) => setState(() => _entryType = t),
                ),

                const SizedBox(height: 22),

                // ── 2. Company / Visitor Name ─────────────────────────────
                _label('COMPANY / VISITOR NAME *'),
                TextFormField(
                  controller: _nameCtrl,
                  focusNode: _nameFocus,
                  textInputAction: TextInputAction.next,
                  onEditingComplete: () =>
                      FocusScope.of(context).requestFocus(_plateFocus),
                  style: const TextStyle(
                      color: Colors.white, fontSize: 15),
                  decoration: _inputDec(
                    hint: 'Enter company or visitor name',
                    icon: Icons.badge_rounded,
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Name is required'
                      : null,
                ),

                const SizedBox(height: 18),

                // ── 3. Vehicle Number Plate (manual) ──────────────────────
                _label('VEHICLE NUMBER PLATE'),
                TextFormField(
                  controller: _plateCtrl,
                  focusNode: _plateFocus,
                  textInputAction: TextInputAction.next,
                  onEditingComplete: () =>
                      FocusScope.of(context).requestFocus(_notesFocus),
                  style: const TextStyle(
                    color: Colors.cyanAccent,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2.5,
                  ),
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [
                    // Auto-uppercase every character
                    TextInputFormatter.withFunction(
                      (old, newVal) => newVal.copyWith(
                        text: newVal.text.toUpperCase(),
                      ),
                    ),
                  ],
                  decoration: _inputDec(
                    hint: 'e.g. MH12AB1234',
                    icon: Icons.directions_car_rounded,
                    suffixIcon: _plateCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded,
                                color: Color(0xFF4A4A7A), size: 18),
                            onPressed: () =>
                                setState(() => _plateCtrl.clear()),
                          )
                        : null,
                  ),
                ),

                const SizedBox(height: 14),

                // ── 4. OR Divider ─────────────────────────────────────────
                Row(
                  children: [
                    const Expanded(
                        child: Divider(color: Color(0xFF1E1E3A))),
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 14),
                      child: Text(
                        'OR',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.18),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                    const Expanded(
                        child: Divider(color: Color(0xFF1E1E3A))),
                  ],
                ),

                const SizedBox(height: 14),

                // ── 5. Scan Number Plate Button ───────────────────────────
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.cyanAccent,
                      side: BorderSide(
                        color: _isScanning
                            ? Colors.cyanAccent.withOpacity(0.4)
                            : Colors.cyanAccent,
                        width: 1.5,
                      ),
                      backgroundColor:
                          Colors.cyanAccent.withOpacity(0.05),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: _isScanning ? null : _scanNumberPlate,
                    icon: _isScanning
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              color: Colors.cyanAccent,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(
                            Icons.document_scanner_rounded,
                            size: 20,
                          ),
                    label: Text(
                      _isScanning ? 'SCANNING...' : 'SCAN NUMBER PLATE',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),

                // Scanned image preview (small thumbnail)
                if (_scannedImage != null) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          _scannedImage!,
                          width: 60,
                          height: 40,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Image captured — will be stored in logs.',
                          style: TextStyle(
                              color: Color(0xFF5A5A8A), fontSize: 11),
                        ),
                      ),
                      GestureDetector(
                        onTap: () =>
                            setState(() => _scannedImage = null),
                        child: const Icon(Icons.close_rounded,
                            color: Color(0xFF4A4A6A), size: 16),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 20),

                // ── 6. Notes ──────────────────────────────────────────────
                _label('NOTES (OPTIONAL)'),
                TextFormField(
                  controller: _notesCtrl,
                  focusNode: _notesFocus,
                  maxLines: 2,
                  textInputAction: TextInputAction.done,
                  onEditingComplete: () => FocusScope.of(context).unfocus(),
                  style: const TextStyle(
                      color: Color(0xFFAAAAAA), fontSize: 14),
                  decoration: _inputDec(
                    hint: 'Any additional remarks...',
                    icon: Icons.notes_rounded,
                  ),
                ),

                const SizedBox(height: 28),

                // ── 7. Submit Button ──────────────────────────────────────
                ScaleTransition(
                  scale: _pulseAnim,
                  child: SizedBox(
                    width: double.infinity,
                    height: 58,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isSubmitting
                            ? Colors.cyanAccent.withOpacity(0.6)
                            : Colors.cyanAccent,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        elevation: _isSubmitting ? 0 : 6,
                        shadowColor:
                            Colors.cyanAccent.withOpacity(0.4),
                      ),
                      onPressed: _isSubmitting ? null : _submitEntry,
                      icon: _isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.black54,
                                strokeWidth: 2.5,
                              ),
                            )
                          : const Icon(Icons.check_circle_rounded,
                              size: 22),
                      label: Text(
                        _isSubmitting
                            ? 'LOGGING ENTRY...'
                            : 'SUBMIT ENTRY',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Entry Type Segmented Selector
// ---------------------------------------------------------------------------

class _EntryTypeSelector extends StatelessWidget {
  final EntryType selected;
  final ValueChanged<EntryType> onChanged;

  const _EntryTypeSelector({
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: EntryType.values.asMap().entries.map((entry) {
        final idx = entry.key;
        final type = entry.value;
        final isSelected = type == selected;
        final isLast = idx == EntryType.values.length - 1;

        return Expanded(
          child: GestureDetector(
            onTap: () => onChanged(type),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              margin: EdgeInsets.only(right: isLast ? 0 : 8),
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                gradient: isSelected
                    ? const LinearGradient(
                        colors: [Color(0xFF00E5FF), Color(0xFF00B4D8)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                color: isSelected ? null : const Color(0xFF13132A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected
                      ? Colors.transparent
                      : const Color(0xFF2A2A4A),
                  width: 1,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: Colors.cyanAccent.withOpacity(0.25),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    type.icon,
                    color: isSelected
                        ? Colors.black
                        : const Color(0xFF4A4A7A),
                    size: 22,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    type.label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isSelected
                          ? Colors.black
                          : const Color(0xFF4A4A7A),
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}