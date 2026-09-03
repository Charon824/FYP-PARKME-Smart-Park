import 'dart:async';
import 'dart:convert';                                // base64 encode/decode
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;
import 'package:firebase_database/firebase_database.dart';
import '../services/parking_service.dart';
import 'admin_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// COLOURS  (matches your appTheme.dart)
// ─────────────────────────────────────────────────────────────────────────────
class _C {
  // Light theme (matches AppColors). "white" stays real white for text on blue.
  static const bg        = Color(0xFFEAF2FD);   // page background
  static const bgCard    = Color(0xFFFFFFFF);   // cards
  static const bgInput   = Color(0xFFF4F8FF);   // input fields
  static const border    = Color(0xFFCBD8EE);
  static const divider   = Color(0xFFDCE6F5);
  static const blue      = Color(0xFF1E90FF);
  static const blueDark  = Color(0xFF1040B0);
  static const available = Color(0xFF22C55E);
  static const reserved  = Color(0xFFF59E0B);
  static const occupied  = Color(0xFFEF4444);
  static const white     = Color(0xFFFFFFFF);   // genuine white (on blue)
  static const text      = Color(0xFF0D1B3E);   // dark primary text
  static const textSec   = Color(0xFF49587C);
  static const textHint  = Color(0xFF8793AE);
}

// ─────────────────────────────────────────────────────────────────────────────
// PARKING SLOT MODEL  (Realtime Database)
// ─────────────────────────────────────────────────────────────────────────────
enum SlotStatus { available, reserved, occupied }

class ParkingSlot {
  final String slotID;
  final SlotStatus status;
  final String plateNum;
  final String userID;
  final String bookingID;
  final String reservationTime;
  final String rfidTag;

  ParkingSlot({
    required this.slotID,
    required this.status,
    this.plateNum        = '',
    this.userID          = '',
    this.bookingID       = '',
    this.reservationTime = '',
    this.rfidTag         = '',
  });

