/* ============================================================================
   ParkMe – Smart Parking System (ESP32 + Firebase)
   ----------------------------------------------------------------------------
   What this firmware does:
     1. Reads 3 ultrasonic sensors to detect whether each slot is physically
        occupied.
     2. Reads each slot's reservation Status from Firebase Realtime Database.
     3. Drives the traffic lights:
            RED    = a car is physically in the slot   (Occupied)
            YELLOW = slot is booked in the app          (Reserved)
            GREEN  = slot is free                       (Available)
     4. Writes occupancy changes back to Firebase so the Flutter app updates live.
     5. On an RFID scan at the gate (3-tier access control):
            - card matches a booking      -> opens gate + navigates the driver
              ("Go to Level 1, A1") via Firebase (Gate/LastScan) + Serial
            - registered card, no booking  -> opens gate (free walk-in entry)
            - unregistered / unknown card  -> ACCESS DENIED, gate stays closed
            - parking full (0 slots free)   -> only a booking holder gets in;
              walk-ins are turned away until a slot frees up
   ----------------------------------------------------------------------------
   Required libraries (Arduino Library Manager):
     - MFRC522            (by GithubCommunity)
     - ESP32Servo
     - Firebase ESP Client (by Mobizt)   <-- #include <Firebase_ESP_Client.h>
   See firmware/README_FIRMWARE.md in the Flutter repo for full setup.
   ============================================================================ */

#include <WiFi.h>
#include <WiFiMulti.h>     // connect to whichever known network is available (there is a multiple wifi to select but need to fill in the username and pass)
#include <time.h>          // NTP clock, for expiring stale reservations
#include <SPI.h>
#include <MFRC522.h>
#include <ESP32Servo.h>

#include <Firebase_ESP_Client.h>
#include "addons/TokenHelper.h"   // ships with the Firebase ESP Client library
#include "addons/RTDBHelper.h"    // ships with the Firebase ESP Client library

// ======================
// WiFi credentials  <-- EDIT THESE
// Add as many networks as you want (phone hotspot + home WiFi). The ESP32 connects to whichever is available. All must be 2.4GHz (ESP32 can't do 5GHz;
// If your phone is IPhone need to turn ON "Maximize Compatibility" for the hotspot and Android direct search for 2.4GHz 
// ======================
WiFiMulti wifiMulti;

#define WIFI1_SSID     ""       // add your own wifi name and password
#define WIFI1_PASSWORD ""

#define WIFI2_SSID     ""              
#define WIFI2_PASSWORD ""

// ======================
// Firebase  
// ======================
#define API_KEY      "AIzaSyC4YizGnn8xIsCJ5ciAL_UYUxn_m0CSuFs"
#define DATABASE_URL "https://parkme-22056469-default-rtdb.asia-southeast1.firebasedatabase.app/"
#define USER_EMAIL    "parkme22056469@gmail.com"
#define USER_PASSWORD "" // create your own firebase account and add the password here

FirebaseData   fbdo;
FirebaseAuth   auth;
FirebaseConfig config;
bool firebaseReady = false;

// ======================
// RFID RC522
// ======================
#define SS_PIN  4
#define RST_PIN 33
MFRC522 rfid(SS_PIN, RST_PIN);

// A physical master card that is always allowed as a demo card.
// Replace with your own card UID once you read it from the Serial monitor.
String testCardUID = "A1B2C3D4";

// ======================
// Servo Motor (gate)
// ======================
#define SERVO_PIN 32
Servo gateServo;

// ======================
// Slot pin map  (3 slots)
//   Slot i uses: ultrasonic TRIG/ECHO + RED/YELLOW/GREEN traffic light
// ======================
// A OCCUPIED_DISTANCE COUNTS CLOSER THAN 10CM cause if make it to 20CM, the sensor is too sensitive (Physical Prototype using A3 acrylic board)
// TUNE IT: open Serial (115200), park the car, read the "cm" for that slot, then set this a few cm ABOVE that reading.
#define OCCUPIED_DISTANCE 10    // cm

// Reservation auto-expiry window — must match the app's 15-minute rule.
const long long RESERVE_TIMEOUT_MS = 15LL * 60LL * 1000LL;

const int NUM_SLOTS = 3;

