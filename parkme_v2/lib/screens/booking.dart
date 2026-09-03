import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../appsColor/app_theme.dart';
import '../widgets/app_logo.dart';
import '../models/parkingSlot.dart';
import '../services/parking_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Booking Screen
// ─────────────────────────────────────────────────────────────────────────────

class BookingScreen extends StatefulWidget {
  const BookingScreen({super.key});

  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen>
    with TickerProviderStateMixin {

  final _service  = ParkingService.instance;
  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? 'guest';

  List<ParkingSlot> _slots             = [];
  bool              _loading           = true;
  String?           _activeBookingSlot;
  List<String>      _myPlates          = [];   // all plates from the user's profile
  String            _countedCompletedId = '';  // booking already counted as completed
  String            _parkedBookingId    = '';  // booking whose car is parked now
  Map<String, dynamic>? _myBooking;            // private plate/booking ID (own)
  Timer?            _expireTimer;
  StreamSubscription? _sub;
  StreamSubscription? _bookingSub;

  late AnimationController _headerCtrl;
  late Animation<double>   _headerFade;

  @override
  void initState() {
    super.initState();
    _headerCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _headerFade = CurvedAnimation(parent: _headerCtrl, curve: Curves.easeOut);

    _sub = _service.slotsStream.listen((slots) {
      final mine = slots.where((s) => s.isReserved && s.userID == _uid);
      // "Completed" = full cycle done: my car parked (Occupied) and then LEFT
      // (the bay is no longer Occupied by me). Count each booking once.
      final myParked = slots.where((s) => s.isOccupied && s.userID == _uid);
      if (myParked.isNotEmpty) {
        // Car is currently parked — remember this booking as in-progress.
        final bId = (_myBooking?['BookingID'] ?? '').toString();
        if (bId.isNotEmpty) _parkedBookingId = bId;
      } else if (_parkedBookingId.isNotEmpty &&
                 _parkedBookingId != _countedCompletedId) {
        // Was parked, now the bay is free → the car left → booking completed.
        _countedCompletedId = _parkedBookingId;
        _incProfileCounter('CompletedBookings');
        _service.removeMyBooking(_uid);   // clear the finished private record
        _parkedBookingId = '';
      }
      setState(() {
        _slots             = slots;
        _loading           = false;
        _activeBookingSlot = mine.isNotEmpty ? mine.first.slotID : null;
      });
      _headerCtrl.forward();
    });

    // Check for expired reservations every 3 min
    _expireTimer = Timer.periodic(
      const Duration(minutes: 3), (_) => _service.expireStaleReservations());

    // Listen to my own private booking details (plate / booking ID).
    _bookingSub = _service.myBookingStream(_uid).listen((b) {
      if (mounted) setState(() => _myBooking = b);
    });

    _loadMyPlate();
  }

  // Increment a running counter on the user's Firestore profile
  // (TotalBookings / CompletedBookings). Best-effort.
  Future<void> _incProfileCounter(String field) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(_uid).set(
        {field: FieldValue.increment(1)}, SetOptions(merge: true));
    } catch (_) {}
  }

  // Pull the saved plates from the user's profile so booking can auto-fill /
  // let the user pick which car (no need to re-type every time).
  Future<void> _loadMyPlate() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(_uid).get();
      final data = doc.data() ?? {};
      final raw = data['Plates'];
      List<String> plates;
      if (raw is List && raw.isNotEmpty) {
        plates = raw.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
      } else {
        final single = (data['PlateNum'] ?? '').toString();
        plates = single.isEmpty ? <String>[] : [single];
      }
      if (mounted) setState(() => _myPlates = plates);
    } catch (_) {}
  }

  @override
  void dispose() {
    _headerCtrl.dispose();
    _expireTimer?.cancel();
    _sub?.cancel();
    _bookingSub?.cancel();
    super.dispose();
  }

  // ── Reserve ─────────────────────────────────────────────────────────────
  Future<void> _reserve(String slotId, String plateNum) async {
    debugPrint('LATENCY reserve tapped ($slotId)');   // confirms the tap ran
    if (_activeBookingSlot != null) {
      _toast('You already have a reservation at $_activeBookingSlot.', isError: true);
      return;
    }
    // Pull the user's registered RFID card UID so the gate can match the card
    // to this booking. Empty is fine — booking still works without a card.
    String rfidTag = '';
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(_uid).get();
      rfidTag = (doc.data()?['RFIDTag'] ?? '').toString();
    } catch (_) {}

    // LATENCY (report): time the reserve transaction round-trip
    // app -> Firebase -> app. Look for "LATENCY reserve write" in the console.
    final sw = Stopwatch()..start();
    final ok = await _service.reserve(
      slotId: slotId, userId: _uid, plateNum: plateNum, rfidTag: rfidTag);
    sw.stop();
    final ms = sw.elapsedMilliseconds;
    debugPrint('LATENCY reserve write ($slotId): $ms ms');
    if (ok) {
      _incProfileCounter('TotalBookings');   // count this booking
      // TEMP (4.5.1 report): latency shown on-screen so it can be read/screenshot
      // without the console. Remove the "  •  ⏱ ${ms} ms" part for the final demo.
      _toast('Reserved $slotId!  •  ⏱ $ms ms  — arrive within 15 min.');
    } else {
      _toast('$slotId no longer available.  •  ⏱ $ms ms', isError: true);
    }
  }

  // ── Cancel ──────────────────────────────────────────────────────────────
  Future<void> _cancel(String slotId) async {
    await _service.freeSlot(slotId);
    await _service.removeMyBooking(_uid);   // clear my private booking record
    _toast('Reservation for $slotId has been cancelled.');
  }

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

  int get _availableCount => _slots.where((s) => s.isAvailable).length;

  // ── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryNavy,
      appBar: AppBar(
        backgroundColor: AppColors.cardNavy,
        title: const AppLogo(height: 32),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 14),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.accentBlue.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.accentBlue.withValues(alpha: 0.4)),
            ),
            child: Text(
              '$_availableCount / ${_slots.length} Free',
              style: const TextStyle(color: AppColors.accentBlue, fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.accentBlue))
          : CustomScrollView(slivers: [
              // ── Availability banner ──────────────────────────────
              SliverToBoxAdapter(
                child: FadeTransition(
                  opacity: _headerFade,
                  child: _AvailabilityBanner(
                    available: _availableCount,
                    total: _slots.length,
                  ),
                ),
              ),

              // ── Active booking reminder ──────────────────────────
              if (_activeBookingSlot != null)
                SliverToBoxAdapter(
                  child: _ActiveBanner(
                    slotID: _activeBookingSlot!,
                    slots:  _slots,
                    onCancel: () => _showCancelDialog(_activeBookingSlot!),
                  ),
                ),

              // ── Section header ───────────────────────────────────
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, 8, 20, 6),
                  child: Row(children: [
                    Text('Select a Slot',
                        style: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
                    Spacer(),
                    // Shrink the legend so it never overflows on narrow screens.
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          _LegendChip(AppColors.available, 'Available'),
                          SizedBox(width: 8),
                          _LegendChip(AppColors.reserved, 'Reserved'),
                          SizedBox(width: 8),
                          _LegendChip(AppColors.occupied, 'Occupied'),
                        ]),
                      ),
                    ),
                  ]),
                ),
              ),

              // ── Slot cards ───────────────────────────────────────
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _SlotCard(
                        slot:       _slots[i],
                        // "mine" = this slot is booked/occupied by ME → only I
                        // see my plate; everyone else sees just the status.
                        isUserSlot: _slots[i].userID == _uid,
                        canBook:    _activeBookingSlot == null,
                        // Show my plate on MY slot whether it's Reserved or
                        // already Occupied (parked). Others get '' → status only.
                        ownPlate:     _slots[i].userID == _uid
                            ? (_myBooking?['PlateNum'] ?? '').toString() : '',
                        ownBookingId: _slots[i].userID == _uid
                            ? (_myBooking?['BookingID'] ?? '').toString() : '',
                        onReserve:  () => _showReserveDialog(_slots[i].slotID),
                        onCancel:   () => _showCancelDialog(_slots[i].slotID),
                      ),
                    ),
                    childCount: _slots.length,
                  ),
                ),
              ),
            ]),
    );
  }

  // ── Dialogs ──────────────────────────────────────────────────────────────
  void _showReserveDialog(String slotId) {
    // Pre-fill with the default (first) plate from the profile.
    final plateCtrl = TextEditingController(
        text: _myPlates.isNotEmpty ? _myPlates.first : '');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: _ReserveSheet(
          slotID:    slotId,
          plateCtrl: plateCtrl,
          savedPlates: _myPlates,
          onConfirm: () {
            final p = plateCtrl.text.trim();
            if (p.length < 3) return;
            Navigator.pop(context);
            _reserve(slotId, p.toUpperCase());
          },
        ),
      ),
    );
  }

  void _showCancelDialog(String slotId) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.cardNavy,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Cancel Reservation?',
            style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 17)),
        content: Text(
          'Your reservation for $slotId will be released.',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        actions: [
          Row(
            children: [
              Expanded(
                child: TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Keep it', style: TextStyle(color: AppColors.textHint)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.occupied,
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () { Navigator.pop(context); _cancel(slotId); },
                  child: const Text('Cancel Booking',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Availability Banner ───────────────────────────────────────────────────
class _AvailabilityBanner extends StatelessWidget {
  final int available, total;
  const _AvailabilityBanner({required this.available, required this.total});

  @override
  Widget build(BuildContext context) {
    final pct   = total == 0 ? 0.0 : available / total;
    final isLow = available <= 1;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isLow
              ? [const Color(0xFFBF360C), const Color(0xFFE53935)]
              : [AppColors.accentBlue, const Color(0xFF1040B0)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: (isLow ? AppColors.occupied : AppColors.accentBlue).withValues(alpha: 0.35),
            blurRadius: 20, offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$available Slot${available == 1 ? '' : 's'} Available',
              style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(isLow ? '⚠️  Almost full — book quickly!' : 'out of $total total slots',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12)),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: pct, minHeight: 7,
              backgroundColor: Colors.white.withValues(alpha: 0.2),
              valueColor: const AlwaysStoppedAnimation(Colors.white),
            ),
          ),
        ])),
        const SizedBox(width: 16),
        Container(
          width: 60, height: 60,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(16),
          ),
          alignment: Alignment.center,
          child: Text('${(pct * 100).round()}%',
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
        ),
      ]),
    );
  }
}