  factory ParkingSlot.fromMap(String id, Map<dynamic, dynamic> m) {
    final raw = (m['Status'] ?? 'Available').toString().toLowerCase();
    SlotStatus st;
    if (raw == 'reserved') {
      st = SlotStatus.reserved;
    } else if (raw == 'occupied') {
      st = SlotStatus.occupied;
    } else {
      st = SlotStatus.available;
    }
    return ParkingSlot(
      slotID:          id,
      status:          st,
      plateNum:        (m['PlateNum']        ?? '').toString(),
      userID:          (m['UserID']          ?? '').toString(),
      bookingID:       (m['BookingID']       ?? '').toString(),
      reservationTime: (m['ReservationTime'] ?? '').toString(),
      rfidTag:         (m['RFIDTag']         ?? '').toString(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PROFILE SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  // ── Firebase refs ──────────────────────────────────────────────────────
  final _auth  = FirebaseAuth.instance;
  final _db    = FirebaseFirestore.instance;
  final _rtdb  = FirebaseDatabase.instance.ref('ParkingSlot');

  User? get _user => _auth.currentUser;

  // An account counts as verified if the email is verified OR it was signed in
  // via phone OTP (phone accounts have no email to verify).
  bool get _isAccountVerified {
    final u = _user;
    if (u == null) return false;
    if (u.emailVerified) return true;
    final hasPhone = (u.phoneNumber?.isNotEmpty ?? false);
    final phoneProvider = u.providerData.any((p) => p.providerId == 'phone');
    return hasPhone || phoneProvider;
  }

  // ── State ──────────────────────────────────────────────────────────────
  Map<String, dynamic> _profile   = {};
  List<ParkingSlot>    _slots     = [];
  String?              _selSlot;          // selected slot id for quick booking
  bool                 _booking   = false;
  bool                 _notifOn   = true;
  bool                 _locationOn= true;
  bool                 _autoRfid  = false;

  StreamSubscription?  _slotSub;
  Timer?               _expireTimer;

  // ── Lifecycle ──────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _fetchProfile();
    _listenSlots();
    _expireTimer = Timer.periodic(
      const Duration(minutes: 3), (_) => _expireStale());
  }

  @override
  void dispose() {
    _slotSub?.cancel();
    _expireTimer?.cancel();
    super.dispose();
  }

  // ── Firestore: load profile ────────────────────────────────────────────
  Future<void> _fetchProfile() async {
    if (_user == null) return;
    try {
      final snap = await _db.collection('users').doc(_user!.uid).get();
      if (mounted) {
        setState(() {
          _profile = snap.data() ?? {};
        });
      }
    } catch (_) {
      // ignore profile load errors; UI falls back to auth defaults
    }
  }

  // ── Firestore: save profile ────────────────────────────────────────────
  Future<void> _saveProfile(Map<String, dynamic> patch) async {
    if (_user == null) return;
    // Update the UI immediately (optimistic) so the change always shows.
    setState(() => _profile.addAll(patch));
    try {
      await _db.collection('users').doc(_user!.uid).set(
        {...patch, 'UpdatedAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
    } catch (e) {
      // Surface the real reason (e.g. Firestore rules blocking the write).
      if (mounted) _toast('Could not save: $e', isError: true);
    }
  }

  // ── Multiple car plates (all tied to the one RFID card) ─────────────────
  // Stored as a list; the FIRST entry is the default used to pre-fill booking.
  List<String> get _plates {
    final raw = _profile['Plates'];
    if (raw is List && raw.isNotEmpty) {
      return raw.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
    }
    final single = (_profile['PlateNum'] ?? '').toString();
    return single.isEmpty ? <String>[] : [single];
  }

  // Persist the list, keeping PlateNum = the default (first) for booking.
  Future<void> _savePlates(List<String> plates) =>
      _saveProfile({'Plates': plates, 'PlateNum': plates.isNotEmpty ? plates.first : ''});

  void _addPlate() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _C.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Add car plate',
            style: TextStyle(color: _C.text, fontSize: 17, fontWeight: FontWeight.w700)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [LengthLimitingTextInputFormatter(10)],
          style: const TextStyle(color: _C.text, fontWeight: FontWeight.w700, letterSpacing: 2),
          decoration: const InputDecoration(hintText: 'e.g. WXY 1234'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: _C.textHint))),
          ElevatedButton(
            onPressed: () {
              final p = ctrl.text.trim().toUpperCase();
              Navigator.pop(ctx);
              if (p.isEmpty) return;
              final list = [..._plates];
              if (!list.contains(p)) list.add(p);
              _savePlates(list);
              _toast('Plate $p added!');
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _removePlate(String p) {
    final list = [..._plates]..remove(p);
    _savePlates(list);
    _toast('Plate $p removed.');
  }

  // Move a plate to the front so it becomes the default for booking.
  void _setDefaultPlate(String p) {
    final list = [..._plates]..remove(p);
    list.insert(0, p);
    _savePlates(list);
    _toast('$p is now your default plate.');
  }

  // ── Realtime DB: live slot stream ──────────────────────────────────────
  void _listenSlots() {
    _slotSub = _rtdb.onValue.listen((ev) {
      if (!ev.snapshot.exists) return;
      final raw = Map<String, dynamic>.from(ev.snapshot.value as Map);
      final list = raw.entries
          .map((e) => ParkingSlot.fromMap(e.key, Map.from(e.value as Map)))
          .toList()
        ..sort((a, b) => a.slotID.compareTo(b.slotID));
      if (mounted) setState(() => _slots = list);
    });
  }

  // ── Reserve slot (atomic transaction) ─────────────────────────────────
  Future<void> _reserveSlot(String slotId) async {
    if (_user == null) return;
    final plate = _profile['PlateNum'] ?? '';
    if (plate.isEmpty) {
      _toast('Please add your car plate number first.', isError: true);
      return;
    }

    // One active booking only
    final alreadyBooked = _slots.any(
      (s) => s.status == SlotStatus.reserved && s.userID == _user!.uid);
    if (alreadyBooked) {
      _toast('You already have an active reservation.', isError: true);
      return;
    }

    setState(() => _booking = true);
    try {
      // Route through ParkingService so the plate / booking ID are stored in the
      // private Bookings/<uid> node (not in the public ParkingSlot).
      final ok = await ParkingService.instance.reserve(
        slotId:   slotId,
        userId:   _user!.uid,
        plateNum: plate,
        rfidTag:  (_profile['RFIDTag'] ?? '').toString(),
      );
      if (ok) {
        _toast('Slot $slotId reserved! Arrive within 15 minutes.');
        setState(() => _selSlot = null);
      } else {
        _toast('Slot no longer available.', isError: true);
      }
    } finally {
      if (mounted) setState(() => _booking = false);
    }
  }

  // ── Cancel reservation ─────────────────────────────────────────────────
  Future<void> _cancelSlot(String slotId) async {
    if (_user == null) return;
    await ParkingService.instance.freeSlot(slotId);
    await ParkingService.instance.removeMyBooking(_user!.uid);
    _toast('Reservation cancelled.');
  }

  // ── Auto-expire stale reservations ────────────────────────────────────
  Future<void> _expireStale() async {
    final snap = await _rtdb.get();
    if (!snap.exists) return;
    final raw = Map<String, dynamic>.from(snap.value as Map);
    for (final e in raw.entries) {
      final d = Map<String, dynamic>.from(e.value as Map);
      if (d['Status'] != 'Reserved') continue;
      final t = DateTime.tryParse(d['ReservationTime'] ?? '');
      if (t != null && DateTime.now().difference(t).inMinutes >= 15) {
        await _rtdb.child(e.key).update({
          'Status': 'Available', 'BookingID': '', 'PlateNum': '',
          'UserID': '', 'RFIDTag': '', 'ReservationTime': '',
        });
      }
    }
  }

  // ── Toast helper ──────────────────────────────────────────────────────
  void _toast(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: _C.white, fontSize: 13)),
      backgroundColor: isError ? _C.occupied : _C.blue,
      behavior:        SnackBarBehavior.floating,
      shape:     RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      margin:    const EdgeInsets.all(16),
      duration:  const Duration(seconds: 4),
    ));
  }

  // ── Build ──────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final name  = _user?.displayName  ?? _profile['Display Name'] ?? 'ParkMe User';
    final email = _user?.email         ?? _profile['Email']        ?? '';
    final phone = _profile['Phone']    ?? _user?.phoneNumber       ?? '';
    final rfid  = _profile['RFIDTag']  ?? '';
    final car   = _profile['CarModel'] ?? '';

    final totalBookings     = _profile['TotalBookings']     ?? 0;
    final completedBookings = _profile['CompletedBookings'] ?? 0;
    final activeCount       = _slots.where(
      (s) => s.status == SlotStatus.reserved && s.userID == (_user?.uid ?? '')).length;

