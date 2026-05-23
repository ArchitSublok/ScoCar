import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/log_sort_service.dart';
import 'log_movement_screen.dart' show activeGuardName;
import '../services/notification_service.dart';
import '../main.dart' show themeNotifier;

import 'discrepancy_alert_overlay.dart';
import 'delivery_request_card.dart';
import 'unified_entry_form.dart';          // ← new unified form
import 'active_visitors_tab.dart';
import 'camera_registration_screen.dart';

// NOTE: fast_delivery_entry_form.dart and log_movement_screen.dart imports
// have been intentionally removed — functionality merged into UnifiedEntryForm.

class GuardDashboard extends StatefulWidget {
  const GuardDashboard({super.key});

  @override
  State<GuardDashboard> createState() => _GuardDashboardState();
}

class _GuardDashboardState extends State<GuardDashboard> {
  String? _guardId;
  bool _tokenSaved = false;
  String _fetchedGuardName = 'Guard On Duty';

  // ─── Lifecycle ────────────────────────────────────────────────────────────

  Future<void> _fetchGuardProfile(String guardId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('guards')
          .doc(guardId)
          .get();

      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        setState(() {
          _fetchedGuardName = data['guardName'] ?? data['name'] ?? 'Guard On Duty';
        });
      }
    } catch (e) {
      debugPrint("Error fetching guard profile: $e");
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments as String?;
    if (args != null && _guardId == null) {
      setState(() => _guardId = args);
      _fetchGuardProfile(args);
    }
    if (_guardId != null && !_tokenSaved) {
      _tokenSaved = true;
      NotificationService().saveGuardToken(_guardId!);
    }
  }

  // ─── Delivery request actions ─────────────────────────────────────────────

  Future<void> _allowDeliveryEntry(
      String docId, String flatNumber) async {
    await FirebaseFirestore.instance
        .collection('approvals')
        .doc(docId)
        .update({
      'status': 'COMPLETED',
      'completedAt': FieldValue.serverTimestamp(),
    });

    await FirebaseFirestore.instance.collection('logs').add({
      'type': 'ENTRY',
      'entryType': 'Delivery',
      'company': 'DELIVERY',
      'flatNumber': flatNumber,
      'plateNumber': '— DELIVERY —',
      'guardId': _guardId ?? 'GUARD',
      'guardName': _fetchedGuardName, // 👈 FIXED: Changed from activeGuardName
      'vehicleModel': 'Unknown',
      'driverName': 'Delivery Agent',
      'driverPic':
          'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=300',
      'otpCode': null,
      'timestamp': FieldValue.serverTimestamp(),
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            '✅ Delivery to $flatNumber — Entry logged & gate cleared.'),
        backgroundColor: Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    }
  }

  Future<void> _denyEntry(String docId, String flatNumber) async {
    // Delete the approval doc so it immediately disappears from the live list.
    // We also set status to DENIED first so the resident dashboard can still
    // show a brief "denied" state before the doc is removed.
    await FirebaseFirestore.instance
        .collection('approvals')
        .doc(docId)
        .update({'status': 'DENIED'});

    // Small delay so the resident's real-time listener catches the DENIED state,
    // then delete the document to clean it off the guard's live list.
    await Future.delayed(const Duration(milliseconds: 800));
    await FirebaseFirestore.instance
        .collection('approvals')
        .doc(docId)
        .delete();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('🚫 Delivery to $flatNumber — Turned away.'),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    }
  }

  // ─── Reusable widgets ─────────────────────────────────────────────────────

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 20, right: 20, top: 24, bottom: 12),
      child: Text(
        title,
        style: TextStyle(
          color: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.color
                  ?.withOpacity(0.7) ??
              Colors.white70,
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildLiveStats() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          // 👈 FIXED: Changed from activeGuardName to _fetchedGuardName
          _statColumn('On Duty', _fetchedGuardName, Colors.greenAccent),
          Container(width: 1, height: 40, color: Colors.white10),
          _statColumn('Terminal Status', 'SECURE', Colors.cyanAccent),
        ],
      ),
    );
  }

  Widget _statColumn(String label, String value, Color highlight) {
    return Column(
      children: [
        Text(label,
            style: TextStyle(
                color: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.color
                        ?.withOpacity(0.6) ??
                    Colors.white38,
                fontSize: 12)),
        const SizedBox(height: 4),
        Text(value,
            style: TextStyle(
                color: highlight,
                fontWeight: FontWeight.bold,
                fontSize: 15)),
      ],
    );
  }

  // ── Main Entry Button ──────────────────────────────────────────────────────

  Widget _buildUnifiedEntryButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: SizedBox(
        width: double.infinity,
        height: 58,
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.cyanAccent,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            elevation: 6,
            shadowColor: Colors.cyanAccent.withOpacity(0.35),
          ),
          onPressed: () => UnifiedEntryForm.show(
            context,
            guardId: _guardId,
          ),
          icon: const Icon(Icons.add_circle_rounded,
              color: Colors.black, size: 22),
          label: const Text(
            'NEW ENTRY LOG',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
              fontSize: 15,
            ),
          ),
        ),
      ),
    );
  }

  // ── Recent Logs Stream ─────────────────────────────────────────────────────

  Widget _buildLogsStream() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('logs')
          .orderBy('timestamp', descending: true)
          .limit(5)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Padding(
            padding:
                const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
            child: Text(
              'No recent logs recorded.',
              style: TextStyle(
                  color: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.color
                      ?.withOpacity(0.6)),
            ),
          );
        }

        // Sort via LogSortService — Dart equivalent of JS sortFirebaseLogs(logs, 'desc')
        final sortedDocs = LogSortService.sort(
          snapshot.data!.docs.toList(),
          direction: SortDirection.desc,
        );
        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: sortedDocs.length,
          itemBuilder: (context, index) {
            final log = sortedDocs[index].data() as Map<String, dynamic>;
            final String type = log['type'] ?? 'ENTRY';
            final String entryType = log['entryType'] ?? '';

            final String subtitle = [
              if (entryType.isNotEmpty) entryType,
              if (log['driverName'] != null) log['driverName'] as String,
              if ((log['plateNumber'] ?? '').isNotEmpty &&
                  log['plateNumber'] != '— DELIVERY —')
                log['plateNumber'] as String,
            ].join(' · ');

            return ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
              leading: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: (type == 'ENTRY'
                          ? Colors.greenAccent
                          : Colors.orangeAccent)
                      .withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  type == 'ENTRY'
                      ? Icons.login_rounded
                      : Icons.logout_rounded,
                  color: type == 'ENTRY'
                      ? Colors.greenAccent
                      : Colors.orangeAccent,
                  size: 18,
                ),
              ),
              title: Text(
                log['company'] ?? log['flatNumber'] ?? '—',
                style: TextStyle(
                    color: Theme.of(context).textTheme.bodyMedium?.color,
                    fontSize: 14,
                    fontWeight: FontWeight.w600),
              ),
              subtitle: subtitle.isNotEmpty
                  ? Text(
                      subtitle,
                      style: TextStyle(
                          color: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.color
                              ?.withOpacity(0.7),
                          fontSize: 12),
                    )
                  : null,
              trailing: Text(
                'Just now',
                style: TextStyle(
                    color: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.color
                        ?.withOpacity(0.4),
                    fontSize: 11),
              ),
            );
          },
        );
      },
    );
  }

  // ── Live Delivery Requests ─────────────────────────────────────────────────

  Widget _buildLiveDeliveryRequests() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('approvals')
          // Only fetch docs that still need guard attention.
          // DENIED / COMPLETED / TIMEOUT are excluded — they auto-disappear.
          // orderBy('timestamp') is intentionally removed: combining whereIn
          // with orderBy requires a Firestore composite index. We sort
          // client-side below instead, which works with no index setup.
          .where('status', whereIn: ['PENDING', 'APPROVED', 'ON_HOLD'])
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(
                child:
                    CircularProgressIndicator(color: Colors.cyanAccent)),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: Theme.of(context).dividerColor),
              ),
              child: Center(
                child: Text(
                  'No active delivery requests.',
                  style: TextStyle(
                      color: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.color),
                ),
              ),
            ),
          );
        }

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            // Sort client-side: newest first
            final sorted = snapshot.data!.docs.toList()
              ..sort((a, b) {
                final tsA = (a.data() as Map<String, dynamic>)['timestamp'];
                final tsB = (b.data() as Map<String, dynamic>)['timestamp'];
                if (tsA == null && tsB == null) return 0;
                if (tsA == null) return 1;
                if (tsB == null) return -1;
                return (tsB as Timestamp).compareTo(tsA as Timestamp);
              });
            final doc = sorted[index];
            final data = doc.data() as Map<String, dynamic>;
            return DeliveryRequestCard(
              docId: doc.id,
              flat: data['flatNumber'] ?? '?',
              company: data['company'] ?? 'DELIVERY',
              status: data['status'] ?? 'PENDING',
              residentPhone: data['residentPhone'],
              onAllowEntry: () =>
                  _allowDeliveryEntry(doc.id, data['flatNumber'] ?? ''),
              onDenyEntry: () =>
                  _denyEntry(doc.id, data['flatNumber'] ?? ''),
            );
          },
        );
      },
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          title: Text(
            _guardId != null
                ? 'Guard: $_guardId'
                : 'Guard Control Terminal',
            style: const TextStyle(
                fontWeight: FontWeight.bold, color: Colors.white),
          ),
          backgroundColor:
              Theme.of(context).appBarTheme.backgroundColor,
          centerTitle: true,
          elevation: 0,
          actions: [
            IconButton(
              icon:
                  const Icon(Icons.videocam_rounded, color: Colors.white70),
              tooltip: 'Manage Cameras',
              onPressed: () =>
                  Navigator.pushNamed(context, '/cameras'),
            ),
            ValueListenableBuilder<ThemeMode>(
              valueListenable: themeNotifier,
              builder: (_, mode, __) => IconButton(
                icon: Icon(
                  mode == ThemeMode.dark
                      ? Icons.light_mode_rounded
                      : Icons.dark_mode_rounded,
                  color: Colors.white70,
                ),
                tooltip:
                    mode == ThemeMode.dark ? 'Light Mode' : 'Dark Mode',
                onPressed: () {
                  themeNotifier.value = mode == ThemeMode.dark
                      ? ThemeMode.light
                      : ThemeMode.dark;
                },
              ),
            ),
            IconButton(
              icon:
                  const Icon(Icons.logout_rounded, color: Colors.white54),
              onPressed: () {
                if (_guardId != null) {
                  FirebaseFirestore.instance
                      .collection('guards')
                      .where('guardId', isEqualTo: _guardId)
                      .get()
                      .then((snap) {
                    for (final doc in snap.docs) {
                      doc.reference.update({
                        'onDuty': false,
                        'dutyEnd': FieldValue.serverTimestamp(),
                      });
                    }
                  });
                }
                Navigator.pushReplacementNamed(context, '/');
              },
            ),
          ],
          bottom: const TabBar(
            indicatorColor: Colors.cyanAccent,
            labelColor: Colors.cyanAccent,
            unselectedLabelColor: Colors.white38,
            tabs: [
              Tab(
                  icon: Icon(Icons.dashboard_rounded), text: 'Control'),
              Tab(
                  icon: Icon(Icons.people_alt_rounded), text: 'Inside'),
            ],
          ),
        ),

        floatingActionButton: FloatingActionButton.extended(
          onPressed: () =>
              UnifiedEntryForm.show(context, guardId: _guardId),
          backgroundColor: Colors.cyanAccent,
          foregroundColor: Colors.black,
          icon: const Icon(Icons.add_rounded),
          label: const Text(
            'NEW ENTRY',
            style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.8),
          ),
          elevation: 8,
        ),

        body: TabBarView(
          children: [
            // ── Control Tab ──────────────────────────────────────────────
            ListView(
              padding: const EdgeInsets.only(bottom: 100),
              children: [
                _buildLiveStats(),

                _sectionHeader('Gate Entry'),
                _buildUnifiedEntryButton(),

                _sectionHeader('Live Delivery Requests'),
                _buildLiveDeliveryRequests(),

                _sectionHeader('Recent Gate Logs'),
                _buildLogsStream(),

                const SizedBox(height: 32),
              ],
            ),

            // ── Inside Tab ───────────────────────────────────────────────
            const ActiveVisitorsTab(),
          ],
        ),
      ),
    );
  }
}