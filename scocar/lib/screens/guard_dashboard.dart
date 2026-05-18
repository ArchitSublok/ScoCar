import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/notification_service.dart';
import 'log_movement_screen.dart';

import 'discrepancy_alert_overlay.dart';
import 'delivery_request_card.dart';
import 'fast_delivery_entry_form.dart';
import 'active_visitors_tab.dart';
import 'camera_registration_screen.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// GuardDashboard
///
/// Changes from original:
///   ✅ NotificationService imported and used
///   ✅ Guard FCM token saved on load (saveGuardToken)
///   ✅ _showApprovalRequestModal → notifyResidentOfDelivery() called after
///      Firestore write so resident gets a real push notification
///   ✅ All original UI preserved; only notification calls added
/// ─────────────────────────────────────────────────────────────────────────────
class GuardDashboard extends StatefulWidget {
  const GuardDashboard({super.key});

  @override
  State<GuardDashboard> createState() => _GuardDashboardState();
}

class _GuardDashboardState extends State<GuardDashboard> {
  String? _guardId;
  bool _tokenSaved = false; // Prevent duplicate token saves

  static const List<Map<String, dynamic>> _deliveryVendors = [
    {
      'name': 'ZOMATO',
      'icon': Icons.fastfood_rounded,
      'color': Colors.redAccent,
      'photo':
          'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=150'
    },
    {
      'name': 'SWIGGY',
      'icon': Icons.delivery_dining_rounded,
      'color': Colors.orangeAccent,
      'photo':
          'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=150'
    },
    {
      'name': 'AMAZON',
      'icon': Icons.local_shipping_rounded,
      'color': Colors.amber,
      'photo':
          'https://images.unsplash.com/photo-1521572267360-ee0c2909d518?w=150'
    },
    {
      'name': 'OTHER',
      'icon': Icons.pending_actions_rounded,
      'color': Colors.blueGrey,
      'photo':
          'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?w=150'
    },
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments as String?;
    if (args != null && _guardId == null) {
      setState(() => _guardId = args);
    }
    // ── NEW: Save guard FCM token so residents can notify them back ──
    if (_guardId != null && !_tokenSaved) {
      _tokenSaved = true;
      NotificationService().saveGuardToken(_guardId!);
    }
  }

  // ============================================================
  // SEND DELIVERY APPROVAL REQUEST — now fires push notification
  // ============================================================
  // void _showApprovalRequestModal(BuildContext context,
  //     {String initialVendor = 'ZOMATO'}) {
  //   final TextEditingController flatController = TextEditingController();
  //   String selectedCompany = initialVendor;

  //   showModalBottomSheet(
  //     context: context,
  //     isScrollControlled: true,
  //     backgroundColor: Colors.transparent,
  //     builder: (context) {
  //       return StatefulBuilder(
  //         builder: (BuildContext ctx, StateSetter setModalState) {
  //           return Container(
  //             padding: EdgeInsets.only(
  //               top: 24,
  //               left: 24,
  //               right: 24,
  //               bottom: MediaQuery.of(ctx).viewInsets.bottom + 28,
  //             ),
  //             decoration: const BoxDecoration(
  //               color: Color(0xFF141428),
  //               borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
  //             ),
  //             child: Column(
  //               mainAxisSize: MainAxisSize.min,
  //               crossAxisAlignment: CrossAxisAlignment.start,
  //               children: [
  //                 // Handle bar
  //                 Center(
  //                   child: Container(
  //                     width: 48,
  //                     height: 5,
  //                     decoration: BoxDecoration(
  //                       color: Colors.white24,
  //                       borderRadius: BorderRadius.circular(10),
  //                     ),
  //                   ),
  //                 ),
  //                 const SizedBox(height: 20),
  //                 const Text(
  //                   'Send Delivery Alert',
  //                   style: TextStyle(
  //                       fontSize: 22,
  //                       fontWeight: FontWeight.bold,
  //                       color: Colors.white),
  //                 ),
  //                 const SizedBox(height: 6),
  //                 const Text(
  //                   'Resident must APPROVE before you allow entry.',
  //                   style: TextStyle(color: Colors.white54, fontSize: 13),
  //                 ),
  //                 const SizedBox(height: 24),

