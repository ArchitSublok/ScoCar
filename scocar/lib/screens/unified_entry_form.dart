import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../../main.dart' show AppTokens, themeNotifier;

// ─────────────────────────────────────────────────────────────────────────────
// EntryType enum
// ─────────────────────────────────────────────────────────────────────────────
enum EntryType { delivery, visitor, generalMovement }

extension EntryTypeExtension on EntryType {
  String get label {
    switch (this) {
      case EntryType.delivery:      return 'DELIVERY';
      case EntryType.visitor:       return 'VISITOR';
      case EntryType.generalMovement: return 'MOVEMENT';
    }
  }

  String get displayName {
    switch (this) {
      case EntryType.delivery:      return 'Delivery';
      case EntryType.visitor:       return 'Visitor';
      case EntryType.generalMovement: return 'General Movement';
    }
  }

  IconData get icon {
    switch (this) {
      case EntryType.delivery:      return Icons.local_shipping_rounded;
      case EntryType.visitor:       return Icons.person_rounded;
      case EntryType.generalMovement: return Icons.swap_vert_rounded;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Public API
// ─────────────────────────────────────────────────────────────────────────────
class UnifiedEntryForm extends StatefulWidget {
  final String? guardId;
  const UnifiedEntryForm({super.key, this.guardId});

  /// Show the form as a full-height modal bottom sheet.
  ///
  /// FIX: barrierColor is now theme-aware and semi-transparent.
  ///   Light mode → rgba(0,0,0,0.40)  — soft dim, content still visible
  ///   Dark mode  → rgba(0,0,0,0.70)  — deeper mask, still not opaque black
  ///
  /// backgroundColor: Colors.transparent keeps the Container's own rounded
  /// decoration visible; the dimming comes from barrierColor only.
  static Future<void> show(
    BuildContext context, {
    String? guardId,
    EntryType initialType = EntryType.delivery,
  }) {
    final isDark =
        Theme.of(context).brightness == Brightness.dark;

    return showModalBottomSheet(
      context           : context,
      isScrollControlled: true,
      useSafeArea       : true,
      // ── THE FIX: semi-transparent barrier, never pitch black ───────────
      barrierColor      : isDark ? AppTokens.darkBarrier : AppTokens.lightBarrier,
      backgroundColor   : Colors.transparent,
      builder           : (_) => UnifiedEntryForm(guardId: guardId),
    );
  }

  @override
  State<UnifiedEntryForm> createState() => _UnifiedEntryFormState();
}

// ─────────────────────────────────────────────────────────────────────────────
// State
// ─────────────────────────────────────────────────────────────────────────────
class _UnifiedEntryFormState extends State<UnifiedEntryForm>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final _nameCtrl  = TextEditingController();
  final _plateCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  // Focus nodes
  final _nameFocus  = FocusNode();
  final _plateFocus = FocusNode();
  final _notesFocus = FocusNode();

  // State
  EntryType _entryType   = EntryType.delivery;
  bool      _isScanning  = false;
  bool      _isSubmitting= false;
  File?     _scannedImage;

  // Submit button pulse
  late AnimationController _pulseCtrl;
  late Animation<double>   _pulseAnim;

  // ─── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync   : this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.03).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
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

  // ─── OCR / Scan ────────────────────────────────────────────────────────────

  Future<void> _scanNumberPlate() async {
    setState(() => _isScanning = true);
    try {
      final picker = ImagePicker();
      final XFile? photo = await picker.pickImage(
        source               : ImageSource.camera,
        imageQuality         : 90,
        preferredCameraDevice: CameraDevice.rear,
      );
      if (photo == null) return;

      _scannedImage = File(photo.path);
      final inputImage = InputImage.fromFile(_scannedImage!);
      final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final RecognizedText result = await recognizer.processImage(inputImage);
      await recognizer.close();

      final detected = _extractNumberPlate(result.text);
      if (!mounted) return;

      if (detected != null) {
        setState(() => _plateCtrl.text = detected);
        _showSnack('✅ Number plate detected — verify if needed.',
            Colors.green.shade700);
      } else {
        final raw = result.text
            .replaceAll('\n', ' ')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim()
            .toUpperCase();
        if (raw.isNotEmpty) setState(() => _plateCtrl.text = raw);
        _showSnack('⚠️  Plate not recognised — please verify manually.',
            Colors.orange.shade700);
      }
      FocusScope.of(context).requestFocus(_notesFocus);
    } catch (e) {
      if (mounted) _showSnack('Camera error: ${e.toString()}', Colors.red.shade700);
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  /// Indian number-plate regex: Standard / BH-series / old 2-col.
  String? _extractNumberPlate(String raw) {
    final text = raw.toUpperCase().replaceAll(RegExp(r'\s+'), '');
    final patterns = [
      RegExp(r'[A-Z]{2}\d{2}[A-Z]{1,3}\d{4}'),
      RegExp(r'\d{2}BH\d{4}[A-Z]{1,2}'),
      RegExp(r'[A-Z]{2}\d{2}\d{4}'),
    ];
    for (final p in patterns) {
      final m = p.firstMatch(text);
      if (m != null) return m.group(0);
    }
    return null;
  }

  // ─── Submit ─────────────────────────────────────────────────────────────────

  Future<void> _submitEntry() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    try {
      await FirebaseFirestore.instance.collection('logs').add({
        'type'            : 'ENTRY',
        'entryType'       : _entryType.displayName,
        'company'         : _nameCtrl.text.trim(),
        'plateNumber'     : _plateCtrl.text.trim().toUpperCase(),
        'notes'           : _notesCtrl.text.trim(),
        'guardId'         : widget.guardId ?? 'GUARD',
        'scannedImagePath': _scannedImage?.path,
        'timestamp'       : FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(children: [
          const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${_entryType.displayName} entry logged successfully.',
              style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white),
            ),
          ),
        ]),
        backgroundColor: Colors.green.shade700,
        behavior       : SnackBarBehavior.floating,
        shape          : RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin         : const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        duration       : const Duration(seconds: 3),
      ));
    } catch (e) {
      if (mounted) {
        _showSnack('Submission failed: $e', Colors.red.shade700);
        setState(() => _isSubmitting = false);
      }
    }
  }

