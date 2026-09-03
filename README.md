# Smart-Parking-Systems-Final-Year-Project-
Smart-Parking-Systems-Final-Year-Project-
│
├── main
│   │
│   └── Complete ParkMe system
│       ├── parkme_v2/
│       │   ├── lib/
│       │   │   ├── main.dart
│       │   │   ├── Firebase configuration/
│       │   │   ├── screens/
│       │   │   ├── services/
│       │   │   ├── models/
│       │   │   └── ...
│       │   ├── pubspec.yaml
│       │   └── ...
│       │
│       ├── hardware/
│       │   └── ESP32 code
│       │
│       └── README.md
│
├── software
│   │
│   └── parkme_v2/
│       ├── lib/
│       │   ├── main.dart
│       │   ├── appsColor/
│       │   │   └── app_theme.dart
│       │   │
│       │   ├── Firebase 
│       │   │   ├── firebase_options.dart
│       │   │   └── firebaseConfig.js
├               |── firestore_rules
│       │   │   └── firestores_indexes.json
|               |── package-lock.json
│       │   │   └── package.json
│       │   │
│       │   ├── screens/
│       │   │   ├── login/
│       │   │   ├── home/
│       │   │   ├── booking/
│       │   │   └── dashboard/
│       │   │   ├── floor_plan/
│       │   │   ├── navigation/
│       │   │   └── profile/
│       │   ├── LoginSystem/
│       │   │   ├── Auth_Service/
│       │   │   ├── Auth_Widgets/
│       │   │   ├── Login/
│       │   │   └── OTP/
│       │   │   ├── SignUp/
│       │   │   ├── welcome/
│       │   │
│       │   ├── services/
│       │   │   └── parking_service.dart
│       │   │
│       │   ├── models/
│       │   └── parkingSlot.dart
│       │
│       ├── pubspec.yaml
│       └── ...
│
├── hardware
│   │
│   └── ESP32
│       ├── main Arduino code
│       ├── RFID MFRC522
│       ├── ultrasonic sensors HC-SR04
│       ├── servo motor
│       └── traffic lights
│
└── firebase
    │
    ├── Firebase rules
    ├── database configuration
    ├── firestore rules
    ├── realtime database rules
    ├── firebase.json
    └── .firebaserc
