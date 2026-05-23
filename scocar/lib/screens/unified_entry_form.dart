import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../main.dart' show AppTokens, themeNotifier;

// ─────────────────────────────────────────────────────────────────────────────
// APPROVAL STATE MACHINE
// ─────────────────────────────────────────────────────────────────────────────
enum _ApprovalState { idle, pendingApproval, approved, denied, timedOut }

// ─────────────────────────────────────────────────────────────────────────────
// EntryType — MOVEMENT REMOVED
//
// GeneralMovement has been intentionally removed. Vehicle ENTRY/EXIT is now
// fully automated:
//   ANPR camera → reads plate → matches vehicles collection → writes log
//
// Guards no longer need to manually log vehicle movements. The camera button
// in the AppBar launches VehicleDetectionScreen which does this automatically.
// ─────────────────────────────────────────────────────────────────────────────
enum EntryType { delivery, visitor }

extension EntryTypeExtension on EntryType {
  String get label {
    switch (this) {
      case EntryType.delivery: return 'DELIVERY';
      case EntryType.visitor:  return 'VISITOR';
    }
  }

  String get displayName {
    switch (this) {
      case EntryType.delivery: return 'Delivery';
      case EntryType.visitor:  return 'Visitor';
    }
  }

  IconData get icon {
    switch (this) {
      case EntryType.delivery: return Icons.local_shipping_rounded;
      case EntryType.visitor:  return Icons.person_rounded;
    }
  }

  String get hint {
    switch (this) {
      case EntryType.delivery: return 'e.g. Zomato, Amazon, FedEx...';
      case EntryType.visitor:  return 'Enter visitor full name';
    }
  }

