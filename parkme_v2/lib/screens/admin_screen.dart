import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../appsColor/app_theme.dart';
import '../models/parkingSlot.dart';
import '../services/parking_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Admin emails — only these accounts can access the admin panel.
// ─────────────────────────────────────────────────────────────────────────────
const _adminEmails = ['ychernxd@gmail.com'];

bool isAdminUser(User? user) {
  if (user == null) return false;
  return _adminEmails.contains(user.email?.toLowerCase());
}

// ─────────────────────────────────────────────────────────────────────────────
// AdminScreen
// ─────────────────────────────────────────────────────────────────────────────
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final _svc = ParkingService.instance;
  List<ParkingSlot> _slots = [];
  bool _loading = true;
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _sub = _svc.slotsStream.listen((slots) {
      if (mounted) setState(() { _slots = slots; _loading = false; });
    });
  }

  @override
  void dispose() { _sub?.cancel(); super.dispose(); }

  // ── Computed ──────────────────────────────────────────────────────────────
  int get _available => _slots.where((s) => s.isAvailable).length;
  int get _reserved  => _slots.where((s) => s.isReserved).length;
  int get _occupied  => _slots.where((s) => s.isOccupied).length;

  // ── Helpers ───────────────────────────────────────────────────────────────
  void _toast(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white, fontSize: 13)),
      backgroundColor: isError ? AppColors.occupied : AppColors.accentBlue,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      margin: const EdgeInsets.all(16),
      duration: const Duration(seconds: 4),
    ));
  }

  // ── Actions ───────────────────────────────────────────────────────────────
  Future<void> _setStatus(String slotId, String status) async {
    await _svc.adminSetStatus(slotId, status);
    _toast('$slotId set to $status');
  }

  Future<void> _deleteSlot(String slotId) async {
    final confirmed = await _confirmDialog(
      'Delete $slotId?',
      'This permanently removes the slot from the database.',
      danger: true,
    );
    if (!confirmed) return;
    await _svc.adminDeleteSlot(slotId);
    _toast('$slotId deleted');
  }

  Future<void> _clearAll() async {
    final confirmed = await _confirmDialog(
      'Clear ALL Reservations?',
      'Every reserved or occupied slot will be set to Available. This cannot be undone.',
      danger: true,
    );
    if (!confirmed) return;
    try {
      await _svc.adminClearAll();
      _toast('All reservations cleared');
    } catch (e) {
      // Almost always a rules issue: this admin account isn't listed under
      // /admins/<uid> in the Realtime Database, so writes are denied.
      _toast('Clear failed — check that your admin UID is in /admins. ($e)',
          isError: true);
    }
  }

  Future<bool> _confirmDialog(String title, String body, {bool danger = false}) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.cardNavy,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title,
            style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 17)),
        content: Text(body,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textHint)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: danger ? AppColors.occupied : AppColors.accentBlue,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _showAddSlotDialog() {
    final ctrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: _AddSlotSheet(
          ctrl: ctrl,
          onAdd: () async {
            final id = ctrl.text.trim();
            if (id.isEmpty) return;
            Navigator.pop(context);
            await _svc.adminAddSlot(id);
            _toast('Slot "$id" added');
          },
        ),
      ),
    );
  }

  void _showStatusMenu(ParkingSlot slot) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _StatusSheet(
        slot: slot,
        onSet: (status) {
          Navigator.pop(context);
          _setStatus(slot.slotID, status);
        },
        onDelete: () {
          Navigator.pop(context);
          _deleteSlot(slot.slotID);
        },
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryNavy,
      appBar: AppBar(
        backgroundColor: AppColors.cardNavy,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.admin_panel_settings_rounded, color: Colors.orange, size: 18),
          ),
          const SizedBox(width: 10),
          const Text('Admin Panel',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w800)),
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline_rounded, color: AppColors.accentBlue),
            tooltip: 'Add Slot',
            onPressed: _showAddSlotDialog,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.accentBlue))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // TEMP DEBUG: your admin UID (paste this into /admins).
                // Remove once /admins/<uid>: true is set in the database.
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('YOUR ADMIN UID (long-press to copy, paste into /admins)',
                        style: TextStyle(color: Colors.orange, fontSize: 10, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    SelectableText(
                      FirebaseAuth.instance.currentUser?.uid ?? '(not signed in)',
                      style: const TextStyle(
                          color: AppColors.textPrimary, fontSize: 13,
                          fontFamily: 'monospace', fontWeight: FontWeight.w700),
                    ),
                  ]),
                ),

                _AdminStatRow(
                  available: _available,
                  reserved: _reserved,
                  occupied: _occupied,
                  total: _slots.length,
                ),
                const SizedBox(height: 16),

                // ── Emergency controls ────────────────────────────────
                _EmergencyCard(onClearAll: _clearAll),
                const SizedBox(height: 16),

                // ── Slots header ──────────────────────────────────────
                Row(children: [
                  const Icon(Icons.local_parking_rounded, color: AppColors.accentBlue, size: 16),
                  const SizedBox(width: 8),
                  const Text('Manage Slots',
                      style: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  Text('${_slots.length} slots',
                      style: const TextStyle(color: AppColors.textHint, fontSize: 12)),
                ]),
                const SizedBox(height: 10),

                // ── Slot cards ────────────────────────────────────────
                ..._slots.map((slot) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _AdminSlotCard(
                    slot: slot,
                    onManage: () => _showStatusMenu(slot),
                  ),
                )),

                const SizedBox(height: 24),
              ],
            ),
    );
  }
}

