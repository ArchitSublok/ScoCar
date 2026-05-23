import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../main.dart' show themeNotifier, AppTokens;
import 'log_movement_screen.dart' show activeGuardName;

// ─────────────────────────────────────────────────────────────────────────────
// Role enum — drives the entire login screen state
// ─────────────────────────────────────────────────────────────────────────────
enum _Role { guard, resident, admin }

extension _RoleExt on _Role {
  String get label {
    switch (this) {
      case _Role.guard:    return 'Guard';
      case _Role.resident: return 'Resident';
      case _Role.admin:    return 'Admin';
    }
  }

  IconData get icon {
    switch (this) {
      case _Role.guard:    return Icons.shield_rounded;
      case _Role.resident: return Icons.home_rounded;
      case _Role.admin:    return Icons.admin_panel_settings_rounded;
    }
  }

  // The accent colour for each role tab (selected state)
  Color get accentColor {
    switch (this) {
      case _Role.guard:    return AppTokens.cyanAction;       // cyan
      case _Role.resident: return AppTokens.cyanAction;       // cyan
      case _Role.admin:    return const Color(0xFFFFB300);    // amber-gold
    }
  }

  Color get accentText {
    return Colors.black; // always black on bright fill
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hard-coded admin credentials (single-user admin — stored only in app)
// Change _kAdminId / _kAdminCode before releasing to production.
// ─────────────────────────────────────────────────────────────────────────────
const String _kAdminId   = 'ADMIN';
const String _kAdminCode = 'SCOCAR@ADMIN2024';

// ─────────────────────────────────────────────────────────────────────────────
// LoginScreen
// ─────────────────────────────────────────────────────────────────────────────
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {

  _Role  _role       = _Role.guard;
  bool   _isLoading  = false;
  bool   _loginLock  = false;
  bool   _obscureCode = true;

  final _idCtrl   = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _idFocus  = FocusNode();
  final _codeFocus= FocusNode();

  // Subtle slide animation when switching roles
  late AnimationController _slideCtrl;
  late Animation<Offset>   _slideAnim;

  @override
  void initState() {
    super.initState();
    _slideCtrl = AnimationController(
      vsync   : this,
      duration: const Duration(milliseconds: 260),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0.04, 0),
      end  : Offset.zero,
    ).animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOut));
    _slideCtrl.forward();
  }

  @override
  void dispose() {
    _slideCtrl.dispose();
    _idCtrl.dispose();
    _codeCtrl.dispose();
    _idFocus.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  // ─── Role switch ────────────────────────────────────────────────────────────

  void _switchRole(_Role r) {
    if (_isLoading || r == _role) return;
    setState(() {
      _role = r;
      _idCtrl.clear();
      _codeCtrl.clear();
      _obscureCode = true;
    });
    _slideCtrl
      ..reset()
      ..forward();
    FocusScope.of(context).unfocus();
  }

  // ─── Auth logic ─────────────────────────────────────────────────────────────

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
      // ── ADMIN auth (local credential check — no Firestore round-trip) ────
      if (_role == _Role.admin) {
        if (inputId != _kAdminId || code != _kAdminCode) {
          _toast('ACCESS DENIED: Invalid admin credentials.', Colors.red);
          setState(() => _isLoading = false);
          _loginLock = false;
          return;
        }
        // Admin OK
        if (mounted) {
          _grantAccess('✅ Admin access granted!');
          await Future.delayed(const Duration(milliseconds: 600));
          if (mounted) {
            Navigator.pushReplacementNamed(context, '/admin_dashboard');
          }
        }
        return;
      }

      // ── Guard auth ───────────────────────────────────────────────────────
      DocumentSnapshot? userDoc;
      Map<String, dynamic>? data;

      if (_role == _Role.guard) {
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
      }

      // ── Resident auth ────────────────────────────────────────────────────
      else {
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

      if (_role == _Role.guard) {
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
        _grantAccess('✅ Access Granted! Loading dashboard...');
        await Future.delayed(const Duration(milliseconds: 600));
        if (mounted) {
          Navigator.pushReplacementNamed(
            context,
            _role == _Role.guard
                ? '/guard_dashboard'
                : '/resident_dashboard',
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

  void _grantAccess(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
      backgroundColor: Colors.green.shade700,
      duration: const Duration(milliseconds: 800),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
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

  // ─── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final Color bgColor      = isDark ? AppTokens.darkBg        : AppTokens.lightBg;
    final Color cardColor    = isDark ? AppTokens.darkSurface    : AppTokens.lightSurface;
    final Color cardBorder   = isDark ? AppTokens.darkBorder     : AppTokens.lightBorder;
    final Color titleColor   = isDark ? AppTokens.darkTextPrimary: AppTokens.lightTextPrimary;
    final Color subtitleColor= isDark ? AppTokens.darkAccent     : AppTokens.lightAccent;
    final Color shadowColor  = isDark ? Colors.black38           : const Color(0xFFCBD5E1);

    // Admin-specific accent overrides
    final bool   isAdmin     = _role == _Role.admin;
    final Color  roleAccent  = _role.accentColor;

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
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Column(
              children: [

                // ── Logo ──────────────────────────────────────────────────
                Hero(
                  tag: 'logo',
                  child: Icon(
                    isAdmin
                        ? Icons.admin_panel_settings_rounded
                        : Icons.qr_code_scanner_rounded,
                    size : 70,
                    color: roleAccent,
                  ),
                ),
                const SizedBox(height: 8),
                Text('SCOCAR',
                    style: TextStyle(
                      color        : titleColor,
                      fontSize     : 22,
                      fontWeight   : FontWeight.bold,
                      letterSpacing: 5,
                    )),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Text(
                    key: ValueKey(_role),
                    isAdmin ? 'ADMIN CONTROL PANEL' : 'SECURE ACCESS TERMINAL',
                    style: TextStyle(
                      color        : roleAccent,
                      fontSize     : 10,
                      letterSpacing: 2,
                      fontWeight   : FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // ── Card ──────────────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color       : cardColor,
                    borderRadius: BorderRadius.circular(24),
                    border      : Border.all(
                      color: isAdmin
                          ? roleAccent.withOpacity(0.4)
                          : cardBorder,
                      width: isAdmin ? 1.5 : 1.0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        blurRadius  : 30,
                        color       : isAdmin
                            ? roleAccent.withOpacity(0.12)
                            : shadowColor,
                      )
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [

                      // ── Three-role toggle ────────────────────────────
                      Row(children: [
                        Expanded(
                          child: _RoleChip(
                            role    : _Role.guard,
                            selected: _role == _Role.guard,
                            isDark  : isDark,
                            onTap   : () => _switchRole(_Role.guard),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _RoleChip(
                            role    : _Role.resident,
                            selected: _role == _Role.resident,
                            isDark  : isDark,
                            onTap   : () => _switchRole(_Role.resident),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _RoleChip(
                            role    : _Role.admin,
                            selected: _role == _Role.admin,
                            isDark  : isDark,
                            onTap   : () => _switchRole(_Role.admin),
                          ),
                        ),
                      ]),

                      // Admin warning banner
                      if (isAdmin) ...[
                        const SizedBox(height: 14),
                        Container(
                          width  : double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color       : const Color(0xFFFFB300).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: const Color(0xFFFFB300).withOpacity(0.4)),
                          ),
                          child: const Row(children: [
                            Icon(Icons.warning_amber_rounded,
                                color: Color(0xFFFFB300), size: 15),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Restricted access — authorised personnel only.',
                                style: TextStyle(
                                    color     : Color(0xFFFFB300),
                                    fontSize  : 11,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                          ]),
                        ),
                      ],

                      const SizedBox(height: 24),

                      // ── Animated form fields (slide on role switch) ───
                      SlideTransition(
                        position: _slideAnim,
                        child: FadeTransition(
                          opacity: _slideCtrl,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [

                              // ID field
                              _buildField(
                                controller : _idCtrl,
                                focusNode  : _idFocus,
                                label      : _roleIdLabel,
                                hint       : _roleIdHint,
                                icon       : _role.icon,
                                inputAction: TextInputAction.next,
                                capitalize : TextCapitalization.characters,
                                onSubmitted: (_) =>
                                    FocusScope.of(context).requestFocus(_codeFocus),
                                isDark     : isDark,
                                accentColor: roleAccent,
                              ),
                              const SizedBox(height: 14),

                              // Access Code field
                              _buildField(
                                controller : _codeCtrl,
                                focusNode  : _codeFocus,
                                label      : 'Access Code',
                                hint       : 'Enter access code',
                                icon       : Icons.lock_rounded,
                                inputAction: TextInputAction.done,
                                obscure    : _obscureCode,
                                onSubmitted: (_) {
                                  if (!_isLoading) _login();
                                },
                                isDark     : isDark,
                                accentColor: roleAccent,
                                suffixIcon : IconButton(
                                  icon: Icon(
                                    _obscureCode
                                        ? Icons.visibility_off_rounded
                                        : Icons.visibility_rounded,
                                    size : 20,
                                    color: isDark
                                        ? Colors.white38
                                        : AppTokens.lightTextHint,
                                  ),
                                  onPressed: () => setState(
                                      () => _obscureCode = !_obscureCode),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 28),

                      // ── Authenticate button ───────────────────────────
                      SizedBox(
                        width : double.infinity,
                        height: 56,
                        child : ElevatedButton(
                          onPressed: _isLoading ? null : _login,
                          style: ElevatedButton.styleFrom(
                            backgroundColor        : roleAccent,
                            foregroundColor        : Colors.black,
                            disabledBackgroundColor: roleAccent.withOpacity(0.3),
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(AppTokens.radiusButton)),
                            elevation: 0,
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width : 24, height: 24,
                                  child : CircularProgressIndicator(
                                      color: Colors.black, strokeWidth: 2.5))
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(_role.icon, size: 18, color: Colors.black),
                                    const SizedBox(width: 8),
                                    Text(
                                      isAdmin
                                          ? 'ENTER ADMIN PANEL'
                                          : 'AUTHENTICATE',
                                      style: const TextStyle(
                                        fontSize     : 15,
                                        fontWeight   : FontWeight.w900,
                                        letterSpacing: 1.3,
                                        color        : Colors.black,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Footer hint
                Text(
                  isAdmin
                      ? 'Admin session is not tracked in Firestore.'
                      : 'Contact your society office if you need access.',
                  style: TextStyle(
                      color  : isDark ? Colors.white24 : Colors.grey.shade400,
                      fontSize: 11),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Dynamic label / hint for ID field ──────────────────────────────────────

  String get _roleIdLabel {
    switch (_role) {
      case _Role.guard:    return 'Guard ID';
      case _Role.resident: return 'Flat Number';
      case _Role.admin:    return 'Admin ID';
    }
  }

  String get _roleIdHint {
    switch (_role) {
      case _Role.guard:    return 'e.g. GUARD1';
      case _Role.resident: return 'e.g. A101';
      case _Role.admin:    return 'Enter admin ID';
    }
  }

  // ─── Field builder ──────────────────────────────────────────────────────────

  Widget _buildField({
    required TextEditingController controller,
    required FocusNode             focusNode,
    required String                label,
    required String                hint,
    required IconData              icon,
    required TextInputAction       inputAction,
    required bool                  isDark,
    Color                          accentColor = AppTokens.cyanAction,
    bool                           obscure     = false,
    TextCapitalization             capitalize  = TextCapitalization.none,
    Widget?                        suffixIcon,
    void Function(String)?         onSubmitted,
  }) {
    final Color textColor   = isDark ? AppTokens.darkTextPrimary : AppTokens.lightTextPrimary;
    final Color labelColor  = isDark ? AppTokens.darkTextSecond  : AppTokens.lightTextSecond;
    final Color hintColor   = isDark ? AppTokens.darkTextHint    : AppTokens.lightTextHint;
    final Color fillColor   = isDark ? AppTokens.darkFieldFill   : AppTokens.lightFieldFill;
    final Color borderColor = isDark ? AppTokens.darkBorder      : AppTokens.lightBorder;

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
        prefixIcon: Icon(icon, color: accentColor, size: 20),
        suffixIcon: suffixIcon,
        filled    : true,
        fillColor : fillColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusInput),
          borderSide  : BorderSide(color: borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusInput),
          borderSide  : BorderSide(color: borderColor, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusInput),
          borderSide  : BorderSide(color: accentColor, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _RoleChip — three-way role toggle button
// ─────────────────────────────────────────────────────────────────────────────
class _RoleChip extends StatelessWidget {
  final _Role        role;
  final bool         selected;
  final bool         isDark;
  final VoidCallback onTap;

  const _RoleChip({
    required this.role,
    required this.selected,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color accent     = role.accentColor;
    final Color idleBorder = isDark ? Colors.white24     : AppTokens.lightBorder;
    final Color idleText   = isDark ? Colors.white54     : AppTokens.lightTextSecond;
    final Color idleIcon   = isDark ? Colors.white38     : AppTokens.lightTextSecond;
    final Color idleFill   = isDark ? Colors.transparent : AppTokens.lightBg;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding : const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color       : selected ? accent : idleFill,
          borderRadius: BorderRadius.circular(AppTokens.radiusInput),
          border: Border.all(
            color: selected ? accent : idleBorder,
            width: selected ? 2.0 : 1.5,
          ),
          boxShadow: selected
              ? [BoxShadow(
                  color    : accent.withOpacity(0.28),
                  blurRadius: 8,
                  offset   : const Offset(0, 3))]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(role.icon,
                size : 20,
                color: selected ? Colors.black : idleIcon),
            const SizedBox(height: 4),
            Text(role.label,
                style: TextStyle(
                  color     : selected ? Colors.black : idleText,
                  fontWeight: FontWeight.bold,
                  fontSize  : 11,
                  letterSpacing: 0.3,
                )),
          ],
        ),
      ),
    );
  }
}