  //                 // Vendor chips
  //                 const Text('Delivery Provider',
  //                     style: TextStyle(
  //                         color: Colors.white70,
  //                         fontWeight: FontWeight.bold,
  //                         fontSize: 13)),
  //                 const SizedBox(height: 10),
  //                 Wrap(
  //                   spacing: 8,
  //                   runSpacing: 8,
  //                   children: _deliveryVendors.map((vendor) {
  //                     final bool sel = selectedCompany == vendor['name'];
  //                     return GestureDetector(
  //                       onTap: () => setModalState(
  //                           () => selectedCompany = vendor['name']),
  //                       child: AnimatedContainer(
  //                         duration: const Duration(milliseconds: 180),
  //                         padding: const EdgeInsets.symmetric(
  //                             horizontal: 16, vertical: 10),
  //                         decoration: BoxDecoration(
  //                           color: sel
  //                               ? (vendor['color'] as Color)
  //                               : Colors.transparent,
  //                           borderRadius: BorderRadius.circular(12),
  //                           border: Border.all(
  //                               color: vendor['color'] as Color, width: 1.5),
  //                         ),
  //                         child: Row(
  //                           mainAxisSize: MainAxisSize.min,
  //                           children: [
  //                             Icon(vendor['icon'] as IconData,
  //                                 size: 16,
  //                                 color: sel
  //                                     ? Colors.white
  //                                     : vendor['color'] as Color),
  //                             const SizedBox(width: 6),
  //                             Text(vendor['name'],
  //                                 style: TextStyle(
  //                                     color: sel
  //                                         ? Colors.white
  //                                         : vendor['color'] as Color,
  //                                     fontWeight: FontWeight.bold,
  //                                     fontSize: 13)),
  //                           ],
  //                         ),
  //                       ),
  //                     );
  //                   }).toList(),
  //                 ),
  //                 const SizedBox(height: 24),

  //                 // Flat number
  //                 TextField(
  //                   controller: flatController,
  //                   textCapitalization: TextCapitalization.characters,
  //                   style: const TextStyle(color: Colors.white),
  //                   decoration: InputDecoration(
  //                     labelText: 'Destination Flat Number',
  //                     hintText: 'e.g. B-201, A-101',
  //                     labelStyle: const TextStyle(color: Colors.white54),
  //                     hintStyle: const TextStyle(color: Colors.white24),
  //                     prefixIcon: const Icon(Icons.home_work_rounded,
  //                         color: Colors.cyanAccent),
  //                     filled: true,
  //                     fillColor: Colors.white.withOpacity(0.06),
  //                     border: OutlineInputBorder(
  //                         borderRadius: BorderRadius.circular(14),
  //                         borderSide:
  //                             const BorderSide(color: Colors.white12)),
  //                     enabledBorder: OutlineInputBorder(
  //                         borderRadius: BorderRadius.circular(14),
  //                         borderSide:
  //                             const BorderSide(color: Colors.white12)),
  //                     focusedBorder: OutlineInputBorder(
  //                         borderRadius: BorderRadius.circular(14),
  //                         borderSide: const BorderSide(
  //                             color: Colors.cyanAccent, width: 1.5)),
  //                   ),
  //                 ),
  //                 const SizedBox(height: 28),

  //                 // ── SEND BUTTON ──────────────────────────────────────────
  //                 SizedBox(
  //                   width: double.infinity,
  //                   height: 54,
  //                   child: ElevatedButton(
  //                     style: ElevatedButton.styleFrom(
  //                       backgroundColor: Colors.cyanAccent,
  //                       foregroundColor: Colors.black,
  //                       shape: RoundedRectangleBorder(
  //                           borderRadius: BorderRadius.circular(14)),
  //                       elevation: 0,
  //                     ),
  //                     onPressed: () async {
  //                       final String flatNumber =
  //                           flatController.text.trim().toUpperCase();
  //                       if (flatNumber.isEmpty) {
  //                         ScaffoldMessenger.of(ctx).showSnackBar(
  //                           const SnackBar(
  //                             content: Text('Please enter a flat number.'),
  //                             backgroundColor: Colors.orange,
  //                           ),
  //                         );
  //                         return;
  //                       }