// ── Stats Row ─────────────────────────────────────────────────────────────
class _AdminStatRow extends StatelessWidget {
  final int available, reserved, occupied, total;
  const _AdminStatRow({required this.available, required this.reserved,
      required this.occupied, required this.total});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(child: _AdminStatCard('Available', available, AppColors.available)),
      const SizedBox(width: 8),
      Expanded(child: _AdminStatCard('Reserved', reserved, AppColors.reserved)),
      const SizedBox(width: 8),
      Expanded(child: _AdminStatCard('Occupied', occupied, AppColors.occupied)),
      const SizedBox(width: 8),
      Expanded(child: _AdminStatCard('Total', total, AppColors.accentBlue)),
    ]);
  }
}

class _AdminStatCard extends StatelessWidget {
  final String label; final int count; final Color color;
  const _AdminStatCard(this.label, this.count, this.color);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
    decoration: BoxDecoration(
      color: AppColors.cardNavy,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: color.withValues(alpha: 0.25)),
    ),
    child: Column(children: [
      Text('$count', style: TextStyle(color: color, fontSize: 24, fontWeight: FontWeight.w800)),
      const SizedBox(height: 2),
      Text(label, style: const TextStyle(color: AppColors.textHint, fontSize: 9, fontWeight: FontWeight.w500)),
    ]),
  );
}

// ── Emergency Controls Card ───────────────────────────────────────────────
class _EmergencyCard extends StatelessWidget {
  final VoidCallback onClearAll;
  const _EmergencyCard({required this.onClearAll});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.occupied.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.occupied.withValues(alpha: 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.warning_amber_rounded, color: AppColors.occupied, size: 16),
          SizedBox(width: 8),
          Text('Emergency Controls',
              style: TextStyle(color: AppColors.occupied, fontSize: 14, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 10),
        const Text(
          'Use these controls when the user interface is unable to function or requires manual override.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.4),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: onClearAll,
            icon: const Icon(Icons.clear_all_rounded, size: 18),
            label: const Text('Clear All Reservations',
                style: TextStyle(fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.occupied,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 46),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
          ),
        ),
      ]),
    );
  }
}

// ── Admin Slot Card ───────────────────────────────────────────────────────
class _AdminSlotCard extends StatelessWidget {
  final ParkingSlot slot;
  final VoidCallback onManage;
  const _AdminSlotCard({required this.slot, required this.onManage});

  Color get _color {
    if (slot.isAvailable) return AppColors.available;
    if (slot.isReserved)  return AppColors.reserved;
    return AppColors.occupied;
  }