// Firebase keys MUST match the Flutter app ("slot 1", "slot 2", ...)
String slotKey[NUM_SLOTS]   = { "slot 1",      "slot 2",      "slot 3"      };
// Human-readable navigation labels shown to the driver
String slotLabel[NUM_SLOTS] = { "Level 1, A1", "Level 1, A2", "Level 1, A3" };

int trigPin[NUM_SLOTS]   = { 18, 21, 15 };
int echoPin[NUM_SLOTS]   = { 19, 35, 34 };
int redPin[NUM_SLOTS]    = { 27,  2, 16 };
int yellowPin[NUM_SLOTS] = { 26, 23, 17 };
int greenPin[NUM_SLOTS]  = { 25, 22,  5 };

// Remembers the last Status we read for each slot so we only write on change.
String lastStatus[NUM_SLOTS] = { "", "", "" };

// After the driver scans in at the gate they still have 5 mins time to drive to the bay.
// The slot ]will remain Reserved (YELLOW) during this window and is NOT free. Only object being detected then turns it RED.
const long long ARRIVAL_GRACE_MS = 5LL * 60LL * 1000LL;   // 5 min to park

// An Occupied slot is only freed after the sensor has been clear this many
// consecutive cycles, so one flaky reading can't drop a parked car's booking.
const int CLEAR_CYCLES_TO_FREE = 3;
int clearCount[NUM_SLOTS] = { 0, 0, 0 };

// Note: no gate LCD — every usable GPIO is taken by the sensors, lights, RFID
// and servo. Navigation is delivered to the driver via the Flutter app pop-up
// (Gate/LastScan) and the Serial monitor below.

// ======================
// Distance Measurement (Ultrasonic sensor)
// ======================
// Latency of the most recent ultrasonic read (set by getDistance()):
float         g_echoUs = 0;   // averaged echo round-trip time  (microseconds)
unsigned long g_readUs = 0;   // full getDistance() duration     (microseconds)

// Returned by getDistance() when the sensor gave no echo at all.
const float NO_ECHO_CM = 999.0;

float getDistance(int trigPin, int echoPin)
{
  unsigned long tStart = micros();
  long totalDuration = 0;
  int  goodSamples = 0;                  // only average samples that echoed
  const int SAMPLES = 3;                 // fewer samples = faster

  for (int i = 0; i < SAMPLES; i++)
  {
    digitalWrite(trigPin, LOW);
    delayMicroseconds(2);
    digitalWrite(trigPin, HIGH);
    delayMicroseconds(10);
    digitalWrite(trigPin, LOW);

    long duration = pulseIn(echoPin, HIGH, 12000);  // ~2m max, quicker no-echo
    if (duration > 0) {                  // 0 = timeout, NOT "0 cm"
      totalDuration += duration;
      goodSamples++;
    }
    delay(6);
  }

  g_readUs = micros() - tStart;        // full read latency incl. averaging

  // No echo on any sample -> sensor is unplugged, unpowered, or the object is
  // inside the HC-SR04's 2cm blind spot. Report "far" so it reads as empty
  if (goodSamples == 0) {
    g_echoUs = 0;
    return NO_ECHO_CM;
  }

  float avgDuration = totalDuration / (float)goodSamples;
  g_echoUs = avgDuration;              // echo round-trip time (sensor latency)
  return avgDuration * 0.0343 / 2.0;
}

// ======================
// Traffic light LED Indicator
// RED(OCCUPIED) YELLOW(RESERVED) GREEN(AVAILABLE)
// ======================
void setLight(int i, bool sensorOccupied, const String &status)
{
  bool red = sensorOccupied;
  bool yellow = (!sensorOccupied && status == "Reserved");
  bool green = (!sensorOccupied && !yellow);

  digitalWrite(redPin[i],    red    ? HIGH : LOW);
  digitalWrite(yellowPin[i], yellow ? HIGH : LOW);
  digitalWrite(greenPin[i],  green  ? HIGH : LOW);
}

// ======================
// Firebase 
// ======================
// The node key "slot 1" has a SPACE. In a Firebase URL path that space must be
// percent-encoded as %20, or writes are rejected with "Bad request". Reads of
// "/ParkingSlot" have no space, which is why only writes fail.
String fbKey(const String &key)
{
  String k = key;
  k.replace(" ", "%20");
  return k;
}

