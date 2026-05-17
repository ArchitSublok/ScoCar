import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'log_movement_screen.dart';

class GuardDashboard extends StatefulWidget {
  const GuardDashboard({super.key});

  @override
  State<GuardDashboard> createState() => _GuardDashboardState();
}

class _GuardDashboardState extends State<GuardDashboard> {
  String? _guardId;

  static const List<Map<String, dynamic>> _deliveryVendors = [
    {
      'name': 'ZOMATO',
      'icon': Icons.fastfood_rounded,
      'color': Colors.redAccent,
      'photo': 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=150'
    },
    {
      'name': 'SWIGGY',
      'icon': Icons.delivery_dining_rounded,
      'color': Colors.orangeAccent,
      'photo': 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=150'
    },
    {
      'name': 'AMAZON',
      'icon': Icons.local_shipping_rounded,
      'color': Colors.amber,
      'photo': 'https://images.unsplash.com/photo-1521572267360-ee0c2909d518?w=150'
    },
    {
      'name': 'OTHER',
      'icon': Icons.pending_actions_rounded,
      'color': Colors.blueGrey,
      'photo': 'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?w=150'
    },
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments as String?;
    if (args != null && _guardId == null) {
      setState(() => _guardId = args);
    }
  }

  // ==========================================
  // SEND DELIVERY APPROVAL REQUEST TO RESIDENT
  // ==========================================
  void _showApprovalRequestModal(BuildContext context, {String initialVendor = "ZOMATO"}) {
    final TextEditingController flatController = TextEditingController();
    String selectedCompany = initialVendor;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Container(
              padding: EdgeInsets.only(
                top: 24,
                left: 24,
                right: 24,
                bottom: MediaQuery.of(context).viewInsets.bottom + 28,
              ),
              decoration: const BoxDecoration(
                color: Color(0xFF141428),
                borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 48,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    "Send Delivery Alert",
                    style: TextStyle(
                        fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    "The resident must APPROVE before you allow entry.",
                    style: TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                  const SizedBox(height: 24),

                  // Vendor chips
                  const Text("Delivery Provider",
                      style: TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.bold,
                          fontSize: 13)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _deliveryVendors.map((vendor) {
                      final bool sel = selectedCompany == vendor['name'];
                      return GestureDetector(
                        onTap: () =>
                            setModalState(() => selectedCompany = vendor['name']),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: sel
                                ? (vendor['color'] as Color)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            border:
                                Border.all(color: vendor['color'] as Color, width: 1.5),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(vendor['icon'] as IconData,
                                  size: 16,
                                  color: sel ? Colors.white : vendor['color'] as Color),
                              const SizedBox(width: 6),
                              Text(vendor['name'],
                                  style: TextStyle(
                                      color:
                                          sel ? Colors.white : vendor['color'] as Color,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13)),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),

                  // Flat number field
                  TextField(
                    controller: flatController,
                    textCapitalization: TextCapitalization.characters,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: "Destination Flat Number",
                      hintText: "e.g. B-201, A-101",
                      labelStyle: const TextStyle(color: Colors.white54),
                      hintStyle: const TextStyle(color: Colors.white24),
                      prefixIcon: const Icon(Icons.home_work_rounded,
                          color: Colors.cyanAccent),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.06),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: Colors.white12)),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: Colors.white12)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide:
                              const BorderSide(color: Colors.cyanAccent, width: 1.5)),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Dispatch button
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.cyanAccent,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      onPressed: () async {
                        final String flatNumber =
                            flatController.text.trim().toUpperCase();
                        if (flatNumber.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text("Please enter a flat number."),
                              backgroundColor: Colors.orange,
                            ),
                          );
                          return;
                        }

                        final vendorMatch = _deliveryVendors.firstWhere(
                          (v) => v['name'] == selectedCompany,
                          orElse: () => _deliveryVendors.last,
                        );

                        await FirebaseFirestore.instance
                            .collection('approvals')
                            .add({
                          'flatNumber': flatNumber,
                          'company': selectedCompany,
                          'status': 'PENDING',
                          'sentBy': _guardId ?? 'GUARD',
                          'timestamp': FieldValue.serverTimestamp(),
                          'visitorPhotoUrl': vendorMatch['photo'],
                        });

                        if (context.mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                  "📲 Request sent to Flat $flatNumber — waiting for resident approval."),
                              backgroundColor: Colors.blueAccent,
                            ),
                          );
                        }
                      },
                      child: const Text(
                        "SEND APPROVAL REQUEST",
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            letterSpacing: 1),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ==========================================
  // ALLOW ENTRY — called when resident approved
  // ==========================================
  Future<void> _allowDeliveryEntry(
      String docId, String flatNumber, String company) async {
    // Mark approval as completed
    await FirebaseFirestore.instance.collection('approvals').doc(docId).update({
      'status': 'COMPLETED',
      'completedAt': FieldValue.serverTimestamp(),
    });

    // Log the entry in gates logs
    await FirebaseFirestore.instance.collection('logs').add({
      'type': 'ENTRY',
      'company': company,
      'flatNumber': flatNumber,
      'plateNumber': '— DELIVERY —',
      'guardId': _guardId ?? 'GUARD',
      'timestamp': FieldValue.serverTimestamp(),
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              "✅ $company delivery to $flatNumber — Entry logged & gate cleared."),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  // ==========================================
  // DENY: Guard marks as DENIED and turns away
  // ==========================================
  Future<void> _denyEntry(String docId, String company, String flatNumber) async {
    await FirebaseFirestore.instance
        .collection('approvals')
        .doc(docId)
        .update({'status': 'DENIED'});

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("🚫 $company delivery to $flatNumber — Turned away."),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A1A),
      appBar: AppBar(
        title: Text(
          _guardId != null ? "Guard: $_guardId" : "Guard Control Terminal",
          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
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
      ),
      body: ListView(
        padding: const EdgeInsets.all(0),
        children: [
          _buildLiveStats(),

          // ── Quick Dispatch Grid ──────────────────────────────────────
          _sectionHeader("Delivery Approval Hub"),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 2.3,
              ),
              itemCount: _deliveryVendors.length,
              itemBuilder: (context, index) {
                final vendor = _deliveryVendors[index];
                return ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: vendor['color'] as Color,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () =>
                      _showApprovalRequestModal(context, initialVendor: vendor['name']),
                  icon: Icon(vendor['icon'] as IconData, color: Colors.white, size: 18),
                  label: Text(vendor['name'],
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13)),
                );
              },
            ),
          ),

          const SizedBox(height: 20),

          // ── Vehicle / General Movement ───────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    backgroundColor: Colors.transparent,
                    builder: (context) => const LogMovementScreen(),
                  );
                },
                icon: const Icon(Icons.swap_vert_rounded, color: Colors.white),
                label: const Text("LOG VEHICLE / GENERAL MOVEMENT",
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // ── LIVE DELIVERY REQUEST STATUS FEED ───────────────────────
          _sectionHeader("Live Delivery Requests"),
          _buildLiveDeliveryRequests(),

          const SizedBox(height: 12),

          // ── Gate Logs ────────────────────────────────────────────────
          _sectionHeader("Recent Gate Logs"),
          _buildLogsStream(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ==========================================
  // LIVE DELIVERY REQUESTS — streams from Firestore
  // Shows PENDING (waiting), APPROVED (resident said yes),
  // DENIED (resident said no), COMPLETED (guard let in)
  // ==========================================
  Widget _buildLiveDeliveryRequests() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('approvals')
          .where('status', whereIn: ['PENDING', 'APPROVED', 'DENIED'])
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator(color: Colors.cyanAccent)),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF141428),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10),
              ),
              child: const Center(
                child: Text("No active delivery requests.",
                    style: TextStyle(color: Colors.white38)),
              ),
            ),
          );
        }

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            final doc = snapshot.data!.docs[index];
            final data = doc.data() as Map<String, dynamic>;
            final String status = data['status'] ?? 'PENDING';
            final String flat = data['flatNumber'] ?? '?';
            final String company = data['company'] ?? 'DELIVERY';

            return _buildDeliveryRequestCard(
              docId: doc.id,
              flat: flat,
              company: company,
              status: status,
            );
          },
        );
      },
    );
  }

  Widget _buildDeliveryRequestCard({
    required String docId,
    required String flat,
    required String company,
    required String status,
  }) {
    // Color + label based on status
    Color statusColor;
    IconData statusIcon;
    String statusLabel;

    switch (status) {
      case 'APPROVED':
        statusColor = Colors.greenAccent;
        statusIcon = Icons.check_circle_rounded;
        statusLabel = "APPROVED — You may allow entry";
        break;
      case 'DENIED':
        statusColor = Colors.redAccent;
        statusIcon = Icons.cancel_rounded;
        statusLabel = "DENIED — Turn delivery away";
        break;
      default:
        statusColor = Colors.orangeAccent;
        statusIcon = Icons.hourglass_top_rounded;
        statusLabel = "PENDING — Waiting for resident...";
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF141428),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: statusColor.withOpacity(0.4), width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Company icon chip
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
                          fontSize: 13)),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text("Flat: $flat",
                      style: const TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.bold,
                          fontSize: 13)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(statusIcon, color: statusColor, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(statusLabel,
                      style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 13)),
                ),
              ],
            ),

            // ── Action buttons only for APPROVED and DENIED ──────────
            if (status == 'APPROVED') ...[
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.greenAccent,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    elevation: 0,
                  ),
                  onPressed: () => _allowDeliveryEntry(docId, flat, company),
                  icon: const Icon(Icons.door_sliding_rounded, size: 20),
                  label: const Text("ALLOW ENTRY & LOG",
                      style: TextStyle(
                          fontWeight: FontWeight.bold, letterSpacing: 1)),
                ),
              ),
            ],

            if (status == 'DENIED') ...[
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: const BorderSide(color: Colors.redAccent),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () => _denyEntry(docId, company, flat),
                  icon: const Icon(Icons.block_rounded, size: 20),
                  label: const Text("DISMISS & TURN AWAY",
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],

            // Pending — show cancel option
            if (status == 'PENDING') ...[
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () {
                    FirebaseFirestore.instance
                        .collection('approvals')
                        .doc(docId)
                        .delete();
                  },
                  icon: const Icon(Icons.close_rounded,
                      size: 16, color: Colors.white38),
                  label: const Text("Cancel request",
                      style: TextStyle(color: Colors.white38, fontSize: 12)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLiveStats() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('logs').snapshots(),
      builder: (context, snap) {
        final int total = snap.data?.docs.length ?? 0;
        final int entries = snap.data?.docs
                .where((d) => (d.data() as Map)['type'] == 'ENTRY')
                .length ??
            0;
        return Container(
          margin: const EdgeInsets.all(20),
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [Color(0xFF0D47A1), Color(0xFF1565C0)]),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _StatTile(value: "$entries", label: "In Society"),
              Container(width: 1, height: 40, color: Colors.white24),
              _StatTile(value: "$total", label: "Daily Total"),
            ],
          ),
        );
      },
    );
  }

  Widget _sectionHeader(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
      child: Text(label,
          style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Colors.white70,
              letterSpacing: 0.5)),
    );
  }

  Widget _buildLogsStream() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('logs')
          .orderBy('timestamp', descending: true)
          .limit(20)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(
                child: Text("No gate logs yet.",
                    style: TextStyle(color: Colors.white38))),
          );
        }

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            final data =
                snapshot.data!.docs[index].data() as Map<String, dynamic>;
            final String type = data['type'] ?? 'ENTRY';
            final bool isEntry = type == 'ENTRY';
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF141428),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color:
                          (isEntry ? Colors.greenAccent : Colors.redAccent).withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isEntry
                          ? Icons.login_rounded
                          : Icons.logout_rounded,
                      color: isEntry ? Colors.greenAccent : Colors.redAccent,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(data['plateNumber'] ?? 'Unknown',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600)),
                        Text(
                            "${data['company'] ?? 'GENERAL'}  •  Flat: ${data['flatNumber'] ?? 'N/A'}",
                            style: const TextStyle(
                                color: Colors.white38, fontSize: 12)),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color:
                          (isEntry ? Colors.greenAccent : Colors.redAccent).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(type,
                        style: TextStyle(
                            color:
                                isEntry ? Colors.greenAccent : Colors.redAccent,
                            fontSize: 11,
                            fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _StatTile extends StatelessWidget {
  final String value, label;
  const _StatTile({required this.value, required this.label});
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: const TextStyle(
                fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ],
    );
  }
}