  String get _num => slot.slotID.replaceAll(RegExp(r'[^0-9]'), '');

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardNavy,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _color.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        // Left status accent
        Container(
          width: 60,
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: _color.withValues(alpha: 0.08),
            borderRadius: const BorderRadius.horizontal(left: Radius.circular(15)),
          ),
          alignment: Alignment.center,
          child: Text('P$_num',
              style: TextStyle(color: _color, fontSize: 22, fontWeight: FontWeight.w900)),
        ),

        // Info
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: _color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(slot.statusLabel.toUpperCase(),
                      style: TextStyle(color: _color, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                ),
              ]),
              const SizedBox(height: 5),
              if (slot.plateNum.isNotEmpty)
                Text('🚗  ${slot.plateNum}',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
              if (slot.userID.isNotEmpty)
                Text('UID: ${slot.userID}',
                    style: const TextStyle(color: AppColors.textHint, fontSize: 10),
                    overflow: TextOverflow.ellipsis),
              if (slot.bookingID.isNotEmpty)
                Text('#${slot.bookingID}',
                    style: const TextStyle(color: AppColors.textHint, fontSize: 10)),
            ]),
          ),
        ),

        // Manage button
        Padding(
          padding: const EdgeInsets.only(right: 14),
          child: GestureDetector(
            onTap: onManage,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.35)),
              ),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.tune_rounded, color: Colors.orange, size: 16),
                SizedBox(width: 5),
                Text('Manage', style: TextStyle(color: Colors.orange, fontSize: 11, fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

// ── Status Bottom Sheet ───────────────────────────────────────────────────
class _StatusSheet extends StatelessWidget {
  final ParkingSlot slot;
  final ValueChanged<String> onSet;
  final VoidCallback onDelete;
  const _StatusSheet({required this.slot, required this.onSet, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.cardNavy,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 40, height: 4,
            decoration: BoxDecoration(color: AppColors.inputBorder, borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 20),
        Text('Manage ${slot.slotID.toUpperCase()}',
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text('Current status: ${slot.statusLabel}',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        const SizedBox(height: 20),

        // Status buttons
        _StatusBtn('Set Available', AppColors.available, Icons.check_circle_outline_rounded,
            () => onSet('Available')),
        const SizedBox(height: 10),
        _StatusBtn('Set Reserved', AppColors.reserved, Icons.bookmark_outline_rounded,
            () => onSet('Reserved')),
        const SizedBox(height: 10),
        _StatusBtn('Set Occupied', AppColors.occupied, Icons.directions_car_outlined,
            () => onSet('Occupied')),
        const SizedBox(height: 16),
        const Divider(color: AppColors.divider),
        const SizedBox(height: 10),
        _StatusBtn('Delete Slot', const Color(0xFF6B7599), Icons.delete_outline_rounded,
            onDelete, subtle: true),
      ]),
    );
  }
}

class _StatusBtn extends StatelessWidget {
  final String label; final Color color; final IconData icon;
  final VoidCallback onTap; final bool subtle;
  const _StatusBtn(this.label, this.color, this.icon, this.onTap, {this.subtle = false});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: subtle ? 0.05 : 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: subtle ? 0.2 : 0.35)),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 12),
        Text(label, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w600)),
      ]),
    ),
  );
}

// ── Add Slot Bottom Sheet ─────────────────────────────────────────────────
class _AddSlotSheet extends StatelessWidget {
  final TextEditingController ctrl;
  final VoidCallback onAdd;
  const _AddSlotSheet({required this.ctrl, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.cardNavy,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 40, height: 4,
            decoration: BoxDecoration(color: AppColors.inputBorder, borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 20),
        const Text('Add New Slot',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
        const SizedBox(height: 20),
        TextFormField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
          decoration: const InputDecoration(
            labelText: 'Slot ID',
            hintText: 'e.g. slot 6',
            prefixIcon: Icon(Icons.local_parking_rounded, color: AppColors.accentBlue),
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: onAdd,
            child: const Text('Add Slot', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
      ]),
    );
  }
}