void setSlotStatus(int i, const String &status)
{
  if (!firebaseReady) return;
  String path = "/ParkingSlot/" + fbKey(slotKey[i]) + "/Status";
  unsigned long tW = micros();                           // time the cloud write
  bool ok = Firebase.RTDB.setString(&fbdo, path.c_str(), status);
  float writeMs = (micros() - tW) / 1000.0;              // ESP32 -> Firebase latency
  if (ok) {
    lastStatus[i] = status;
    Serial.printf("   -> %s set to %s\n", slotKey[i].c_str(), status.c_str());
    Serial.printf("LATENCY  Firebase write (%s): %.2f ms\n", slotKey[i].c_str(), writeMs);
    Serial.printf("WRITECSV,%lu,%.2f\n", millis(), writeMs);   // for graphing
  } else {
    Serial.printf("   !! write failed (%s): %s\n",
                  slotKey[i].c_str(), fbdo.errorReason().c_str());
  }
}

// When a car physically leaves an Occupied slot, it will show available (clear booking info).
void freeSlot(int i)
{
  if (!firebaseReady) return;
  FirebaseJson json;
  json.set("Status",          "Available");
  json.set("BookingID",       "");
  json.set("PlateNum",        "");
  json.set("UserID",          "");
  json.set("RFIDTag",         "");
  json.set("ReservationTime", "");
  json.set("ReservedAtMs",    0);
  json.set("ArrivedAtMs",     0);   // clear the gate-arrival stamp too
  String path = "/ParkingSlot/" + fbKey(slotKey[i]);
  unsigned long tW = micros();                           // time the cloud write
  bool ok = Firebase.RTDB.updateNode(&fbdo, path.c_str(), &json);
  float writeMs = (micros() - tW) / 1000.0;              // ESP32 -> Firebase latency
  if (ok) {
    lastStatus[i] = "Available";
    Serial.printf("   -> %s freed (car left)\n", slotKey[i].c_str());
    Serial.printf("LATENCY  Firebase write (%s): %.2f ms\n", slotKey[i].c_str(), writeMs);
    Serial.printf("WRITECSV,%lu,%.2f\n", millis(), writeMs);   // for graphing
  }
}

// Look up the driver's name for a scanned card.
//   RegisteredCards/<cardUid> = { "UserID": "...", "Name": "Alice" }
// The app writes this when the user saves their RFID tag on the profile page.
// Returns "" if the card was never registered, so the caller falls back to a
// generic greeting.
String lookupCardName(const String &cardUid)
{
  if (!firebaseReady || cardUid.length() == 0) return "";

  String path = "/RegisteredCards/" + fbKey(cardUid) + "/Name";
  if (Firebase.RTDB.getString(&fbdo, path.c_str())) {
    String name = fbdo.to<const char *>();
    name.trim();
    return name;
  }
  return "";   // unregistered card, or an older entry with no Name field
}

// One Firebase read of RegisteredCards/<uid> that returns BOTH the driver name
// and whether the card is registered. Combining the greeting lookup and the
// access-control check into a single network round-trip (instead of two) makes
// the gate respond noticeably faster on a slow / unstable WiFi link.
// The demo/master card is always treated as registered, with no network read.
void getCardInfo(const String &cardUid, String &outName, bool &outRegistered)
{
  outName = "";
  outRegistered = false;
  if (cardUid == testCardUID) { outRegistered = true; return; }   // master card
  if (!firebaseReady || cardUid.length() == 0) return;

  String path = "/RegisteredCards/" + fbKey(cardUid);
  if (Firebase.RTDB.getJSON(&fbdo, path.c_str())) {
    FirebaseJson j = fbdo.to<FirebaseJson>();
    FirebaseJsonData d;
    if (j.get(d, "UserID")) { String u = d.to<String>(); u.trim(); outRegistered = (u.length() > 0); }
    if (j.get(d, "Name"))   { outName = d.to<String>(); outName.trim(); }
  }
}