    return Scaffold(
      backgroundColor: _C.bg,
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                // ── Hero header ───────────────────────────────────
                _buildHero(name, email, totalBookings, activeCount, completedBookings),

                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Column(children: [

                    // ── Personal info ─────────────────────────────
                    const _SectionLabel(icon: Icons.person_outline_rounded, label: 'Personal Info'),
                    const SizedBox(height: 8),
                    _InfoCard(items: [
                      _InfoRow(icon: Icons.person_outline_rounded,   label: 'Full name',   value: name,  onTap: () => _editField('Display Name', 'Full name', name)),
                      _InfoRow(icon: Icons.email_outlined,            label: 'Email',        value: email, onTap: null),
                      _InfoRow(icon: Icons.phone_outlined,            label: 'Phone',        value: phone.isNotEmpty ? phone : 'Not set', onTap: () => _editField('Phone', 'Phone number', phone)),
                      // Verified if the email is verified OR the account was
                      // created/verified via phone OTP (phone users have no email).
                      _InfoRow(icon: Icons.verified_user_outlined,    label: 'Status',
                        value: _isAccountVerified ? 'Verified' : 'Unverified',
                        valueColor: _isAccountVerified ? _C.available : _C.occupied, onTap: null),
                    ]),

                    const SizedBox(height: 20),

                    // ── Vehicle & RFID ────────────────────────────
                    const _SectionLabel(icon: Icons.directions_car_outlined, label: 'Vehicle & RFID'),
                    const SizedBox(height: 8),
                    _VehicleCard(
                      plates: _plates,
                      rfid:  rfid,
                      car:   car,
                      onAddPlate:     _addPlate,
                      onRemovePlate:  _removePlate,
                      onSetDefault:   _setDefaultPlate,
                      onEditCar:   () => _editField('CarModel', 'Car model', car,
                        hint: 'e.g. Perodua Myvi 1.5 AV'),
                      onScanRfid:  () => _scanRfidDialog(),
                    ),

                    const SizedBox(height: 20),

                    // ── Quick booking ─────────────────────────────
                    const _SectionLabel(icon: Icons.bookmark_outline_rounded, label: 'Quick Booking'),
                    const SizedBox(height: 8),
                    _QuickBookCard(
                      slots:       _slots,
                      selectedId:  _selSlot,
                      plate:       _plates.isNotEmpty ? _plates.first : '',
                      booking:     _booking,
                      currentUid:  _user?.uid ?? '',
                      onSlotTap:   (id) {
                        final slot = _slots.firstWhere((s) => s.slotID == id);
                        if (slot.status != SlotStatus.available) return;
                        setState(() => _selSlot = _selSlot == id ? null : id);
                      },
                      onConfirm:   _selSlot == null ? null : () => _reserveSlot(_selSlot!),
                      onCancel:    (id) => _showCancelDialog(id),
                    ),

                    const SizedBox(height: 20),

                    // ── Preferences ───────────────────────────────
                    const _SectionLabel(icon: Icons.settings_outlined, label: 'Settings'),
                    const SizedBox(height: 8),
                    _PrefsCard(
                      notifOn:    _notifOn,
                      locationOn: _locationOn,
                      autoRfid:   _autoRfid,
                      onNotif:    (v) => setState(() => _notifOn    = v),
                      onLocation: (v) => setState(() => _locationOn = v),
                      onAutoRfid: (v) => setState(() => _autoRfid   = v),
                    ),

                    const SizedBox(height: 20),

                    // ── Admin Panel (only for admins) ─────────────
                    if (isAdminUser(_user)) ...[
                      const SizedBox(height: 8),
                      _DangerBtn(
                        label: 'Admin Panel',
                        icon:  Icons.admin_panel_settings_rounded,
                        color: Colors.orange,
                        onTap: () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => const AdminScreen())),
                      ),
                    ],

                    // ── Sign out button ───────────────────────────
                    _DangerBtn(
                      label: 'Sign Out',
                      icon:  Icons.logout_rounded,
                      color: _C.occupied,
                      onTap: _confirmSignOut,
                    ),
                    const SizedBox(height: 28),
                  ]),
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  // ── Hero ──────────────────────────────────────────────────────────────
  Widget _buildHero(String name, String email,
      int total, int active, int completed) {
    final initials = _initials(name);
    final photo    = _user?.photoURL;
    final photoB64 = (_profile['PhotoBase64'] ?? '').toString();
    final since    = _memberSince(_user?.metadata.creationTime);

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFFEAF2FD), Color(0xFFDCEAFB)],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Title row
        const Text('My Profile',
            style: TextStyle(color: _C.text, fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 18),

        // Avatar row
        Row(children: [
          GestureDetector(
            onTap: _pickPhoto,
            child: Stack(children: [
              Container(
                width: 70, height: 70,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [_C.blue, _C.blueDark],
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                  ),
                  border: Border.all(color: _C.blue.withValues(alpha: .5), width: 2.5),
                ),
                child: photoB64.isNotEmpty
                    // Uploaded photo (stored as base64 in Firestore).
                    ? ClipOval(child: Image.memory(base64Decode(photoB64),
                        width: 70, height: 70, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Center(
                          child: Text(initials, style: const TextStyle(
                            color: _C.white, fontSize: 24, fontWeight: FontWeight.w800)))))
                    : (photo != null && photo.isNotEmpty
                        ? ClipOval(child: Image.network(photo, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Center(
                              child: Text(initials, style: const TextStyle(
                                color: _C.white, fontSize: 24, fontWeight: FontWeight.w800)))))
                        : Center(child: Text(initials, style: const TextStyle(
                            color: _C.white, fontSize: 24, fontWeight: FontWeight.w800)))),
              ),
              Positioned(
                bottom: 0, right: 0,
                child: Container(
                  width: 22, height: 22,
                  decoration: BoxDecoration(
                    color: _C.blue, shape: BoxShape.circle,
                    border: Border.all(color: _C.bg, width: 2),
                  ),
                  child: const Icon(Icons.camera_alt_rounded, color: _C.white, size: 11),
                ),
              ),
            ]),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: const TextStyle(color: _C.text, fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 3),
            Text(email, style: const TextStyle(color: _C.textSec, fontSize: 11),
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 7),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _C.blue.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _C.blue.withValues(alpha: .3)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.calendar_today_outlined, color: _C.blue, size: 11),
                const SizedBox(width: 5),
                Text('Member since $since',
                    style: const TextStyle(color: _C.blue, fontSize: 10, fontWeight: FontWeight.w600)),
              ]),
            ),
          ])),
        ]),

        const SizedBox(height: 18),

        // Stat strip
        Row(children: [
          Expanded(child: _StatBox(count: '$total',     label: 'Total\nBookings',  color: _C.blue)),
          const SizedBox(width: 8),
          Expanded(child: _StatBox(count: '$active',    label: 'Active\nNow',      color: _C.available)),
          const SizedBox(width: 8),
          Expanded(child: _StatBox(count: '$completed', label: 'Completed',        color: _C.reserved)),
        ]),
      ]),
    );
  }

  // ── Dialogs & sheets ──────────────────────────────────────────────────

  void _editField(String key, String label, String current,
      {String hint = '', bool caps = false}) {
    final ctrl = TextEditingController(text: current);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: _EditSheet(
          label: label, hint: hint,
          controller: ctrl, caps: caps,
          onSave: () {
            final val = ctrl.text.trim();
            if (val.isEmpty) return;
            Navigator.pop(context);
            _saveProfile({key: val});
            _toast('$label updated!');
          },
        ),
      ),
    );
  }

  void _scanRfidDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,        // allow the sheet to grow / scroll
      backgroundColor: Colors.transparent,
      builder: (_) => _RfidSheet(
        current: _profile['RFIDTag'] ?? '',
        onSave: (tag) {
          Navigator.pop(context);
          final oldTag = (_profile['RFIDTag'] ?? '').toString();
          _saveProfile({'RFIDTag': tag});
          // Mirror into the RTDB registry so the gate recognises this card.
          if (_user != null) {
            ParkingService.instance.registerRfidCard(
              cardUid: tag.trim().toUpperCase(),
              userId: _user!.uid,
              oldCardUid: oldTag.trim().toUpperCase(),
              displayName: _user?.displayName
                  ?? (_profile['Display Name'] ?? '').toString(),
            );
          }
          _toast('RFID tag saved!');
        },
      ),
    );
  }

  void _showCancelDialog(String slotId) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _C.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Cancel Reservation?',
            style: TextStyle(color: _C.text, fontWeight: FontWeight.w700)),
        content: Text('Release slot $slotId?',
            style: const TextStyle(color: _C.textSec, fontSize: 13)),
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
                  child: const Text('Keep', style: TextStyle(color: _C.textHint)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _C.occupied,
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () { Navigator.pop(context); _cancelSlot(slotId); },
                  child: const Text('Cancel Booking',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: _C.text, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _confirmSignOut() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _C.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Sign Out?',
            style: TextStyle(color: _C.text, fontWeight: FontWeight.w700)),
        content: const Text('You will be returned to the login screen.',
            style: TextStyle(color: _C.textSec, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: _C.textHint))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _C.blue,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              minimumSize: const Size(0, 38),
            ),
            onPressed: () async {
              Navigator.pop(context);
              await _auth.signOut();
            },
            child: const Text('Sign Out',
                style: TextStyle(color: _C.text, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Future<void> _pickPhoto() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 300, maxHeight: 300, imageQuality: 45,  // keep it small
      );
      if (picked == null) return;                      // user cancelled
      final bytes = await picked.readAsBytes();
      // Firestore doc limit is ~1MB; a 300px/45% JPEG is well under this.
      if (bytes.lengthInBytes > 900000) {
        _toast('That image is too large — please pick a smaller one.', isError: true);
        return;
      }
      final b64 = base64Encode(bytes);
      _saveProfile({'PhotoBase64': b64});              // saves + updates UI
      _toast('Profile photo updated!');
    } catch (e) {
      _toast('Could not pick photo: $e', isError: true);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────
  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.substring(0, name.length.clamp(1, 2)).toUpperCase();
  }

  String _memberSince(DateTime? dt) {
    if (dt == null) return '—';
    const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${m[dt.month - 1]} ${dt.year}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// REUSABLE WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

// ── Stat box ──────────────────────────────────────────────────────────────
class _StatBox extends StatelessWidget {
  final String count, label; final Color color;
  const _StatBox({required this.count, required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color.withValues(alpha: .2)),
    ),
    child: Column(children: [
      Text(count, style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.w800)),
      const SizedBox(height: 3),
      Text(label, textAlign: TextAlign.center,
          style: const TextStyle(color: _C.textHint, fontSize: 9, fontWeight: FontWeight.w500, height: 1.3)),
    ]),
  );
}

