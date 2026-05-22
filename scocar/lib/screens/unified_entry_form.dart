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
//
//   IDLE              — form is being filled in, no request sent yet
//   PENDING_APPROVAL  — request sent to resident, waiting for response
//   APPROVED          — resident accepted; guard may allow entry
//   DENIED            — resident explicitly denied
//   TIMED_OUT         — 60-second TTL expired with no response
//
// Only Delivery and Visitor entries go through the approval flow.
// GeneralMovement writes directly to logs and closes immediately.
// ─────────────────────────────────────────────────────────────────────────────
enum _ApprovalState { idle, pendingApproval, approved, denied, timedOut }

// ─────────────────────────────────────────────────────────────────────────────
// EntryType enum
// ─────────────────────────────────────────────────────────────────────────────
enum EntryType { delivery, visitor, generalMovement }

extension EntryTypeExtension on EntryType {
  String get label {
    switch (this) {
      case EntryType.delivery:        return 'DELIVERY';
      case EntryType.visitor:         return 'VISITOR';
      case EntryType.generalMovement: return 'MOVEMENT';
    }
  }

  String get displayName {
    switch (this) {
      case EntryType.delivery:        return 'Delivery';
      case EntryType.visitor:         return 'Visitor';
      case EntryType.generalMovement: return 'General Movement';
    }
  }

  IconData get icon {
    switch (this) {
      case EntryType.delivery:        return Icons.local_shipping_rounded;
      case EntryType.visitor:         return Icons.person_rounded;
      case EntryType.generalMovement: return Icons.swap_vert_rounded;
    }
  }

  // Whether this entry type requires resident approval before logging
  bool get requiresApproval =>
      this == EntryType.delivery || this == EntryType.visitor;
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
      context           : context,
      isScrollControlled: true,
      useSafeArea       : true,
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

  // ── Text controllers ───────────────────────────────────────────────────────
  final _nameCtrl        = TextEditingController(); // company / visitor name
  final _plateCtrl       = TextEditingController(); // vehicle number plate
  final _flatCtrl        = TextEditingController(); // resident flat number (DELIVERY+VISITOR)
  final _movementFlatCtrl= TextEditingController(); // flat number for MOVEMENT tab
  final _notesCtrl       = TextEditingController();

  // ── Focus nodes ────────────────────────────────────────────────────────────
  final _nameFocus        = FocusNode();
  final _plateFocus       = FocusNode();
  final _flatFocus        = FocusNode();
  final _movementFlatFocus= FocusNode();
  final _notesFocus       = FocusNode();

  // ── Form state (IDLE) ──────────────────────────────────────────────────────
  EntryType _entryType      = EntryType.delivery;
  bool      _isScanning     = false;
  bool      _isMovementEntry = true; // true = Entry, false = Exit

  // ── Delivery agent photo ───────────────────────────────────────────────────
  // Stores the captured image file. Submitted as the file path in the log.
  File? _agentPhoto;       // captured photo of the delivery agent
  bool  _isCapturingPhoto = false;

  // ── Number-plate scan image ────────────────────────────────────────────────
  File? _scannedPlateImage;

  // ── APPROVAL STATE MACHINE ─────────────────────────────────────────────────
  _ApprovalState _approvalState = _ApprovalState.idle;

  // The Firestore document ID of the pending approval record.
  // Used to listen for real-time status changes and to clean up on cancel.
  String? _pendingApprovalDocId;

  // Real-time Firestore listener subscription
  StreamSubscription<DocumentSnapshot>? _approvalListener;

  // 60-second countdown timer
  static const int _timeoutSeconds = 60;
  int    _countdownRemaining = _timeoutSeconds;
  Timer? _countdownTimer;

  // ── Submit button pulse animation ──────────────────────────────────────────
  late AnimationController _pulseCtrl;
  late Animation<double>   _pulseAnim;

  // ─────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────────────────

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
    // Cancel all async resources before unmounting
    _approvalListener?.cancel();
    _countdownTimer?.cancel();
    _nameCtrl.dispose();
    _plateCtrl.dispose();
    _flatCtrl.dispose();
    _movementFlatCtrl.dispose();
    _notesCtrl.dispose();
    _nameFocus.dispose();
    _plateFocus.dispose();
    _flatFocus.dispose();
    _movementFlatFocus.dispose();
    _notesFocus.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Feature 1 — Delivery Agent Photo Capture
  // ─────────────────────────────────────────────────────────────────────────

  /// Opens the front camera to take a photo of the delivery agent.
  /// Stores the captured File in [_agentPhoto].
  /// Shows a "Retake" option by simply calling this again.
  Future<void> _captureAgentPhoto() async {
    setState(() => _isCapturingPhoto = true);
    try {
      final picker = ImagePicker();
      final XFile? photo = await picker.pickImage(
        source               : ImageSource.camera,
        imageQuality         : 85,
        // Front camera to capture the agent's face
        preferredCameraDevice: CameraDevice.front,
      );
      if (!mounted) return;
      if (photo != null) {
        setState(() => _agentPhoto = File(photo.path));
        _showSnack('📸 Agent photo captured.', Colors.green.shade700);
      }
    } catch (e) {
      if (mounted) {
        _showSnack('Camera error: ${e.toString()}', Colors.red.shade700);
      }
    } finally {
      if (mounted) setState(() => _isCapturingPhoto = false);
    }
  }

