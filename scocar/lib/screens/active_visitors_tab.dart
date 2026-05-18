// ─────────────────────────────────────────────────────────────────────────────
// AREA 6: ActiveVisitorsTab
//
// A persistent tab on the Guard Dashboard showing all delivery runners
// currently inside the society (status == 'approved', exitTime == null).
//
// HOW TO ADD TO guard_dashboard.dart:
//
// 1. Wrap the Scaffold body in DefaultTabController(length: 2, ...) [or length: 3]
// 2. Add a TabBar to the AppBar's bottom:
//      bottom: const TabBar(tabs: [
//        Tab(icon: Icon(Icons.dashboard_rounded), text: 'Dashboard'),
//        Tab(icon: Icon(Icons.people_alt_rounded), text: 'Inside'),
//      ]),
// 3. Replace body: ListView(...) with body: TabBarView(children: [
//        _existingDashboardListView(),
//        const ActiveVisitorsTab(),
//      ])
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ActiveVisitorsTab extends StatelessWidget {
  const ActiveVisitorsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('approvals')
          .where('status', isEqualTo: 'COMPLETED') // COMPLETED = allowed inside
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.cyanAccent),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Text('Error: ${snapshot.error}',
                style: const TextStyle(color: Colors.redAccent)),
          );
        }

        // ── Filter: only those WITHOUT an exitTime ─────────────────────
        final docs = (snapshot.data?.docs ?? [])
            .where((doc) {
              final data = doc.data() as Map<String, dynamic>;
              return data['exitTime'] == null;
            })
            .toList();

        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.greenAccent.withOpacity(0.08),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_circle_outline_rounded,
                      color: Colors.greenAccent, size: 48),
                ),
                const SizedBox(height: 16),
                const Text('No active visitors inside',
                    style: TextStyle(
                        color: Colors.white60,
                        fontSize: 16,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 6),
                const Text('Society perimeter is clear.',
                    style: TextStyle(color: Colors.white30, fontSize: 13)),
              ],
            ),
          );
        }

        return Column(
          children: [
            // ── Header count ─────────────────────────────────────────
            Container(
              margin: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.orangeAccent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: Colors.orangeAccent.withOpacity(0.4), width: 1.5),
              ),
              child: Row(
                children: [
                  const Icon(Icons.people_alt_rounded,
                      color: Colors.orangeAccent, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    '${docs.length} visitor${docs.length == 1 ? '' : 's'} currently inside',
                    style: const TextStyle(
                        color: Colors.orangeAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 14),
                  ),
                ],
              ),
            ),

            // ── Visitor list ─────────────────────────────────────────
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final doc = docs[index];
                  final data = doc.data() as Map<String, dynamic>;
                  return _VisitorTile(docId: doc.id, data: data);
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Individual visitor tile with [Log Exit] button
// ─────────────────────────────────────────────────────────────────────────────
class _VisitorTile extends StatefulWidget {
  final String docId;
  final Map<String, dynamic> data;

  const _VisitorTile({required this.docId, required this.data});

  @override
  State<_VisitorTile> createState() => _VisitorTileState();
}

class _VisitorTileState extends State<_VisitorTile> {
  bool _loggingExit = false;

  Future<void> _logExit() async {
    setState(() => _loggingExit = true);
    try {
      await FirebaseFirestore.instance
          .collection('approvals')
          .doc(widget.docId)
          .update({
        'exitTime': FieldValue.serverTimestamp(),
        'status': 'EXITED',
      });
      // The StreamBuilder will automatically remove this tile because
      // exitTime will no longer be null after the Firestore write resolves.
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to log exit: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      setState(() => _loggingExit = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final String company = widget.data['company'] ?? 'Visitor';
    final String flat = widget.data['flatNumber'] ?? '?';
    final String? photoUrl = widget.data['visitorPhotoUrl'] as String?;

    // Time inside calculation
    String timeInsideLabel = '';
    final ts = widget.data['completedAt'] ?? widget.data['timestamp'];
    if (ts is Timestamp) {
      final diff = DateTime.now().difference(ts.toDate());
      if (diff.inMinutes < 60) {
        timeInsideLabel = '${diff.inMinutes}m inside';
      } else {
        timeInsideLabel = '${diff.inHours}h ${diff.inMinutes % 60}m inside';
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF141428),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          // ── Visitor thumbnail ───────────────────────────────────────
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: photoUrl != null && photoUrl.isNotEmpty
                ? Image.network(
                    photoUrl,
                    width: 60,
                    height: 60,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _avatarFallback(company),
                  )
                : _avatarFallback(company),
          ),
          const SizedBox(width: 14),

          // ── Details ─────────────────────────────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(company,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15)),
                const SizedBox(height: 3),
                Row(children: [
                  const Icon(Icons.apartment_rounded,
                      color: Colors.cyanAccent, size: 13),
                  const SizedBox(width: 4),
                  Text('Flat $flat',
                      style: const TextStyle(
                          color: Colors.cyanAccent, fontSize: 12)),
                ]),
                if (timeInsideLabel.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(timeInsideLabel,
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 11)),
                ],
              ],
            ),
          ),

          // ── Log Exit button ─────────────────────────────────────────
          SizedBox(
            width: 88,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              onPressed: _loggingExit ? null : _logExit,
              child: _loggingExit
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    )
                  : const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.exit_to_app_rounded,
                            color: Colors.white, size: 16),
                        SizedBox(height: 2),
                        Text('Log Exit',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatarFallback(String company) {
    return Container(
      width: 60,
      height: 60,
      color: Colors.white10,
      child: Center(
        child: Text(
          company.isNotEmpty ? company[0] : '?',
          style: const TextStyle(
              color: Colors.white60,
              fontWeight: FontWeight.bold,
              fontSize: 22),
        ),
      ),
    );
  }
}