// ── Section label ─────────────────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final IconData icon; final String label;
  const _SectionLabel({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(icon, color: _C.blue, size: 14),
    const SizedBox(width: 6),
    Text(label.toUpperCase(),
        style: const TextStyle(color: _C.textHint, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: .7)),
  ]);
}

// ── Info card ─────────────────────────────────────────────────────────────
class _InfoCard extends StatelessWidget {
  final List<_InfoRow> items;
  const _InfoCard({required this.items});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: _C.bgCard,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: _C.border),
    ),
    child: Column(children: items),
  );
}

class _InfoRow extends StatelessWidget {
  final IconData icon; final String label, value;
  final Color? valueColor; final VoidCallback? onTap;
  const _InfoRow({required this.icon, required this.label, required this.value,
    this.valueColor, this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(14),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: _C.divider, width: .5))),
      child: Row(children: [
        Container(
          width: 34, height: 34,
          decoration: BoxDecoration(
            color: _C.blue.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, color: _C.blue, size: 17),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: _C.textHint, fontSize: 10, fontWeight: FontWeight.w500)),
          const SizedBox(height: 3),
          Text(value,
              style: TextStyle(color: valueColor ?? _C.text, fontSize: 13, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis),
        ])),
        if (onTap != null)
          const Icon(Icons.chevron_right_rounded, color: _C.textHint, size: 18),
      ]),
    ),
  );
}

