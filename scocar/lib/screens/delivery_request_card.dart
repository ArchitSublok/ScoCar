// ─────────────────────────────────────────────────────────────────────────────
// AREA 2: DeliveryRequestCard with 60-Second Countdown + Timeout Fallback
//
// REPLACES the _buildDeliveryRequestCard() method in guard_dashboard.dart.
// Paste this widget below _denyEntry() and call it from _buildLiveDeliveryRequests().
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart'; // Add url_launcher to pubspec.yaml

/// Timeout duration in seconds. Change to adjust the countdown.
const int kApprovalTimeoutSeconds = 60;

class DeliveryRequestCard extends StatefulWidget {
  final String docId;
  final String flat;
  final String company;
  final String status;
  final String? residentPhone; // optional, pulled from residents collection
  final VoidCallback? onAllowEntry;
  final VoidCallback? onDenyEntry;

  const DeliveryRequestCard({
    super.key,
    required this.docId,
    required this.flat,
    required this.company,
    required this.status,
    this.residentPhone,
    this.onAllowEntry,
    this.onDenyEntry,
  });

  @override
  State<DeliveryRequestCard> createState() => _DeliveryRequestCardState();
}

class _DeliveryRequestCardState extends State<DeliveryRequestCard> {
  Timer? _countdownTimer;
  int _secondsRemaining = kApprovalTimeoutSeconds;
  bool _timedOut = false;

  @override
  void initState() {
    super.initState();
    // Only start countdown for PENDING requests
    if (widget.status == 'PENDING') {
      _startCountdown();
    }
  }