// ── Active Booking Banner with live countdown ─────────────────────────────
class _ActiveBanner extends StatefulWidget {
  final String slotID; final List<ParkingSlot> slots; final VoidCallback onCancel;
  const _ActiveBanner({required this.slotID, required this.slots, required this.onCancel});
  @override State<_ActiveBanner> createState() => _ActiveBannerState();
}

class _ActiveBannerState extends State<_ActiveBanner> {
  Timer? _t;
  int _secsLeft = 900;

  @override
  void initState() {
    super.initState();
    _calc();
    _t = Timer.periodic(const Duration(seconds: 1), (_) => _calc());
  }

  @override
  void dispose() { _t?.cancel(); super.dispose(); }

  void _calc() {
    final slot = widget.slots.firstWhere(
      (s) => s.slotID == widget.slotID,
      orElse: () => ParkingSlot(slotID: widget.slotID, status: SlotStatus.reserved),
    );
    if (slot.reservationTime.isEmpty) return;
    final r = DateTime.tryParse(slot.reservationTime);
    if (r == null) return;
    setState(() => _secsLeft = (900 - DateTime.now().difference(r).inSeconds).clamp(0, 900));
  }

  String get _fmt {
    final m = (_secsLeft ~/ 60).toString().padLeft(2, '0');
    final s = (_secsLeft % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Color get _col {
    if (_secsLeft > 600) return AppColors.available;
    if (_secsLeft > 300) return AppColors.reserved;
    return AppColors.occupied;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
      ),
      child: Row(children: [
        Icon(Icons.schedule_rounded, color: _col, size: 28),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Active: ${widget.slotID.toUpperCase()}',
              style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 14)),
          Text('Auto-cancels in $_fmt',
              style: TextStyle(fontSize: 12, color: _col, fontWeight: FontWeight.w600)),
        ])),
        TextButton.icon(
          onPressed: widget.onCancel,
          icon: const Icon(Icons.cancel_outlined, size: 16, color: AppColors.occupied),
          label: const Text('Cancel', style: TextStyle(fontSize: 12, color: AppColors.occupied, fontWeight: FontWeight.w600)),
          style: TextButton.styleFrom(
            backgroundColor: AppColors.occupied.withValues(alpha: 0.08),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ]),
    );
  }
}

