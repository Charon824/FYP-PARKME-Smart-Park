import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android: return android;
      case TargetPlatform.iOS:     return ios;
      default:
        throw UnsupportedError('Unsupported platform');
    }
  }

  // ── Android ──────────────────────────────────────────────
  // From: google-services.json → client[0].api_key[0].current_key
  static const FirebaseOptions android = FirebaseOptions(
    apiKey:            'AIzaSyC4YizGnn8xIsCJ5ciAL_UYUxn_m0CSuFs',
    appId:             '1:264720095382:web:08ceb91d5c7edfecdbcab7',       // e.g. 1:123456789:android:abcdef
    messagingSenderId: '264720095382',            // e.g. 123456789012
    projectId:         'parkme-22056469',           // e.g. parkme-app
    storageBucket:     'parkme-22056469.firebasestorage.app',
    databaseURL:       'https://parkme-22056469-default-rtdb.asia-southeast1.firebasedatabase.app/',
  );

  // ── iOS ──────────────────────────────────────────────────
  // From: GoogleService-Info.plist
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey:            'AIzaSyBOOzAF_VJZLUMdnXG3bIIabhJYwJiZXaE',
    appId:             '1:264720095382:ios:4ea2f3985249a39ddbcab7',           // e.g. 1:123456789:ios:abcdef
    messagingSenderId: '264720095382',
    projectId:         'parkme-22056469',
    storageBucket:     'parkme-22056469.firebasestorage.app',
    databaseURL:       'https://parkme-22056469-default-rtdb.asia-southeast1.firebasedatabase.app',
    iosBundleId:       'com.ParkMe.parkmeapp',    // must match your app bundle ID
  );

  // ── Web ──────────────────────────────────────────────────
  static const FirebaseOptions web = FirebaseOptions(
    apiKey:            'AIzaSyCAhnD5OKPltpWl8MwlLJQ-1vmcnxXmgaA',
    appId:             '1:264720095382:web:08ceb91d5c7edfecdbcab7',
    messagingSenderId: '264720095382',
    projectId:         'parkme-22056469',
    storageBucket:     'parkme-22056469.firebasestorage.app',
    databaseURL:       'https://parkme-22056469-default-rtdb.asia-southeast1.firebasedatabase.app/',
    authDomain:        'parkme-22056469.firebaseapp.com',
    measurementId:     'G-V8RD9EX357',
  );
}