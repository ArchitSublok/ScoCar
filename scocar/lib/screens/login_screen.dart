import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../main.dart' show themeNotifier;
import 'log_movement_screen.dart' show activeGuardName;

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool isGuard = true;
  bool isLoading = false;
  bool _loginLock = false;

  final TextEditingController _idController       = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  @override
  void dispose() {
    _idController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _dismissKeyboard() => FocusScope.of(context).unfocus();

  Future<void> _login() async {
    if (_loginLock) return;
    _loginLock = true;

    final String userInputId = _idController.text.trim().toUpperCase();
    final String password    = _passwordController.text.trim();

    _dismissKeyboard();

    if (userInputId.isEmpty || password.isEmpty) {
      _showMessage('Error: Fields cannot be left blank.', Colors.orange);
      _loginLock = false;
      return;
    }

    setState(() => isLoading = true);

    try {
      DocumentSnapshot? userDoc;
      Map<String, dynamic>? data;

      if (isGuard) {
        // Guards: query by guardId field
        final QuerySnapshot querySnapshot = await FirebaseFirestore.instance
            .collection('guards')
            .where('guardId', isEqualTo: userInputId)
            .get();

        if (querySnapshot.docs.isEmpty) {
          if (mounted) {
            _showMessage('ACCESS DENIED: ID not registered in system.', Colors.red);
            setState(() => isLoading = false);
          }
          _loginLock = false;
          return;
        }
        userDoc = querySnapshot.docs.first;
        data = userDoc.data() as Map<String, dynamic>?;
      } else {
        // Residents: document ID IS the flat number (e.g. "A101")
        final DocumentSnapshot snap = await FirebaseFirestore.instance
            .collection('residents')
            .doc(userInputId)
            .get();

        if (!snap.exists) {
          if (mounted) {
            _showMessage('ACCESS DENIED: Flat not registered in system.', Colors.red);
            setState(() => isLoading = false);
          }
          _loginLock = false;
          return;
        }
        userDoc = snap;
        data = userDoc.data() as Map<String, dynamic>?;
      }

      if (data == null || !data.containsKey('accessCode') || data['accessCode'] == null) {
        if (mounted) {
          _showMessage('SERVER ERROR: Profile configuration incomplete.', Colors.redAccent);
          setState(() => isLoading = false);
        }
        _loginLock = false;
        return;
      }

      final String dbPassword = data['accessCode'].toString().trim();

      if (dbPassword != password) {
        if (mounted) {
          _showMessage('ACCESS DENIED: Incorrect Access Code.', Colors.red);
          setState(() => isLoading = false);
        }
        _loginLock = false;
        return;
      }

      // Feature 2: Capture guard name from Firestore or fallback to ID
      if (isGuard) {
        final guardName = (data['guardName'] as String?)?.trim() ?? '';
        // Update the global so LogMovementScreen always reads the live name
        activeGuardName = guardName.isNotEmpty ? guardName : userInputId;

        // Mark this guard as on duty in Firestore so residents can see who's working
        await FirebaseFirestore.instance
            .collection('guards')
            .doc(userDoc.id)
            .update({
          'onDuty'   : true,
          'dutyStart': FieldValue.serverTimestamp(),
          'guardName': activeGuardName,
          'guardId'  : userInputId,
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Access Granted! Loading dashboard...',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
            backgroundColor: Colors.green,
            duration: Duration(milliseconds: 800),
          ),
        );

        await Future.delayed(const Duration(milliseconds: 600));

        if (mounted) {
          Navigator.pushReplacementNamed(
            context,
            isGuard ? '/guard_dashboard' : '/resident_dashboard',
            arguments: userInputId,
          );
        }
      }
    } catch (e, stacktrace) {
      debugPrint('🚨 AUTH SYSTEM ERROR: $e\n$stacktrace');
      if (mounted) {
        _showMessage('System Error. Please try again.', Colors.red);
        setState(() => isLoading = false);
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
      _loginLock = false;
    }
  }

  void _showMessage(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(message,
            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 4),
      ));
  }

  @override
  Widget build(BuildContext context) {
    // Feature 1: Dark/light mode supported — use theme, not hardcoded colors
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0A0A1A) : const Color(0xFFF0F4FF);
    final cardColor = isDark ? const Color(0xFF141428) : Colors.white;
    final borderColor = isDark ? Colors.white10 : Colors.grey.shade200;
    final labelColor = isDark ? Colors.white54 : Colors.grey.shade600;
    final hintColor = isDark ? Colors.white24 : Colors.grey.shade400;
    final fieldFill = isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade50;
    final enabledBorder = isDark ? Colors.white12 : Colors.grey.shade300;
    final titleColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final subtitleColor = isDark ? Colors.cyanAccent : const Color(0xFF1565C0);

    return Scaffold(
      backgroundColor: bgColor,
      // Feature 1: AppBar with theme toggle button
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          ValueListenableBuilder<ThemeMode>(
            valueListenable: themeNotifier,
            builder: (_, mode, __) => IconButton(
              icon: Icon(
                mode == ThemeMode.dark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                color: Colors.white54,
              ),
              tooltip: 'Toggle Theme',
              onPressed: () {
                themeNotifier.value =
                    mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
              },
            ),
          ),
        ],
      ),
      body: GestureDetector(
        onTap: _dismissKeyboard,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Hero(
                  tag: 'logo',
                  child: Icon(Icons.qr_code_scanner_rounded,
                      size: 70, color: Colors.cyanAccent),
                ),
                const SizedBox(height: 8),
                Text('SCOCAR OS',
                    style: TextStyle(
                        color: titleColor,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 5)),
                Text('SECURE ACCESS TERMINAL',
                    style: TextStyle(
                        color: subtitleColor, fontSize: 10, letterSpacing: 2)),
                const SizedBox(height: 36),

                Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    color: cardColor,
                    border: Border.all(color: borderColor),
                    boxShadow: [BoxShadow(blurRadius: 30, color: isDark ? Colors.black38 : Colors.blueGrey.shade100)],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Role toggle
                      Row(
                        children: [
                          Expanded(
                            child: _roleButton(
                              title: 'Guard',
                              icon: Icons.shield_rounded,
                              selected: isGuard,
                              onTap: isLoading ? () {} : () => setState(() => isGuard = true),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _roleButton(
                              title: 'Resident',
                              icon: Icons.home_rounded,
                              selected: !isGuard,
                              onTap: isLoading ? () {} : () => setState(() => isGuard = false),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),

                      _buildField(
                        controller: _idController,
                        label: isGuard ? 'Guard ID' : 'Flat Number',
                        hint: isGuard ? 'e.g. G-001' : 'e.g. B-201',
                        icon: isGuard ? Icons.badge_rounded : Icons.home_rounded,
                        inputAction: TextInputAction.next,
                        capitalize: TextCapitalization.characters,
                      ),
                      const SizedBox(height: 16),

                      _buildField(
                        controller: _passwordController,
                        label: 'Access Code',
                        hint: 'Enter your access code',
                        icon: Icons.lock_rounded,
                        inputAction: TextInputAction.done,
                        obscure: true,
                        onSubmitted: (_) { if (!isLoading) _login(); },
                      ),
                      const SizedBox(height: 32),

                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: isLoading ? null : _login,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.cyanAccent,
                            foregroundColor: Colors.black,
                            disabledBackgroundColor: Colors.cyanAccent.withOpacity(0.3),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                            elevation: 0,
                          ),
                          child: isLoading
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                      color: Colors.black, strokeWidth: 2.5))
                              : const Text('AUTHENTICATE',
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.5)),
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

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required TextInputAction inputAction,
    bool obscure = false,
    TextCapitalization capitalize = TextCapitalization.none,
    void Function(String)? onSubmitted,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final labelColor = isDark ? Colors.white54 : Colors.grey.shade600;
    final hintColor = isDark ? Colors.white24 : Colors.grey.shade400;
    final fieldFill = isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade50;
    final borderNormal = isDark ? Colors.white12 : Colors.grey.shade300;

    return TextField(
      controller: controller,
      enabled: !isLoading,
      obscureText: obscure,
      textCapitalization: capitalize,
      textInputAction: inputAction,
      onSubmitted: onSubmitted,
      style: TextStyle(color: textColor),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: TextStyle(color: labelColor),
        hintStyle: TextStyle(color: hintColor),
        prefixIcon: Icon(icon, color: Colors.cyanAccent),
        filled: true,
        fillColor: fieldFill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: borderNormal),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: borderNormal),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.cyanAccent, width: 1.5),
        ),
      ),
    );
  }

  Widget _roleButton({
    required String title,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: selected ? Colors.cyanAccent : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: selected ? Colors.cyanAccent : Colors.white24, width: 1.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: selected ? Colors.black : Colors.white54),
            const SizedBox(width: 8),
            Text(title,
                style: TextStyle(
                    color: selected ? Colors.black : Colors.white54,
                    fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