// ── Vehicle & RFID card ────────────────────────────────────────────────────
class _VehicleCard extends StatelessWidget {
  final List<String> plates;
  final String rfid, car;
  final VoidCallback onAddPlate, onEditCar, onScanRfid;
  final void Function(String plate) onRemovePlate, onSetDefault;

  const _VehicleCard({
    required this.plates, required this.rfid, required this.car,
    required this.onAddPlate, required this.onRemovePlate, required this.onSetDefault,
    required this.onEditCar, required this.onScanRfid,
  });

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: _C.bgCard,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: _C.blue.withValues(alpha: .35)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Header
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: _C.blue.withValues(alpha: .08),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
          border: const Border(bottom: BorderSide(color: Color(0x331E90FF), width: .5)),
        ),
        child: Row(children: [
          const Icon(Icons.directions_car_outlined, color: _C.blue, size: 17),
          const SizedBox(width: 8),
          const Text('My Vehicle',
              style: TextStyle(color: _C.blue, fontSize: 13, fontWeight: FontWeight.w700)),
          const Spacer(),
          GestureDetector(
            onTap: onEditCar,
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.edit_outlined, color: _C.blue, size: 14),
              SizedBox(width: 4),
              Text('Edit', style: TextStyle(color: _C.blue, fontSize: 11, fontWeight: FontWeight.w600)),
            ]),
          ),
        ]),
      ),

      // Car plates (multiple; the first is the default for booking)
      _VField(
        icon: Icons.credit_card_rounded, iconColor: _C.reserved,
        label: 'Car plates (default is used for booking)',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (plates.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Text('No plates yet — add one below.',
                  style: TextStyle(color: _C.textHint, fontSize: 12)),
            ),
          ...plates.asMap().entries.map((e) {
            final isDefault = e.key == 0;
            final p = e.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Expanded(child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _C.bgInput,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isDefault ? _C.blue.withValues(alpha: .6) : _C.border,
                      width: isDefault ? 1.5 : 1,
                    ),
                  ),
                  child: Row(children: [
                    Text(p, style: const TextStyle(
                      color: _C.blue, fontSize: 15, fontWeight: FontWeight.w800,
                      letterSpacing: 2, fontFamily: 'monospace')),
                    if (isDefault) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: _C.blue.withValues(alpha: .15),
                          borderRadius: BorderRadius.circular(20)),
                        child: const Text('DEFAULT',
                            style: TextStyle(color: _C.blue, fontSize: 8, fontWeight: FontWeight.w800)),
                      ),
                    ],
                  ]),
                )),
                // Make default
                if (!isDefault)
                  IconButton(
                    icon: const Icon(Icons.star_outline_rounded, color: _C.textHint, size: 18),
                    tooltip: 'Set as default',
                    onPressed: () => onSetDefault(p),
                  ),
                // Remove
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: _C.occupied, size: 18),
                  tooltip: 'Remove',
                  onPressed: () => onRemovePlate(p),
                ),
              ]),
            );
          }),
          GestureDetector(
            onTap: onAddPlate,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(
                color: _C.blue.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _C.blue.withValues(alpha: .3)),
              ),
              child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.add_rounded, color: _C.blue, size: 16),
                SizedBox(width: 6),
                Text('Add car plate',
                    style: TextStyle(color: _C.blue, fontSize: 12, fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        ]),
      ),

      // RFID tag
      _VField(
        icon: Icons.wifi_rounded, iconColor: _C.available,
        label: 'RFID tag',
        child: Row(children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: _C.bgInput,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: rfid.isNotEmpty ? _C.available.withValues(alpha: .5) : _C.border,
                ),
              ),
              child: Row(children: [
                Icon(
                  rfid.isNotEmpty ? Icons.check_circle_outline_rounded : Icons.radio_button_unchecked_rounded,
                  color: rfid.isNotEmpty ? _C.available : _C.textHint, size: 14),
                const SizedBox(width: 7),
                Expanded(child: Text(
                  rfid.isNotEmpty ? rfid : 'No RFID linked',
                  style: TextStyle(
                    color: rfid.isNotEmpty ? _C.available : _C.textHint,
                    fontSize: 12, fontWeight: FontWeight.w600, fontFamily: 'monospace'),
                  overflow: TextOverflow.ellipsis,
                )),
              ]),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onScanRfid,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: _C.available.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _C.available.withValues(alpha: .3)),
              ),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.qr_code_scanner_rounded, color: _C.available, size: 16),
                SizedBox(width: 5),
                Text('Scan', style: TextStyle(color: _C.available, fontSize: 11, fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        ]),
      ),

      // Car model
      _VField(
        icon: Icons.directions_car_filled_rounded, iconColor: _C.blue,
        label: 'Car model',
        isLast: true,
        child: GestureDetector(
          onTap: onEditCar,
          child: Text(
            car.isNotEmpty ? car : 'Tap to add car model',
            style: TextStyle(
              color: car.isNotEmpty ? _C.text : _C.textHint,
              fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    ]),
  );
}