// The driver scanned in at the gate but has not parked yet. Keep the slot Reserved (YELLOW) and stamp the arrival time so the 15-minute booking clock
// is replaced by the shorter "you're inside, go park" grace window.
void markArrived(int i)
{
  if (!firebaseReady) return;
  time_t nowSec = time(nullptr);
  if (nowSec < 1700000000) return;            // NTP not synced, skip the stamp

  FirebaseJson json;
  json.set("Status",      "Reserved");        // stays YELLOW until sensed
  json.set("ArrivedAtMs", (double) nowSec * 1000.0);
  String path = "/ParkingSlot/" + fbKey(slotKey[i]);
  if (Firebase.RTDB.updateNode(&fbdo, path.c_str(), &json)) {
    lastStatus[i] = "Reserved";
    Serial.printf("   -> %s: driver entered, waiting for car to park\n",
                  slotKey[i].c_str());
  }
}

// Publish the result of an RFID scan so the Flutter app can react.
void publishScan(const String &uid, const String &userId,
                 const String &slotId, const String &label,
                 const String &action, const String &message)
{
  Serial.println("   " + message);

  if (!firebaseReady) return;
  FirebaseJson g;
  g.set("UID",       uid);
  g.set("UserID",    userId);
  g.set("SlotID",    slotId);
  g.set("Label",     label);
  g.set("Action",    action);     // "navigate" | "entry"
  g.set("Message",   message);
  g.set("Timestamp", (double) millis());
  Firebase.RTDB.setJSON(&fbdo, "/Gate/LastScan", &g);
}

// ======================
// Gate open/close
// ======================
void openGate()
{
  Serial.println("   >> Opening gate...");
  gateServo.setPeriodHertz(50);
  gateServo.attach(SERVO_PIN, 500, 2400);
  gateServo.write(90);      // OPEN  (arm up)
  delay(5000);              // keep open 5s for the car
  gateServo.write(0);       // CLOSE (arm back down) 
  delay(1000);
  gateServo.detach();       // silent
  Serial.println("   >> Gate closed.");
}

// ======================
// RFID: read a card, find its booking, open the gate
// `slotsJson`   is the ParkingSlot tree we already fetched this cycle.
// `parkingFull` is true when 0 slots are available -> the barrier stays shut
//               for walk-ins and unknown cards (nowhere to park). A booking
//               holder is STILL admitted, because their bay is held for them.
// ======================
void checkRFID(FirebaseJson &slotsJson, bool parkingFull)
{
  if (!rfid.PICC_IsNewCardPresent()) return;       // nothing in the RF field
  unsigned long tRfid = micros();                  // start timing the read
  Serial.println(">> Card sensed in field, reading...");
  if (!rfid.PICC_ReadCardSerial()) {
    Serial.println(">> ...reading failed (Please hold the card flat & still on the reader).");
    return;
  }

  String uid = "";
  for (byte i = 0; i < rfid.uid.size; i++) {
    if (rfid.uid.uidByte[i] < 0x10) uid += "0";
    uid += String(rfid.uid.uidByte[i], HEX);
  }
  uid.toUpperCase();

  // --- RFID latency: from card sensed to UID decoded ---
  float rfidMs = (micros() - tRfid) / 1000.0;
  Serial.printf("LATENCY  RC522 RFID: read=%.2f ms\n", rfidMs);
  Serial.printf("RFIDCSV,%lu,%.2f\n", millis(), rfidMs);   // for graphing

  Serial.println("--------------------------------");
  Serial.print("RFID UID: ");
  Serial.println(uid);

  // Search reserved/occupied slots for a matching RFID tag.
  int    matchIdx  = -1;
  String matchUser = "";
  FirebaseJsonData jdata;
  for (int i = 0; i < NUM_SLOTS; i++) {
    String tagPath = slotKey[i] + "/RFIDTag";
    String stPath  = slotKey[i] + "/Status";
    String userPath= slotKey[i] + "/UserID";

    String tag = "";
    if (slotsJson.get(jdata, tagPath.c_str())) tag = jdata.to<String>();
    tag.trim(); tag.toUpperCase();

    String st = "";
    if (slotsJson.get(jdata, stPath.c_str())) st = jdata.to<String>();

    if (tag.length() > 0 && tag == uid &&
        (st == "Reserved" || st == "Occupied")) {
      matchIdx = i;
      if (slotsJson.get(jdata, userPath.c_str())) matchUser = jdata.to<String>();
      break;
    }
  }

  // Single Firebase read: gets the driver's name AND whether the card is
  // registered, in one round-trip (was two separate reads before).
  String driver; bool registered;
  getCardInfo(uid, driver, registered);
  String greeting = (driver.length() > 0) ? ("Welcome, " + driver + "! ")
                                          : "Welcome! ";

  if (matchIdx >= 0) {
    // TIER 1 — Booked Parking Spot -> navigate them to their slot. Do NOT mark it
    // Occupied here: the car arrived at the gate, so the slot sensor would see an
    // empty bay. The slot stays Reserved (YELLOW) and only turns Occupied (RED)
    // once the sensor detects an object.
    String msg = greeting + "Go to " + slotLabel[matchIdx];
    Serial.println("ACCESS GRANTED. " + msg);
    publishScan(uid, matchUser, slotKey[matchIdx],
                slotLabel[matchIdx], "Navigate", msg);
    markArrived(matchIdx);
    openGate();
  } else if (parkingFull) {
    // PARKING FULL, and this card has no reserved slot -> keep the gate closed.
    // Booking holders (Tier 1 above) are exempt because their bay is held for
    // them; walk-ins and unknown cards have nowhere to park.
    Serial.println("ACCESS DENIED. PARKING FULL - no free slot for this card.");
    publishScan(uid, "", "", "", "full",
                "Parking is full. Please wait for a slot to free up.");
  } else if (registered) {
    // TIER 2 — Registered driver with no active booking -> free walk-in entry.
    Serial.println("ACCESS GRANTED (free entry). No reservation found for this card.");
    publishScan(uid, "", "", "", "entry",
                greeting + "You didn't make any booking - please find a free slot.");
    openGate();
  } else {
    // TIER 3 — Unregistered / unknown card -> DENY. Gate stays closed.
    Serial.println("ACCESS DENIED. Unregistered card - Please register in the ParkMe app first.");
    publishScan(uid, "", "", "", "denied",
                "Access denied: this card is not registered. Please register in the ParkMe app.");
    // NOTE: openGate() is deliberately NOT called here, so the barrier stays shut.
  }

  rfid.PICC_HaltA();
  rfid.PCD_StopCrypto1();
}