  @override
  void didUpdateWidget(DeliveryRequestCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Stop countdown if status changed away from PENDING
    if (widget.status != 'PENDING' && _countdownTimer != null) {
      _countdownTimer!.cancel();
    }
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_secondsRemaining > 0) {
          _secondsRemaining--;
        } else {
          _timedOut = true;
          timer.cancel();
          // Mark Firestore document as timed out
          FirebaseFirestore.instance
              .collection('approvals')
              .doc(widget.docId)
              .update({
            'status': 'TIMEOUT',
            'timedOutAt': FieldValue.serverTimestamp(),
          });
        }
      });
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  // ── Call resident via phone ────────────────────────────────────────────
  Future<void> _callResident() async {
    if (widget.residentPhone == null || widget.residentPhone!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No phone number on record for this flat.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    final Uri callUri = Uri(scheme: 'tel', path: widget.residentPhone);
    if (await canLaunchUrl(callUri)) {
      await launchUrl(callUri);
    }
  }

  // ── Hold delivery at gate (writes to Firestore) ────────────────────────
  Future<void> _holdAtGate() async {
    await FirebaseFirestore.instance
        .collection('approvals')
        .doc(widget.docId)
        .update({
      'status': 'ON_HOLD',
      'heldAt': FieldValue.serverTimestamp(),
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '⏸ ${widget.company} delivery held at gate for Flat ${widget.flat}.'),
          backgroundColor: Colors.blueGrey,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // ── Resolve card state ─────────────────────────────────────────────
    if (_timedOut || widget.status == 'TIMEOUT') {
      return _buildTimeoutCard();
    }

    Color statusColor;
    IconData statusIcon;
    String statusLabel;

    switch (widget.status) {
      case 'APPROVED':
        statusColor = Colors.greenAccent;
        statusIcon = Icons.check_circle_rounded;
        statusLabel = 'APPROVED — You may allow entry';
        break;
      case 'DENIED':
        statusColor = Colors.redAccent;
        statusIcon = Icons.cancel_rounded;
        statusLabel = 'DENIED — Turn delivery away';
        break;
      case 'ON_HOLD':
        statusColor = Colors.blueGrey;
        statusIcon = Icons.pause_circle_filled_rounded;
        statusLabel = 'ON HOLD — Delivery waiting at gate';
        break;
      default:
        statusColor = Colors.orangeAccent;
        statusIcon = Icons.hourglass_top_rounded;
        statusLabel = 'PENDING — Waiting for resident...';
    }

    final double progress = _secondsRemaining / kApprovalTimeoutSeconds;

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
            // ── Chips ────────────────────────────────────────────────
            Row(children: [
              _chip(widget.company, statusColor),
              const SizedBox(width: 8),
              _chip('Flat: ${widget.flat}', Colors.white54),
            ]),
            const SizedBox(height: 12),

            // ── Status row ──────────────────────────────────────────
            Row(children: [
              Icon(statusIcon, color: statusColor, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(statusLabel,
                    style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 13)),
              ),
            ]),

            // ── Countdown (PENDING only) ─────────────────────────────
            if (widget.status == 'PENDING') ...[
              const SizedBox(height: 12),
              Row(children: [
                Icon(Icons.timer_rounded,
                    size: 14,
                    color: _secondsRemaining < 15
                        ? Colors.redAccent
                        : Colors.white38),
                const SizedBox(width: 6),
                Text(
                  '${_secondsRemaining}s remaining',
                  style: TextStyle(
                    color: _secondsRemaining < 15
                        ? Colors.redAccent
                        : Colors.white38,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ]),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: Colors.white10,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    _secondsRemaining < 15
                        ? Colors.redAccent
                        : Colors.orangeAccent,
                  ),
                ),
              ),
            ],

            // ── Action buttons ───────────────────────────────────────
            if (widget.status == 'APPROVED') ...[
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
                      elevation: 0),
                  onPressed: widget.onAllowEntry,
                  icon: const Icon(Icons.door_sliding_rounded, size: 20),
                  label: const Text('ALLOW ENTRY & LOG',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, letterSpacing: 1)),
                ),
              ),
            ],
            if (widget.status == 'DENIED') ...[
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.redAccent,
                      side: const BorderSide(color: Colors.redAccent),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12)),
                  onPressed: widget.onDenyEntry,
                  icon: const Icon(Icons.block_rounded, size: 20),
                  label: const Text('DISMISS & TURN AWAY',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
            if (widget.status == 'PENDING') ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => FirebaseFirestore.instance
                      .collection('approvals')
                      .doc(widget.docId)
                      .delete(),
                  icon: const Icon(Icons.close_rounded,
                      size: 16, color: Colors.white38),
                  label: const Text('Cancel request',
                      style: TextStyle(color: Colors.white38, fontSize: 12)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Timeout state card ───────────────────────────────────────────────
  Widget _buildTimeoutCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF141428),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.redAccent.withOpacity(0.5), width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              _chip(widget.company, Colors.redAccent),
              const SizedBox(width: 8),
              _chip('Flat: ${widget.flat}', Colors.white54),
              const SizedBox(width: 8),
              _chip('TIMED OUT', Colors.redAccent),
            ]),
            const SizedBox(height: 12),
            const Row(children: [
              Icon(Icons.alarm_off_rounded, color: Colors.redAccent, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Resident did not respond in 60 seconds',
                  style: TextStyle(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.w600,
                      fontSize: 13),
                ),
              ),
            ]),
            const SizedBox(height: 14),

            // ── Fallback actions ────────────────────────────────────
            Row(children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A3A6B),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  onPressed: _callResident,
                  icon: const Icon(Icons.phone_rounded,
                      color: Colors.cyanAccent, size: 18),
                  label: const Text('Call Resident',
                      style: TextStyle(
                          color: Colors.cyanAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2A1A0A),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  onPressed: _holdAtGate,
                  icon: const Icon(Icons.pause_circle_outline_rounded,
                      color: Colors.orangeAccent, size: 18),
                  label: const Text('Hold at Gate',
                      style: TextStyle(
                          color: Colors.orangeAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.bold)),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text,
          style: TextStyle(
              color: color, fontWeight: FontWeight.bold, fontSize: 12)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HOW TO SWAP IN:
//
// In guard_dashboard.dart, change _buildLiveDeliveryRequests() itemBuilder to:
//
//   return DeliveryRequestCard(
//     docId: doc.id,
//     flat: data['flatNumber'] ?? '?',
//     company: data['company'] ?? 'DELIVERY',
//     status: data['status'] ?? 'PENDING',
//     residentPhone: data['residentPhone'],   // add this field when writing approvals
//     onAllowEntry: () => _allowDeliveryEntry(doc.id, data['flatNumber'], data['company']),
//     onDenyEntry:  () => _denyEntry(doc.id, data['company'], data['flatNumber']),
//   );
//
// Also add to pubspec.yaml:
//   url_launcher: ^6.3.0
// ─────────────────────────────────────────────────────────────────────────────