class _VField extends StatelessWidget {
  final IconData icon; final Color iconColor;
  final String label; final Widget child; final bool isLast;
  const _VField({required this.icon, required this.iconColor,
    required this.label, required this.child, this.isLast = false});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
    decoration: BoxDecoration(
      border: isLast ? null : const Border(bottom: BorderSide(color: _C.divider, width: .5)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(icon, color: iconColor, size: 13),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(color: _C.textHint, fontSize: 10, fontWeight: FontWeight.w600)),
      ]),
      const SizedBox(height: 8),
      child,
    ]),
  );
}

// ── Quick Booking card ─────────────────────────────────────────────────────
class _QuickBookCard extends StatelessWidget {
  final List<ParkingSlot> slots;
  final String?           selectedId;
  final String            plate;
  final bool              booking;
  final String            currentUid;
  final ValueChanged<String> onSlotTap;
  final VoidCallback?     onConfirm;
  final ValueChanged<String> onCancel;

  const _QuickBookCard({
    required this.slots, required this.selectedId, required this.plate,
    required this.booking, required this.currentUid, required this.onSlotTap,
    required this.onConfirm, required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final myActive = slots.where(
      (s) => s.status == SlotStatus.reserved && s.userID == currentUid);

    return Container(
      decoration: BoxDecoration(
        color: _C.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _C.blue.withValues(alpha: .3)),
      ),
      child: Column(children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: _C.blue.withValues(alpha: .08),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
            border: const Border(bottom: BorderSide(color: Color(0x331E90FF), width: .5)),
          ),
          child: Row(children: [
            const Icon(Icons.location_on_outlined, color: _C.blue, size: 16),
            const SizedBox(width: 8),
            const Text('Lot A — Ground Floor',
                style: TextStyle(color: _C.text, fontSize: 13, fontWeight: FontWeight.w700)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: _C.available.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                _PulseDot(),
                SizedBox(width: 5),
                Text('Live', style: TextStyle(color: _C.available, fontSize: 10, fontWeight: FontWeight.w700)),
              ]),
            ),
          ]),
        ),

        // Active booking warning
        if (myActive.isNotEmpty)
          Container(
            margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: _C.reserved.withValues(alpha: .08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _C.reserved.withValues(alpha: .35)),
            ),
            child: Row(children: [
              const Icon(Icons.schedule_rounded, color: _C.reserved, size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text(
                'Active: ${myActive.first.slotID}  •  Arrive within 15 min',
                style: const TextStyle(color: _C.reserved, fontSize: 11, fontWeight: FontWeight.w600),
              )),
              GestureDetector(
                onTap: () => onCancel(myActive.first.slotID),
                child: const Text('Cancel',
                    style: TextStyle(color: _C.occupied, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
            ]),
          ),

        // Legend
        const Padding(
          padding: EdgeInsets.fromLTRB(14, 12, 14, 6),
          child: Row(children: [
            _Leg(_C.available,  'Available'),
            SizedBox(width: 12),
            _Leg(_C.reserved,  'Reserved'),
            SizedBox(width: 12),
            _Leg(_C.occupied,    'Occupied'),
          ]),
        ),

        // Slot grid
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 1.5),
            itemCount: slots.isEmpty ? 6 : slots.length,
            itemBuilder: (_, i) {
              if (slots.isEmpty) return _SlotTile.placeholder(i + 1);
              final s   = slots[i];
              final sel = selectedId == s.slotID;
              final mine= s.userID == currentUid && s.status == SlotStatus.reserved;
              return _SlotTile(slot: s, selected: sel, isMine: mine,
                  onTap: () => onSlotTap(s.slotID));
            },
          ),
        ),

        // Footer
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: _C.divider, width: .5))),
          child: Column(children: [
            // Plate preview
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _C.bgInput,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Row(children: [
                const Icon(Icons.credit_card_rounded, color: _C.blue, size: 15),
                const SizedBox(width: 8),
                const Text('Booking as ', style: TextStyle(color: _C.textSec, fontSize: 12)),
                Text(
                  plate.isNotEmpty ? plate : 'Add plate first',
                  style: TextStyle(
                    color: plate.isNotEmpty ? _C.text : _C.occupied,
                    fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1),
                ),
                if (selectedId != null) ...[
                  const Text('  ·  ', style: TextStyle(color: _C.textHint, fontSize: 12)),
                  Text('Slot $selectedId',
                      style: const TextStyle(color: _C.blue, fontSize: 12, fontWeight: FontWeight.w700)),
                ],
              ]),
            ),
            const SizedBox(height: 10),

            // Confirm button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onConfirm,
                icon: booking
                    ? const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: _C.white))
                    : const Icon(Icons.bookmark_add_rounded, size: 18),
                label: Text(
                  selectedId != null
                      ? 'Confirm Booking — Slot $selectedId'
                      : 'Select a slot above',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: onConfirm != null ? _C.blue : _C.textHint.withValues(alpha: .3),
                  foregroundColor: _C.white,
                  minimumSize:     const Size(double.infinity, 44),
                  shape:     RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
                  elevation: 0,
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _SlotTile extends StatelessWidget {
  final ParkingSlot? slot;
  final bool selected, isMine;
  final VoidCallback? onTap;
  final int placeholderNum;

  const _SlotTile({this.slot, required this.selected, required this.isMine,
    this.onTap, this.placeholderNum = 0});

  factory _SlotTile.placeholder(int n) =>
      _SlotTile(slot: null, selected: false, isMine: false, placeholderNum: n);

  Color get _col {
    if (slot == null)                          return _C.textHint;
    if (selected)                              return _C.blue;
    if (slot!.status == SlotStatus.available)  return _C.available;
    if (slot!.status == SlotStatus.reserved)   return _C.reserved;
    return _C.occupied;
  }

  String get _label {
    if (slot == null) return 'P$placeholderNum';
    final n = slot!.slotID.replaceAll(RegExp(r'[^0-9]'), '');
    return 'P$n';
  }

  String get _status {
    if (slot == null)                          return '—';
    if (selected)                              return 'Selected';
    if (slot!.status == SlotStatus.available)  return 'Open';
    if (slot!.status == SlotStatus.reserved)   return 'Reserved';
    return 'Occupied';
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: _col.withValues(alpha: selected ? .2 : .08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _col.withValues(alpha: selected ? 1 : .35),
          width: selected ? 2 : 1.2,
        ),
      ),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(_label,
            style: TextStyle(color: _col, fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(_status,
            style: TextStyle(color: _col, fontSize: 8, fontWeight: FontWeight.w600, letterSpacing: .4)),
        if (isMine)
          Container(
            margin: const EdgeInsets.only(top: 3),
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: _C.blue.withValues(alpha: .2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text('YOURS',
                style: TextStyle(color: _C.blue, fontSize: 7, fontWeight: FontWeight.w800)),
          ),
      ]),
    ),
  );
}

