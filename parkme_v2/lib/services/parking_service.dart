import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import '../models/parkingSlot.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ParkingService
// All reads and writes to Firebase Realtime Database live here.
// ─────────────────────────────────────────────────────────────────────────────

class ParkingService {
  ParkingService._();
  static final ParkingService instance = ParkingService._();

  final DatabaseReference _root = FirebaseDatabase.instance.ref('ParkingSlot');
  final DatabaseReference _gate = FirebaseDatabase.instance.ref('Gate/LastScan');
  // Private per-user booking details (plate number, booking ID). Lives OUTSIDE
  // ParkingSlot so security rules can lock each entry to its owner — other
  // users (and the public slot grid) never see another driver's plate/booking.
  final DatabaseReference _bookings = FirebaseDatabase.instance.ref('Bookings');
  // Registry of physical RFID cards -> owning user, so the gate can tell a
  // registered driver (walk-in allowed) from an unknown card (register first).
  final DatabaseReference _cards = FirebaseDatabase.instance.ref('RegisteredCards');

  // Human-readable navigation labels per slot (must match the ESP32 firmware).
  static const Map<String, String> slotLabels = {
    'slot 1': 'Basement 1, A1',
    'slot 2': 'Basement 1, A2',
    'slot 3': 'Basement 1, A3',
  };

  // ── Real-time stream of sorted slots ────────────────────────────────────
  Stream<List<ParkingSlot>> get slotsStream {
    return _root.onValue.map((event) {
      if (!event.snapshot.exists) return <ParkingSlot>[];
      final raw = Map<String, dynamic>.from(event.snapshot.value as Map);
      final list = raw.entries
          .map((e) => ParkingSlot.fromMap(e.key, Map.from(e.value as Map)))
          .toList()
        ..sort((a, b) => a.slotID.compareTo(b.slotID));
      return list;
    });
  }

  // ── One-time fetch ───────────────────────────────────────────────────────
  Future<List<ParkingSlot>> fetchSlots() async {
    final snap = await _root.get();
    if (!snap.exists) return [];
    final raw = Map<String, dynamic>.from(snap.value as Map);
    return raw.entries
        .map((e) => ParkingSlot.fromMap(e.key, Map.from(e.value as Map)))
        .toList()
      ..sort((a, b) => a.slotID.compareTo(b.slotID));
  }

  // ── Seed 3 empty slots (run once) ───────────────────────────────────────
  // 3 slots = the 3 physical bays wired to the ESP32.
  Future<void> seedSlots({int count = 3}) async {
    final snap = await _root.get();
    if (snap.exists) return; // already seeded
    final Map<String, dynamic> init = {};
    for (int i = 1; i <= count; i++) {
      final id = 'slot $i';
      init[id] = {
        'Status':          'Available',
        'Label':           slotLabels[id] ?? 'Level 1, A$i',
        'RFIDTag':         '',
        'ReservationTime': '',
        'BookingID':       '',
        'PlateNum':        '',
        'SlotID':          id,
        'UserID':          '',
        'ReservedAtMs':    0,   // set on reserve; ESP32 uses it for expiry
        'ArrivedAtMs':     0,   // set by the ESP32 when the driver scans in
      };
    }
    await _root.set(init);
  }

  // ── Reserve (atomic transaction) ────────────────────────────────────────
  // [rfidTag] must be the user's PHYSICAL card UID (e.g. "04A1B2C3") so the
  // ESP32 gate can match the scanned card to this booking. It comes from the
  // user's profile (Vehicle & RFID section). Empty tag = no card registered;
  // the booking still works, but the gate can't auto-navigate them.
  Future<bool> reserve({
    required String slotId,
    required String userId,
    required String plateNum,
    String rfidTag = '',
  }) async {
    final now       = DateTime.now();
    final bookingID = 'BK${now.millisecondsSinceEpoch.toString().substring(7)}';

    // 1) Claim the slot atomically. Note: PlateNum/BookingID are NOT written
    //    here — they are private and go to Bookings/<uid> below.
    final ref = _root.child(slotId);
    final result = await ref.runTransaction((current) {
      if (current == null) return Transaction.abort();
      final data = Map<String, dynamic>.from(current as Map);
      if (data['Status'] != 'Available') return Transaction.abort();

      data['Status']          = 'Reserved';
      data['UserID']          = userId;
      data['RFIDTag']         = rfidTag;
      data['ReservationTime'] = now.toIso8601String();
      data['ReservedAtMs']    = now.millisecondsSinceEpoch; // for ESP32 expiry
      data['PlateNum']        = '';   // keep cleared in the public node
      data['BookingID']       = '';
      return Transaction.success(data);
    });

    // 2) Store the private details under the owner's uid (rule-protected).
    if (result.committed) {
      await _bookings.child(userId).set({
        'SlotID':          slotId,
        'PlateNum':        plateNum,
        'BookingID':       bookingID,
        'ReservationTime': now.toIso8601String(),
      });
    }
    return result.committed;
  }

  // ── My booking details (private: plate number + booking ID) ──────────────
  // Live stream of the signed-in user's own booking record. Only the owner can
  // read this path under the security rules.
  Stream<Map<String, dynamic>?> myBookingStream(String userId) {
    return _bookings.child(userId).onValue.map((e) {
      if (!e.snapshot.exists) return null;
      return Map<String, dynamic>.from(e.snapshot.value as Map);
    });
  }

  Future<Map<String, dynamic>?> getMyBooking(String userId) async {
    final snap = await _bookings.child(userId).get();
    if (!snap.exists) return null;
    return Map<String, dynamic>.from(snap.value as Map);
  }

  // Remove the user's own private booking record (call on cancel).
  Future<void> removeMyBooking(String userId) async {
    await _bookings.child(userId).remove();
  }