  void _retakeAgentPhoto() {
    setState(() => _agentPhoto = null);
    _captureAgentPhoto();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // OCR — Number plate scan (rear camera)
  // ─────────────────────────────────────────────────────────────────────────

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

      _scannedPlateImage = File(photo.path);
      final inputImage = InputImage.fromFile(_scannedPlateImage!);
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
        _showSnack(
            '⚠️ Plate not recognised — please verify manually.',
            Colors.orange.shade700);
      }
      FocusScope.of(context).requestFocus(_notesFocus);
    } catch (e) {
      if (mounted) {
        _showSnack('Camera error: ${e.toString()}', Colors.red.shade700);
      }
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  /// Indian number-plate regex: Standard / BH-series
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

  // ─────────────────────────────────────────────────────────────────────────
  // SUBMIT — state transitions
  //
  // For GeneralMovement:
  //   IDLE → write logs → close modal
  //
  // For Delivery / Visitor:
  //   IDLE → write approval request to Firestore → PENDING_APPROVAL
  //   PENDING_APPROVAL → listen for doc change →
  //       APPROVED  (resident accepted)
  //       DENIED    (resident denied)
  //       TIMED_OUT (60 s elapsed with no answer)
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _onSubmitPressed() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    if (_entryType == EntryType.generalMovement) {
      // ── Direct log — no approval needed ────────────────────────────────
      await _writeMovementLog();
    } else {
      // ── Approval flow ───────────────────────────────────────────────────
      await _sendApprovalRequest();
    }
  }

  // ─── Direct movement log ─────────────────────────────────────────────────

  Future<void> _writeMovementLog() async {
    setState(() => _approvalState = _ApprovalState.pendingApproval);
    final String movFlat = _movementFlatCtrl.text.trim().toUpperCase();
    final String movType = _isMovementEntry ? 'ENTRY' : 'EXIT';
    try {
      await FirebaseFirestore.instance.collection('logs').add({
        'type'        : movType,
        'entryType'   : _entryType.displayName,
        'movement_type': movType,
        'visitor_name': _nameCtrl.text.trim(),
        'company'     : _nameCtrl.text.trim(),
        'plateNumber' : _plateCtrl.text.trim().toUpperCase(),
        'vehicle_number': _plateCtrl.text.trim().toUpperCase(),
        'notes'       : _notesCtrl.text.trim(),
        'guardId'     : widget.guardId ?? 'GUARD',
        'flatNumber'  : movFlat,
        'flat_number' : movFlat,
        'timestamp'   : FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      Navigator.pop(context);
      _showSnack('✅ Movement $movType logged for Flat $movFlat.', Colors.green.shade700);
    } catch (e) {
      if (mounted) {
        setState(() => _approvalState = _ApprovalState.idle);
        _showSnack('Log failed: $e', Colors.red.shade700);
      }
    }
  }

  // ─── PENDING_APPROVAL — write to Firestore and start listener ────────────

  Future<void> _sendApprovalRequest() async {
    // Transition: IDLE → PENDING_APPROVAL
    setState(() {
      _approvalState       = _ApprovalState.pendingApproval;
      _countdownRemaining  = _timeoutSeconds;
    });

    try {
      // 1. Write the approval request document to Firestore.
      //    The resident's dashboard listens to this collection and shows
      //    the incoming request in real time.
      final docRef = await FirebaseFirestore.instance
          .collection('approvals')
          .add({
        'status'         : 'PENDING',  // resident changes this to APPROVED / DENIED
        'entryType'      : _entryType.displayName,
        'company'        : _nameCtrl.text.trim(),
        'plateNumber'    : _plateCtrl.text.trim().toUpperCase(),
        'flatNumber'     : _flatCtrl.text.trim().toUpperCase(),
        'notes'          : _notesCtrl.text.trim(),
        'guardId'        : widget.guardId ?? 'GUARD',
        'agentPhotoPath' : _agentPhoto?.path,
        'plateImagePath' : _scannedPlateImage?.path,
        'timestamp'      : FieldValue.serverTimestamp(),
        'expiresAt'      : Timestamp.fromDate(
            DateTime.now().add(const Duration(seconds: _timeoutSeconds))),
      });

      _pendingApprovalDocId = docRef.id;

      // 2. Start the 60-second countdown timer.
      _startCountdown();

      // 3. Attach a real-time Firestore listener on the new document.
      //    Any change to the `status` field triggers _onApprovalUpdate().
      _approvalListener = docRef.snapshots().listen(
        _onApprovalUpdate,
        onError: (_) {
          if (mounted) _handleTimeout();
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() => _approvalState = _ApprovalState.idle);
        _showSnack('Failed to send request: $e', Colors.red.shade700);
      }
    }
  }

  // ─── Real-time listener callback ──────────────────────────────────────────

  void _onApprovalUpdate(DocumentSnapshot snap) {
    if (!mounted || !snap.exists) return;

    final data   = snap.data() as Map<String, dynamic>?;
    final status = data?['status'] as String? ?? 'PENDING';

    if (status == 'APPROVED') {
      _cancelCountdown();
      _writeApprovedLog();                    // write final log entry
      setState(() => _approvalState = _ApprovalState.approved);
    } else if (status == 'DENIED') {
      _cancelCountdown();
      setState(() => _approvalState = _ApprovalState.denied);
    }
    // PENDING — keep waiting
  }

  // ─── Write the confirmed log after APPROVED ───────────────────────────────

  Future<void> _writeApprovedLog() async {
    try {
      await FirebaseFirestore.instance.collection('logs').add({
        'type'           : 'ENTRY',
        'entryType'      : _entryType.displayName,
        'company'        : _nameCtrl.text.trim(),
        'plateNumber'    : _plateCtrl.text.trim().toUpperCase(),
        'flatNumber'     : _flatCtrl.text.trim().toUpperCase(),
        'notes'          : _notesCtrl.text.trim(),
        'guardId'        : widget.guardId ?? 'GUARD',
        'agentPhotoPath' : _agentPhoto?.path,
        'plateImagePath' : _scannedPlateImage?.path,
        'approvalDocId'  : _pendingApprovalDocId,
        'timestamp'      : FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Log write after approval failed: $e');
    }
  }

  // ─── Countdown timer ─────────────────────────────────────────────────────

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _countdownRemaining--);
      if (_countdownRemaining <= 0) {
        t.cancel();
        _handleTimeout();
      }
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

    // Mark the Firestore document as expired so the resident's app cleans up
    if (_pendingApprovalDocId != null) {
      FirebaseFirestore.instance
          .collection('approvals')
          .doc(_pendingApprovalDocId)
          .update({'status': 'TIMEOUT'})
          .catchError((_) {});
    }
  }

  // ─── Reset back to IDLE to retry ─────────────────────────────────────────

  void _resetToIdle() {
    _cancelCountdown();
    setState(() {
      _approvalState        = _ApprovalState.idle;
      _pendingApprovalDocId = null;
      _countdownRemaining   = _timeoutSeconds;
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────────

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
    required String   hint,
    required IconData icon,
    Widget?           suffixIcon,
    bool              isDark = true,
  }) {
    final Color fill       = isDark ? AppTokens.darkFieldFill   : AppTokens.lightFieldFill;
    final Color border     = isDark ? AppTokens.darkBorder      : AppTokens.lightBorder;
    final Color focusBorder= isDark ? AppTokens.darkBorderFocus : AppTokens.lightBorderFocus;
    final Color hintCol    = isDark ? AppTokens.darkTextHint    : AppTokens.lightTextHint;
    final Color iconCol    = isDark ? const Color(0xFF5A6A8A)   : AppTokens.lightTextSecond;

    return InputDecoration(
      hintText          : hint,
      hintStyle         : TextStyle(color: hintCol, fontSize: 14),
      prefixIcon        : Icon(icon, color: iconCol, size: 20),
      suffixIcon        : suffixIcon,
      filled            : true,
      fillColor         : fill,
      border            : OutlineInputBorder(borderRadius: BorderRadius.circular(AppTokens.radiusInput), borderSide: BorderSide(color: border)),
      enabledBorder     : OutlineInputBorder(borderRadius: BorderRadius.circular(AppTokens.radiusInput), borderSide: BorderSide(color: border)),
      focusedBorder     : OutlineInputBorder(borderRadius: BorderRadius.circular(AppTokens.radiusInput), borderSide: BorderSide(color: focusBorder, width: 2)),
      errorBorder       : OutlineInputBorder(borderRadius: BorderRadius.circular(AppTokens.radiusInput), borderSide: const BorderSide(color: Colors.redAccent)),
      focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTokens.radiusInput), borderSide: const BorderSide(color: Colors.redAccent, width: 2)),
      errorStyle        : const TextStyle(color: Colors.redAccent, fontSize: 11),
      contentPadding    : const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    );
  }

  Widget _label(String text, {required bool isDark}) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: TextStyle(
      color        : isDark ? const Color(0xFF7A7AAA) : AppTokens.lightTextSecond,
      fontSize     : 11,
      fontWeight   : FontWeight.w700,
      letterSpacing: 0.8,
    )),
  );

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD ROOT
  //
  // The root Container always shows. Inside it, we switch between:
  //   _buildForm()          — _ApprovalState.idle
  //   _buildApprovalOverlay — everything else
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final Color sheetBg     = isDark ? const Color(0xFF0A0A1A) : AppTokens.lightSurface;
    final Color sheetBorder = isDark ? const Color(0xFF1E1E3A) : AppTokens.lightBorder;
    final Color handleColor = isDark ? const Color(0xFF2A2A4A) : AppTokens.lightDivider;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Container(
        decoration: BoxDecoration(
          color       : sheetBg,
          borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppTokens.radiusSheet)),
          border: Border(top: BorderSide(color: sheetBorder, width: 1)),
        ),
        padding: EdgeInsets.only(
          left  : 20,
          right : 20,
          top   : 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 28,
        ),
        child: AnimatedSwitcher(
          duration       : const Duration(milliseconds: 320),
          switchInCurve  : Curves.easeOutCubic,
          switchOutCurve : Curves.easeIn,
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position: Tween<Offset>(
                      begin: const Offset(0, 0.04), end: Offset.zero)
                  .animate(anim),
              child: child,
            ),
          ),
          child: _approvalState == _ApprovalState.idle
              ? _buildForm(isDark, handleColor)
              : _buildApprovalOverlay(isDark),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FORM VIEW — _ApprovalState.idle
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildForm(bool isDark, Color handleColor) {
    final Color dividerColor  = isDark ? const Color(0xFF1A1A3A) : AppTokens.lightDivider;
    final Color titleColor    = isDark ? Colors.white             : AppTokens.lightTextPrimary;
    final Color subtitleColor = isDark ? const Color(0xFF5A5A8A)  : AppTokens.lightTextSecond;
    final Color bodyTextColor = isDark ? Colors.white             : AppTokens.lightTextPrimary;
    final Color notesColor    = isDark ? const Color(0xFFAAAAAA)  : AppTokens.lightTextSecond;
    final Color orDivColor    = isDark
        ? Colors.white.withOpacity(0.18)
        : AppTokens.lightTextHint.withOpacity(0.5);
    final Color scanBtnBorder = isDark ? AppTokens.cyanAction      : AppTokens.lightBorderFocus;
    final Color scanBtnFg     = isDark ? AppTokens.cyanAction      : AppTokens.lightAccent;
    final Color scanBtnFill   = isDark
        ? AppTokens.cyanAction.withOpacity(0.05)
        : AppTokens.lightAccent.withOpacity(0.06);

    // Whether to show delivery-specific fields
    final bool isDeliveryOrVisitor = _entryType.requiresApproval;

    return SingleChildScrollView(
      key: const ValueKey('form'),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize      : MainAxisSize.min,
          children: [

            // ── Handle bar ─────────────────────────────────────────────
            Center(
              child: Container(
                width : 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                    color: handleColor, borderRadius: BorderRadius.circular(2)),
              ),
            ),

            // ── Header ─────────────────────────────────────────────────
            Row(children: [
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
                          color        : titleColor,
                          fontSize     : 17,
                          fontWeight   : FontWeight.w900,
                          letterSpacing: 1.2)),
                  Text('Fill details or scan number plate',
                      style: TextStyle(color: subtitleColor, fontSize: 12)),
                ],
              ),
              const Spacer(),
              // Theme toggle
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
            ]),

            const SizedBox(height: 24),
            Divider(color: dividerColor, height: 1),
            const SizedBox(height: 20),

            // ── 1. Entry Type ──────────────────────────────────────────
            _label('ENTRY TYPE', isDark: isDark),
            _EntryTypeSelector(
              selected : _entryType,
              onChanged: (t) => setState(() {
                _entryType = t;
                // Clear agent photo if switching away from delivery/visitor
                if (!t.requiresApproval) _agentPhoto = null;
              }),
              isDark: isDark,
            ),
            const SizedBox(height: 22),

            // ── 2. Delivery Agent Photo (DELIVERY + VISITOR only) ──────
            if (isDeliveryOrVisitor) ...[
              _label('AGENT / VISITOR PHOTO', isDark: isDark),
              _AgentPhotoBox(
                photo          : _agentPhoto,
                isCapturing    : _isCapturingPhoto,
                isDark         : isDark,
                onTakePhoto    : _captureAgentPhoto,
                onRetakePhoto  : _retakeAgentPhoto,
                onClearPhoto   : () => setState(() => _agentPhoto = null),
              ),
              const SizedBox(height: 22),
            ],

            // ── 3. Company / Visitor Name ──────────────────────────────
            _label('COMPANY / VISITOR NAME *', isDark: isDark),
            TextFormField(
              controller       : _nameCtrl,
              focusNode        : _nameFocus,
              textInputAction  : TextInputAction.next,
              onEditingComplete: () =>
                  FocusScope.of(context).requestFocus(
                      isDeliveryOrVisitor ? _flatFocus : _plateFocus),
              style     : TextStyle(color: bodyTextColor, fontSize: 15),
              decoration: _inputDec(
                hint  : _entryType == EntryType.delivery
                    ? 'e.g. Zomato, Amazon, FedEx...'
                    : 'Enter visitor name',
                icon  : Icons.badge_rounded,
                isDark: isDark,
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Name is required' : null,
            ),
            const SizedBox(height: 18),

            // ── 4. Resident Flat Number (DELIVERY + VISITOR only) ──────
            if (isDeliveryOrVisitor) ...[
              _label('RESIDENT FLAT NUMBER *', isDark: isDark),
              TextFormField(
                controller       : _flatCtrl,
                focusNode        : _flatFocus,
                textInputAction  : TextInputAction.next,
                onEditingComplete: () =>
                    FocusScope.of(context).requestFocus(_plateFocus),
                textCapitalization: TextCapitalization.characters,
                inputFormatters  : [
                  TextInputFormatter.withFunction(
                    (old, newVal) =>
                        newVal.copyWith(text: newVal.text.toUpperCase()),
                  ),
                ],
                style: TextStyle(
                  color     : isDark ? AppTokens.cyanAction : AppTokens.lightAccent,
                  fontSize  : 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
                decoration: _inputDec(
                  hint  : 'Enter flat number, e.g. A-402',
                  icon  : Icons.apartment_rounded,
                  isDark: isDark,
                ),
                validator: (v) {
                  if (!isDeliveryOrVisitor) return null;
                  if (v == null || v.trim().isEmpty) {
                    return 'Flat number is required for approval';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 18),
            ],

            // ── 5. Vehicle Number Plate ────────────────────────────────
            _label('VEHICLE NUMBER PLATE', isDark: isDark),
            TextFormField(
              controller       : _plateCtrl,
              focusNode        : _plateFocus,
              textInputAction  : TextInputAction.next,
              onEditingComplete: () =>
                  FocusScope.of(context).requestFocus(_notesFocus),
              style: TextStyle(
                color        : isDark ? AppTokens.cyanAction : AppTokens.lightAccent,
                fontSize     : 17,
                fontWeight   : FontWeight.bold,
                letterSpacing: 2.5,
              ),
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                TextInputFormatter.withFunction(
                  (old, newVal) =>
                      newVal.copyWith(text: newVal.text.toUpperCase()),
                ),
              ],
              decoration: _inputDec(
                hint  : 'e.g. MH12AB1234',
                icon  : Icons.directions_car_rounded,
                isDark: isDark,
                suffixIcon: _plateCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear_rounded,
                            color: isDark
                                ? const Color(0xFF4A4A7A)
                                : AppTokens.lightTextSecond,
                            size: 18),
                        onPressed: () => setState(() => _plateCtrl.clear()),
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 14),

            // ── OR divider ─────────────────────────────────────────────
            Row(children: [
              Expanded(child: Divider(color: dividerColor)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Text('OR',
                    style: TextStyle(
                        color        : orDivColor,
                        fontSize     : 11,
                        fontWeight   : FontWeight.w700,
                        letterSpacing: 1.5)),
              ),
              Expanded(child: Divider(color: dividerColor)),
            ]),
            const SizedBox(height: 14),

            // ── 6. Scan plate button ───────────────────────────────────
            SizedBox(
              width : double.infinity,
              height: 52,
              child : OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: scanBtnFg,
                  side: BorderSide(
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
                            color: scanBtnFg, strokeWidth: 2))
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

            // Scanned plate image thumbnail
            if (_scannedPlateImage != null) ...[
              const SizedBox(height: 10),
              Row(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(_scannedPlateImage!,
                      width: 60, height: 40, fit: BoxFit.cover),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Plate image captured — stored with entry.',
                    style: TextStyle(color: subtitleColor, fontSize: 11),
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() => _scannedPlateImage = null),
                  child: Icon(Icons.close_rounded,
                      color: subtitleColor, size: 16),
                ),
              ]),
            ],
            const SizedBox(height: 20),

            // ── MOVEMENT-specific fields ──────────────────────────────
            if (_entryType == EntryType.generalMovement) ...[
              // ── Flat Number for Movement ─────────────────────────────
              _label('RESIDENT FLAT NUMBER *', isDark: isDark),
              TextFormField(
                controller        : _movementFlatCtrl,
                focusNode         : _movementFlatFocus,
                textInputAction   : TextInputAction.next,
                onEditingComplete : () => FocusScope.of(context).requestFocus(_notesFocus),
                textCapitalization: TextCapitalization.characters,
                style: TextStyle(
                  color     : isDark ? AppTokens.cyanAction : AppTokens.lightAccent,
                  fontSize  : 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
                decoration: _inputDec(
                  hint  : 'Enter flat number, e.g. A-402',
                  icon  : Icons.apartment_rounded,
                  isDark: isDark,
                ),
                validator: (v) {
                  if (_entryType != EntryType.generalMovement) return null;
                  if (v == null || v.trim().isEmpty) return 'Flat number is required';
                  return null;
                },
              ),
              const SizedBox(height: 18),

              // ── Entry / Exit Toggle ──────────────────────────────────
              _label('MOVEMENT TYPE', isDark: isDark),
              _MovementToggle(
                isEntry  : _isMovementEntry,
                isDark   : isDark,
                onChanged: (val) => setState(() => _isMovementEntry = val),
              ),
              const SizedBox(height: 18),
            ],

            // ── 7. Notes ───────────────────────────────────────────────
            _label('NOTES (OPTIONAL)', isDark: isDark),
            TextFormField(
              controller       : _notesCtrl,
              focusNode        : _notesFocus,
              maxLines         : 2,
              textInputAction  : TextInputAction.done,
              onEditingComplete: () => FocusScope.of(context).unfocus(),
              style    : TextStyle(color: notesColor, fontSize: 14),
              decoration: _inputDec(
                hint  : 'Any additional remarks...',
                icon  : Icons.notes_rounded,
                isDark: isDark,
              ),
            ),
            const SizedBox(height: 28),

            // ── 8. Submit ──────────────────────────────────────────────
            ScaleTransition(
              scale: _pulseAnim,
              child: SizedBox(
                width : double.infinity,
                height: 58,
                child : ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTokens.cyanAction,
                    foregroundColor: AppTokens.cyanActionText,
                    shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(AppTokens.radiusButton)),
                    elevation  : 6,
                    shadowColor: AppTokens.cyanAction.withOpacity(0.4),
                  ),
                  onPressed: _onSubmitPressed,
                  icon : const Icon(Icons.send_rounded, size: 22),
                  label: Text(
                    _entryType.requiresApproval
                        ? 'SEND APPROVAL REQUEST'
                        : 'SUBMIT ENTRY',
                    style: const TextStyle(
                        fontWeight  : FontWeight.w900,
                        letterSpacing: 1.1,
                        fontSize    : 15),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // APPROVAL OVERLAY — shown for all non-idle states
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildApprovalOverlay(bool isDark) {
    return SizedBox(
      key   : const ValueKey('overlay'),
      width : double.infinity,
      child : _ApprovalOverlay(
        state            : _approvalState,
        countdownRemaining: _countdownRemaining,
        totalSeconds     : _timeoutSeconds,
        flatNumber       : _flatCtrl.text.trim().toUpperCase(),
        company          : _nameCtrl.text.trim(),
        isDark           : isDark,
        onRetry          : _resetToIdle,
        onClose          : () => Navigator.pop(context),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _AgentPhotoBox
//
// Shows a camera-shaped container with three states:
//   • Empty     — "Take Photo" prompt with camera icon
//   • Capturing — loading spinner
//   • Captured  — frozen preview with "Retake" + "Clear" actions
// ─────────────────────────────────────────────────────────────────────────────
class _AgentPhotoBox extends StatelessWidget {
  final File?        photo;
  final bool         isCapturing;
  final bool         isDark;
  final VoidCallback onTakePhoto;
  final VoidCallback onRetakePhoto;
  final VoidCallback onClearPhoto;

  const _AgentPhotoBox({
    required this.photo,
    required this.isCapturing,
    required this.isDark,
    required this.onTakePhoto,
    required this.onRetakePhoto,
    required this.onClearPhoto,
  });

  @override
  Widget build(BuildContext context) {
    final Color boxBg     = isDark ? const Color(0xFF12122A) : const Color(0xFFF8FAFF);
    final Color boxBorder = isDark ? const Color(0xFF2E2E5E) : AppTokens.lightBorder;
    final Color iconColor = isDark ? const Color(0xFF4A4A8A) : AppTokens.lightTextSecond;
    final Color labelColor= isDark ? const Color(0xFF6A6A9A) : AppTokens.lightTextSecond;

    return Container(
      width : double.infinity,
      height: 180,
      decoration: BoxDecoration(
        color       : boxBg,
        borderRadius: BorderRadius.circular(AppTokens.radiusCard),
        border      : Border.all(
          color: photo != null
              ? AppTokens.cyanAction.withOpacity(0.5)
              : boxBorder,
          width: photo != null ? 1.5 : 1.0,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTokens.radiusCard - 1),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: isCapturing
              // ── Capturing state ─────────────────────────────────────
              ? _buildCapturingState(isDark)
              : photo == null
                  // ── Empty state ─────────────────────────────────────
                  ? _buildEmptyState(iconColor, labelColor)
                  // ── Photo captured state ────────────────────────────
                  : _buildCapturedState(isDark),
        ),
      ),
    );
  }

  Widget _buildEmptyState(Color iconColor, Color labelColor) {
    return GestureDetector(
      key     : const ValueKey('empty'),
      onTap   : onTakePhoto,
      behavior: HitTestBehavior.opaque,
      child   : Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.camera_alt_rounded, size: 48, color: iconColor),
          const SizedBox(height: 12),
          Text('Tap to take agent photo',
              style: TextStyle(
                  color     : labelColor,
                  fontSize  : 13,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('Front camera will open',
              style: TextStyle(
                  color   : labelColor.withOpacity(0.6),
                  fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildCapturingState(bool isDark) {
    return Center(
      key : const ValueKey('capturing'),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: AppTokens.cyanAction, strokeWidth: 2.5),
          const SizedBox(height: 14),
          Text('Opening camera...',
              style: TextStyle(
                  color   : isDark ? Colors.white54 : AppTokens.lightTextSecond,
                  fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildCapturedState(bool isDark) {
    return Stack(
      key     : const ValueKey('captured'),
      fit     : StackFit.expand,
      children: [
        // Frozen preview
        Image.file(photo!, fit: BoxFit.cover),

        // Gradient overlay at bottom
        Positioned(
          left: 0, right: 0, bottom: 0,
          child: Container(
            height: 60,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin  : Alignment.topCenter,
                end    : Alignment.bottomCenter,
                colors : [Colors.transparent, Colors.black87],
              ),
            ),
          ),
        ),

        // Action buttons — bottom row
        Positioned(
          left: 10, right: 10, bottom: 10,
          child: Row(
            children: [
              // Retake
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white60),
                    backgroundColor: Colors.black45,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: onRetakePhoto,
                  icon : const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Retake',
                      style: TextStyle(
                          fontSize  : 12,
                          fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 8),
              // Clear
              IconButton(
                onPressed    : onClearPhoto,
                icon         : const Icon(Icons.close_rounded, color: Colors.white70),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black45,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.all(6),
                ),
              ),
            ],
          ),
        ),

        // Captured badge — top-right
        Positioned(
          top: 10, right: 10,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color       : Colors.green.shade700,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle_rounded,
                    size: 12, color: Colors.white),
                SizedBox(width: 4),
                Text('CAPTURED',
                    style: TextStyle(
                        color     : Colors.white,
                        fontSize  : 10,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ApprovalOverlay
//
// Replaces the form body while the approval request is in flight.
// Renders a different UI for each approval state:
//
//   PENDING_APPROVAL → animated spinner + countdown arc
//   APPROVED         → green success UI
//   DENIED           → red denied UI with retry
//   TIMED_OUT        → amber timeout UI with retry
// ─────────────────────────────────────────────────────────────────────────────
class _ApprovalOverlay extends StatefulWidget {
  final _ApprovalState state;
  final int            countdownRemaining;
  final int            totalSeconds;
  final String         flatNumber;
  final String         company;
  final bool           isDark;
  final VoidCallback   onRetry;
  final VoidCallback   onClose;

  const _ApprovalOverlay({
    required this.state,
    required this.countdownRemaining,
    required this.totalSeconds,
    required this.flatNumber,
    required this.company,
    required this.isDark,
    required this.onRetry,
    required this.onClose,
  });

  @override
  State<_ApprovalOverlay> createState() => _ApprovalOverlayState();
}

class _ApprovalOverlayState extends State<_ApprovalOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _spinCtrl;

  @override
  void initState() {
    super.initState();
    _spinCtrl = AnimationController(
      vsync   : this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _spinCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 10),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 400),
        child   : _buildStateContent(),
      ),
    );
  }

  Widget _buildStateContent() {
    switch (widget.state) {
      case _ApprovalState.pendingApproval:
        return _buildPending();
      case _ApprovalState.approved:
        return _buildApproved();
      case _ApprovalState.denied:
        return _buildDenied();
      case _ApprovalState.timedOut:
        return _buildTimedOut();
      case _ApprovalState.idle:
        return const SizedBox.shrink(); // never shown
    }
  }

  // ── PENDING_APPROVAL ──────────────────────────────────────────────────────

  Widget _buildPending() {
    final double progress =
        widget.countdownRemaining / widget.totalSeconds;
    final bool isUrgent = widget.countdownRemaining <= 15;

    final Color arcColor  = isUrgent ? Colors.redAccent : AppTokens.cyanAction;
    final Color textColor = widget.isDark ? Colors.white : AppTokens.lightTextPrimary;
    final Color subColor  = widget.isDark ? Colors.white60 : AppTokens.lightTextSecond;

    return Column(
      key             : const ValueKey('pending'),
      mainAxisSize    : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [

        // ── Countdown arc + spinner ────────────────────────────────────
        SizedBox(
          width : 120,
          height: 120,
          child : Stack(
            alignment: Alignment.center,
            children: [
              // Background track
              CircularProgressIndicator(
                value          : 1.0,
                strokeWidth    : 8,
                valueColor     : AlwaysStoppedAnimation<Color>(
                    widget.isDark
                        ? Colors.white.withOpacity(0.08)
                        : Colors.grey.shade200),
              ),
              // Countdown arc — shrinks as time runs out
              CircularProgressIndicator(
                value      : progress,
                strokeWidth: 8,
                strokeCap  : StrokeCap.round,
                valueColor : AlwaysStoppedAnimation<Color>(arcColor),
              ),
              // Spinning inner ring
              RotationTransition(
                turns: _spinCtrl,
                child: SizedBox(
                  width : 80,
                  height: 80,
                  child : CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor : AlwaysStoppedAnimation<Color>(
                        arcColor.withOpacity(0.3)),
                  ),
                ),
              ),
              // Countdown number
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${widget.countdownRemaining}',
                    style: TextStyle(
                      color     : isUrgent ? Colors.redAccent : arcColor,
                      fontSize  : 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text('sec',
                      style: TextStyle(
                          color  : subColor,
                          fontSize: 11)),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 28),

        // ── Status text ────────────────────────────────────────────────
        Text('Waiting for Resident Response',
            style: TextStyle(
                color     : textColor,
                fontSize  : 18,
                fontWeight: FontWeight.bold),
            textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(
          'Approval request sent to Flat ${widget.flatNumber}.\n'
          'Resident will be notified on their dashboard.',
          style    : TextStyle(color: subColor, fontSize: 13, height: 1.5),
          textAlign: TextAlign.center,
        ),

        const SizedBox(height: 20),

        // ── Company chip ──────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color       : AppTokens.cyanAction.withOpacity(0.08),
            borderRadius: BorderRadius.circular(20),
            border      : Border.all(
                color: AppTokens.cyanAction.withOpacity(0.25)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.local_shipping_rounded,
                  size : 14,
                  color: AppTokens.cyanAction.withOpacity(0.7)),
              const SizedBox(width: 8),
              Text(widget.company,
                  style: TextStyle(
                    color     : AppTokens.cyanAction,
                    fontSize  : 13,
                    fontWeight: FontWeight.bold,
                  )),
            ],
          ),
        ),

        if (isUrgent) ...[
          const SizedBox(height: 16),
          Text('⚠️  Expiring soon!',
              style: const TextStyle(
                  color    : Colors.redAccent,
                  fontSize : 12,
                  fontWeight: FontWeight.bold)),
        ],
      ],
    );
  }

  // ── APPROVED ──────────────────────────────────────────────────────────────

  Widget _buildApproved() {
    return Column(
      key             : const ValueKey('approved'),
      mainAxisSize    : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Success icon with glow
        Container(
          width : 96,
          height: 96,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.green.withOpacity(0.12),
            boxShadow: [
              BoxShadow(
                  color    : Colors.green.withOpacity(0.3),
                  blurRadius: 28,
                  spreadRadius: 4),
            ],
          ),
          child: const Icon(Icons.check_circle_rounded,
              size: 54, color: Colors.greenAccent),
        ),
        const SizedBox(height: 28),
        const Text('Entry Approved!',
            style: TextStyle(
                color     : Colors.greenAccent,
                fontSize  : 22,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Text(
          'Resident of Flat ${widget.flatNumber} accepted.\n'
          'Entry has been logged successfully.',
          style    : TextStyle(
              color : widget.isDark ? Colors.white60 : AppTokens.lightTextSecond,
              fontSize: 13,
              height: 1.5),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        SizedBox(
          width : double.infinity,
          height: 52,
          child : ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.greenAccent,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTokens.radiusButton)),
              elevation: 0,
            ),
            onPressed: widget.onClose,
            icon : const Icon(Icons.done_rounded, size: 20),
            label: const Text('DONE',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
          ),
        ),
      ],
    );
  }

  // ── DENIED ────────────────────────────────────────────────────────────────

  Widget _buildDenied() {
    return Column(
      key             : const ValueKey('denied'),
      mainAxisSize    : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width : 96,
          height: 96,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.red.withOpacity(0.12),
            boxShadow: [
              BoxShadow(
                  color    : Colors.red.withOpacity(0.25),
                  blurRadius: 24,
                  spreadRadius: 4),
            ],
          ),
          child: const Icon(Icons.cancel_rounded,
              size: 54, color: Colors.redAccent),
        ),
        const SizedBox(height: 28),
        const Text('Entry Denied',
            style: TextStyle(
                color     : Colors.redAccent,
                fontSize  : 22,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Text(
          'Resident of Flat ${widget.flatNumber} denied this request.\n'
          'The delivery agent cannot be allowed in.',
          style    : TextStyle(
              color   : widget.isDark ? Colors.white60 : AppTokens.lightTextSecond,
              fontSize: 13,
              height  : 1.5),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        _TwoActionRow(
          primaryLabel: 'NEW ENTRY',
          primaryColor: AppTokens.cyanAction,
          primaryTextColor: Colors.black,
          onPrimary: widget.onRetry,
          secondaryLabel: 'CLOSE',
          secondaryColor: Colors.redAccent,
          onSecondary: widget.onClose,
        ),
      ],
    );
  }

  // ── TIMED_OUT ─────────────────────────────────────────────────────────────

  Widget _buildTimedOut() {
    return Column(
      key             : const ValueKey('timeout'),
      mainAxisSize    : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width : 96,
          height: 96,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.orange.withOpacity(0.12),
            boxShadow: [
              BoxShadow(
                  color    : Colors.orange.withOpacity(0.25),
                  blurRadius: 24,
                  spreadRadius: 4),
            ],
          ),
          child: const Icon(Icons.timer_off_rounded,
              size: 54, color: Colors.orangeAccent),
        ),
        const SizedBox(height: 28),
        const Text('Request Timed Out',
            style: TextStyle(
                color     : Colors.orangeAccent,
                fontSize  : 22,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Text(
          'No response from Flat ${widget.flatNumber} within 60 seconds.\n'
          'The request has been automatically cancelled.',
          style    : TextStyle(
              color   : widget.isDark ? Colors.white60 : AppTokens.lightTextSecond,
              fontSize: 13,
              height  : 1.5),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        _TwoActionRow(
          primaryLabel    : 'RETRY REQUEST',
          primaryColor    : AppTokens.cyanAction,
          primaryTextColor: Colors.black,
          onPrimary       : widget.onRetry,
          secondaryLabel  : 'CLOSE',
          secondaryColor  : Colors.white38,
          onSecondary     : widget.onClose,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _TwoActionRow — shared button row for DENIED and TIMED_OUT states
// ─────────────────────────────────────────────────────────────────────────────
class _TwoActionRow extends StatelessWidget {
  final String     primaryLabel;
  final Color      primaryColor;
  final Color      primaryTextColor;
  final VoidCallback onPrimary;
  final String     secondaryLabel;
  final Color      secondaryColor;
  final VoidCallback onSecondary;

  const _TwoActionRow({
    required this.primaryLabel,
    required this.primaryColor,
    required this.primaryTextColor,
    required this.onPrimary,
    required this.secondaryLabel,
    required this.secondaryColor,
    required this.onSecondary,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              foregroundColor: primaryTextColor,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTokens.radiusInput)),
              elevation: 0,
              padding  : const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: onPrimary,
            child: Text(primaryLabel,
                style: TextStyle(
                    fontWeight  : FontWeight.w900,
                    fontSize    : 13,
                    color       : primaryTextColor,
                    letterSpacing: 0.8)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: secondaryColor,
              side: BorderSide(color: secondaryColor.withOpacity(0.5)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTokens.radiusInput)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: onSecondary,
            child: Text(secondaryLabel,
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize  : 13,
                    color     : secondaryColor)),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _EntryTypeSelector — theme-aware segmented control (unchanged)
// ─────────────────────────────────────────────────────────────────────────────
class _EntryTypeSelector extends StatelessWidget {
  final EntryType               selected;
  final ValueChanged<EntryType> onChanged;
  final bool                    isDark;

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

        final Color idleBg     = isDark ? const Color(0xFF13132A) : AppTokens.lightDivider.withOpacity(0.5);
        final Color idleBorder = isDark ? const Color(0xFF2A2A4A) : AppTokens.lightBorder;
        final Color idleIcon   = isDark ? const Color(0xFF4A4A7A) : AppTokens.lightTextSecond;
        final Color idleText   = isDark ? const Color(0xFF4A4A7A) : AppTokens.lightTextSecond;

        return Expanded(
          child: GestureDetector(
            onTap: () => onChanged(type),
            child: AnimatedContainer(
              duration    : const Duration(milliseconds: 200),
              curve       : Curves.easeOut,
              margin      : EdgeInsets.only(right: isLast ? 0 : 8),
              padding     : const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                gradient: isSelected
                    ? const LinearGradient(
                        colors: [Color(0xFF00E5FF), Color(0xFF00B4D8)],
                        begin : Alignment.topLeft,
                        end   : Alignment.bottomRight)
                    : null,
                color       : isSelected ? null : idleBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: isSelected ? Colors.transparent : idleBorder,
                    width: 1),
                boxShadow: isSelected
                    ? [BoxShadow(
                        color     : AppTokens.cyanAction.withOpacity(0.25),
                        blurRadius: 10,
                        offset    : const Offset(0, 4))]
                    : null,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(type.icon,
                      color: isSelected ? Colors.black : idleIcon,
                      size : 22),
                  const SizedBox(height: 5),
                  Text(type.label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color        : isSelected ? Colors.black : idleText,
                        fontSize     : 9,
                        fontWeight   : FontWeight.w800,
                        letterSpacing: 0.6,
                      )),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _MovementToggle — Entry / Exit segmented toggle for General Movement tab
// ─────────────────────────────────────────────────────────────────────────────
class _MovementToggle extends StatelessWidget {
  final bool                isEntry;
  final bool                isDark;
  final ValueChanged<bool>  onChanged;

  const _MovementToggle({
    required this.isEntry,
    required this.isDark,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _chip(
          label    : 'ENTRY',
          icon     : Icons.login_rounded,
          selected : isEntry,
          accent   : Colors.greenAccent,
          isDark   : isDark,
          onTap    : () => onChanged(true),
        ),
        const SizedBox(width: 12),
        _chip(
          label    : 'EXIT',
          icon     : Icons.logout_rounded,
          selected : !isEntry,
          accent   : Colors.redAccent,
          isDark   : isDark,
          onTap    : () => onChanged(false),
        ),
      ],
    );
  }

  Widget _chip({
    required String    label,
    required IconData  icon,
    required bool      selected,
    required Color     accent,
    required bool      isDark,
    required VoidCallback onTap,
  }) {
    final idleBg     = isDark ? const Color(0xFF13132A) : const Color(0xFFF0F4FF);
    final idleBorder = isDark ? const Color(0xFF2A2A4A) : AppTokens.lightBorder;
    final idleText   = isDark ? const Color(0xFF5A5A8A) : AppTokens.lightTextSecond;

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration  : const Duration(milliseconds: 200),
          height    : 52,
          decoration: BoxDecoration(
            color : selected ? accent.withOpacity(0.15) : idleBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? accent : idleBorder,
              width: selected ? 1.8 : 1.0,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                size : 18,
                color: selected ? accent : idleText),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color     : selected ? accent : idleText,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                  fontSize  : 13,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