  IconData get nameIcon {
    switch (this) {
      case EntryType.delivery: return Icons.local_shipping_rounded;
      case EntryType.visitor:  return Icons.badge_rounded;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Public API
// ─────────────────────────────────────────────────────────────────────────────
class UnifiedEntryForm extends StatefulWidget {
  final String? guardId;
  const UnifiedEntryForm({super.key, this.guardId});

  static Future<void> show(
    BuildContext context, {
    String? guardId,
    EntryType initialType = EntryType.delivery,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return showModalBottomSheet(
      context            : context,
      isScrollControlled : true,
      useSafeArea        : true,
      barrierColor       : isDark ? AppTokens.darkBarrier : AppTokens.lightBarrier,
      backgroundColor    : Colors.transparent,
      builder            : (_) => UnifiedEntryForm(guardId: guardId),
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

  final _nameCtrl  = TextEditingController();
  final _plateCtrl = TextEditingController();
  final _flatCtrl  = TextEditingController();
  final _notesCtrl = TextEditingController();

  final _nameFocus  = FocusNode();
  final _plateFocus = FocusNode();
  final _flatFocus  = FocusNode();
  final _notesFocus = FocusNode();

  EntryType _entryType  = EntryType.delivery;
  bool      _isScanning = false;

  File? _agentPhoto;
  bool  _isCapturingPhoto = false;
  File? _scannedPlateImage;

  _ApprovalState _approvalState        = _ApprovalState.idle;
  String?        _pendingApprovalDocId;
  StreamSubscription<DocumentSnapshot>? _approvalListener;

  static const int _timeoutSeconds    = 60;
  int    _countdownRemaining          = _timeoutSeconds;
  Timer? _countdownTimer;

  late AnimationController _pulseCtrl;
  late Animation<double>   _pulseAnim;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.03).animate(
        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => FocusScope.of(context).requestFocus(_nameFocus));
  }

  @override
  void dispose() {
    _approvalListener?.cancel();
    _countdownTimer?.cancel();
    for (final c in [_nameCtrl, _plateCtrl, _flatCtrl, _notesCtrl]) {
      c.dispose();
    }
    for (final f in [_nameFocus, _plateFocus, _flatFocus, _notesFocus]) {
      f.dispose();
    }
    _pulseCtrl.dispose();
    super.dispose();
  }

  // ── Photo ──────────────────────────────────────────────────────────────────

  Future<void> _captureAgentPhoto() async {
    setState(() => _isCapturingPhoto = true);
    try {
      final XFile? photo = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        preferredCameraDevice: CameraDevice.front,
      );
      if (!mounted) return;
      if (photo != null) {
        setState(() => _agentPhoto = File(photo.path));
        _showSnack('📸 Photo captured.', Colors.green.shade700);
      }
    } catch (e) {
      if (mounted) _showSnack('Camera error: $e', Colors.red.shade700);
    } finally {
      if (mounted) setState(() => _isCapturingPhoto = false);
    }
  }

  void _retakeAgentPhoto() {
    setState(() => _agentPhoto = null);
    _captureAgentPhoto();
  }

  // ── OCR ────────────────────────────────────────────────────────────────────

  Future<void> _scanNumberPlate() async {
    setState(() => _isScanning = true);
    try {
      final XFile? photo = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 90,
        preferredCameraDevice: CameraDevice.rear,
      );
      if (photo == null) return;
      _scannedPlateImage = File(photo.path);
      final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final result = await recognizer.processImage(
          InputImage.fromFile(_scannedPlateImage!));
      await recognizer.close();
      if (!mounted) return;
      final detected = _extractPlate(result.text);
      if (detected != null) {
        setState(() => _plateCtrl.text = detected);
        _showSnack('✅ Plate detected — verify if needed.', Colors.green.shade700);
      } else {
        final raw = result.text
            .replaceAll('\n', ' ')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim()
            .toUpperCase();
        if (raw.isNotEmpty) setState(() => _plateCtrl.text = raw);
        _showSnack('⚠️ Not recognised — verify manually.', Colors.orange.shade700);
      }
      FocusScope.of(context).requestFocus(_notesFocus);
    } catch (e) {
      if (mounted) _showSnack('Camera error: $e', Colors.red.shade700);
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  String? _extractPlate(String raw) {
    final text = raw.toUpperCase().replaceAll(RegExp(r'\s+'), '');
    for (final p in [
      RegExp(r'[A-Z]{2}\d{2}[A-Z]{1,3}\d{4}'),
      RegExp(r'\d{2}BH\d{4}[A-Z]{1,2}'),
      RegExp(r'[A-Z]{2}\d{2}\d{4}'),
    ]) {
      final m = p.firstMatch(text);
      if (m != null) return m.group(0);
    }
    return null;
  }

  // ── Submit ─────────────────────────────────────────────────────────────────

  Future<void> _onSubmitPressed() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    await _sendApprovalRequest();
  }

  Future<void> _sendApprovalRequest() async {
    setState(() {
      _approvalState      = _ApprovalState.pendingApproval;
      _countdownRemaining = _timeoutSeconds;
    });
    try {
      final docRef = await FirebaseFirestore.instance.collection('approvals').add({
        'status'         : 'PENDING',
        'flatNumber'     : _flatCtrl.text.trim().toUpperCase(),
        'company'        : _nameCtrl.text.trim(),
        'plateNumber'    : _plateCtrl.text.trim().toUpperCase(),
        'guardId'        : widget.guardId ?? 'GUARD',
        'sentBy'         : widget.guardId ?? 'GUARD',
        'photoUrl'       : _agentPhoto?.path
            ?? 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=300',
        'visitorPhotoUrl': _agentPhoto?.path
            ?? 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=300',
        'createdAt'      : FieldValue.serverTimestamp(),
        'entryType'      : _entryType.displayName,
        'driverName'     : _nameCtrl.text.trim().isNotEmpty
            ? _nameCtrl.text.trim() : 'Agent',
        'otpCode'        : (1000 + DateTime.now().millisecond % 9000).toString(),
        'notes'          : _notesCtrl.text.trim(),
        'agentPhotoPath' : _agentPhoto?.path ?? '',
        'plateImagePath' : _scannedPlateImage?.path ?? '',
        'timestamp'      : FieldValue.serverTimestamp(),
        'expiresAt'      : Timestamp.fromDate(
            DateTime.now().add(const Duration(seconds: _timeoutSeconds))),
      });
      _pendingApprovalDocId = docRef.id;
      _startCountdown();
      _approvalListener = docRef.snapshots().listen(
          _onApprovalUpdate,
          onError: (_) { if (mounted) _handleTimeout(); });
    } catch (e) {
      if (mounted) {
        setState(() => _approvalState = _ApprovalState.idle);
        _showSnack('Failed to send: $e', Colors.red.shade700);
      }
    }
  }

  void _onApprovalUpdate(DocumentSnapshot snap) {
    if (!mounted || !snap.exists) return;
    final status = (snap.data() as Map<String, dynamic>?)?['status'] as String? ?? 'PENDING';
    if (status == 'APPROVED') {
      _cancelCountdown();
      _writeApprovedLog();
      setState(() => _approvalState = _ApprovalState.approved);
    } else if (status == 'DENIED') {
      _cancelCountdown();
      setState(() => _approvalState = _ApprovalState.denied);
    }
  }

  Future<void> _writeApprovedLog() async {
    try {
      await FirebaseFirestore.instance.collection('logs').add({
        'type'          : 'ENTRY',
        'entryType'     : _entryType.displayName,
        'driverName'    : _nameCtrl.text.trim().isNotEmpty ? _nameCtrl.text.trim() : 'Agent',
        'company'       : _nameCtrl.text.trim(),
        'plateNumber'   : _plateCtrl.text.trim().toUpperCase(),
        'flatNumber'    : _flatCtrl.text.trim().toUpperCase(),
        'notes'         : _notesCtrl.text.trim(),
        'guardId'       : widget.guardId ?? 'GUARD',
        'agentPhotoPath': _agentPhoto?.path,
        'plateImagePath': _scannedPlateImage?.path,
        'approvalDocId' : _pendingApprovalDocId,
        'timestamp'     : FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Log write failed: $e');
    }
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _countdownRemaining--);
      if (_countdownRemaining <= 0) { t.cancel(); _handleTimeout(); }
    });
  }

  void _cancelCountdown() {
    _countdownTimer?.cancel();
    _approvalListener?.cancel();
  }

  void _handleTimeout() {
    if (!mounted) return;
    _cancelCountdown();
    setState(() => _approvalState = _ApprovalState.timedOut);
    if (_pendingApprovalDocId != null) {
      FirebaseFirestore.instance
          .collection('approvals')
          .doc(_pendingApprovalDocId)
          .update({'status': 'TIMEOUT'}).catchError((_) {});
    }
  }

  void _resetToIdle() {
    _cancelCountdown();
    setState(() {
      _approvalState        = _ApprovalState.idle;
      _pendingApprovalDocId = null;
      _countdownRemaining   = _timeoutSeconds;
    });
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _showSnack(String msg, Color bg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content        : Text(msg, style: const TextStyle(color: Colors.white)),
      backgroundColor: bg,
      behavior       : SnackBarBehavior.floating,
      shape          : RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin         : const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    ));
  }

  InputDecoration _inputDec({
    required String hint, required IconData icon,
    Widget? suffixIcon, bool isDark = true,
  }) {
    final fill   = isDark ? AppTokens.darkFieldFill   : AppTokens.lightFieldFill;
    final border = isDark ? AppTokens.darkBorder      : AppTokens.lightBorder;
    final focus  = isDark ? AppTokens.darkBorderFocus : AppTokens.lightBorderFocus;
    final hint2  = isDark ? AppTokens.darkTextHint    : AppTokens.lightTextHint;
    final ico    = isDark ? const Color(0xFF5A6A8A)   : AppTokens.lightTextSecond;
    return InputDecoration(
      hintText          : hint,
      hintStyle         : TextStyle(color: hint2, fontSize: 14),
      prefixIcon        : Icon(icon, color: ico, size: 20),
      suffixIcon        : suffixIcon,
      filled            : true,
      fillColor         : fill,
      border            : OutlineInputBorder(borderRadius: BorderRadius.circular(AppTokens.radiusInput), borderSide: BorderSide(color: border)),
      enabledBorder     : OutlineInputBorder(borderRadius: BorderRadius.circular(AppTokens.radiusInput), borderSide: BorderSide(color: border)),
      focusedBorder     : OutlineInputBorder(borderRadius: BorderRadius.circular(AppTokens.radiusInput), borderSide: BorderSide(color: focus, width: 2)),
      errorBorder       : OutlineInputBorder(borderRadius: BorderRadius.circular(AppTokens.radiusInput), borderSide: const BorderSide(color: Colors.redAccent)),
      focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTokens.radiusInput), borderSide: const BorderSide(color: Colors.redAccent, width: 2)),
      errorStyle        : const TextStyle(color: Colors.redAccent, fontSize: 11),
      contentPadding    : const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    );
  }

  Widget _label(String t, {required bool isDark}) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(t, style: TextStyle(
      color        : isDark ? const Color(0xFF7A7AAA) : AppTokens.lightTextSecond,
      fontSize     : 11, fontWeight: FontWeight.w700, letterSpacing: 0.8,
    )),
  );

  // ── Build root ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheetBg     = isDark ? const Color(0xFF0A0A1A) : AppTokens.lightSurface;
    final sheetBorder = isDark ? const Color(0xFF1E1E3A) : AppTokens.lightBorder;
    final handle      = isDark ? const Color(0xFF2A2A4A) : AppTokens.lightDivider;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Container(
        decoration: BoxDecoration(
          color: sheetBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(AppTokens.radiusSheet)),
          border: Border(top: BorderSide(color: sheetBorder)),
        ),
        padding: EdgeInsets.only(
          left: 20, right: 20, top: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 28,
        ),
        child: AnimatedSwitcher(
          duration     : const Duration(milliseconds: 320),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position: Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero).animate(anim),
              child: child,
            ),
          ),
          child: _approvalState == _ApprovalState.idle
              ? _buildForm(isDark, handle)
              : _buildOverlay(isDark),
        ),
      ),
    );
  }

  // ── Form ───────────────────────────────────────────────────────────────────

  Widget _buildForm(bool isDark, Color handle) {
    final divCol    = isDark ? const Color(0xFF1A1A3A) : AppTokens.lightDivider;
    final titleCol  = isDark ? Colors.white             : AppTokens.lightTextPrimary;
    final subCol    = isDark ? const Color(0xFF5A5A8A)  : AppTokens.lightTextSecond;
    final bodyCol   = isDark ? Colors.white             : AppTokens.lightTextPrimary;
    final notesCol  = isDark ? const Color(0xFFAAAAAA)  : AppTokens.lightTextSecond;
    final orCol     = isDark ? Colors.white.withOpacity(0.18) : AppTokens.lightTextHint.withOpacity(0.5);
    final scanBdr   = isDark ? AppTokens.cyanAction    : AppTokens.lightBorderFocus;
    final scanFg    = isDark ? AppTokens.cyanAction    : AppTokens.lightAccent;
    final scanFill  = isDark ? AppTokens.cyanAction.withOpacity(0.05) : AppTokens.lightAccent.withOpacity(0.06);

    return SingleChildScrollView(
      key: const ValueKey('form'),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize      : MainAxisSize.min,
          children: [
            // Handle
            Center(child: Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(color: handle, borderRadius: BorderRadius.circular(2)),
            )),

            // Header row
            Row(children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: AppTokens.cyanAction.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.add_circle_outline_rounded, color: AppTokens.cyanAction, size: 20),
              ),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('NEW ENTRY LOG', style: TextStyle(
                    color: titleCol, fontSize: 17, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
                Text('Delivery & Visitor approvals', style: TextStyle(color: subCol, fontSize: 12)),
              ]),
              const Spacer(),
              ValueListenableBuilder<ThemeMode>(
                valueListenable: themeNotifier,
                builder: (_, mode, __) => GestureDetector(
                  onTap: () => themeNotifier.value =
                      mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark,
                  child: Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withOpacity(0.06) : AppTokens.lightBorder.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      mode == ThemeMode.dark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                      size: 18,
                      color: isDark ? Colors.white54 : AppTokens.lightTextSecond,
                    ),
                  ),
                ),
              ),
            ]),

            const SizedBox(height: 16),

            // ── ANPR info banner ────────────────────────────────────────
            _buildAnprBanner(isDark),

            const SizedBox(height: 20),
            Divider(color: divCol, height: 1),
            const SizedBox(height: 20),

            // 1. Entry Type selector (2 options only)
            _label('ENTRY TYPE', isDark: isDark),
            _EntryTypeSelector(
              selected : _entryType,
              onChanged: (t) => setState(() => _entryType = t),
              isDark   : isDark,
            ),
            const SizedBox(height: 22),

            // 2. Photo
            _label(
              _entryType == EntryType.delivery ? 'AGENT PHOTO' : 'VISITOR PHOTO',
              isDark: isDark,
            ),
            _AgentPhotoBox(
              photo        : _agentPhoto,
              isCapturing  : _isCapturingPhoto,
              isDark       : isDark,
              onTakePhoto  : _captureAgentPhoto,
              onRetakePhoto: _retakeAgentPhoto,
              onClearPhoto : () => setState(() => _agentPhoto = null),
            ),
            const SizedBox(height: 22),

            // 3. Name
            _label(
              _entryType == EntryType.delivery ? 'COMPANY NAME *' : 'VISITOR NAME *',
              isDark: isDark,
            ),
            TextFormField(
              controller       : _nameCtrl,
              focusNode        : _nameFocus,
              textInputAction  : TextInputAction.next,
              onEditingComplete: () => FocusScope.of(context).requestFocus(_flatFocus),
              style            : TextStyle(color: bodyCol, fontSize: 15),
              decoration: _inputDec(
                  hint: _entryType.hint, icon: _entryType.nameIcon, isDark: isDark),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'This field is required' : null,
            ),
            const SizedBox(height: 18),

            // 4. Flat
            _label('RESIDENT FLAT NUMBER *', isDark: isDark),
            TextFormField(
              controller        : _flatCtrl,
              focusNode         : _flatFocus,
              textInputAction   : TextInputAction.next,
              onEditingComplete : () => FocusScope.of(context).requestFocus(_plateFocus),
              textCapitalization: TextCapitalization.characters,
              inputFormatters   : [TextInputFormatter.withFunction(
                  (o, n) => n.copyWith(text: n.text.toUpperCase()))],
              style: TextStyle(
                color: isDark ? AppTokens.cyanAction : AppTokens.lightAccent,
                fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.5,
              ),
              decoration: _inputDec(
                  hint: 'e.g. A-402', icon: Icons.apartment_rounded, isDark: isDark),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Flat number is required' : null,
            ),
            const SizedBox(height: 18),

            // 5. Plate (optional)
            _label('VEHICLE PLATE (OPTIONAL)', isDark: isDark),
            TextFormField(
              controller        : _plateCtrl,
              focusNode         : _plateFocus,
              textInputAction   : TextInputAction.next,
              onEditingComplete : () => FocusScope.of(context).requestFocus(_notesFocus),
              textCapitalization: TextCapitalization.characters,
              inputFormatters   : [TextInputFormatter.withFunction(
                  (o, n) => n.copyWith(text: n.text.toUpperCase()))],
              style: TextStyle(
                color: isDark ? AppTokens.cyanAction : AppTokens.lightAccent,
                fontSize: 17, fontWeight: FontWeight.bold, letterSpacing: 2.5,
              ),
              decoration: _inputDec(
                hint: 'e.g. MH12AB1234',
                icon: Icons.directions_car_rounded,
                isDark: isDark,
                suffixIcon: _plateCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear_rounded,
                            color: isDark ? const Color(0xFF4A4A7A) : AppTokens.lightTextSecond,
                            size: 18),
                        onPressed: () => setState(() => _plateCtrl.clear()),
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 14),

            // OR divider
            Row(children: [
              Expanded(child: Divider(color: divCol)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Text('OR', style: TextStyle(
                    color: orCol, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
              ),
              Expanded(child: Divider(color: divCol)),
            ]),
            const SizedBox(height: 14),

            // Scan plate button
            SizedBox(
              width: double.infinity, height: 52,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: scanFg,
                  side: BorderSide(
                      color: _isScanning ? scanBdr.withOpacity(0.4) : scanBdr, width: 1.5),
                  backgroundColor: scanFill,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTokens.radiusInput)),
                ),
                onPressed: _isScanning ? null : _scanNumberPlate,
                icon: _isScanning
                    ? SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(color: scanFg, strokeWidth: 2))
                    : const Icon(Icons.document_scanner_rounded, size: 20),
                label: Text(
                  _isScanning ? 'SCANNING...' : 'SCAN PLATE MANUALLY',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, letterSpacing: 1.2, fontSize: 13),
                ),
              ),
            ),

            if (_scannedPlateImage != null) ...[
              const SizedBox(height: 10),
              Row(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(_scannedPlateImage!, width: 60, height: 40, fit: BoxFit.cover),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text('Plate image captured.',
                    style: TextStyle(color: subCol, fontSize: 11))),
                GestureDetector(
                  onTap: () => setState(() => _scannedPlateImage = null),
                  child: Icon(Icons.close_rounded, color: subCol, size: 16),
                ),
              ]),
            ],
            const SizedBox(height: 20),

            // Notes
            _label('NOTES (OPTIONAL)', isDark: isDark),
            TextFormField(
              controller       : _notesCtrl,
              focusNode        : _notesFocus,
              maxLines         : 2,
              textInputAction  : TextInputAction.done,
              onEditingComplete: () => FocusScope.of(context).unfocus(),
              style            : TextStyle(color: notesCol, fontSize: 14),
              decoration: _inputDec(
                  hint: 'Any additional remarks...', icon: Icons.notes_rounded, isDark: isDark),
            ),
            const SizedBox(height: 28),

            // Submit
            ScaleTransition(
              scale: _pulseAnim,
              child: SizedBox(
                width: double.infinity, height: 58,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTokens.cyanAction,
                    foregroundColor: AppTokens.cyanActionText,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppTokens.radiusButton)),
                    elevation: 6,
                    shadowColor: AppTokens.cyanAction.withOpacity(0.4),
                  ),
                  onPressed: _onSubmitPressed,
                  icon : const Icon(Icons.send_rounded, size: 22),
                  label: const Text('SEND APPROVAL REQUEST',
                      style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.1, fontSize: 15)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── ANPR info banner ────────────────────────────────────────────────────────

  Widget _buildAnprBanner(bool isDark) {
    final bg     = isDark ? const Color(0xFF0D1F2D) : const Color(0xFFE8F4FD);
    final border = isDark ? const Color(0xFF1A3A50) : const Color(0xFFB3D9F5);
    final ico    = isDark ? const Color(0xFF38BDF8) : const Color(0xFF0369A1);
    final title  = isDark ? const Color(0xFF7DD3FC) : const Color(0xFF0369A1);
    final sub    = isDark ? const Color(0xFF4A90AA) : const Color(0xFF5B9CBD);

    return Container(
      width  : double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color       : bg,
        borderRadius: BorderRadius.circular(12),
        border      : Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: ico.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
            child: Icon(Icons.videocam_rounded, color: ico, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('🚗  Vehicle Movement is Automated',
                  style: TextStyle(color: title, fontWeight: FontWeight.bold, fontSize: 12.5)),
              const SizedBox(height: 4),
              Text(
                'The ANPR camera reads each number plate, matches it to the registered vehicles list, and auto-logs ENTRY or EXIT — no manual guard input needed.',
                style: TextStyle(color: sub, fontSize: 11, height: 1.45),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  // ── Approval overlay ────────────────────────────────────────────────────────

  Widget _buildOverlay(bool isDark) => SizedBox(
    key  : const ValueKey('overlay'),
    width: double.infinity,
    child: _ApprovalOverlay(
      state             : _approvalState,
      countdownRemaining: _countdownRemaining,
      totalSeconds      : _timeoutSeconds,
      flatNumber        : _flatCtrl.text.trim().toUpperCase(),
      company           : _nameCtrl.text.trim(),
      isDark            : isDark,
      onRetry           : _resetToIdle,
      onClose           : () => Navigator.pop(context),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// _AgentPhotoBox
// ─────────────────────────────────────────────────────────────────────────────
class _AgentPhotoBox extends StatelessWidget {
  final File? photo; final bool isCapturing; final bool isDark;
  final VoidCallback onTakePhoto, onRetakePhoto, onClearPhoto;

  const _AgentPhotoBox({
    required this.photo, required this.isCapturing, required this.isDark,
    required this.onTakePhoto, required this.onRetakePhoto, required this.onClearPhoto,
  });

  @override
  Widget build(BuildContext context) {
    final bg  = isDark ? const Color(0xFF12122A) : const Color(0xFFF8FAFF);
    final bdr = isDark ? const Color(0xFF2E2E5E) : AppTokens.lightBorder;
    final ico = isDark ? const Color(0xFF4A4A8A) : AppTokens.lightTextSecond;
    final lbl = isDark ? const Color(0xFF6A6A9A) : AppTokens.lightTextSecond;

    return Container(
      width: double.infinity, height: 180,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppTokens.radiusCard),
        border: Border.all(
          color: photo != null ? AppTokens.cyanAction.withOpacity(0.5) : bdr,
          width: photo != null ? 1.5 : 1.0,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTokens.radiusCard - 1),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: isCapturing ? _capturing() : photo == null ? _empty(ico, lbl) : _captured(),
        ),
      ),
    );
  }

  Widget _empty(Color ico, Color lbl) => GestureDetector(
    key: const ValueKey('e'), onTap: onTakePhoto, behavior: HitTestBehavior.opaque,
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.camera_alt_rounded, size: 48, color: ico),
      const SizedBox(height: 12),
      Text('Tap to take photo',
          style: TextStyle(color: lbl, fontSize: 13, fontWeight: FontWeight.w600)),
      const SizedBox(height: 4),
      Text('Front camera will open',
          style: TextStyle(color: lbl.withOpacity(0.6), fontSize: 11)),
    ]),
  );

  Widget _capturing() => Center(
    key: const ValueKey('c'),
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const CircularProgressIndicator(color: AppTokens.cyanAction, strokeWidth: 2.5),
      const SizedBox(height: 14),
      Text('Opening camera...',
          style: TextStyle(color: isDark ? Colors.white54 : AppTokens.lightTextSecond, fontSize: 13)),
    ]),
  );

  Widget _captured() => Stack(
    key: const ValueKey('p'), fit: StackFit.expand,
    children: [
      Image.file(photo!, fit: BoxFit.cover),
      Positioned(left: 0, right: 0, bottom: 0, child: Container(
        height: 60,
        decoration: const BoxDecoration(gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.black87])),
      )),
      Positioned(left: 10, right: 10, bottom: 10, child: Row(children: [
        Expanded(child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: const BorderSide(color: Colors.white60),
            backgroundColor: Colors.black45,
            padding: const EdgeInsets.symmetric(vertical: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: onRetakePhoto,
          icon: const Icon(Icons.refresh_rounded, size: 16),
          label: const Text('Retake', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        )),
        const SizedBox(width: 8),
        IconButton(
          onPressed: onClearPhoto,
          icon: const Icon(Icons.close_rounded, color: Colors.white70),
          style: IconButton.styleFrom(
            backgroundColor: Colors.black45,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            padding: const EdgeInsets.all(6),
          ),
        ),
      ])),
      Positioned(top: 10, right: 10, child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: Colors.green.shade700, borderRadius: BorderRadius.circular(8)),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.check_circle_rounded, size: 12, color: Colors.white),
          SizedBox(width: 4),
          Text('CAPTURED', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
        ]),
      )),
    ],
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// _EntryTypeSelector — ONLY Delivery & Visitor, no Movement tab
// ─────────────────────────────────────────────────────────────────────────────
class _EntryTypeSelector extends StatelessWidget {
  final EntryType selected;
  final ValueChanged<EntryType> onChanged;
  final bool isDark;
  const _EntryTypeSelector({required this.selected, required this.onChanged, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: EntryType.values.asMap().entries.map((e) {
        final idx        = e.key;
        final type       = e.value;
        final isSel      = type == selected;
        final isLast     = idx == EntryType.values.length - 1;
        final idleBg     = isDark ? const Color(0xFF13132A) : AppTokens.lightDivider.withOpacity(0.5);
        final idleBdr    = isDark ? const Color(0xFF2A2A4A) : AppTokens.lightBorder;
        final idleIco    = isDark ? const Color(0xFF4A4A7A) : AppTokens.lightTextSecond;
        final idleTxt    = isDark ? const Color(0xFF4A4A7A) : AppTokens.lightTextSecond;

        return Expanded(
          child: GestureDetector(
            onTap: () => onChanged(type),
            child: AnimatedContainer(
              duration    : const Duration(milliseconds: 200),
              curve       : Curves.easeOut,
              margin      : EdgeInsets.only(right: isLast ? 0 : 14),
              padding     : const EdgeInsets.symmetric(vertical: 20),
              decoration: BoxDecoration(
                gradient: isSel ? const LinearGradient(
                    colors: [Color(0xFF00E5FF), Color(0xFF00B4D8)],
                    begin: Alignment.topLeft, end: Alignment.bottomRight) : null,
                color       : isSel ? null : idleBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: isSel ? Colors.transparent : idleBdr),
                boxShadow: isSel ? [BoxShadow(
                    color: AppTokens.cyanAction.withOpacity(0.25),
                    blurRadius: 10, offset: const Offset(0, 4))] : null,
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(type.icon, color: isSel ? Colors.black : idleIco, size: 28),
                const SizedBox(height: 8),
                Text(type.label, textAlign: TextAlign.center, style: TextStyle(
                    color: isSel ? Colors.black : idleTxt,
                    fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
              ]),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ApprovalOverlay
// ─────────────────────────────────────────────────────────────────────────────
class _ApprovalOverlay extends StatefulWidget {
  final _ApprovalState state; final int countdownRemaining; final int totalSeconds;
  final String flatNumber; final String company; final bool isDark;
  final VoidCallback onRetry; final VoidCallback onClose;

  const _ApprovalOverlay({
    required this.state, required this.countdownRemaining, required this.totalSeconds,
    required this.flatNumber, required this.company, required this.isDark,
    required this.onRetry, required this.onClose,
  });
  @override State<_ApprovalOverlay> createState() => _ApprovalOverlayState();
}

class _ApprovalOverlayState extends State<_ApprovalOverlay> with SingleTickerProviderStateMixin {
  late AnimationController _spin;
  @override void initState() { super.initState(); _spin = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(); }
  @override void dispose() { _spin.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 10),
    child: AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      child: _content(),
    ),
  );

  Widget _content() {
    switch (widget.state) {
      case _ApprovalState.pendingApproval: return _pending();
      case _ApprovalState.approved:        return _approved();
      case _ApprovalState.denied:          return _denied();
      case _ApprovalState.timedOut:        return _timedOut();
      case _ApprovalState.idle:            return const SizedBox.shrink();
    }
  }

  Widget _pending() {
    final p       = widget.countdownRemaining / widget.totalSeconds;
    final urgent  = widget.countdownRemaining <= 15;
    final arc     = urgent ? Colors.redAccent : AppTokens.cyanAction;
    final txt     = widget.isDark ? Colors.white : AppTokens.lightTextPrimary;
    final sub     = widget.isDark ? Colors.white60 : AppTokens.lightTextSecond;
    return Column(key: const ValueKey('pend'), mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center, children: [
      SizedBox(width: 120, height: 120, child: Stack(alignment: Alignment.center, children: [
        CircularProgressIndicator(value: 1.0, strokeWidth: 8,
            valueColor: AlwaysStoppedAnimation(widget.isDark ? Colors.white.withOpacity(0.08) : Colors.grey.shade200)),
        CircularProgressIndicator(value: p, strokeWidth: 8, strokeCap: StrokeCap.round,
            valueColor: AlwaysStoppedAnimation(arc)),
        RotationTransition(turns: _spin, child: SizedBox(width: 80, height: 80,
            child: CircularProgressIndicator(strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(arc.withOpacity(0.3))))),
        Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${widget.countdownRemaining}', style: TextStyle(
              color: urgent ? Colors.redAccent : arc, fontSize: 28, fontWeight: FontWeight.bold)),
          Text('sec', style: TextStyle(color: sub, fontSize: 11)),
        ]),
      ])),
      const SizedBox(height: 28),
      Text('Waiting for Resident Response',
          style: TextStyle(color: txt, fontSize: 18, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center),
      const SizedBox(height: 8),
      Text('Approval request sent to Flat ${widget.flatNumber}.\nResident will be notified on their dashboard.',
          style: TextStyle(color: sub, fontSize: 13, height: 1.5), textAlign: TextAlign.center),
      const SizedBox(height: 20),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(color: AppTokens.cyanAction.withOpacity(0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTokens.cyanAction.withOpacity(0.25))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.local_shipping_rounded, size: 14, color: AppTokens.cyanAction.withOpacity(0.7)),
          const SizedBox(width: 8),
          Text(widget.company, style: const TextStyle(color: AppTokens.cyanAction, fontSize: 13, fontWeight: FontWeight.bold)),
        ]),
      ),
      if (urgent) ...[const SizedBox(height: 16),
        const Text('⚠️  Expiring soon!', style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold))],
    ]);
  }

  Widget _approved() => Column(key: const ValueKey('app'), mainAxisSize: MainAxisSize.min,
    mainAxisAlignment: MainAxisAlignment.center, children: [
    Container(width: 96, height: 96, decoration: BoxDecoration(shape: BoxShape.circle,
        color: Colors.green.withOpacity(0.12),
        boxShadow: [BoxShadow(color: Colors.green.withOpacity(0.3), blurRadius: 28, spreadRadius: 4)]),
        child: const Icon(Icons.check_circle_rounded, size: 54, color: Colors.greenAccent)),
    const SizedBox(height: 28),
    const Text('Entry Approved!', style: TextStyle(color: Colors.greenAccent, fontSize: 22, fontWeight: FontWeight.bold)),
    const SizedBox(height: 10),
    Text('Resident of Flat ${widget.flatNumber} accepted.\nEntry has been logged successfully.',
        style: TextStyle(color: widget.isDark ? Colors.white60 : AppTokens.lightTextSecond, fontSize: 13, height: 1.5),
        textAlign: TextAlign.center),
    const SizedBox(height: 32),
    SizedBox(width: double.infinity, height: 52, child: ElevatedButton.icon(
      style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent, foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTokens.radiusButton)), elevation: 0),
      onPressed: widget.onClose,
      icon: const Icon(Icons.done_rounded, size: 20),
      label: const Text('DONE', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
    )),
  ]);

  Widget _denied() => Column(key: const ValueKey('den'), mainAxisSize: MainAxisSize.min,
    mainAxisAlignment: MainAxisAlignment.center, children: [
    Container(width: 96, height: 96, decoration: BoxDecoration(shape: BoxShape.circle,
        color: Colors.red.withOpacity(0.12),
        boxShadow: [BoxShadow(color: Colors.red.withOpacity(0.25), blurRadius: 24, spreadRadius: 4)]),
        child: const Icon(Icons.cancel_rounded, size: 54, color: Colors.redAccent)),
    const SizedBox(height: 28),
    const Text('Entry Denied', style: TextStyle(color: Colors.redAccent, fontSize: 22, fontWeight: FontWeight.bold)),
    const SizedBox(height: 10),
    Text('Resident of Flat ${widget.flatNumber} denied this request.\nThe agent cannot be allowed in.',
        style: TextStyle(color: widget.isDark ? Colors.white60 : AppTokens.lightTextSecond, fontSize: 13, height: 1.5),
        textAlign: TextAlign.center),
    const SizedBox(height: 32),
    _TwoActionRow(primaryLabel: 'NEW ENTRY', primaryColor: AppTokens.cyanAction,
        primaryTextColor: Colors.black, onPrimary: widget.onRetry,
        secondaryLabel: 'CLOSE', secondaryColor: Colors.redAccent, onSecondary: widget.onClose),
  ]);

  Widget _timedOut() => Column(key: const ValueKey('to'), mainAxisSize: MainAxisSize.min,
    mainAxisAlignment: MainAxisAlignment.center, children: [
    Container(width: 96, height: 96, decoration: BoxDecoration(shape: BoxShape.circle,
        color: Colors.orange.withOpacity(0.12),
        boxShadow: [BoxShadow(color: Colors.orange.withOpacity(0.25), blurRadius: 24, spreadRadius: 4)]),
        child: const Icon(Icons.timer_off_rounded, size: 54, color: Colors.orangeAccent)),
    const SizedBox(height: 28),
    const Text('Request Timed Out', style: TextStyle(color: Colors.orangeAccent, fontSize: 22, fontWeight: FontWeight.bold)),
    const SizedBox(height: 10),
    Text('No response from Flat ${widget.flatNumber} within 60 seconds.\nRequest automatically cancelled.',
        style: TextStyle(color: widget.isDark ? Colors.white60 : AppTokens.lightTextSecond, fontSize: 13, height: 1.5),
        textAlign: TextAlign.center),
    const SizedBox(height: 32),
    _TwoActionRow(primaryLabel: 'RETRY', primaryColor: AppTokens.cyanAction,
        primaryTextColor: Colors.black, onPrimary: widget.onRetry,
        secondaryLabel: 'CLOSE', secondaryColor: Colors.white38, onSecondary: widget.onClose),
  ]);
}