  // ── Gate scan stream (written by the ESP32 on each RFID tap) ─────────────
  Stream<GateScan?> get gateScanStream {
    return _gate.onValue.map((event) {
      if (!event.snapshot.exists) return null;
      return GateScan.fromMap(Map.from(event.snapshot.value as Map));
    });
  }

  // ── Register / update the user's physical RFID card ──────────────────────
  // Mirrors the card UID saved in the profile into
  //   RegisteredCards/<cardUid> = { UserID, Name }
  // so the ESP32 gate can greet the driver by name on a scan. Only the FIRST
  // name is stored: RegisteredCards is readable by every signed-in user (see
  // database.rules.json), so a full name here would expose who owns which card.
  // Pass [oldCardUid] when changing cards so the stale entry is removed.
  Future<void> registerRfidCard({
    required String cardUid,
    required String userId,
    String oldCardUid = '',
    String displayName = '',
  }) async {
    if (oldCardUid.isNotEmpty && oldCardUid != cardUid) {
      await _cards.child(oldCardUid).remove();
    }
    if (cardUid.isNotEmpty) {
      final firstName = displayName.trim().split(' ').first;
      await _cards.child(cardUid).set({
        'UserID': userId,
        'Name'  : firstName,
      });
    }
  }

  // ── Gate: find the active reservation for a scanned RFID card ────────────
  // Given the card UID read at the gate, returns the slot the card is booked
  // into (Reserved or already Occupied). Returns null if that card has no
  // active reservation — i.e. the gate should stay closed / deny entry.
  Future<ParkingSlot?> findReservationByRfid(String scannedUid) async {
    if (scannedUid.isEmpty) return null;
    final snap = await _root.get();
    if (!snap.exists) return null;
    final raw = Map<String, dynamic>.from(snap.value as Map);
    for (final e in raw.entries) {
      final slot = ParkingSlot.fromMap(e.key, Map.from(e.value as Map));
      if (slot.rfidTag == scannedUid && (slot.isReserved || slot.isOccupied)) {
        return slot;
      }
    }
    return null;
  }

  // ── Gate: publish a scan result to Gate/LastScan ─────────────────────────
  // Normally the ESP32 writes this node directly. This mirror lets the app (or
  // an admin "simulate scan" button) drive the same flow for testing without
  // hardware. The Flutter app listens via [gateScanStream].
  Future<void> publishGateScan({
    required String uid,
    required String userId,
    required String slotId,
    required String label,
    required String action,   // "navigate" | "denied" | "entry"
    required String message,
  }) async {
    await _gate.set({
      'UID':       uid,
      'UserID':    userId,
      'SlotID':    slotId,
      'Label':     label,
      'Action':    action,
      'Message':   message,
      'Timestamp': ServerValue.timestamp,
    });
  }

  // ── Cancel / free a slot ────────────────────────────────────────────────
  Future<void> freeSlot(String slotId) async {
    await _root.child(slotId).update({
      'Status':          'Available',
      'RFIDTag':         '',
      'ReservationTime': '',
      'ReservedAtMs':    0,
      'BookingID':       '',
      'PlateNum':        '',
      'UserID':          '',
    });
  }

  // ── Admin: force-set slot status ────────────────────────────────────────
  Future<void> adminSetStatus(String slotId, String status) async {
    if (status == 'Available') {
      await freeSlot(slotId);
    } else {
      await _root.child(slotId).update({'Status': status});
    }
  }

  // ── Admin: add a new slot ────────────────────────────────────────────────
  Future<void> adminAddSlot(String slotId) async {
    await _root.child(slotId).set({
      'Status':          'Available',
      'RFIDTag':         '',
      'ReservationTime': '',
      'BookingID':       '',
      'PlateNum':        '',
      'SlotID':          slotId,
      'UserID':          '',
    });
  }

  // ── Admin: delete a slot ─────────────────────────────────────────────────
  Future<void> adminDeleteSlot(String slotId) async {
    await _root.child(slotId).remove();
  }

  // ── Admin: clear ALL reservations ────────────────────────────────────────
  // Frees every slot and removes each owner's private booking record.
  //
  // NOTE: we delete Bookings/<uid> per child, NOT the whole /Bookings node.
  // The security rules only grant write at Bookings/$uid, so a bulk
  // _bookings.remove() on the parent path is denied and throws. The owner uids
  // come from each slot's UserID field.
  Future<void> adminClearAll() async {
    final snap = await _root.get();
    if (!snap.exists) return;
    final raw = Map<String, dynamic>.from(snap.value as Map);
    for (final entry in raw.entries) {
      final slot = Map<String, dynamic>.from(entry.value as Map);
      final uid  = (slot['UserID'] ?? '').toString();
      await freeSlot(entry.key);
      if (uid.isNotEmpty) {
        // Best-effort: don't let one stale booking record abort the whole sweep.
        try { await _bookings.child(uid).remove(); } catch (_) {}
      }
    }
  }

  // ── Auto-cancel expired reservations (call periodically) ────────────────
  Future<void> expireStaleReservations({int windowMinutes = 15}) async {
    final snap = await _root.get();
    if (!snap.exists) return;
    final raw = Map<String, dynamic>.from(snap.value as Map);
    for (final entry in raw.entries) {
      final slot = Map<String, dynamic>.from(entry.value as Map);
      if (slot['Status'] != 'Reserved') continue;
      final rawTime = slot['ReservationTime']?.toString() ?? '';
      if (rawTime.isEmpty) continue;
      final reserved = DateTime.tryParse(rawTime);
      if (reserved == null) continue;
      if (DateTime.now().difference(reserved).inMinutes >= windowMinutes) {
        await freeSlot(entry.key);
      }
    }
  }
}