// ── Slot Card ─────────────────────────────────────────────────────────────
class _SlotCard extends StatelessWidget {
  final ParkingSlot slot;
  final bool isUserSlot, canBook;
  final String ownPlate, ownBookingId;   // private details, only for own slot
  final VoidCallback onReserve, onCancel;
  const _SlotCard({required this.slot, required this.isUserSlot, required this.canBook, this.ownPlate = '', this.ownBookingId = '', required this.onReserve, required this.onCancel});

  Color get _color {
    if (slot.isAvailable) return AppColors.available;
    if (slot.isReserved)  return const Color(0xFFF59E0B);
    return AppColors.occupied;
  }

  Color get _bg {
    if (slot.isAvailable) return AppColors.available.withValues(alpha: 0.08);
    if (slot.isReserved)  return AppColors.reserved.withValues(alpha: 0.08);
    return AppColors.occupied.withValues(alpha: 0.08);
  }

  IconData get _icon {
    if (slot.isAvailable) return Icons.check_circle_outline_rounded;
    if (slot.isReserved)  return Icons.schedule_rounded;
    return Icons.directions_car_rounded;
  }

  String get _num => slot.slotID.replaceAll(RegExp(r'[^0-9]'), '');

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        color: AppColors.cardNavy,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isUserSlot ? AppColors.accentBlue : _color.withValues(alpha: 0.3),
          width: isUserSlot ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(color: _color.withValues(alpha: 0.08), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(children: [
        // Left accent
        Container(
          width: 70,
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            color: _bg,
            borderRadius: const BorderRadius.horizontal(left: Radius.circular(17)),
          ),
          alignment: Alignment.center,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('P$_num', style: TextStyle(color: _color, fontSize: 26, fontWeight: FontWeight.w900)),
            Container(width: 28, height: 3, margin: const EdgeInsets.only(top: 4),
              decoration: BoxDecoration(color: _color.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(2))),
          ]),
        ),

