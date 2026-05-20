import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/notification_service.dart';
import 'log_movement_screen.dart';
import '../../main.dart' show themeNotifier;

import 'discrepancy_alert_overlay.dart';
import 'delivery_request_card.dart';
import 'fast_delivery_entry_form.dart';
import 'active_visitors_tab.dart';
import 'camera_registration_screen.dart';

class GuardDashboard extends StatefulWidget {
  const GuardDashboard({super.key});

  @override
  State<GuardDashboard> createState() => _GuardDashboardState();
}

class _GuardDashboardState extends State<GuardDashboard> {
  String? _guardId;
  bool _tokenSaved = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments as String?;
    if (args != null && _guardId == null) {
      setState(() => _guardId = args);
    }
    if (_guardId != null && !_tokenSaved) {
      _tokenSaved = true;
      NotificationService().saveGuardToken(_guardId!);
    }
  }

  // Feature 5: Generic allow-entry — no vendor-specific logic
  Future<void> _allowDeliveryEntry(String docId, String flatNumber) async {
    await FirebaseFirestore.instance.collection('approvals').doc(docId).update({
      'status': 'COMPLETED',
      'completedAt': FieldValue.serverTimestamp(),
    });

    await FirebaseFirestore.instance.collection('logs').add({
      'type'       : 'ENTRY',
      'company'    : 'DELIVERY',              // Feature 5: generic
      'flatNumber' : flatNumber,
      'plateNumber': '— DELIVERY —',
      'guardId'    : _guardId ?? 'GUARD',
      'guardName'  : activeGuardName,          // Feature 2
      'vehicleModel': 'Unknown',
      'driverName' : 'Delivery Agent',
      'driverPic'  : 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=300',
      'otpCode'    : null,
      'timestamp'  : FieldValue.serverTimestamp(),
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('✅ Delivery to $flatNumber — Entry logged & gate cleared.'),
        backgroundColor: Colors.green,
      ));
    }
  }

  Future<void> _denyEntry(String docId, String flatNumber) async {
    await FirebaseFirestore.instance
        .collection('approvals')
        .doc(docId)
        .update({'status': 'DENIED'});

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('🚫 Delivery to $flatNumber — Turned away.'),
        backgroundColor: Colors.red,
      ));
    }
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 20, right: 20, top: 24, bottom: 12),
      child: Text(
        title,
        style: TextStyle(
          color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.7) ?? Colors.white70,
          fontSize: 16,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildLiveStats() {
    return Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _statColumn('On Duty', activeGuardName, Colors.greenAccent), // Feature 2
          Container(width: 1, height: 40, color: Colors.white10),
          _statColumn('Terminal Status', 'SECURE', Colors.cyanAccent),
        ],
      ),
    );
  }

  Widget _statColumn(String label, String value, Color highlight) {
    return Column(
      children: [
        Text(label, style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.6) ?? Colors.white38, fontSize: 12)),
        const SizedBox(height: 4),
        Text(value,
            style: TextStyle(
                color: highlight, fontWeight: FontWeight.bold, fontSize: 15)),
      ],
    );
  }

  Widget _buildLogsStream() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('logs')
          .orderBy('timestamp', descending: true)
          .limit(5)
          .snapshots(),s
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return  Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
            child: Text('No recent logs recorded.',
                style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.6))),
          );
        }
        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            final log =
                snapshot.data!.docs[index].data() as Map<String, dynamic>;
            final String type = log['type'] ?? 'ENTRY';
            // Feature 7: Show driverName in subtitle if available
            final String subtitle = log['driverName'] != null
                ? '${log['driverName']} · ${log['plateNumber'] ?? '—'}'
                : log['plateNumber'] ?? 'General Movement';
            return ListTile(
              leading: Icon(
                type == 'ENTRY'
                    ? Icons.login_rounded
                    : Icons.logout_rounded,
                color:
                    type == 'ENTRY' ? Colors.greenAccent : Colors.orangeAccent,
              ),
              title: Text('Flat ${log['flatNumber'] ?? '—'}',
                  style: TextStyle(color: Theme.of(context).textTheme.bodyMedium?.color)),
              subtitle: Text(subtitle,
                  style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color)),
              trailing: Text('Just now',
                  style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.5), fontSize: 11)),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          title: Text(
            _guardId != null ? 'Guard: $_guardId' : 'Guard Control Terminal',
            style: const TextStyle(
                fontWeight: FontWeight.bold, color: Colors.white),
          ),
          backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
          centerTitle: true,
          elevation: 0,
          actions: [
            IconButton(
              icon: const Icon(Icons.videocam_rounded, color: Colors.white70),
              tooltip: 'Manage Cameras',
              onPressed: () => Navigator.pushNamed(context, '/cameras'),
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
              onPressed: () {
                // Mark guard as off duty when they log out
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
              Tab(icon: Icon(Icons.dashboard_rounded), text: 'Control'),
              Tab(icon: Icon(Icons.people_alt_rounded), text: 'Inside'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            ListView(
              padding: EdgeInsets.zero,
              children: [
                _buildLiveStats(),
                _sectionHeader('System AI Enhancements'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.cyanAccent,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        elevation: 4,
                      ),
                      onPressed: () =>
                          Navigator.pushNamed(context, '/detect_vehicle'),
                      icon: const Icon(Icons.document_scanner_rounded,
                          color: Colors.black, size: 22),
                      label: const Text(
                        'SCAN NUMBER PLATE',
                        style: TextStyle(
                            fontWeight: FontWeight.w900, letterSpacing: 0.5),
                      ),
                    ),
                  ),
                ),

                // Feature 5: Single streamlined "Delivery / Visitor Log" button
                _sectionHeader('Delivery / Visitor Log'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      // Opens the fast form (generic — no vendor preselected)
                      onPressed: () => FastDeliveryEntryForm.show(
                        context,
                        guardId: _guardId,
                        initialVendor: 'OTHER',
                      ),
                      icon: const Icon(Icons.local_shipping_rounded,
                          color: Colors.white),
                      label: const Text(
                        'NEW DELIVERY / VISITOR ENTRY',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1C1C3A),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                        side: const BorderSide(color: Colors.blueAccent),
                      ),
                      onPressed: () => showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        useSafeArea: true,
                        backgroundColor: Colors.transparent,
                        builder: (_) => const LogMovementScreen(),
                      ),
                      icon: const Icon(Icons.swap_vert_rounded,
                          color: Colors.white),
                      label: const Text(
                        'LOG VEHICLE / GENERAL MOVEMENT',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                _sectionHeader('Live Delivery Requests'),
                _buildLiveDeliveryRequests(),
                const SizedBox(height: 12),
                _sectionHeader('Recent Gate Logs'),
                _buildLogsStream(),
                const SizedBox(height: 32),
              ],
            ),
            const ActiveVisitorsTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveDeliveryRequests() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('approvals')
          .where('status',
              whereIn: ['PENDING', 'APPROVED', 'DENIED', 'TIMEOUT', 'ON_HOLD'])
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(
                child: CircularProgressIndicator(color: Colors.cyanAccent)),
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
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: Center(
                child: Text('No active delivery requests.',
                    style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color)),
              ),
            ),
          );
        }
        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            final doc  = snapshot.data!.docs[index];
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
}
