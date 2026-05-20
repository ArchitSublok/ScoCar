import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/notification_service.dart';
import 'add_vehicle_screen.dart';
import '../../main.dart' show themeNotifier;

class ResidentDashboard extends StatefulWidget {
  const ResidentDashboard({super.key});

  @override
  State<ResidentDashboard> createState() => _ResidentDashboardState();
}

class _ResidentDashboardState extends State<ResidentDashboard> {
  String? _flatId;
  bool _tokenSaved = false;

  // Feature 6: Track last seen doc count to detect new arrivals
  int _lastPendingCount = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final String? args =
        ModalRoute.of(context)?.settings.arguments as String?;
    if (args != null && args != _flatId) {
      setState(() => _flatId = args);
      if (!_tokenSaved) {
        _tokenSaved = true;
        NotificationService().saveResidentToken(args);
      }
    }
  }

  Future<void> _handleApproval({
    required String docId,
    required String company,
    required String guardId,
    required bool approved,
  }) async {
    final String newStatus = approved ? 'APPROVED' : 'DENIED';

    await FirebaseFirestore.instance
        .collection('approvals')
        .doc(docId)
        .update({
      'status': newStatus,
      'respondedAt': FieldValue.serverTimestamp(),
    });

    await NotificationService().notifyGuardOfDecision(
      guardId: guardId,
      flatNumber: _flatId ?? 'UNKNOWN',
      company: company,
      approved: approved,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(approved
            ? '✅ $company delivery approved — Guard has been notified.'
            : '🚫 $company delivery denied — Guard has been notified.'),
        backgroundColor: approved ? Colors.green : Colors.redAccent,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    // Feature 1: Use theme colors
    final theme = Theme.of(context);
    final String activeFlat = _flatId ?? 'UNKNOWN';

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          title: Text('FLAT $activeFlat',
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold)),
          backgroundColor: theme.appBarTheme.backgroundColor,
          centerTitle: true,
          elevation: 0,
          actions: [
            // Dark/Light mode toggle
            ValueListenableBuilder<ThemeMode>(
              valueListenable: themeNotifier,
              builder: (_, mode, __) => IconButton(
                icon: Icon(
                  mode == ThemeMode.dark
                      ? Icons.light_mode_rounded
                      : Icons.dark_mode_rounded,
                  color: Colors.white70,
                ),
                tooltip: mode == ThemeMode.dark ? 'Light Mode' : 'Dark Mode',
                onPressed: () {
                  themeNotifier.value = mode == ThemeMode.dark
                      ? ThemeMode.light
                      : ThemeMode.dark;
                },
              ),
            ),
            IconButton(
              icon: const Icon(Icons.logout_rounded, color: Colors.white54),
              onPressed: () =>
                  Navigator.pushReplacementNamed(context, '/'),
            ),
          ],
          bottom: const TabBar(
            indicatorColor: Colors.cyanAccent,
            labelColor: Colors.cyanAccent,
            unselectedLabelColor: Colors.white38,
            tabs: [
              Tab(icon: Icon(Icons.directions_car), text: 'My Vehicles'),
              Tab(icon: Icon(Icons.gpp_good_rounded), text: 'Gate Approvals'),
              Tab(icon: Icon(Icons.shield_rounded), text: 'Guard On Duty'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // TAB 1: Vehicles
            Column(
              children: [
                _buildProfileCard(activeFlat),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('REGISTERED VEHICLES',
                          style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onSurface.withOpacity(0.5),
                              letterSpacing: 1)),
                      ElevatedButton.icon(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  AddVehicleScreen(defaultFlat: activeFlat)),
                        ),
                        icon: const Icon(Icons.add,
                            size: 16, color: Colors.black),
                        label: const Text('ADD VEHICLE',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.black)),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.cyanAccent,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10))),
                      ),
                    ],
                  ),
                ),
                Expanded(child: _buildVehicleList(activeFlat)),
              ],
            ),

            // TAB 2: Gate Approvals with live OTP + driver profile
            _buildApprovalsList(activeFlat),

            // TAB 3: Guard On Duty
            _buildGuardOnDutyTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileCard(String flatId) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('residents')
          .doc(flatId)
          .snapshots(),
      builder: (context, snapshot) {
        String ownerName = 'Resident Owner';
        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>?;
          ownerName = data?['ownerName'] ?? 'Resident Owner';
        }
        return Container(
          margin: const EdgeInsets.all(20),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0D47A1), Color(0xFF1565C0)],
            ),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(children: [
            const CircleAvatar(
              radius: 28,
              backgroundColor: Colors.white24,
              child: Icon(Icons.person_rounded, size: 32, color: Colors.white),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(ownerName,
                      style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                  const SizedBox(height: 3),
                  Text('Apartment: $flatId',
                      style: const TextStyle(
                          color: Colors.white60, fontSize: 13)),
                ],
              ),
            ),
          ]),
        );
      },
    );
  }

  Widget _buildVehicleList(String flatId) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('vehicles')
          .where('flatNumber', isEqualTo: flatId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: Colors.cyanAccent));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
              child: Text('No vehicles registered.',
                  style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.5))));
        }
        return ListView.builder(
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            final v =
                snapshot.data!.docs[index].data() as Map<String, dynamic>;
            return Container(
              margin:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: const BoxDecoration(
                      color: Colors.blueAccent, shape: BoxShape.circle),
                  child: const Icon(Icons.directions_car,
                      color: Colors.white, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(v['plateNumber'] ?? 'UNKNOWN',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).textTheme.bodyMedium?.color,
                              fontSize: 15)),
                      Text('Owner: ${v['ownerName'] ?? 'Verified'}',
                          style: TextStyle(
                              color: Theme.of(context).textTheme.bodySmall?.color, fontSize: 12)),
                    ],
                  ),
                ),
              ]),
            );
          },
        );
      },
    );
  }

  // Feature 6 + 7: Approvals list with sound alert + profile cards
  Widget _buildApprovalsList(String flatId) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('approvals')
          .where('flatNumber', isEqualTo: flatId)
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: Colors.cyanAccent));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle_outline_rounded,
                    size: 56, color: Theme.of(context).dividerColor),
                const SizedBox(height: 12),
                Text('No pending delivery requests.',
                    style:
                        TextStyle(color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.6), fontSize: 14)),
                const SizedBox(height: 4),
                Text('Flat: $flatId',
                    style: TextStyle(
                        color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.4), fontSize: 12)),
              ],
            ),
          );
        }

        // Feature 6: Count PENDING docs and alert if new one arrived
        final docs = snapshot.data!.docs;
        final int currentPending = docs
            .where((d) =>
                (d.data() as Map<String, dynamic>)['status'] == 'PENDING')
            .length;

        // Schedule post-frame callback so setState doesn't fire during build
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (currentPending > _lastPendingCount && mounted) {
            _lastPendingCount = currentPending;
            // Show a prominent alert banner (audioplayers not in pubspec yet —
            // using SnackBar + vibration-style notice as the in-app ringer)
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Row(
                  children: [
                    Icon(Icons.notifications_active_rounded,
                        color: Colors.white),
                    SizedBox(width: 10),
                    Text('🔔 New delivery request at your gate!',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 5),
                action: SnackBarAction(
                  label: 'VIEW',
                  textColor: Colors.white,
                  onPressed: () {},
                ),
              ),
            );
          } else if (currentPending < _lastPendingCount && mounted) {
            _lastPendingCount = currentPending;
          }
        });

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc  = docs[index];
            final data = doc.data() as Map<String, dynamic>;
            return _buildApprovalCard(
              docId  : doc.id,
              data   : data,
              flatId : flatId,
            );
          },
        );
      },
    );
  }

  // Feature 7: Enhanced profile card for resident
  Widget _buildApprovalCard({
    required String docId,
    required Map<String, dynamic> data,
    required String flatId,
  }) {
    final String company   = data['company']    ?? 'DELIVERY';
    final String status    = data['status']     ?? 'PENDING';
    final String guardId   = data['sentBy']     ?? data['guardName'] ?? 'GUARD';
    final String driverName = data['driverName'] ?? 'Unknown Driver';
    final String driverPic  = data['driverPic']  ?? '';
    final String plate      = data['plateNumber'] ?? '—';
    final String vehicleModel = data['vehicleModel'] ?? '—';
    // Feature 4: Show OTP to resident
    final String? otpCode   = data['otpCode'] as String?;

    Color statusColor;
    String statusText;
    IconData statusIcon;

    switch (status) {
      case 'APPROVED':
        statusColor = Colors.greenAccent;
        statusText  = 'APPROVED — Guard will allow entry';
        statusIcon  = Icons.check_circle_rounded;
        break;
      case 'DENIED':
        statusColor = Colors.redAccent;
        statusText  = 'DENIED — Delivery turned away';
        statusIcon  = Icons.cancel_rounded;
        break;
      case 'COMPLETED':
        statusColor = Colors.blueAccent;
        statusText  = 'COMPLETED — Delivery entered';
        statusIcon  = Icons.done_all_rounded;
        break;
      default:
        statusColor = Colors.orangeAccent;
        statusText  = 'Awaiting your decision';
        statusIcon  = Icons.notifications_active_rounded;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: statusColor.withOpacity(0.4), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Feature 7: Driver photo + identity header
          ClipRRect(
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
            child: Stack(
              children: [
                if (driverPic.isNotEmpty)
                  SizedBox(
                    width: double.infinity,
                    height: 120,
                    child: Image.network(
                      driverPic,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        height: 120,
                         color: Theme.of(context).cardColor,
                        child: const Center(
                          child: Icon(Icons.person_rounded,
                              size: 60, color: Colors.white24),
                        ),
                      ),
                    ),
                  ),
                // Gradient overlay for readability
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 60,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Theme.of(context).cardColor.withOpacity(0.95),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 10,
                  left: 14,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(driverName,
                          style: TextStyle(
                              color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16)),
                      Text(plate,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Status + company row
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(company,
                        style: TextStyle(
                            color: statusColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 13)),
                  ),
                  const SizedBox(width: 8),
                  _infoChip(vehicleModel, Colors.blueAccent),
                  const Spacer(),
                  Icon(statusIcon, color: statusColor, size: 18),
                  const SizedBox(width: 5),
                  Text(status,
                      style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 12)),
                ]),
                const SizedBox(height: 8),
                Text(statusText,
                    style: TextStyle(
                        color: Theme.of(context).textTheme.bodySmall?.color, fontSize: 13)),

                // Feature 4: OTP display
                if (otpCode != null && otpCode.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.cyanAccent.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: Colors.cyanAccent.withOpacity(0.4)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.vpn_key_rounded,
                            color: Colors.cyanAccent, size: 18),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('SHARE THIS OTP WITH VISITOR',
                                style: TextStyle(
                                    color: Colors.white38,
                                    fontSize: 10,
                                    letterSpacing: 1)),
                            Text(otpCode,
                                style: const TextStyle(
                                    color: Colors.cyanAccent,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 22,
                                    letterSpacing: 6)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],

                // Approve / Deny — only for PENDING
                if (status == 'PENDING') ...[
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.greenAccent,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          padding:
                              const EdgeInsets.symmetric(vertical: 12),
                          elevation: 0,
                        ),
                        onPressed: () => _handleApproval(
                          docId: docId,
                          company: company,
                          guardId: guardId,
                          approved: true,
                        ),
                        icon: const Icon(Icons.check_rounded, size: 18),
                        label: const Text('APPROVE',
                            style:
                                TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                          side: const BorderSide(color: Colors.redAccent),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          padding:
                              const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: () => _handleApproval(
                          docId: docId,
                          company: company,
                          guardId: guardId,
                          approved: false,
                        ),
                        icon: const Icon(Icons.close_rounded, size: 18),
                        label: const Text('DENY',
                            style:
                                TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ]),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }


  // ─── TAB 3: Guard On Duty ─────────────────────────────────────────────────
  Widget _buildGuardOnDutyTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('guards')
          .where('onDuty', isEqualTo: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: Colors.cyanAccent));
        }

        final guards = snapshot.hasData ? snapshot.data!.docs : <DocumentSnapshot>[];
        final onDutyGuards = guards
            .map((d) => d.data() as Map<String, dynamic>)
            .toList();

        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Status header card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF0D2137), Color(0xFF0A3D62)],
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: onDutyGuards.isEmpty
                      ? Colors.redAccent.withOpacity(0.4)
                      : Colors.greenAccent.withOpacity(0.4),
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: onDutyGuards.isEmpty
                          ? Colors.redAccent.withOpacity(0.15)
                          : Colors.greenAccent.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      onDutyGuards.isEmpty
                          ? Icons.no_accounts_rounded
                          : Icons.shield_rounded,
                      color: onDutyGuards.isEmpty
                          ? Colors.redAccent
                          : Colors.greenAccent,
                      size: 32,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          onDutyGuards.isEmpty
                              ? 'No Guard On Duty'
                              : 'Gate is Secured',
                          style: TextStyle(
                            color: onDutyGuards.isEmpty
                                ? Colors.redAccent
                                : Colors.greenAccent,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          onDutyGuards.isEmpty
                              ? 'No guard is currently logged in to the system.'
                              : '${onDutyGuards.length} guard${onDutyGuards.length > 1 ? "s are" : " is"} actively on duty.',
                          style: const TextStyle(
                              color: Colors.white60, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            if (onDutyGuards.isEmpty) ...[
              const Center(
                child: Padding(
                  padding: EdgeInsets.only(top: 40),
                  child: Column(
                    children: [
                      Icon(Icons.person_off_rounded,
                          size: 64, color: Colors.white12),
                      SizedBox(height: 12),
                      Text(
                        'Your gate is currently unmonitored.',
                        style: TextStyle(
                            color: Colors.white38, fontSize: 14),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ] else ...[
              const Text(
                'GUARDS CURRENTLY ON DUTY',
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 12),
              ...onDutyGuards.map((guard) => _buildGuardCard(guard)),
            ],
          ],
        );
      },
    );
  }

  Widget _buildGuardCard(Map<String, dynamic> guard) {
    final String name    = guard['guardName'] ?? guard['guardId'] ?? 'Guard';
    final String id      = guard['guardId']   ?? '—';
    final Timestamp? ts  = guard['dutyStart'] as Timestamp?;
    final DateTime? start = ts?.toDate();
    final String since   = start != null
        ? '${start.hour.toString().padLeft(2, "0")}:${start.minute.toString().padLeft(2, "0")}'
        : 'Unknown time';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.greenAccent.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: Colors.blueAccent.withOpacity(0.2),
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : 'G',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Positioned(
                bottom: 2,
                right: 2,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Colors.greenAccent,
                    shape: BoxShape.circle,
                     border: Border.all(color: Theme.of(context).cardColor, width: 2),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
                const SizedBox(height: 3),
                Text('ID: $id',
                    style: const TextStyle(
                        color: Colors.white54, fontSize: 12)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.greenAccent.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: Colors.greenAccent.withOpacity(0.3)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.circle,
                              size: 7, color: Colors.greenAccent),
                          SizedBox(width: 5),
                          Text('ACTIVE',
                              style: TextStyle(
                                  color: Colors.greenAccent,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.8)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Since $since',
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Icon(Icons.verified_user_rounded,
              color: Colors.greenAccent, size: 22),
        ],
      ),
    );
  }

  Widget _infoChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text,
          style: TextStyle(
              color: color, fontWeight: FontWeight.bold, fontSize: 11)),
    );
  }
}