// ======================
// Setup
// ======================
void setup()
{
  Serial.begin(115200);

  // Ultrasonic + traffic light pins
  for (int i = 0; i < NUM_SLOTS; i++) {
    pinMode(trigPin[i], OUTPUT);
    pinMode(echoPin[i], INPUT);
    pinMode(redPin[i],    OUTPUT);
    pinMode(yellowPin[i], OUTPUT);
    pinMode(greenPin[i],  OUTPUT);
  }

  // Servo -> ESP32Servo needs a PWM timer + 50Hz set BEFORE attach, or it
  // won't move at all. Attach once and stay attached so openGate() works.
  ESP32PWM::allocateTimer(0);
  ESP32PWM::allocateTimer(1);
  ESP32PWM::allocateTimer(2);
  ESP32PWM::allocateTimer(3);
  gateServo.setPeriodHertz(50);            // standard servo frequency
  gateServo.attach(SERVO_PIN, 500, 2400);
  gateServo.write(10);   // closed position
  delay(500);
  gateServo.detach();    // release at idle -> no buzzing until a card opens it

  // RFID
  SPI.begin(14, 13, 12, SS_PIN);
  rfid.PCD_Init();
  delay(50);
  rfid.PCD_AntennaOn();                          // make sure the RF field is on
  rfid.PCD_SetAntennaGain(rfid.RxGain_max);      // max read range / weak-power help
  delay(50);

  // --- RC522 self-check ---
  byte rfidVersion = rfid.PCD_ReadRegister(rfid.VersionReg);
  Serial.print("RC522 firmware version: 0x");
  Serial.println(rfidVersion, HEX);
  if (rfidVersion == 0x00 || rfidVersion == 0xFF) {
    Serial.println("!! RC522 NOT detected - check wiring (SDA=4, SCK=14,");
    Serial.println("   MOSI=12, MISO=13, RST=33) and power it from 3.3V, not 5V.");
  } else {
    Serial.println("RC522 detected OK. Tap a card to read its UID.");
  }

  // ---- WiFi ----
  WiFi.mode(WIFI_STA);
  WiFi.disconnect();
  delay(100);

  // Search for every network that show in the WiFi list as it was been detected
  Serial.println("Scanning for networks...");
  int n = WiFi.scanNetworks();
  if (n == 0) {
    Serial.println("  No networks found! (hotspot off / 5GHz only / out of range)");
  } else {
    for (int i = 0; i < n; i++) {
      Serial.printf("  %d) '%s'  (signal %d dBm)%s\n", i + 1,
                    WiFi.SSID(i).c_str(), WiFi.RSSI(i),
                    (WiFi.SSID(i) == WIFI1_SSID) ? "  <-- YOUR HOTSPOT" : "");
    }
  }
  Serial.println("Looking for: '" WIFI1_SSID "'");

  wifiMulti.addAP(WIFI1_SSID, WIFI1_PASSWORD);   // WiFi
  wifiMulti.addAP(WIFI2_SSID, WIFI2_PASSWORD);   // Hotspot
  Serial.print("Connecting to WiFi");
  unsigned long t0 = millis();
  while (wifiMulti.run() != WL_CONNECTED && millis() - t0 < 20000) {
    delay(300);
    Serial.print(".");
  }
  Serial.println();

  // ---- Firebase ----
  if (WiFi.status() == WL_CONNECTED) {
    Serial.print("WiFi connected, IP: ");
    Serial.println(WiFi.localIP());

    config.api_key      = API_KEY;
    config.database_url  = DATABASE_URL;
    auth.user.email      = USER_EMAIL;
    auth.user.password   = USER_PASSWORD;
    config.token_status_callback = tokenStatusCallback;

    Firebase.begin(&config, &auth);
    Firebase.reconnectWiFi(true);
    fbdo.setBSSLBufferSize(4096, 1024);
    firebaseReady = true;
    Serial.println("Firebase initialised.");

    // Real clock via NTP (UTC) — needed to expire reservations after 15 min.
    configTime(0, 0, "pool.ntp.org", "time.nist.gov");
    Serial.print("Syncing time");
    for (int i = 0; i < 20 && time(nullptr) < 1700000000; i++) {
      delay(300);
      Serial.print(".");
    }
    Serial.println(time(nullptr) > 1700000000 ? " time OK" : " time NOT synced");
  } else {
    Serial.println("WiFi FAILED to connect - Running offline (sensors/lights only).");
  }

  Serial.println("================================");
  Serial.println(" SMART PARKING SYSTEM STARTED ");
  Serial.println("================================");

  // CSV header for the latency graph (matches the CSV rows in loop()).
  Serial.println("CSV, ms, echo1_us, read1_ms, echo2_us, read2_ms, echo3_us, read3_ms");
}

