import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../main.dart' show themeNotifier, AppTokens;
import 'log_movement_screen.dart' show activeGuardName;

// ─────────────────────────────────────────────────────────────────────────────
// LoginScreen — theme-aware, high-contrast credentials login
//
// Contrast targets met in BOTH themes:
//   • Primary text   ≥ 7:1  against surface backgrounds
//   • Secondary text ≥ 4.5:1
//   • Input borders  clearly visible (not hairline grey)
//   • Focused ring   2dp accent color, unambiguous
//   • Cyan button    always carries black text (never white on bright cyan)
//   • Role toggle    unselected uses explicit per-theme border/text colors,
//                    never the dark-only Colors.white24
// ─────────────────────────────────────────────────────────────────────────────

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isGuard  = true;
  bool _isLoading= false;
  bool _loginLock= false;
  bool _obscureCode = true;

  final _idCtrl   = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _idFocus  = FocusNode();
  final _codeFocus= FocusNode();

  @override
  void dispose() {
    _idCtrl.dispose();
    _codeCtrl.dispose();
    _idFocus.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  // ─── Auth logic (unchanged from original) ─────────────────────────────────

  Future<void> _login() async {
    if (_loginLock) return;
    _loginLock = true;

    final String inputId = _idCtrl.text.trim().toUpperCase();
    final String code    = _codeCtrl.text.trim();

    FocusScope.of(context).unfocus();

    if (inputId.isEmpty || code.isEmpty) {
      _toast('Error: Fields cannot be left blank.', Colors.orange);
      _loginLock = false;
      return;
    }

    setState(() => _isLoading = true);

    try {
      DocumentSnapshot? userDoc;
      Map<String, dynamic>? data;

      if (_isGuard) {
        final snap = await FirebaseFirestore.instance
            .collection('guards')
            .where('guardId', isEqualTo: inputId)
            .get();
        if (snap.docs.isEmpty) {
          _toast('ACCESS DENIED: ID not registered in system.', Colors.red);
          setState(() => _isLoading = false);
          _loginLock = false;
          return;
        }
        userDoc = snap.docs.first;
        data    = userDoc.data() as Map<String, dynamic>?;
      } else {
        final snap = await FirebaseFirestore.instance
            .collection('residents')
            .doc(inputId)
            .get();
        if (!snap.exists) {
          _toast('ACCESS DENIED: Flat not registered in system.', Colors.red);
          setState(() => _isLoading = false);
          _loginLock = false;
          return;
        }
        userDoc = snap;
        data    = userDoc.data() as Map<String, dynamic>?;
      }

      if (data == null ||
          !data.containsKey('accessCode') ||
          data['accessCode'] == null) {
        _toast('SERVER ERROR: Profile configuration incomplete.', Colors.redAccent);
        setState(() => _isLoading = false);
        _loginLock = false;
        return;
      }

      if (data['accessCode'].toString().trim() != code) {
        _toast('ACCESS DENIED: Incorrect Access Code.', Colors.red);
        setState(() => _isLoading = false);
        _loginLock = false;
        return;
      }

      if (_isGuard) {
        final guardName = (data['guardName'] as String?)?.trim() ?? '';
        activeGuardName = guardName.isNotEmpty ? guardName : inputId;

        await FirebaseFirestore.instance
            .collection('guards')
            .doc(userDoc!.id)
            .update({
          'onDuty'   : true,
          'dutyStart': FieldValue.serverTimestamp(),
          'guardName': activeGuardName,
          'guardId'  : inputId,
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('✅ Access Granted! Loading dashboard...',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          backgroundColor: Colors.green,
          duration: Duration(milliseconds: 800),
        ));
        await Future.delayed(const Duration(milliseconds: 600));
        if (mounted) {
          Navigator.pushReplacementNamed(
            context,
            _isGuard ? '/guard_dashboard' : '/resident_dashboard',
            arguments: inputId,
          );
        }
      }
    } catch (e, st) {
      debugPrint('🚨 AUTH ERROR: $e\n$st');
      if (mounted) {
        _toast('System Error. Please try again.', Colors.red);
        setState(() => _isLoading = false);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
      _loginLock = false;
    }
  }

  void _toast(String msg, Color bg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(msg,
            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: bg,
        behavior       : SnackBarBehavior.floating,
        margin         : const EdgeInsets.all(16),
        shape          : RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration       : const Duration(seconds: 4),
      ));
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // ── Per-theme tokens ───────────────────────────────────────────────────
    final Color bgColor      = isDark ? AppTokens.darkBg       : AppTokens.lightBg;
    final Color cardColor    = isDark ? AppTokens.darkSurface   : AppTokens.lightSurface;
    final Color cardBorder   = isDark ? AppTokens.darkBorder    : AppTokens.lightBorder;
    final Color titleColor   = isDark ? AppTokens.darkTextPrimary: AppTokens.lightTextPrimary;
    final Color subtitleColor= isDark ? AppTokens.darkAccent    : AppTokens.lightAccent;
    final Color shadowColor  = isDark ? Colors.black38          : const Color(0xFFCBD5E1);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          ValueListenableBuilder<ThemeMode>(
            valueListenable: themeNotifier,
            builder: (_, mode, __) => IconButton(
              icon: Icon(
                mode == ThemeMode.dark
                    ? Icons.light_mode_rounded
                    : Icons.dark_mode_rounded,
                color: isDark ? Colors.white54 : AppTokens.lightTextSecond,
              ),
              tooltip: 'Toggle Theme',
              onPressed: () {
                themeNotifier.value = mode == ThemeMode.dark
                    ? ThemeMode.light
                    : ThemeMode.dark;
              },
            ),
          ),
        ],
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                // ── Logo ──────────────────────────────────────────────────
                Hero(
                  tag: 'logo',
                  child: Icon(Icons.qr_code_scanner_rounded,
                      size: 70,
                      color: isDark ? AppTokens.cyanAction : AppTokens.lightAccent),
                ),
                const SizedBox(height: 8),
                Text('SCOCAR',
                    style: TextStyle(
                      color      : titleColor,
                      fontSize   : 22,
                      fontWeight : FontWeight.bold,
                      letterSpacing: 5,
                    )),
                Text('SECURE ACCESS TERMINAL',
                    style: TextStyle(
                      color    : subtitleColor,
                      fontSize : 10,
                      letterSpacing: 2,
                      fontWeight: FontWeight.w600,
                    )),
                const SizedBox(height: 36),

                // ── Card ──────────────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color       : cardColor,
                    borderRadius: BorderRadius.circular(24),
                    border      : Border.all(color: cardBorder),
                    boxShadow   : [BoxShadow(blurRadius: 30, color: shadowColor)],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [

                      // ── Role toggle ─────────────────────────────────────
                      Row(children: [
                        Expanded(
                          child: _RoleChip(
                            title   : 'Guard',
                            icon    : Icons.shield_rounded,
                            selected: _isGuard,
                            isDark  : isDark,
                            onTap   : _isLoading
                                ? null
                                : () => setState(() {
                                      _isGuard = true;
                                      _idCtrl.clear();
                                    }),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _RoleChip(
                            title   : 'Resident',
                            icon    : Icons.home_rounded,
                            selected: !_isGuard,
                            isDark  : isDark,
                            onTap   : _isLoading
                                ? null
                                : () => setState(() {
                                      _isGuard = false;
                                      _idCtrl.clear();
                                    }),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 28),

                      // ── ID / Flat field ─────────────────────────────────
                      _buildField(
                        controller : _idCtrl,
                        focusNode  : _idFocus,
                        label      : _isGuard ? 'Guard ID' : 'Flat Number',
                        hint       : _isGuard ? 'e.g. GUARD1' : 'e.g. A101',
                        icon       : _isGuard
                            ? Icons.badge_rounded
                            : Icons.apartment_rounded,
                        inputAction: TextInputAction.next,
                        capitalize : TextCapitalization.characters,
                        onSubmitted: (_) =>
                            FocusScope.of(context).requestFocus(_codeFocus),
                        isDark     : isDark,
                      ),
                      const SizedBox(height: 16),

                      // ── Access Code field ───────────────────────────────
                      _buildField(
                        controller  : _codeCtrl,
                        focusNode   : _codeFocus,
                        label       : 'Access Code',
                        hint        : 'Enter your access code',
                        icon        : Icons.lock_rounded,
                        inputAction : TextInputAction.done,
                        obscure     : _obscureCode,
                        onSubmitted : (_) { if (!_isLoading) _login(); },
                        isDark      : isDark,
                        suffixIcon  : IconButton(
                          icon: Icon(
                            _obscureCode
                                ? Icons.visibility_off_rounded
                                : Icons.visibility_rounded,
                            size : 20,
                            color: isDark
                                ? Colors.white38
                                : AppTokens.lightTextHint,
                          ),
                          onPressed: () =>
                              setState(() => _obscureCode = !_obscureCode),
                        ),
                      ),
                      const SizedBox(height: 32),

                      // ── Authenticate button ─────────────────────────────
                      SizedBox(
                        width : double.infinity,
                        height: 56,
                        child : ElevatedButton(
                          onPressed: _isLoading ? null : _login,
                          style: ElevatedButton.styleFrom(
                            // Always bright cyan, always black text — no contrast issues
                            backgroundColor: AppTokens.cyanAction,
                            foregroundColor: AppTokens.cyanActionText,
                            disabledBackgroundColor:
                                AppTokens.cyanAction.withOpacity(0.3),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                    AppTokens.radiusButton)),
                            elevation: 0,
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width : 24, height: 24,
                                  child : CircularProgressIndicator(
                                      color: Colors.black, strokeWidth: 2.5))
                              : const Text('AUTHENTICATE',
                                  style: TextStyle(
                                    fontSize     : 16,
                                    fontWeight   : FontWeight.w900,
                                    letterSpacing: 1.5,
                                    color        : Colors.black,
                                  )),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Field builder ─────────────────────────────────────────────────────────

  Widget _buildField({
    required TextEditingController controller,
    required FocusNode             focusNode,
    required String                label,
    required String                hint,
    required IconData              icon,
    required TextInputAction       inputAction,
    required bool                  isDark,
    bool                           obscure    = false,
    TextCapitalization             capitalize = TextCapitalization.none,
    Widget?                        suffixIcon,
    void Function(String)?         onSubmitted,
  }) {
    // ── Per-theme input colors ──────────────────────────────────────────────
    final Color textColor  = isDark ? AppTokens.darkTextPrimary : AppTokens.lightTextPrimary;
    final Color labelColor = isDark ? AppTokens.darkTextSecond  : AppTokens.lightTextSecond;
    final Color hintColor  = isDark ? AppTokens.darkTextHint    : AppTokens.lightTextHint;
    final Color fillColor  = isDark ? AppTokens.darkFieldFill   : AppTokens.lightFieldFill;
    final Color border     = isDark ? AppTokens.darkBorder      : AppTokens.lightBorder;
    final Color focusBorder= isDark ? AppTokens.darkBorderFocus : AppTokens.lightBorderFocus;
    final Color iconColor  = isDark ? AppTokens.darkAccent      : AppTokens.lightAccent;

    return TextField(
      controller        : controller,
      focusNode         : focusNode,
      enabled           : !_isLoading,
      obscureText       : obscure,
      textCapitalization: capitalize,
      textInputAction   : inputAction,
      onSubmitted       : onSubmitted,
      style             : TextStyle(
          color: textColor, fontSize: 15, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        labelText : label,
        hintText  : hint,
        labelStyle: TextStyle(color: labelColor, fontSize: 14),
        hintStyle : TextStyle(color: hintColor,  fontSize: 14),
        prefixIcon: Icon(icon, color: iconColor, size: 20),
        suffixIcon: suffixIcon,
        filled    : true,
        fillColor : fillColor,
        // ── Borders — well-defined, never hairline ───────────────────────
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusInput),
          borderSide  : BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusInput),
          borderSide  : BorderSide(color: border, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusInput),
          borderSide  : BorderSide(color: focusBorder, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _RoleChip — theme-aware role toggle button
// ─────────────────────────────────────────────────────────────────────────────
class _RoleChip extends StatelessWidget {
  final String    title;
  final IconData  icon;
  final bool      selected;
  final bool      isDark;
  final VoidCallback? onTap;

  const _RoleChip({
    required this.title,
    required this.icon,
    required this.selected,
    required this.isDark,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // ── Unselected: explicit per-theme colors (never Colors.white24 in light) ─
    final Color idleBorder = isDark ? Colors.white24     : AppTokens.lightBorder;
    final Color idleText   = isDark ? Colors.white54     : AppTokens.lightTextSecond;
    final Color idleIcon   = isDark ? Colors.white38     : AppTokens.lightTextSecond;
    final Color idleFill   = isDark ? Colors.transparent : AppTokens.lightBg;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color       : selected ? AppTokens.cyanAction : idleFill,
          borderRadius: BorderRadius.circular(AppTokens.radiusInput),
          border: Border.all(
            color: selected ? AppTokens.cyanAction : idleBorder,
            width: selected ? 2.0 : 1.5,
          ),
          boxShadow: selected
              ? [BoxShadow(
                  color    : AppTokens.cyanAction.withOpacity(0.25),
                  blurRadius: 8,
                  offset   : const Offset(0, 3),
                )]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size : 18,
                color: selected ? Colors.black : idleIcon),
            const SizedBox(width: 8),
            Text(title,
                style: TextStyle(
                  color     : selected ? Colors.black : idleText,
                  fontWeight: FontWeight.bold,
                  fontSize  : 14,
                )),
          ],
        ),
      ),
    );
  }
}
