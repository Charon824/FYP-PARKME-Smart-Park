// ─────────────────────────────────────────────────────────────────────────────
// ParkingSlot model
// Mirrors the Firebase Realtime Database node:
//   ParkingSlot / "slot 1" / { Status, RFIDTag, ReservationTime, ... }
// ─────────────────────────────────────────────────────────────────────────────

enum SlotStatus {available, reserved, occupied, cancelled}

class ParkingSlot {
  final String slotID;
  final SlotStatus status;
  final String rfidTag;
  final String reservationTime;
  final String bookingID;
  final String plateNum;
  final String userID;

  const ParkingSlot({
    required this.slotID,
    required this.status,
    this.rfidTag        = '',
    this.reservationTime = '',
    this.bookingID      = '',
    this.plateNum       = '',
    this.userID         = '',
  });

  factory ParkingSlot.fromMap(String id, Map<dynamic, dynamic> map) {
    final raw = (map['Status'] ?? 'Available').toString();
    SlotStatus st;
    switch (raw.toLowerCase()) {
      case 'reserved':  st = SlotStatus.reserved;  break;
      case 'occupied':  st = SlotStatus.occupied;   break;
      case 'cancelled': st = SlotStatus.cancelled;  break;
      default:          st = SlotStatus.available;
    }
    return ParkingSlot(
      slotID:           id,
      status:           st,
      rfidTag:          (map['RFIDTag']          ?? '').toString(),
      reservationTime:  (map['ReservationTime']  ?? '').toString(),
      bookingID:        (map['BookingID']        ?? '').toString(),
      plateNum:         (map['PlateNum']         ?? '').toString(),
      userID:           (map['UserID']           ?? '').toString(),
    );
  }

  bool get isAvailable  => status == SlotStatus.available;
  bool get isReserved   => status == SlotStatus.reserved;
  bool get isOccupied   => status == SlotStatus.occupied;

  String get statusLabel {
    switch (status) {
      case SlotStatus.available:  return 'Available';
      case SlotStatus.reserved:   return 'Reserved';
      case SlotStatus.occupied:   return 'Occupied';
      case SlotStatus.cancelled:  return 'Cancelled';
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GateScan
// Mirrors Firebase node Gate/LastScan, written by the ESP32 on each RFID tap:
//   { UID, UserID, SlotID, Label, Action, Message, Timestamp }
//   Action: "navigate" (booked card -> go to slot) | "entry" (free entry)
// ─────────────────────────────────────────────────────────────────────────────
class GateScan {
  final String uid;
  final String userID;
  final String slotID;
  final String label;
  final String action;
  final String message;
  final int    timestamp;

  const GateScan({
    required this.uid,
    required this.userID,
    required this.slotID,
    required this.label,
    required this.action,
    required this.message,
    required this.timestamp,
  });

  factory GateScan.fromMap(Map<dynamic, dynamic> map) {
    return GateScan(
      uid:       (map['UID']     ?? '').toString(),
      userID:    (map['UserID']  ?? '').toString(),
      slotID:    (map['SlotID']  ?? '').toString(),
      label:     (map['Label']   ?? '').toString(),
      action:    (map['Action']  ?? '').toString(),
      message:   (map['Message'] ?? '').toString(),
      timestamp: (map['Timestamp'] is num)
          ? (map['Timestamp'] as num).toInt()
          : int.tryParse('${map['Timestamp']}') ?? 0,
    );
  }

  // Compared case-insensitively: the ESP32 sketch writes "Navigate" while the
  // app's own publishGateScan writes "navigate".
  bool get isNavigate => action.toLowerCase() == 'navigate'; // reserved driver -> go to slot
  bool get isEntry    => action.toLowerCase() == 'entry';    // registered walk-in -> park anywhere
}
