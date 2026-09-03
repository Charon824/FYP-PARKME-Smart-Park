import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../appsColor/app_theme.dart';
import '../models/parkingSlot.dart';
import '../services/parking_service.dart';
import '../LoginSystem/Auth_Service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Dashboard Screen
// Shows real-time stats from Firebase Realtime Database (populated by sensors)
// ─────────────────────────────────────────────────────────────────────────────

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {

  final _service = ParkingService.instance;
  List<ParkingSlot> _slots      = [];
  bool              _loading    = true;
  DateTime          _lastSync   = DateTime.now();
  StreamSubscription? _sub;
  StreamSubscription? _bookingSub;
  Map<String, dynamic>? _myBooking;            // own private plate/booking ID
  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  // ── Pulse animation for LIVE badge ───────────────────────────────────────
  late AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _sub = _service.slotsStream.listen((slots) {
      setState(() {
        _slots    = slots;
        _loading  = false;
        _lastSync = DateTime.now();
      });
    });

    _bookingSub = _service.myBookingStream(_uid).listen((b) {
      if (mounted) setState(() => _myBooking = b);
    });
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _sub?.cancel();
    _bookingSub?.cancel();
    super.dispose();
  }

  // ── Computed counts ──────────────────────────────────────────────────────
  int get _available => _slots.where((s) => s.isAvailable).length;
  int get _reserved  => _slots.where((s) => s.isReserved).length;
  int get _occupied  => _slots.where((s) => s.isOccupied).length;
  int get _total     => _slots.length;

  String get _syncLabel {
    final diff = DateTime.now().difference(_lastSync);
    if (diff.inSeconds < 10) return 'just now';
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    return '${diff.inMinutes}m ago';
  }

  // ── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryNavy,
      body: Stack(children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFF2F8FF), AppColors.primaryNavy, AppColors.secondaryNavy],
            ),
          ),
        ),

        SafeArea(
          child: Column(children: [
            // ── Header bar ─────────────────────────────────────────
            _buildHeader(),

            // ── Body ───────────────────────────────────────────────
            Expanded(
              child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.accentBlue))
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // 1. Stat cards row
                      _StatRow(available: _available, reserved: _reserved, occupied: _occupied, total: _total),
                      const SizedBox(height: 16),

                      // 2. Occupancy bar
                      _OccupancyBar(available: _available, reserved: _reserved, occupied: _occupied, total: _total),
                      const SizedBox(height: 16),

                      // 3. Floor map grid
                      _FloorMap(slots: _slots),
                      const SizedBox(height: 16),

                      // 4. Slot detail list
                      _SlotDetailList(slots: _slots, uid: _uid, myBooking: _myBooking),
                      const SizedBox(height: 16),

                      // 5. Sensor info card
                      _SensorCard(lastSync: _lastSync),
                      const SizedBox(height: 24),
                    ],
                  ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _buildHeader() {
    return Container(
      color: AppColors.cardNavy.withValues(alpha: 0.8),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(children: [
        // Live dot
        AnimatedBuilder(
          animation: _pulseCtrl,
          builder: (_, __) => Container(
            width: 10, height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.available.withValues(alpha: 0.4 + _pulseCtrl.value * 0.6),
            ),
          ),
        ),
        const SizedBox(width: 8),
        const Text('LIVE', style: TextStyle(color: AppColors.available, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1)),
        const SizedBox(width: 12),
        const Text('Dashboard', style: TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w800)),
        const Spacer(),
        // Sync time
        Text('Updated $_syncLabel',
            style: const TextStyle(color: AppColors.textHint, fontSize: 11)),
        const SizedBox(width: 10),
        // Sign out
        GestureDetector(
          onTap: () async => AuthService().signOut(),
          child: const Icon(Icons.logout_rounded, color: AppColors.textHint, size: 18),
        ),
      ]),
    );
  }
}

// ── Stat Row ──────────────────────────────────────────────────────────────
class _StatRow extends StatelessWidget {
  final int available, reserved, occupied, total;
  const _StatRow({required this.available, required this.reserved, required this.occupied, required this.total});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(child: _StatCard('Available', available, Icons.check_circle_outline_rounded, AppColors.available)),
      const SizedBox(width: 8),
      Expanded(child: _StatCard('Reserved',  reserved,  Icons.bookmark_outline_rounded,     AppColors.reserved)),
      const SizedBox(width: 8),
      Expanded(child: _StatCard('Occupied',  occupied,  Icons.directions_car_rounded,       AppColors.occupied)),
      const SizedBox(width: 8),
      Expanded(child: _StatCard('Total',     total,     Icons.local_parking_rounded,        AppColors.accentBlue)),
    ]);
  }
}

class _StatCard extends StatelessWidget {
  final String label; final int count; final IconData icon; final Color color;
  const _StatCard(this.label, this.count, this.icon, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
      decoration: BoxDecoration(
        color: AppColors.cardNavy,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: color, size: 16),
        ),
        const SizedBox(height: 8),
        Text('$count', style: TextStyle(color: color, fontSize: 24, fontWeight: FontWeight.w800, height: 1)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: AppColors.textHint, fontSize: 9, fontWeight: FontWeight.w500)),
      ]),
    );
  }
}