  //                       final vendorMatch = _deliveryVendors.firstWhere(
  //                         (v) => v['name'] == selectedCompany,
  //                         orElse: () => _deliveryVendors.last,
  //                       );

  //                       // 1. Write approval request to Firestore
  //                       final DocumentReference docRef =
  //                           await FirebaseFirestore.instance
  //                               .collection('approvals')
  //                               .add({
  //                         'flatNumber': flatNumber,
  //                         'company': selectedCompany,
  //                         'status': 'PENDING',
  //                         'sentBy': _guardId ?? 'GUARD',
  //                         'timestamp': FieldValue.serverTimestamp(),
  //                         'visitorPhotoUrl': vendorMatch['photo'],
  //                       });

  //                       // 2. ── NEW: Send push notification to resident ──
  //                       await NotificationService().notifyResidentOfDelivery(
  //                         flatNumber: flatNumber,
  //                         company: selectedCompany,
  //                         guardId: _guardId ?? 'GUARD',
  //                         approvalDocId: docRef.id,
  //                       );

  //                       if (ctx.mounted) {
  //                         Navigator.pop(ctx);
  //                         ScaffoldMessenger.of(context).showSnackBar(
  //                           SnackBar(
  //                             content: Text(
  //                                 '📲 Notification sent to Flat $flatNumber — waiting for approval.'),
  //                             backgroundColor: Colors.blueAccent,
  //                           ),
  //                         );
  //                       }
  //                     },
  //                     child: const Text(
  //                       'SEND APPROVAL REQUEST',
  //                       style: TextStyle(
  //                           fontWeight: FontWeight.bold,
  //                           fontSize: 15,
  //                           letterSpacing: 1),
  //                     ),
  //                   ),
  //                 ),
  //               ],
  //             ),
  //           );
  //         },
  //       );
  //     },
  //   );
  // }

  // ============================================================
  // ALLOW ENTRY — resident approved, guard lets delivery in
  // ============================================================
  Future<void> _allowDeliveryEntry(
      String docId, String flatNumber, String company) async {
    await FirebaseFirestore.instance
        .collection('approvals')
        .doc(docId)
        .update({
      'status': 'COMPLETED',
      'completedAt': FieldValue.serverTimestamp(),
    });

    await FirebaseFirestore.instance.collection('logs').add({
      'type': 'ENTRY',
      'company': company,
      'flatNumber': flatNumber,
      'plateNumber': '— DELIVERY —',
      'guardId': _guardId ?? 'GUARD',
      'timestamp': FieldValue.serverTimestamp(),
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            '✅ $company delivery to $flatNumber — Entry logged & gate cleared.'),
        backgroundColor: Colors.green,
      ));
    }
  }

  // ============================================================
  // DENY ENTRY
  // ============================================================
  Future<void> _denyEntry(
      String docId, String company, String flatNumber) async {
    await FirebaseFirestore.instance
        .collection('approvals')
        .doc(docId)
        .update({'status': 'DENIED'});

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('🚫 $company delivery to $flatNumber — Turned away.'),
        backgroundColor: Colors.red,
      ));
    }
  }

  // ============================================================
  // BUILD
  // ============================================================
  @override
  // ============================================================
  // BUILD
  // ============================================================
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0A1A),
        appBar: AppBar(
          title: Text(
            _guardId != null ? 'Guard: $_guardId' : 'Guard Control Terminal',
            style: const TextStyle(
                fontWeight: FontWeight.bold, color: Colors.white),
          ),
          backgroundColor: const Color(0xFF141428),
          centerTitle: true,
          elevation: 0,
          actions: [
            IconButton(
              icon: const Icon(Icons.videocam_rounded, color: Colors.white70),
              tooltip: 'Manage Cameras',
              onPressed: () => Navigator.pushNamed(context, '/cameras'),
            ),
            IconButton(
              icon: const Icon(Icons.logout_rounded, color: Colors.white54),
              onPressed: () => Navigator.pushReplacementNamed(context, '/'),
            ),
          ],
          // ── ADDED: TabBar inside AppBar bottom ──────────────────────
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
        // ── ADDED: TabBarView to separate your tabs ──────────────────
        body: TabBarView(
          children: [
            // ── Tab 1: Your existing ListView (Control Terminal) ─────
            ListView(
              padding: EdgeInsets.zero,
              children: [
                _buildLiveStats(),
                _sectionHeader('Delivery Approval Hub'),
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
                        onPressed: () => FastDeliveryEntryForm.show(context,
                            guardId: _guardId, initialVendor: vendor['name']),
                        icon: Icon(vendor['icon'] as IconData,
                            color: Colors.white, size: 18),
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
                      label: const Text('LOG VEHICLE / GENERAL MOVEMENT',
                          style: TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold)),
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
            // ── Tab 2: Live visitors inside ──────────────────────────
            const ActiveVisitorsTab(),
          ],
        ),
      ),
    );
  }