// ─────────────────────────────────────────────────────────────────────────────
// _TwoActionRow
// ─────────────────────────────────────────────────────────────────────────────
class _TwoActionRow extends StatelessWidget {
  final String primaryLabel; final Color primaryColor; final Color primaryTextColor;
  final VoidCallback onPrimary; final String secondaryLabel;
  final Color secondaryColor; final VoidCallback onSecondary;

  const _TwoActionRow({
    required this.primaryLabel, required this.primaryColor, required this.primaryTextColor,
    required this.onPrimary, required this.secondaryLabel,
    required this.secondaryColor, required this.onSecondary,
  });

  @override
  Widget build(BuildContext context) => Row(children: [
    Expanded(child: ElevatedButton(
      style: ElevatedButton.styleFrom(backgroundColor: primaryColor, foregroundColor: primaryTextColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTokens.radiusInput)),
          elevation: 0, padding: const EdgeInsets.symmetric(vertical: 14)),
      onPressed: onPrimary,
      child: Text(primaryLabel, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13,
          color: primaryTextColor, letterSpacing: 0.8)),
    )),
    const SizedBox(width: 12),
    Expanded(child: OutlinedButton(
      style: OutlinedButton.styleFrom(foregroundColor: secondaryColor,
          side: BorderSide(color: secondaryColor.withOpacity(0.5)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTokens.radiusInput)),
          padding: const EdgeInsets.symmetric(vertical: 14)),
      onPressed: onSecondary,
      child: Text(secondaryLabel, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: secondaryColor)),
    )),
  ]);
}