// ======================
// Loop
// ======================
void loop()
{
  // 1) Read the whole ParkingSlot tree once this cycle.
  FirebaseJson slotsJson;
  bool haveData = false;
  if (firebaseReady && Firebase.ready()) {
    if (Firebase.RTDB.getJSON(&fbdo, "/ParkingSlot")) {
      slotsJson = fbdo.to<FirebaseJson>();
      haveData = true;
    } else {
      Serial.print("Read /ParkingSlot failed: ");
      Serial.println(fbdo.errorReason());
    }
  }

  FirebaseJsonData jdata;
  int availableSlots = 0;
  float echoArr[NUM_SLOTS] = {0};   // captured per cycle for CSV / graphing
  float readArr[NUM_SLOTS] = {0};

  // Current real time (epoch ms, UTC) for reservation expiry.
  time_t  nowSec = time(nullptr);
  bool    timeOk = nowSec > 1700000000;          // NTP has synced
  long long nowMs = (long long) nowSec * 1000LL;

  Serial.println("--------------------------------");

  // 2) Per-slot: measure, drive lights, sync occupancy.
  for (int i = 0; i < NUM_SLOTS; i++) {
    float d = getDistance(trigPin[i], echoPin[i]);
    // --- Ultrasonic latency ---
    Serial.printf("LATENCY  %s ultrasonic: echo=%.0f us | read=%.2f ms (%.1f cm)\n",
                  slotKey[i].c_str(), g_echoUs, g_readUs / 1000.0, d);
    echoArr[i] = g_echoUs;
    readArr[i] = g_readUs / 1000.0;
    delay(10);
    bool sensorOccupied = (d > 0 && d < OCCUPIED_DISTANCE);

    // Current Status from Firebase (defaults to Available offline).
    String status = "Available";
    if (haveData) {
      String p = slotKey[i] + "/Status";
      if (slotsJson.get(jdata, p.c_str())) status = jdata.to<String>();
    }

    // Auto-expire a Reserved slot that has no car. Which clock applies depends
    // on whether the driver has already scanned in at the gate:
    //   ArrivedAtMs set -> they are inside driving to the bay, so allow the shorter ARRIVAL_GRACE_MS before giving the slot up.
    //   otherwise       -> the normal 15-minute no-show booking window.
    // A Reserved slot is never freed by an empty sensor alone, only by a clock.
    if (haveData && timeOk && status == "Reserved" && !sensorOccupied) {
      double reservedAtMs = 0, arrivedAtMs = 0;
      String rp = slotKey[i] + "/ReservedAtMs";
      String ap = slotKey[i] + "/ArrivedAtMs";
      if (slotsJson.get(jdata, rp.c_str())) reservedAtMs = jdata.to<double>();
      if (slotsJson.get(jdata, ap.c_str())) arrivedAtMs  = jdata.to<double>();

      bool      arrived  = (arrivedAtMs > 0);
      double    startMs  = arrived ? arrivedAtMs : reservedAtMs;
      long long windowMs = arrived ? ARRIVAL_GRACE_MS : RESERVE_TIMEOUT_MS;

      if (startMs > 0 && (nowMs - (long long) startMs) >= windowMs) {
        Serial.printf("   -> %s %s expired, freeing\n", slotKey[i].c_str(),
                      arrived ? "parking grace period" : "reservation (> 15 min)");
        freeSlot(i);
        status = "Available";
      }
    }

    // Lights reflect physical car > reservation > free.
    setLight(i, sensorOccupied, status);

    // Occupancy state machine (firmware owns Occupied <-> sensor transitions;
    // the app owns Available <-> Reserved).
    if (haveData) {
      if (sensorOccupied) {
        clearCount[i] = 0;                  // car is there, reset the leave timer
        if (status != "Occupied") {
          setSlotStatus(i, "Occupied");     // a car parked here -> RED
        }
      } else if (status == "Occupied") {
        // Only free after the sensor has been clear for several cycles in a row,  so a single missed echo doesn't wipe a parked car's booking.
        clearCount[i]++;
        if (clearCount[i] >= CLEAR_CYCLES_TO_FREE) {
          freeSlot(i);                      // the car really left
          clearCount[i] = 0;
        } else {
          Serial.printf("   .. %s looks empty (%d/%d) - confirming\n",
                        slotKey[i].c_str(), clearCount[i], CLEAR_CYCLES_TO_FREE);
        }
      } else {
        clearCount[i] = 0;                  // Reserved/Available: nothing to time
      }
    }

    if (!sensorOccupied && status != "Reserved" && status != "Occupied")
      availableSlots++;

    Serial.printf("%s (%s): %.1f cm | sensor=%s | status=%s\n",
                  slotKey[i].c_str(), slotLabel[i].c_str(), d,
                  sensorOccupied ? "Occupied" : "Empty", status.c_str());
  }

  Serial.printf("Available Slots: %d\n", availableSlots);
  if (availableSlots == 0) Serial.println("PARKING FULL");

  // CSV row for graphing — copy lines starting with "CSV," into Excel/Sheets.
  Serial.printf("CSV,%lu,%.0f,%.2f,%.0f,%.2f,%.0f,%.2f\n",
                millis(), echoArr[0], readArr[0], echoArr[1], readArr[1],
                echoArr[2], readArr[2]);

  // 3) Handle gate scans. Poll the reader for ~0.8s (keeps the loop fast so
  //    sensor status updates quickly, while still catching most card taps).
  //    When the lot is full, checkRFID() lets booking holders in but turns
  //    walk-ins away (no free slot for them).
  bool parkingFull = (availableSlots == 0);
  for (int t = 0; t < 40; t++) {
    checkRFID(slotsJson, parkingFull);
    delay(20);
  }
}
