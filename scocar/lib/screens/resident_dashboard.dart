import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/notification_service.dart';
import 'add_vehicle_screen.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// ResidentDashboard
///
/// Changes from original:
///   ✅ NotificationService used (replaces raw FirebaseMessaging.getToken call)
///   ✅ _handleApproval() — calls notifyGuardOfDecision() after Firestore update
///   ✅ All UI preserved exactly; only notification logic added
/// ─────────────────────────────────────────────────────────────────────────────
class ResidentDashboard extends StatefulWidget {
  const ResidentDashboard({super.key});

  @override
  State<ResidentDashboard> createState() => _ResidentDashboardState();
}

class _ResidentDashboardState extends State<ResidentDashboard> {
  String? _flatId;
  bool _tokenSaved = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final String? args =
        ModalRoute.of(context)?.settings.arguments as String?;
    if (args != null && args != _flatId) {
      setState(() => _flatId = args);
      // ── NEW: Use NotificationService to save token (cleaner + refreshes) ──
      if (!_tokenSaved) {
        _tokenSaved = true;
        NotificationService().saveResidentToken(args);
      }
    }
  }

  // ============================================================
  // HANDLE APPROVE / DENY → update Firestore + notify guard
  // ============================================================
  Future<void> _handleApproval({
    required String docId,
    required String company,
    required String guardId,
    required bool approved,
  }) async {
    final String newStatus = approved ? 'APPROVED' : 'DENIED';

    // 1. Update Firestore
    await FirebaseFirestore.instance
        .collection('approvals')
        .doc(docId)
        .update({
      'status': newStatus,
      'respondedAt': FieldValue.serverTimestamp(),
    });

    // 2. ── NEW: Send push notification to guard ──
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
    final String activeFlat = _flatId ?? 'UNKNOWN';

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0A1A),
        appBar: AppBar(
          title: Text('FLAT $activeFlat',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFF141428),
          centerTitle: true,
          elevation: 0,
          actions: [
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
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // ── TAB 1: Vehicles ────────────────────────────────────────
            Column(
              children: [
                _buildProfileCard(activeFlat),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('REGISTERED VEHICLES',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: Colors.white54,
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

            // ── TAB 2: Gate Approvals ──────────────────────────────────
            _buildApprovalsList(activeFlat),
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
          return const Center(
              child: Text('No vehicles registered.',
                  style: TextStyle(color: Colors.white38)));
        }
        return ListView.builder(
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            final v =
                snapshot.data!.docs[index].data() as Map<String, dynamic>;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF141428),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10),
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
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              fontSize: 15)),
                      Text('Owner: ${v['ownerName'] ?? 'Verified'}',
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 12)),
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

  // ============================================================
  // GATE APPROVALS — resident sees pending requests + acts
  // ============================================================
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
                const Icon(Icons.check_circle_outline_rounded,
                    size: 56, color: Colors.white12),
                const SizedBox(height: 12),
                const Text('No pending delivery requests.',
                    style: TextStyle(color: Colors.white38, fontSize: 14)),
                const SizedBox(height: 4),
                Text('Flat: $flatId',
                    style: const TextStyle(
                        color: Colors.white24, fontSize: 12)),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            final doc = snapshot.data!.docs[index];
            final data = doc.data() as Map<String, dynamic>;
            return _buildApprovalCard(
              docId: doc.id,
              company: data['company'] ?? 'DELIVERY',
              status: data['status'] ?? 'PENDING',
              guardId: data['sentBy'] ?? 'GUARD', // who sent the request
              flatId: flatId,
            );
          },
        );
      },
    );
  }

  Widget _buildApprovalCard({
    required String docId,
    required String company,
    required String status,
    required String guardId,
    required String flatId,
  }) {
    Color statusColor;
    String statusText;
    IconData statusIcon;

    switch (status) {
      case 'APPROVED':
        statusColor = Colors.greenAccent;
        statusText = 'APPROVED — Guard will allow entry';
        statusIcon = Icons.check_circle_rounded;
        break;
      case 'DENIED':
        statusColor = Colors.redAccent;
        statusText = 'DENIED — Delivery turned away';
        statusIcon = Icons.cancel_rounded;
        break;
      case 'COMPLETED':
        statusColor = Colors.blueAccent;
        statusText = 'COMPLETED — Delivery entered';
        statusIcon = Icons.done_all_rounded;
        break;
      default:
        statusColor = Colors.orangeAccent;
        statusText = 'Awaiting your decision';
        statusIcon = Icons.notifications_active_rounded;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF141428),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: statusColor.withOpacity(0.4), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(company,
                  style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 14)),
            ),
            const Spacer(),
            Icon(statusIcon, color: statusColor, size: 20),
            const SizedBox(width: 6),
            Text(status,
                style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 13)),
          ]),
          const SizedBox(height: 10),
          Text(statusText,
              style: const TextStyle(color: Colors.white60, fontSize: 13)),

          // ── Approve / Deny — only for PENDING ─────────────────────
          if (status == 'PENDING') ...[
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.greenAccent,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    elevation: 0,
                  ),
                  // ── NEW: calls _handleApproval instead of raw Firestore update
                  onPressed: () => _handleApproval(
                    docId: docId,
                    company: company,
                    guardId: guardId,
                    approved: true,
                  ),
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text('APPROVE',
                      style: TextStyle(fontWeight: FontWeight.bold)),
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
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  // ── NEW: calls _handleApproval instead of raw Firestore update
                  onPressed: () => _handleApproval(
                    docId: docId,
                    company: company,
                    guardId: guardId,
                    approved: false,
                  ),
                  icon: const Icon(Icons.close_rounded, size: 18),
                  label: const Text('DENY',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ]),
          ],
        ],
      ),
    );
  }
}
