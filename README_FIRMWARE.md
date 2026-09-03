# ParkMe — ESP32 ↔ Firebase ↔ Flutter Integration

This document explains how the smart-parking hardware talks to the Flutter app
through Firebase Realtime Database.

The firmware sketch lives at:
`C:\Users\ASUS\Downloads\SmartParking_Test\SmartParking_Test.ino`

---

## 1. How the whole system works

```
                 reserve a slot                 turns slot light YELLOW
   Flutter app  ───────────────►  Firebase RTDB  ◄───────────────  ESP32 reads Status
   (booking)                      /ParkingSlot                      drives traffic lights

   driver taps RFID card at gate
        │
        ▼
   ESP32 looks up the card UID among RESERVED slots
        │
        ├─ match  → opens gate, sets slot = Occupied,
        │           writes /Gate/LastScan { Action:"navigate", Label:"Level 1, A1" }
        │                       │
        │                       ▼
        │            Flutter shows "Go to Level 1, A1"
        │
        └─ no match → opens gate anyway (free entry),
                      writes /Gate/LastScan { Action:"entry" }
```

**Traffic light rule (per slot):**
| Condition (priority order)            | Light  |
|---------------------------------------|--------|
| Car physically detected (ultrasonic)  | RED    |
| Slot `Status == "Reserved"` in app    | YELLOW |
| Otherwise                             | GREEN  |

---

## 2. Firebase data structure (Realtime Database)

```
ParkingSlot/
  slot 1/
    Status:          "Available" | "Reserved" | "Occupied"
    Label:           "Level 1, A1"          # navigation label (matches firmware)
    RFIDTag:         "04A1B2C3"             # the reserver's PHYSICAL card UID
    BookingID:       "BK12345"
    PlateNum:        "WXY1234"
    UserID:          "<firebase auth uid>"
    ReservationTime: "2026-06-24T10:00:00"
    SlotID:          "slot 1"
  slot 2/ ...
  slot 3/ ...

Gate/
  LastScan/                  # written by the ESP32 on every card tap
    UID:       "04A1B2C3"
    UserID:    "<uid or ''>"
    SlotID:    "slot 1"      # "" when no booking
    Label:     "Level 1, A1" # "" when no booking
    Action:    "navigate"    # "navigate" (booked) | "entry" (free entry)
    Message:   "Go to Level 1, A1"
    Timestamp: 123456        # millis() since ESP32 boot
```

### Who writes what (ownership — avoids the app and ESP32 fighting)
- **App** owns: `Available → Reserved` (booking) and `Reserved → Available` (cancel / 15-min expiry).
- **ESP32** owns: `→ Occupied` when a car is physically detected, and
  `Occupied → Available` when the car leaves.

---

## 3. The RFID ↔ booking link (important)

A physical RFID card has a hardware UID like `04A1B2C3`. For the gate to know
"this card belongs to the person who booked slot A1", the booking must store
that **same UID** in `RFIDTag`.

Flow:
1. In the app: **Profile → Vehicle & RFID → Scan**, type your card's UID
   (see step 5 for how to find it). This saves `RFIDTag` to your Firestore
   profile (`users/{uid}`).
2. When you reserve a slot, the app copies that UID into
   `ParkingSlot/slot N/RFIDTag`.
3. At the gate, the ESP32 compares the scanned UID against the `RFIDTag` of
   every `Reserved`/`Occupied` slot. A match → navigate you to that slot.

A **demo/master card** is also hardcoded in the firmware (`testCardUID`) — it is
always let in even without a booking.

---

## 4. One-time setup

### 4a. Arduino libraries (Library Manager)
- **MFRC522** (GithubCommunity)
- **ESP32Servo**
- **Firebase ESP Client** by *Mobizt* → provides `<Firebase_ESP_Client.h>`
  and the `addons/TokenHelper.h` + `addons/RTDBHelper.h` includes.

### 4b. Create a device account for the ESP32
Firebase Console → **Authentication** → **Users** → *Add user*:
- Email: `parkme22056469@gmail.com`
- Password: `parkme22056469#`

(These must match `USER_EMAIL` / `USER_PASSWORD` in the sketch.)

### 4c. Realtime Database rules
For development, allow signed-in clients to read/write:
```json
{
  "rules": {
    ".read":  "auth != null",
    ".write": "auth != null"
  }
}
```

### 4d. Edit the sketch
At the top of `SmartParking_Test.ino`, set:
- `WIFI_SSID`, `WIFI_PASSWORD`
- `USER_EMAIL`, `USER_PASSWORD` (the account from 4b)
- `API_KEY`, `DATABASE_URL` are already filled in for project `parkme-22056469`.

---

## 5. Finding a card's UID
1. Flash the sketch and open the **Serial Monitor** at **115200 baud**.
2. Tap the RFID card on the reader.
3. The line `RFID UID: 04A1B2C3` is that card's UID — enter it in the app
   (Profile → Vehicle & RFID).

---

## 6. Where the driver sees "Go to Level 1, A1"

No gate LCD is used — with the 3-slot wiring every usable ESP32 GPIO is already
taken by the sensors, traffic lights, RFID and servo. Navigation is delivered to
the driver in two places:
- **Flutter app pop-up** when their booked card is tapped (via `Gate/LastScan`).
- **Serial monitor** (115200 baud) for testing/debugging.

---

## 7. Quick test checklist
1. Power the ESP32 → Serial shows `WiFi connected` then `Firebase initialised`.
2. In the app, reserve `slot 1` → that slot's light turns **YELLOW**.
3. Place an object in front of sensor 1 → light turns **RED**, app shows `Occupied`.
4. Tap the booked card at the gate → gate opens, app pops up **"Go to Level 1, A1"**.
5. Tap an unregistered card → gate still opens (free entry), no navigation.
