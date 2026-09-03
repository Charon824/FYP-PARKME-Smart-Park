# ParkMe — Privacy & Security Rules

This explains how each driver's **plate number** and **booking ID** are kept
private so other users can only ever see their own information.

## The idea
Firebase Realtime Database read permission **cascades**: if a user can read a node, they can read *every* field under it. So you cannot hide individual fields with rules alone. The fix is to **split the data**:

```
ParkingSlot/                 <- PUBLIC (everyone signed in can read)
  slot 1/
    Status, Label, UserID, RFIDTag, ReservationTime   (no plate / booking ID)

Bookings/                    <- PRIVATE (each entry locked to its owner)
  <userUID>/
    SlotID, PlateNum, BookingID, ReservationTime
```

- The **slot grid** (availability) reads `ParkingSlot` → everyone sees
  Available / Reserved / Occupied, but **no plate or booking ID**.
- A driver's **own** plate / booking ID lives in `Bookings/<their uid>`, which the rules allow **only that user** (and admins) to read.
- The **ESP32** never needs plate/booking ID — it only reads
  `Status` + `RFIDTag` from `ParkingSlot`, so the **firmware is unchanged**.

## How to apply the rules

### 1. Realtime Database rules
1. Firebase Console → **Realtime Database** → **Rules** tab.
2. Paste the contents of [`database.rules.json`](database.rules.json).
3. **Replace `DEVICE_UID_HERE`** with the ESP32 account's UID:
   Console → **Authentication → Users** → copy the **User UID** of
   `parkme22056469@gmail.com`.
4. Click **Publish**.

### 2. Make yourself an admin (so the Admin panel keeps working)
In Realtime Database → Data, add manually:
```
admins/
  <your-admin-account-uid>: true
```
(Use the UID of the account you log into the Admin panel with.)

### 3. Firestore (user profiles) — protect the profile too
The profile (name, plates, RFID) is in Firestore. Console → **Firestore →
Rules**, paste:
```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{uid} {
      allow read, write: if request.auth != null && request.auth.uid == uid;
    }
  }
}
```

## What each rule does
| Path | Read | Write |
|---|---|---|
| `ParkingSlot` | any signed-in user (status/label only) | the ESP32, an admin, the slot's owner, or a user reserving a free slot |
| `Bookings/<uid>` | **only that user** + admins | only that user + admins |
| `Gate/LastScan` | any signed-in user | the ESP32 + admins |
| `RegisteredCards` | any signed-in user | a user can only map a card to **their own** uid |
| `admins` | any signed-in user | console only (never from the app) |

## ⚠️ One behaviour change to know about
With these rules, a normal user can only free/cancel **their own** slot. So the
app's 15-minute auto-expiry only cleans up **your own** stale booking, not other
people's. Options:
- Leave as-is (each user's app expires their own booking) — fine for a demo.
- Or move expiry to the **ESP32** (it's authenticated as the device and may free
  any slot) or a Firebase **Cloud Function** for fully automatic expiry.

## Test it
1. Log in as **User A**, reserve a slot (enter a plate).
2. Log in as **User B** on another device: the booking screen shows that slot as
   **"Reserved by another user"** with **no plate / no booking ID**.
3. In Firebase Console, try reading `Bookings/<User A uid>` while authenticated
   as B (e.g. via the rules simulator) → **permission denied**. ✅