  // ─── Helpers ────────────────────────────────────────────────────────────────

  void _showSnack(String msg, Color bg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content  : Text(msg, style: const TextStyle(color: Colors.white)),
      backgroundColor: bg,
      behavior : SnackBarBehavior.floating,
      shape    : RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin   : const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    ));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Theme-aware decoration helpers
  // Every color is resolved from AppTokens based on the current brightness.
  // ─────────────────────────────────────────────────────────────────────────

  /// Returns theme-correct InputDecoration.
  InputDecoration _inputDec({
    required String   hint,
    required IconData icon,
    Widget?           suffixIcon,
    bool              isDark = true,
  }) {
    final Color fill      = isDark ? AppTokens.darkFieldFill  : AppTokens.lightFieldFill;
    final Color border    = isDark ? AppTokens.darkBorder     : AppTokens.lightBorder;
    final Color focusBorder= isDark ? AppTokens.darkBorderFocus: AppTokens.lightBorderFocus;
    final Color hintCol   = isDark ? AppTokens.darkTextHint   : AppTokens.lightTextHint;
    final Color iconCol   = isDark ? const Color(0xFF5A6A8A)  : AppTokens.lightTextSecond;

    return InputDecoration(
      hintText       : hint,
      hintStyle      : TextStyle(color: hintCol, fontSize: 14),
      prefixIcon     : Icon(icon, color: iconCol, size: 20),
      suffixIcon     : suffixIcon,
      filled         : true,
      fillColor      : fill,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusInput),
        borderSide  : BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusInput),
        borderSide  : BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusInput),
        borderSide  : BorderSide(color: focusBorder, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusInput),
        borderSide  : const BorderSide(color: Colors.redAccent),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusInput),
        borderSide  : const BorderSide(color: Colors.redAccent, width: 2),
      ),
      errorStyle     : const TextStyle(color: Colors.redAccent, fontSize: 11),
      contentPadding : const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    );
  }

  /// Section label — adapts color to theme.
  Widget _label(String text, {required bool isDark}) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: TextStyle(
        color      : isDark ? const Color(0xFF7A7AAA) : AppTokens.lightTextSecond,
        fontSize   : 11,
        fontWeight : FontWeight.w700,
        letterSpacing: 0.8,
      ),
    ),
  );

  // ─── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Resolve theme once at the top; pass down as `isDark` flag.
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // ── Color tokens for this widget ──────────────────────────────────────
    final Color sheetBg       = isDark ? const Color(0xFF0A0A1A)    : AppTokens.lightSurface;
    final Color sheetBorder   = isDark ? const Color(0xFF1E1E3A)    : AppTokens.lightBorder;
    final Color handleColor   = isDark ? const Color(0xFF2A2A4A)    : AppTokens.lightDivider;
    final Color dividerColor  = isDark ? const Color(0xFF1A1A3A)    : AppTokens.lightDivider;
    final Color titleColor    = isDark ? Colors.white               : AppTokens.lightTextPrimary;
    final Color subtitleColor = isDark ? const Color(0xFF5A5A8A)    : AppTokens.lightTextSecond;
    final Color bodyTextColor = isDark ? Colors.white               : AppTokens.lightTextPrimary;
    final Color notesColor    = isDark ? const Color(0xFFAAAAAA)    : AppTokens.lightTextSecond;
    final Color orDivColor    = isDark
        ? Colors.white.withOpacity(0.18)
        : AppTokens.lightTextHint.withOpacity(0.5);
    final Color scanBtnBorder = isDark ? AppTokens.cyanAction       : AppTokens.lightBorderFocus;
    final Color scanBtnFg     = isDark ? AppTokens.cyanAction       : AppTokens.lightAccent;
    final Color scanBtnFill   = isDark
        ? AppTokens.cyanAction.withOpacity(0.05)
        : AppTokens.lightAccent.withOpacity(0.06);

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Container(
        // ── Modal content card ─────────────────────────────────────────────
        // Light: pure white surface with dark charcoal text
        // Dark : deep navy surface with light text
        decoration: BoxDecoration(
          color        : sheetBg,
          borderRadius : const BorderRadius.vertical(
              top: Radius.circular(AppTokens.radiusSheet)),
          border       : Border(top: BorderSide(color: sheetBorder, width: 1)),
        ),
        padding: EdgeInsets.only(
          left  : 20,
          right : 20,
          top   : 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 28,
        ),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize      : MainAxisSize.min,
              children: [

                // ── Handle bar ───────────────────────────────────────────
                Center(
                  child: Container(
                    width : 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color       : handleColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),

                // ── Header ──────────────────────────────────────────────
                Row(
                  children: [
                    Container(
                      width : 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color       : AppTokens.cyanAction.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.add_circle_outline_rounded,
                          color: AppTokens.cyanAction, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('NEW ENTRY LOG',
                            style: TextStyle(
                              color     : titleColor,
                              fontSize  : 17,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.2,
                            )),
                        Text('Fill details or scan number plate',
                            style: TextStyle(color: subtitleColor, fontSize: 12)),
                      ],
                    ),
                    // Theme toggle inside the sheet
                    const Spacer(),
                    ValueListenableBuilder<ThemeMode>(
                      valueListenable: themeNotifier,
                      builder: (_, mode, __) => GestureDetector(
                        onTap: () {
                          themeNotifier.value = mode == ThemeMode.dark
                              ? ThemeMode.light
                              : ThemeMode.dark;
                        },
                        child: Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withOpacity(0.06)
                                : AppTokens.lightBorder.withOpacity(0.4),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            mode == ThemeMode.dark
                                ? Icons.light_mode_rounded
                                : Icons.dark_mode_rounded,
                            size : 18,
                            color: isDark ? Colors.white54 : AppTokens.lightTextSecond,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),
                Divider(color: dividerColor, height: 1),
                const SizedBox(height: 20),

                // ── 1. Entry Type ────────────────────────────────────────
                _label('ENTRY TYPE', isDark: isDark),
                _EntryTypeSelector(
                  selected : _entryType,
                  onChanged: (t) => setState(() => _entryType = t),
                  isDark   : isDark,
                ),
                const SizedBox(height: 22),

                // ── 2. Company / Visitor Name ────────────────────────────
                _label('COMPANY / VISITOR NAME *', isDark: isDark),
                TextFormField(
                  controller     : _nameCtrl,
                  focusNode      : _nameFocus,
                  textInputAction: TextInputAction.next,
                  onEditingComplete: () =>
                      FocusScope.of(context).requestFocus(_plateFocus),
                  style    : TextStyle(color: bodyTextColor, fontSize: 15),
                  decoration: _inputDec(
                    hint  : 'Enter company or visitor name',
                    icon  : Icons.badge_rounded,
                    isDark: isDark,
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Name is required' : null,
                ),
                const SizedBox(height: 18),

                // ── 3. Vehicle Number Plate ──────────────────────────────
                _label('VEHICLE NUMBER PLATE', isDark: isDark),
                TextFormField(
                  controller     : _plateCtrl,
                  focusNode      : _plateFocus,
                  textInputAction: TextInputAction.next,
                  onEditingComplete: () =>
                      FocusScope.of(context).requestFocus(_notesFocus),
                  style: TextStyle(
                    color      : isDark ? AppTokens.cyanAction : AppTokens.lightAccent,
                    fontSize   : 17,
                    fontWeight : FontWeight.bold,
                    letterSpacing: 2.5,
                  ),
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [
                    TextInputFormatter.withFunction(
                      (old, newVal) => newVal.copyWith(
                          text: newVal.text.toUpperCase()),
                    ),
                  ],
                  decoration: _inputDec(
                    hint  : 'e.g. MH12AB1234',
                    icon  : Icons.directions_car_rounded,
                    isDark: isDark,
                    suffixIcon: _plateCtrl.text.isNotEmpty
                        ? IconButton(
                            icon : Icon(Icons.clear_rounded,
                                color: isDark
                                    ? const Color(0xFF4A4A7A)
                                    : AppTokens.lightTextSecond,
                                size: 18),
                            onPressed: () =>
                                setState(() => _plateCtrl.clear()),
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 14),

                // ── OR divider ───────────────────────────────────────────
                Row(children: [
                  Expanded(child: Divider(color: dividerColor)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Text('OR',
                        style: TextStyle(
                          color      : orDivColor,
                          fontSize   : 11,
                          fontWeight : FontWeight.w700,
                          letterSpacing: 1.5,
                        )),
                  ),
                  Expanded(child: Divider(color: dividerColor)),
                ]),
                const SizedBox(height: 14),

                // ── 4. Scan button ───────────────────────────────────────
                SizedBox(
                  width : double.infinity,
                  height: 52,
                  child : OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: scanBtnFg,
                      side           : BorderSide(
                        color: _isScanning
                            ? scanBtnBorder.withOpacity(0.4)
                            : scanBtnBorder,
                        width: 1.5,
                      ),
                      backgroundColor: scanBtnFill,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppTokens.radiusInput)),
                    ),
                    onPressed: _isScanning ? null : _scanNumberPlate,
                    icon : _isScanning
                        ? SizedBox(
                            width : 18, height: 18,
                            child : CircularProgressIndicator(
                                color: scanBtnFg, strokeWidth: 2),
                          )
                        : const Icon(Icons.document_scanner_rounded, size: 20),
                    label: Text(
                      _isScanning ? 'SCANNING...' : 'SCAN NUMBER PLATE',
                      style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                          fontSize: 13),
                    ),
                  ),
                ),

                // Scanned image thumbnail
                if (_scannedImage != null) ...[
                  const SizedBox(height: 10),
                  Row(children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(_scannedImage!,
                          width: 60, height: 40, fit: BoxFit.cover),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Image captured — will be stored in logs.',
                        style: TextStyle(
                            color: subtitleColor, fontSize: 11),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => setState(() => _scannedImage = null),
                      child: Icon(Icons.close_rounded,
                          color: subtitleColor, size: 16),
                    ),
                  ]),
                ],
                const SizedBox(height: 20),

                // ── 5. Notes ─────────────────────────────────────────────
                _label('NOTES (OPTIONAL)', isDark: isDark),
                TextFormField(
                  controller     : _notesCtrl,
                  focusNode      : _notesFocus,
                  maxLines       : 2,
                  textInputAction: TextInputAction.done,
                  onEditingComplete: () => FocusScope.of(context).unfocus(),
                  style    : TextStyle(color: notesColor, fontSize: 14),
                  decoration: _inputDec(
                    hint  : 'Any additional remarks...',
                    icon  : Icons.notes_rounded,
                    isDark: isDark,
                  ),
                ),
                const SizedBox(height: 28),

                // ── 6. Submit ────────────────────────────────────────────
                ScaleTransition(
                  scale: _pulseAnim,
                  child: SizedBox(
                    width : double.infinity,
                    height: 58,
                    child : ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isSubmitting
                            ? AppTokens.cyanAction.withOpacity(0.6)
                            : AppTokens.cyanAction,
                        foregroundColor: AppTokens.cyanActionText,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppTokens.radiusButton)),
                        elevation  : _isSubmitting ? 0 : 6,
                        shadowColor: AppTokens.cyanAction.withOpacity(0.4),
                      ),
                      onPressed: _isSubmitting ? null : _submitEntry,
                      icon : _isSubmitting
                          ? const SizedBox(
                              width : 20, height: 20,
                              child : CircularProgressIndicator(
                                  color: Colors.black54, strokeWidth: 2.5),
                            )
                          : const Icon(Icons.check_circle_rounded, size: 22),
                      label: Text(
                        _isSubmitting ? 'LOGGING ENTRY...' : 'SUBMIT ENTRY',
                        style: const TextStyle(
                          fontWeight  : FontWeight.w900,
                          letterSpacing: 1.2,
                          fontSize    : 15,
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

// ─────────────────────────────────────────────────────────────────────────────
// _EntryTypeSelector — theme-aware segmented control
// ─────────────────────────────────────────────────────────────────────────────
class _EntryTypeSelector extends StatelessWidget {
  final EntryType                selected;
  final ValueChanged<EntryType>  onChanged;
  final bool                     isDark;

  const _EntryTypeSelector({
    required this.selected,
    required this.onChanged,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: EntryType.values.asMap().entries.map((entry) {
        final idx        = entry.key;
        final type       = entry.value;
        final isSelected = type == selected;
        final isLast     = idx == EntryType.values.length - 1;

        // Idle colors differ between light and dark
        final Color idleBg     = isDark
            ? const Color(0xFF13132A)
            : AppTokens.lightDivider.withOpacity(0.5);
        final Color idleBorder = isDark
            ? const Color(0xFF2A2A4A)
            : AppTokens.lightBorder;
        final Color idleIcon   = isDark
            ? const Color(0xFF4A4A7A)
            : AppTokens.lightTextSecond;
        final Color idleText   = isDark
            ? const Color(0xFF4A4A7A)
            : AppTokens.lightTextSecond;

        return Expanded(
          child: GestureDetector(
            onTap: () => onChanged(type),
            child: AnimatedContainer(
              duration : const Duration(milliseconds: 200),
              curve    : Curves.easeOut,
              margin   : EdgeInsets.only(right: isLast ? 0 : 8),
              padding  : const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                gradient: isSelected
                    ? const LinearGradient(
                        colors: [Color(0xFF00E5FF), Color(0xFF00B4D8)],
                        begin : Alignment.topLeft,
                        end   : Alignment.bottomRight,
                      )
                    : null,
                color       : isSelected ? null : idleBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? Colors.transparent : idleBorder,
                  width: 1,
                ),
                boxShadow: isSelected
                    ? [BoxShadow(
                        color     : AppTokens.cyanAction.withOpacity(0.25),
                        blurRadius: 10,
                        offset    : const Offset(0, 4),
                      )]
                    : null,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    type.icon,
                    color: isSelected ? Colors.black : idleIcon,
                    size : 22,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    type.label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color      : isSelected ? Colors.black : idleText,
                      fontSize   : 9,
                      fontWeight : FontWeight.w800,
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