// ── Stacked Occupancy Bar ─────────────────────────────────────────────────
class _OccupancyBar extends StatelessWidget {
  final int available, reserved, occupied, total;
  const _OccupancyBar({required this.available, required this.reserved, required this.occupied, required this.total});

  @override
  Widget build(BuildContext context) {
    final double av = total == 0 ? 0 : available / total;
    final double re = total == 0 ? 0 : reserved  / total;
    final double oc = total == 0 ? 0 : occupied  / total;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardNavy,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.inputBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Lot Occupancy', style: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: AppColors.accentBlue.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
            child: Text('${total == 0 ? 0 : ((occupied + reserved) / total * 100).round()}% in use',
                style: const TextStyle(color: AppColors.accentBlue, fontSize: 11, fontWeight: FontWeight.w600)),
          ),
        ]),
        const SizedBox(height: 14),

        // Stacked bar
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: 14,
            child: Row(children: [
              if (oc > 0) Flexible(flex: (oc * 100).round(), child: Container(color: AppColors.occupied)),
              if (re > 0) Flexible(flex: (re * 100).round(), child: Container(color: AppColors.reserved)),
              if (av > 0) Flexible(flex: (av * 100).round(), child: Container(color: AppColors.available)),
            ]),
          ),
        ),
        const SizedBox(height: 12),

        // Legend
        Row(children: [
          _BarLegend(AppColors.occupied,              'Occupied  $occupied'),
          const SizedBox(width: 16),
          _BarLegend(AppColors.reserved,      'Reserved  $reserved'),
          const SizedBox(width: 16),
          _BarLegend(AppColors.available,            'Available $available'),
        ]),
      ]),
    );
  }
}

class _BarLegend extends StatelessWidget {
  final Color color; final String label;
  const _BarLegend(this.color, this.label);
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
    const SizedBox(width: 5),
    Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
  ]);
}

// ── Visual Floor Map ──────────────────────────────────────────────────────
class _FloorMap extends StatelessWidget {
  final List<ParkingSlot> slots;
  const _FloorMap({required this.slots});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardNavy,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.inputBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.map_outlined, color: AppColors.accentBlue, size: 16),
          SizedBox(width: 8),
          Text('Floor Map', style: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 14),

        // Entrance label
        Row(children: [
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.accentBlue.withValues(alpha: 0.1),
              border: Border.all(color: AppColors.accentBlue.withValues(alpha: 0.3)),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.arrow_downward_rounded, color: AppColors.accentBlue, size: 12),
              SizedBox(width: 4),
              Text('ENTRANCE', style: TextStyle(color: AppColors.accentBlue, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1)),
            ]),
          ),
          const Spacer(),
        ]),
        const SizedBox(height: 12),

        // Slot boxes — arranged in two rows of max 3
        if (slots.isNotEmpty) ...[
          _buildRow(slots.take(3).toList()),
          const SizedBox(height: 10),
          // Drive lane
          Row(children: [
            Expanded(child: Container(height: 1, color: AppColors.divider)),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: Text('DRIVE LANE', style: TextStyle(color: AppColors.textHint, fontSize: 8, letterSpacing: 1)),
            ),
            Expanded(child: Container(height: 1, color: AppColors.divider)),
          ]),
          const SizedBox(height: 10),
          if (slots.length > 3) _buildRow(slots.skip(3).toList()),
        ],
      ]),
    );
  }

  Widget _buildRow(List<ParkingSlot> row) {
    return Row(
      children: row.map((slot) {
        Color bg, border, textColor;
        String icon;

        if (slot.isAvailable) {
          bg = AppColors.available.withValues(alpha: 0.12);
          border = AppColors.available.withValues(alpha: 0.4);
          textColor = AppColors.available;
          icon = '🅿';
        } else if (slot.isReserved) {
          bg = AppColors.reserved.withValues(alpha: 0.12);
          border = AppColors.reserved.withValues(alpha: 0.4);
          textColor = AppColors.reserved;
          icon = '🔖';
        } else {
          bg = AppColors.occupied.withValues(alpha: 0.12);
          border = AppColors.occupied.withValues(alpha: 0.4);
          textColor = AppColors.occupied;
          icon = '🚗';
        }

        final num = slot.slotID.replaceAll(RegExp(r'[^0-9]'), '');

        return Expanded(child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Container(
            height: 72,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: border, width: 1.5),
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(icon, style: const TextStyle(fontSize: 18)),
              const SizedBox(height: 4),
              Text('P$num', style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w800)),
              Text(slot.statusLabel, style: TextStyle(color: textColor.withValues(alpha: 0.7), fontSize: 8, fontWeight: FontWeight.w500)),
            ]),
          ),
        ));
      }).toList(),
    );
  }
}