class _Leg extends StatelessWidget {
  final Color color; final String label;
  const _Leg(this.color, this.label);
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 8, height: 8,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
    const SizedBox(width: 4),
    Text(label, style: const TextStyle(color: _C.textHint, fontSize: 9, fontWeight: FontWeight.w500)),
  ]);
}

class _PulseDot extends StatefulWidget {
  const _PulseDot();
  @override State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _anim;
  @override void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }
  @override void dispose() { _ctrl.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => FadeTransition(
    opacity: _anim,
    child: Container(width: 6, height: 6,
        decoration: const BoxDecoration(color: _C.available, shape: BoxShape.circle)),
  );
}

// ── Preferences card ──────────────────────────────────────────────────────
class _PrefsCard extends StatelessWidget {
  final bool notifOn, locationOn, autoRfid;
  final ValueChanged<bool> onNotif, onLocation, onAutoRfid;
  const _PrefsCard({required this.notifOn, required this.locationOn,
    required this.autoRfid, required this.onNotif, required this.onLocation,
    required this.onAutoRfid});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: _C.bgCard, borderRadius: BorderRadius.circular(14),
      border: Border.all(color: _C.border)),
    child: Column(children: [
      _ToggleRow(icon: Icons.notifications_outlined, iconColor: _C.blue,
        label: 'Push notifications', sub: 'Booking alerts & reminders',
        value: notifOn, onChanged: onNotif),
      _ToggleRow(icon: Icons.location_on_outlined, iconColor: _C.available,
        label: 'Location access', sub: 'Find nearby parking lots',
        value: locationOn, onChanged: onLocation),
      _ToggleRow(icon: Icons.wifi_rounded, iconColor: _C.reserved,
        label: 'Auto RFID scan', sub: 'Scan on app launch',
        value: autoRfid, onChanged: onAutoRfid, isLast: true),
    ]),
  );
}

class _ToggleRow extends StatelessWidget {
  final IconData icon; final Color iconColor;
  final String label, sub;
  final bool value, isLast;
  final ValueChanged<bool> onChanged;
  const _ToggleRow({required this.icon, required this.iconColor,
    required this.label, required this.sub, required this.value,
    required this.onChanged, this.isLast = false});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    decoration: BoxDecoration(
      border: isLast ? null : const Border(bottom: BorderSide(color: _C.divider, width: .5))),
    child: Row(children: [
      Container(width: 34, height: 34,
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: .1), borderRadius: BorderRadius.circular(9)),
        child: Icon(icon, color: iconColor, size: 17)),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(color: _C.text, fontSize: 13, fontWeight: FontWeight.w500)),
        const SizedBox(height: 2),
        Text(sub, style: const TextStyle(color: _C.textHint, fontSize: 10)),
      ])),
      Switch(
        value: value, onChanged: onChanged,
        activeThumbColor: _C.blue,
        activeTrackColor: _C.blue.withValues(alpha: .3),
        inactiveThumbColor: _C.textHint,
        inactiveTrackColor: _C.bgInput,
      ),
    ]),
  );
}

// ── Danger button ─────────────────────────────────────────────────────────
class _DangerBtn extends StatelessWidget {
  final String label; final IconData icon; final Color color;
  final VoidCallback onTap;
  const _DangerBtn({required this.label, required this.icon,
    required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: color.withValues(alpha: .35)),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 9),
        Text(label, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w700)),
      ]),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// EDIT FIELD SHEET
