import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool isGuard = true;
  bool isLoading = false;

  // ==========================================
  // SECURITY LOCK: Prevents double-invocation of _login()
  // from simultaneous onSubmitted + button tap events.
  // ==========================================
  bool _loginLock = false;

  final TextEditingController _idController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  @override
  void dispose() {
    _idController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _dismissKeyboard() {
    FocusScope.of(context).unfocus();
  }

  // ==========================================
  // CORE AUTHENTICATION — LOCKED & DEFENSIVE
  // ==========================================
  Future<void> _login() async {
    // LOCK GATE: If a login attempt is already in flight, abort immediately.
    // This kills the race condition between the keyboard "done" action and
    // the AUTHENTICATE button both calling _login() at the same time.
    if (_loginLock) return;
    _loginLock = true;

    final String userInputId = _idController.text.trim().toUpperCase();
    final String password = _passwordController.text.trim();

    _dismissKeyboard();

    if (userInputId.isEmpty || password.isEmpty) {
      _showMessage("Error: Fields cannot be left blank.", Colors.orange);
      _loginLock = false;
      return;
    }

    setState(() => isLoading = true);

    try {
      final String collection = isGuard ? "guards" : "residents";
      final String fieldFilter = isGuard ? "guardId" : "flatNumber";

      final QuerySnapshot querySnapshot = await FirebaseFirestore.instance
          .collection(collection)
          .where(fieldFilter, isEqualTo: userInputId)
          .get();

      // ── GATE 1: ID must exist in Firestore ──────────────────────────────
      if (querySnapshot.docs.isEmpty) {
        if (mounted) {
          _showMessage("ACCESS DENIED: ID not registered in system.", Colors.red);
          setState(() => isLoading = false);
        }
        _loginLock = false;
        return; // Hard stop — nothing below runs.
      }

      final DocumentSnapshot userDoc = querySnapshot.docs.first;
      final data = userDoc.data() as Map<String, dynamic>?;

      // ── GATE 2: Document schema must contain accessCode ─────────────────
      if (data == null || !data.containsKey('accessCode') || data['accessCode'] == null) {
        if (mounted) {
          _showMessage("SERVER ERROR: Profile configuration incomplete.", Colors.redAccent);
          setState(() => isLoading = false);
        }
        _loginLock = false;
        return; // Hard stop.
      }

      final String dbPassword = data['accessCode'].toString().trim();

      // ── GATE 3: Access code must match exactly ───────────────────────────
      if (dbPassword != password) {
        if (mounted) {
          _showMessage("ACCESS DENIED: Incorrect Access Code.", Colors.red);
          setState(() => isLoading = false);
        }
        _loginLock = false;
        return; // Hard stop.
      }

      // ── ALL GATES PASSED: Navigate ───────────────────────────────────────
      if (mounted) {
        // Brief success flash before transition
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("✅ Access Granted! Loading dashboard...",
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
            backgroundColor: Colors.green,
            duration: Duration(milliseconds: 800),
          ),
        );

        // Small delay so the green snackbar is visible before the route push
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
      debugPrint("🚨 AUTH SYSTEM ERROR: $e\n$stacktrace");
      if (mounted) {
        _showMessage("System Error. Please try again.", Colors.red);
        setState(() => isLoading = false);
      }
    } finally {
      // Only reset loading if we didn't navigate away (mounted guard handles this)
      if (mounted) {
        setState(() => isLoading = false);
      }
      // Lock is released either via explicit return above or here on error
      _loginLock = false;
    }
  }

  void _showMessage(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message,
            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A1A),
      body: GestureDetector(
        onTap: _dismissKeyboard,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                // ── Logo ─────────────────────────────────────────────────
                const Hero(
                  tag: 'logo',
                  child: Icon(Icons.qr_code_scanner_rounded,
                      size: 70, color: Colors.cyanAccent),
                ),
                const SizedBox(height: 8),
                const Text("SCOCAR OS",
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 5)),
                const Text("SECURE ACCESS TERMINAL",
                    style: TextStyle(
                        color: Colors.cyanAccent, fontSize: 10, letterSpacing: 2)),
                const SizedBox(height: 36),

                // ── Card ─────────────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    color: const Color(0xFF141428),
                    border: Border.all(color: Colors.white10),
                    boxShadow: const [BoxShadow(blurRadius: 30, color: Colors.black38)],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Role toggle
                      Row(
                        children: [
                          Expanded(
                            child: _roleButton(
                              title: "Guard",
                              icon: Icons.shield_rounded,
                              selected: isGuard,
                              onTap: isLoading ? () {} : () => setState(() => isGuard = true),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _roleButton(
                              title: "Resident",
                              icon: Icons.home_rounded,
                              selected: !isGuard,
                              onTap: isLoading ? () {} : () => setState(() => isGuard = false),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),

                      // ID field
                      _buildField(
                        controller: _idController,
                        label: isGuard ? "Guard ID" : "Flat Number",
                        hint: isGuard ? "e.g. G-001" : "e.g. B-201",
                        icon: isGuard ? Icons.badge_rounded : Icons.home_rounded,
                        inputAction: TextInputAction.next,
                        capitalize: TextCapitalization.characters,
                      ),
                      const SizedBox(height: 16),

                      // Password field
                      _buildField(
                        controller: _passwordController,
                        label: "Access Code",
                        hint: "Enter your access code",
                        icon: Icons.lock_rounded,
                        inputAction: TextInputAction.done,
                        obscure: true,
                        onSubmitted: (_) {
                          if (!isLoading) _login();
                        },
                      ),
                      const SizedBox(height: 32),

                      // Submit button
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
                              : const Text("AUTHENTICATE",
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
    return TextField(
      controller: controller,
      enabled: !isLoading,
      obscureText: obscure,
      textCapitalization: capitalize,
      textInputAction: inputAction,
      onSubmitted: onSubmitted,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: Colors.white54),
        hintStyle: const TextStyle(color: Colors.white24),
        prefixIcon: Icon(icon, color: Colors.cyanAccent),
        filled: true,
        fillColor: Colors.white.withOpacity(0.05),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white12),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white12),
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
            Icon(icon,
                size: 18,
                color: selected ? Colors.black : Colors.white54),
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