//   Widget build(BuildContext context) {
//     return DefaultTabController(
//       length: 2,
//       child: Scaffold(
//     backgroundColor: const Color(0xFF0A0A1A),
//       appBar: AppBar(
//         title: Text(
//           _guardId != null ? 'Guard: $_guardId' : 'Guard Control Terminal',
//           style: const TextStyle(
//               fontWeight: FontWeight.bold, color: Colors.white),
//         ),
//         backgroundColor: const Color(0xFF141428),
//         centerTitle: true,
//         elevation: 0,
//         // actions: [
//         //   IconButton(
//         //     icon: const Icon(Icons.logout_rounded, color: Colors.white54),
//         //     onPressed: () =>
//         //         Navigator.pushReplacementNamed(context, '/'),
//         //   ),
//         // ],

//         actions: [
//   IconButton(
//     icon: const Icon(Icons.videocam_rounded, color: Colors.white70),
//     tooltip: 'Manage Cameras',
//     onPressed: () => Navigator.pushNamed(context, '/cameras'),
//   ),
//   IconButton(
//     icon: const Icon(Icons.logout_rounded, color: Colors.white54),
//     onPressed: () => Navigator.pushReplacementNamed(context, '/'),
//   ),
// ],

//       ),

      



//       body: ListView(
//         padding: EdgeInsets.zero,
//         children: [
//           _buildLiveStats(),
//           _sectionHeader('Delivery Approval Hub'),
//           Padding(
//             padding: const EdgeInsets.symmetric(horizontal: 20),
//             child: GridView.builder(
//               shrinkWrap: true,
//               physics: const NeverScrollableScrollPhysics(),
//               gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
//                 crossAxisCount: 2,
//                 crossAxisSpacing: 12,
//                 mainAxisSpacing: 12,
//                 childAspectRatio: 2.3,
//               ),
//               itemCount: _deliveryVendors.length,
//               itemBuilder: (context, index) {
//                 final vendor = _deliveryVendors[index];
//                 return ElevatedButton.icon(
//                   style: ElevatedButton.styleFrom(
//                     backgroundColor: vendor['color'] as Color,
//                     elevation: 0,
//                     shape: RoundedRectangleBorder(
//                         borderRadius: BorderRadius.circular(14)),
//                   ),
//                   onPressed: () => FastDeliveryEntryForm.show(context,
//     guardId: _guardId,
//     initialVendor: vendor['name']),
//                   icon: Icon(vendor['icon'] as IconData,
//                       color: Colors.white, size: 18),
//                   label: Text(vendor['name'],
//                       style: const TextStyle(
//                           color: Colors.white,
//                           fontWeight: FontWeight.bold,
//                           fontSize: 13)),
//                 );
//               },
//             ),
//           ),
//           const SizedBox(height: 20),
//           Padding(
//             padding: const EdgeInsets.symmetric(horizontal: 20),
//             child: SizedBox(
//               width: double.infinity,
//               child: ElevatedButton.icon(
//                 style: ElevatedButton.styleFrom(
//                   backgroundColor: Colors.blueAccent,
//                   padding: const EdgeInsets.symmetric(vertical: 14),
//                   shape: RoundedRectangleBorder(
//                       borderRadius: BorderRadius.circular(14)),
//                   elevation: 0,
//                 ),
//                 onPressed: () {
//                   showModalBottomSheet(
//                     context: context,
//                     isScrollControlled: true,
//                     useSafeArea: true,
//                     backgroundColor: Colors.transparent,
//                     builder: (context) => const LogMovementScreen(),
//                   );
//                 },
//                 icon: const Icon(Icons.swap_vert_rounded, color: Colors.white),
//                 label: const Text('LOG VEHICLE / GENERAL MOVEMENT',
//                     style: TextStyle(
//                         color: Colors.white, fontWeight: FontWeight.bold)),
//               ),
//             ),
//           ),
//           const SizedBox(height: 24),
//           _sectionHeader('Live Delivery Requests'),
//           _buildLiveDeliveryRequests(),
//           const SizedBox(height: 12),
//           _sectionHeader('Recent Gate Logs'),
//           _buildLogsStream(),
//           const SizedBox(height: 32),
//         ],
//       ),
//     );
//   }

  // ── Live delivery requests stream ─────────────────────────────────────────
  Widget _buildLiveDeliveryRequests() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('approvals')
          // .where('status', whereIn: ['PENDING', 'APPROVED', 'DENIED'])
          .where('status', whereIn: ['PENDING', 'APPROVED', 'DENIED', 'TIMEOUT', 'ON_HOLD'])
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
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF141428),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10),
              ),
              child: const Center(
                child: Text('No active delivery requests.',
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
            return DeliveryRequestCard(
  docId: doc.id,
  flat: data['flatNumber'] ?? '?',
  company: data['company'] ?? 'DELIVERY',
  status: data['status'] ?? 'PENDING',
  residentPhone: data['residentPhone'],
  onAllowEntry: () => _allowDeliveryEntry(doc.id, data['flatNumber'], data['company']),
  onDenyEntry:  () => _denyEntry(doc.id, data['company'], data['flatNumber']),
);
          },
        );
      },
    );
  }

  // Widget _buildDeliveryRequestCard({
  //   required String docId,
  //   required String flat,
  //   required String company,
  //   required String status,
  // }) {
  //   Color statusColor;
  //   IconData statusIcon;
  //   String statusLabel;

  //   switch (status) {
  //     case 'APPROVED':
  //       statusColor = Colors.greenAccent;
  //       statusIcon = Icons.check_circle_rounded;
  //       statusLabel = 'APPROVED — You may allow entry';
  //       break;
  //     case 'DENIED':
  //       statusColor = Colors.redAccent;
  //       statusIcon = Icons.cancel_rounded;
  //       statusLabel = 'DENIED — Turn delivery away';
  //       break;
  //     default:
  //       statusColor = Colors.orangeAccent;
  //       statusIcon = Icons.hourglass_top_rounded;
  //       statusLabel = 'PENDING — Waiting for resident...';
  //   }

  //   return Padding(
  //     padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
  //     child: Container(
  //       padding: const EdgeInsets.all(16),
  //       decoration: BoxDecoration(
  //         color: const Color(0xFF141428),
  //         borderRadius: BorderRadius.circular(18),
  //         border: Border.all(color: statusColor.withOpacity(0.4), width: 1.5),
  //       ),
  //       child: Column(
  //         crossAxisAlignment: CrossAxisAlignment.start,
  //         children: [
  //           Row(children: [
  //             _chip(company, statusColor),
  //             const SizedBox(width: 8),
  //             _chip('Flat: $flat', Colors.white54),
  //           ]),
  //           const SizedBox(height: 12),
  //           Row(children: [
  //             Icon(statusIcon, color: statusColor, size: 18),
  //             const SizedBox(width: 8),
  //             Expanded(
  //                 child: Text(statusLabel,
  //                     style: TextStyle(
  //                         color: statusColor,
  //                         fontWeight: FontWeight.w600,
  //                         fontSize: 13))),
  //           ]),
  //           if (status == 'APPROVED') ...[
  //             const SizedBox(height: 14),
  //             SizedBox(
  //               width: double.infinity,
  //               child: ElevatedButton.icon(
  //                 style: ElevatedButton.styleFrom(
  //                     backgroundColor: Colors.greenAccent,
  //                     foregroundColor: Colors.black,
  //                     shape: RoundedRectangleBorder(
  //                         borderRadius: BorderRadius.circular(12)),
  //                     padding: const EdgeInsets.symmetric(vertical: 12),
  //                     elevation: 0),
  //                 onPressed: () => _allowDeliveryEntry(docId, flat, company),
  //                 icon: const Icon(Icons.door_sliding_rounded, size: 20),
  //                 label: const Text('ALLOW ENTRY & LOG',
  //                     style: TextStyle(
  //                         fontWeight: FontWeight.bold, letterSpacing: 1)),
  //               ),
  //             ),
  //           ],
  //           if (status == 'DENIED') ...[
  //             const SizedBox(height: 14),
  //             SizedBox(
  //               width: double.infinity,
  //               child: OutlinedButton.icon(
  //                 style: OutlinedButton.styleFrom(
  //                     foregroundColor: Colors.redAccent,
  //                     side: const BorderSide(color: Colors.redAccent),
  //                     shape: RoundedRectangleBorder(
  //                         borderRadius: BorderRadius.circular(12)),
  //                     padding: const EdgeInsets.symmetric(vertical: 12)),
  //                 onPressed: () => _denyEntry(docId, company, flat),
  //                 icon: const Icon(Icons.block_rounded, size: 20),
  //                 label: const Text('DISMISS & TURN AWAY',
  //                     style: TextStyle(fontWeight: FontWeight.bold)),
  //               ),
  //             ),
  //           ],
  //           if (status == 'PENDING') ...[
  //             const SizedBox(height: 10),
  //             Align(
  //               alignment: Alignment.centerRight,
  //               child: TextButton.icon(
  //                 onPressed: () => FirebaseFirestore.instance
  //                     .collection('approvals')
  //                     .doc(docId)
  //                     .delete(),
  //                 icon: const Icon(Icons.close_rounded,
  //                     size: 16, color: Colors.white38),
  //                 label: const Text('Cancel request',
  //                     style:
  //                         TextStyle(color: Colors.white38, fontSize: 12)),
  //               ),
  //             ),
  //           ],
  //         ],
  //       ),
  //     ),
  //   );
  // }

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text,
          style: TextStyle(
              color: color, fontWeight: FontWeight.bold, fontSize: 13)),
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
          padding:
              const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [Color(0xFF0D47A1), Color(0xFF1565C0)]),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _StatTile(value: '$entries', label: 'In Society'),
              Container(width: 1, height: 40, color: Colors.white24),
              _StatTile(value: '$total', label: 'Daily Total'),
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
                child: Text('No gate logs yet.',
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
            final bool isEntry = (data['type'] ?? 'ENTRY') == 'ENTRY';
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF141428),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: (isEntry ? Colors.greenAccent : Colors.redAccent)
                        .withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isEntry ? Icons.login_rounded : Icons.logout_rounded,
                    color:
                        isEntry ? Colors.greenAccent : Colors.redAccent,
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
                    color: (isEntry ? Colors.greenAccent : Colors.redAccent)
                        .withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(data['type'] ?? 'ENTRY',
                      style: TextStyle(
                          color: isEntry
                              ? Colors.greenAccent
                              : Colors.redAccent,
                          fontSize: 11,
                          fontWeight: FontWeight.bold)),
                ),
              ]),
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
    return Column(children: [
      Text(value,
          style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white)),
      const SizedBox(height: 2),
      Text(label,
          style: const TextStyle(color: Colors.white70, fontSize: 12)),
    ]);
  }
}