// ── Slot Detail List ──────────────────────────────────────────────────────
class _SlotDetailList extends StatelessWidget {
  final List<ParkingSlot> slots;
  final String uid;                            // current user (to mark "mine")
  final Map<String, dynamic>? myBooking;       // own private plate/booking ID
  const _SlotDetailList({required this.slots, required this.uid, this.myBooking});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardNavy,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.inputBorder),
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Row(children: [
            const Icon(Icons.list_alt_rounded, color: AppColors.accentBlue, size: 16),
            const SizedBox(width: 8),
            const Text('Slot Details', style: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
            const Spacer(),
            Text('${slots.length} slots', style: const TextStyle(color: AppColors.textHint, fontSize: 12)),
          ]),
        ),
        const Divider(color: AppColors.divider, height: 1),
        ...slots.map((s) => _SlotRow(
              slot: s,
              ownPlate:     s.userID == uid ? (myBooking?['PlateNum'] ?? '').toString() : '',
              ownBookingId: s.userID == uid ? (myBooking?['BookingID'] ?? '').toString() : '',
            )),
      ]),
    );
  }
}

class _SlotRow extends StatelessWidget {
  final ParkingSlot slot;
  final String ownPlate, ownBookingId;        // private details, only for own slot
  const _SlotRow({required this.slot, this.ownPlate = '', this.ownBookingId = ''});

  Color get _col {
    if (slot.isAvailable) return AppColors.available;
    if (slot.isReserved)  return AppColors.reserved;
    return AppColors.occupied;
  }

  @override
  Widget build(BuildContext context) {
    final num = slot.slotID.replaceAll(RegExp(r'[^0-9]'), '');
    // Only the slot's owner may see plate / RFID / booking ID. Everyone else
    // sees just the status (Available / Reserved / Occupied).
    final mine = slot.userID.isNotEmpty &&
        slot.userID == FirebaseAuth.instance.currentUser?.uid;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Row(children: [
        // Slot number badge
        Container(
          width: 42, height: 42,
          decoration: BoxDecoration(
            color: _col.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _col.withValues(alpha: 0.3)),
          ),
          alignment: Alignment.center,
          child: Text('P$num', style: TextStyle(color: _col, fontSize: 13, fontWeight: FontWeight.w800)),
        ),
        const SizedBox(width: 12),

        // Info
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: _col.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
              child: Text(slot.statusLabel,
                  style: TextStyle(color: _col, fontSize: 10, fontWeight: FontWeight.w700)),
            ),
            if (mine && ownPlate.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text('• $ownPlate',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
            ],
          ]),
          if (mine && slot.rfidTag.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text('RFID: ${slot.rfidTag}',
                  style: const TextStyle(color: AppColors.textHint, fontSize: 10)),
            ),
          if (mine && ownBookingId.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('#$ownBookingId',
                  style: const TextStyle(color: AppColors.textHint, fontSize: 10)),
            ),
        ])),

        // Sensor dot
        Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(shape: BoxShape.circle, color: _col),
          ),
          const SizedBox(height: 2),
          const Text('sensor', style: TextStyle(color: AppColors.textHint, fontSize: 8)),
        ]),
      ]),
    );
  }
}

// ── Sensor Info Card ──────────────────────────────────────────────────────
class _SensorCard extends StatelessWidget {
  final DateTime lastSync;
  const _SensorCard({required this.lastSync});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.accentBlue.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.accentBlue.withValues(alpha: 0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.sensors_rounded, color: AppColors.accentBlue, size: 16),
          SizedBox(width: 8),
          Text('Sensor Status', style: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 12),
        const _SensorRow('Connection',   'Firebase Realtime DB',  Icons.cloud_done_rounded,   AppColors.available),
        const SizedBox(height: 8),
        const _SensorRow('Protocol',     'Sensor → Firebase → App', Icons.sync_alt_rounded,   AppColors.accentBlue),
        const SizedBox(height: 8),
        _SensorRow('Last update',  _fmt(lastSync),           Icons.access_time_rounded,  AppColors.textSecondary),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.cardNavy,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.inputBorder),
          ),
          child: const Row(children: [
            Icon(Icons.info_outline_rounded, color: AppColors.textHint, size: 14),
            SizedBox(width: 8),
            Expanded(child: Text(
              'Each slot is monitored by an IR / ultrasonic sensor. '
              'When a car parks or leaves, the sensor updates Firebase in real time, '
              'and this dashboard reflects the change instantly.',
              style: TextStyle(color: AppColors.textHint, fontSize: 11, height: 1.5),
            )),
          ]),
        ),
      ]),
    );
  }

  String _fmt(DateTime dt) {
    final h  = dt.hour.toString().padLeft(2, '0');
    final m  = dt.minute.toString().padLeft(2, '0');
    final s  = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}

class _SensorRow extends StatelessWidget {
  final String label, value; final IconData icon; final Color color;
  const _SensorRow(this.label, this.value, this.icon, this.color);
  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(icon, color: color, size: 14),
    const SizedBox(width: 8),
    Text('$label: ', style: const TextStyle(color: AppColors.textHint, fontSize: 12)),
    Expanded(child: Text(value, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600))),
  ]);
}