        // Info
        Expanded(child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(color: _color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(_icon, size: 10, color: _color),
                  const SizedBox(width: 4),
                  Text(slot.statusLabel.toUpperCase(),
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: _color)),
                ]),
              ),
              if (isUserSlot) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: AppColors.accentBlue.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
                  child: const Text('YOUR SLOT', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: AppColors.accentBlue)),
                ),
              ],
            ]),
            const SizedBox(height: 6),
            // Only show plate / booking ID on the user's OWN slot, read from the
            // private Bookings/<uid> node. Other users' slots show status only.
            if (!slot.isAvailable && isUserSlot && ownPlate.isNotEmpty)
              Text('🚗  $ownPlate   •   #$ownBookingId',
                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                  overflow: TextOverflow.ellipsis)
            else if (!slot.isAvailable)
              Text(slot.isReserved ? 'Reserved by another user' : 'Currently occupied',
                  style: const TextStyle(fontSize: 11, color: AppColors.textHint))
            else if (slot.isAvailable)
              const Text('Tap to reserve this slot',
                  style: TextStyle(fontSize: 11, color: AppColors.textHint)),
          ]),
        )),

        // Action button
        Padding(
          padding: const EdgeInsets.only(right: 14),
          child: _buildAction(),
        ),
      ]),
    );
  }

  Widget _buildAction() {
    if (isUserSlot && slot.isReserved) {
      return _ActionBtn(label: 'Cancel', icon: Icons.cancel_outlined, color: AppColors.occupied, onTap: onCancel);
    }
    if (slot.isAvailable && canBook) {
      return _ActionBtn(label: 'Reserve', icon: Icons.add_circle_outline_rounded, color: AppColors.accentBlue, onTap: onReserve);
    }
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: AppColors.inputFill, borderRadius: BorderRadius.circular(12)),
      child: const Icon(Icons.lock_outline_rounded, size: 22, color: AppColors.textHint),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final String label; final IconData icon; final Color color; final VoidCallback onTap;
  const _ActionBtn({required this.label, required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
        ]),
      ),
    );
  }
}