// ─────────────────────────────────────────────────────────────────────────────
class _EditSheet extends StatelessWidget {
  final String label, hint;
  final TextEditingController controller;
  final bool caps;
  final VoidCallback onSave;
  const _EditSheet({required this.label, required this.hint,
    required this.controller, required this.caps, required this.onSave});

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: _C.bgCard, borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
    padding: const EdgeInsets.fromLTRB(22, 12, 22, 30),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 40, height: 4,
        decoration: BoxDecoration(color: _C.border, borderRadius: BorderRadius.circular(2))),
      const SizedBox(height: 18),
      Text('Edit $label',
          style: const TextStyle(color: _C.text, fontSize: 17, fontWeight: FontWeight.w700)),
      const SizedBox(height: 18),
      TextFormField(
        controller: controller,
        autofocus: true,
        textCapitalization: caps ? TextCapitalization.characters : TextCapitalization.words,
        inputFormatters: caps ? [
          FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9 ]')),
          _UpperCase(),
        ] : [],
        style: const TextStyle(color: _C.text, fontSize: 15),
        decoration: InputDecoration(
          hintText: hint, labelText: label,
          filled: true, fillColor: _C.bgInput,
          border:        OutlineInputBorder(borderRadius: BorderRadius.circular(13), borderSide: const BorderSide(color: _C.border)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(13), borderSide: const BorderSide(color: _C.border)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(13), borderSide: const BorderSide(color: _C.blue, width: 1.8)),
        ),
      ),
      const SizedBox(height: 16),
      SizedBox(width: double.infinity,
        child: ElevatedButton(
          onPressed: onSave,
          style: ElevatedButton.styleFrom(
            backgroundColor: _C.blue, foregroundColor: _C.white,
            minimumSize: const Size(double.infinity, 50),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
            elevation: 0,
          ),
          child: const Text('Save', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        ),
      ),
    ]),
  );
}

class _UpperCase extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue o, TextEditingValue n) =>
      n.copyWith(text: n.text.toUpperCase());
}

// ─────────────────────────────────────────────────────────────────────────────
// RFID SCAN SHEET
// ─────────────────────────────────────────────────────────────────────────────
class _RfidSheet extends StatefulWidget {
  final String current;
  final ValueChanged<String> onSave;
  const _RfidSheet({required this.current, required this.onSave});
  @override State<_RfidSheet> createState() => _RfidSheetState();
}

class _RfidSheetState extends State<_RfidSheet> {
  late TextEditingController _ctrl;
  String _lastTapped = '';
  StreamSubscription? _gateSub;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.current);
    // Listen for the last card tapped on the gate reader (written by the ESP32
    // to Gate/LastScan). So the user just taps their card and it shows up here.
    _gateSub = FirebaseDatabase.instance.ref('Gate/LastScan/UID').onValue.listen((e) {
      final uid = (e.snapshot.value ?? '').toString().trim().toUpperCase();
      if (uid.isNotEmpty && mounted) setState(() => _lastTapped = uid);
    });
  }

  @override
  void dispose() { _gateSub?.cancel(); _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: _C.bgCard, borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
    // Keyboard-aware padding + scrollable so it never overflows.
    padding: EdgeInsets.only(
      left: 22, right: 22, top: 12,
      bottom: 24 + MediaQuery.of(context).viewInsets.bottom,
    ),
    child: SingleChildScrollView(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 40, height: 4,
        decoration: BoxDecoration(color: _C.border, borderRadius: BorderRadius.circular(2))),
      const SizedBox(height: 18),
      const Text('RFID Tag',
          style: TextStyle(color: _C.text, fontSize: 17, fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      const Text('Tap your card on the gate reader — the last card tapped '
          'appears below. Then press “Use this card”.',
          style: TextStyle(color: _C.textSec, fontSize: 12)),
      const SizedBox(height: 20),

      // Live last-tapped card from the gate reader (Gate/LastScan)
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
        decoration: BoxDecoration(
          color: _C.available.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _C.available.withValues(alpha: .35)),
        ),
        child: Column(children: [
          const Icon(Icons.nfc_rounded, color: _C.available, size: 38),
          const SizedBox(height: 10),
          if (_lastTapped.isEmpty) ...[
            const Text('Waiting for a card tap…',
                style: TextStyle(color: _C.textSec, fontSize: 13, fontWeight: FontWeight.w600)),
          ] else ...[
            const Text('Last tapped card',
                style: TextStyle(color: _C.textSec, fontSize: 11)),
            const SizedBox(height: 4),
            Text(_lastTapped,
                style: const TextStyle(color: _C.available, fontSize: 20,
                    fontWeight: FontWeight.w800, fontFamily: 'monospace', letterSpacing: 2)),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: () => setState(() => _ctrl.text = _lastTapped),
              icon: const Icon(Icons.check_rounded, size: 16),
              label: const Text('Use this card'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _C.available, foregroundColor: _C.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ]),
      ),
      const SizedBox(height: 14),
      const Row(children: [
        Expanded(child: Divider(color: _C.divider)),
        Padding(padding: EdgeInsets.symmetric(horizontal: 12),
          child: Text('or enter manually', style: TextStyle(color: _C.textHint, fontSize: 11))),
        Expanded(child: Divider(color: _C.divider)),
      ]),
      const SizedBox(height: 14),

      TextFormField(
        controller: _ctrl,
        style: const TextStyle(color: _C.available, fontSize: 14,
            fontWeight: FontWeight.w600, fontFamily: 'monospace'),
        decoration: InputDecoration(
          hintText: 'e.g. 04A1B2C3',
          prefixIcon: const Icon(Icons.wifi_rounded, color: _C.available, size: 20),
          filled: true, fillColor: _C.bgInput,
          border:        OutlineInputBorder(borderRadius: BorderRadius.circular(13), borderSide: const BorderSide(color: _C.border)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(13), borderSide: const BorderSide(color: _C.border)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(13), borderSide: const BorderSide(color: _C.available, width: 1.8)),
        ),
      ),
      const SizedBox(height: 16),
      SizedBox(width: double.infinity,
        child: ElevatedButton(
          onPressed: () {
            final tag = _ctrl.text.trim();
            if (tag.isEmpty) return;
            widget.onSave(tag);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: _C.blue, foregroundColor: _C.white,
            minimumSize: const Size(double.infinity, 50),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
            elevation: 0,
          ),
          child: const Text('Save RFID Tag',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        ),
      ),
    ]),
    ),
  );
}