// ── Reserve Bottom Sheet ──────────────────────────────────────────────────
class _ReserveSheet extends StatefulWidget {
  final String slotID;
  final TextEditingController plateCtrl;
  final List<String> savedPlates;
  final VoidCallback onConfirm;
  const _ReserveSheet({
    required this.slotID,
    required this.plateCtrl,
    required this.savedPlates,
    required this.onConfirm,
  });

  @override
  State<_ReserveSheet> createState() => _ReserveSheetState();
}

class _ReserveSheetState extends State<_ReserveSheet> {
  String get _num => widget.slotID.replaceAll(RegExp(r'[^0-9]'), '');

  @override
  Widget build(BuildContext context) {
    final plateCtrl = widget.plateCtrl;
    final onConfirm = widget.onConfirm;
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
        Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: AppColors.accentBlue.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(14)),
            child: const Icon(Icons.local_parking_rounded, color: AppColors.accentBlue, size: 22),
          ),
          const SizedBox(width: 14),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Reserve Slot $_num',
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
            const Text('Arrive within 15 minutes',
                style: TextStyle(fontSize: 11, color: Color(0xFFF59E0B))),
          ]),
        ]),
        const SizedBox(height: 22),

        // Saved-plate picker (tap a car to use it). Only if more than one.
        if (widget.savedPlates.isNotEmpty) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              widget.savedPlates.length > 1 ? 'Choose your car' : 'Your car',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8, runSpacing: 8,
            children: widget.savedPlates.map((p) {
              final selected = plateCtrl.text.trim().toUpperCase() == p.toUpperCase();
              return GestureDetector(
                onTap: () => setState(() => plateCtrl.text = p),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: selected ? AppColors.accentBlue.withValues(alpha: 0.18) : AppColors.inputFill,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selected ? AppColors.accentBlue : AppColors.inputBorder,
                      width: selected ? 1.6 : 1,
                    ),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(selected ? Icons.directions_car_rounded : Icons.directions_car_outlined,
                        size: 15, color: selected ? AppColors.accentBlue : AppColors.textHint),
                    const SizedBox(width: 6),
                    Text(p, style: TextStyle(
                      color: selected ? AppColors.accentBlue : AppColors.textSecondary,
                      fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 1)),
                  ]),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
        ],

        // Plate input (editable — for a car not in your saved list)
        TextFormField(
          controller: plateCtrl,
          onChanged: (_) => setState(() {}),
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [
            _UpperCaseFormatter(),
            LengthLimitingTextInputFormatter(10),
          ],
          style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 15),
          decoration: const InputDecoration(
            labelText:   'Plate Number',
            hintText:    'e.g. WXY 1234',
            prefixIcon:  Icon(Icons.credit_card_rounded, color: AppColors.accentBlue),
          ),
        ),
        const SizedBox(height: 14),

        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
          ),
          child: const Row(children: [
            Icon(Icons.info_outline_rounded, color: Color(0xFFF59E0B), size: 16),
            SizedBox(width: 8),
            Expanded(child: Text(
              'Reservation auto-cancels if you do not arrive within 15 minutes.',
              style: TextStyle(fontSize: 11, color: Color(0xFFF59E0B)),
            )),
          ]),
        ),
        const SizedBox(height: 20),

        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: onConfirm,
            child: const Text('Confirm Reservation', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          ),
        ),
      ]),
    );
  }
}

class _LegendChip extends StatelessWidget {
  final Color color; final String label;
  const _LegendChip(this.color, this.label);
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
    const SizedBox(width: 4),
    Text(label, style: const TextStyle(color: AppColors.textHint, fontSize: 9, fontWeight: FontWeight.w500)),
  ]);
}

class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue o, TextEditingValue n) =>
      n.copyWith(text: n.text.toUpperCase());
}
