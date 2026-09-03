import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart' show FieldValue, FirebaseFirestore;

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  // Current user stream
  Stream<User?> get userStream => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  // Helpers
  // Best-effort: a Firestore failure (e.g. security rules) must NEVER block
  // sign-in / sign-up. The account already exists in Firebase Auth, so we just
  // log and move on instead of throwing the user back out.
  Future<void> _saveUserToFirestoreData(User user, {String? displayName}) async {
    try {
    final ref = _db.collection('users').doc(user.uid);
    final snap = await ref.get();
    if (!snap.exists) {
      await ref.set({
        'User uid': user.uid,
        'Email': user.email,
        'Phone': user.phoneNumber,
        'Display Name': displayName ?? user.displayName ?? '',
        'Photo URL': user.photoURL ?? '',
        'Provider': user.providerData.isNotEmpty
            ? user.providerData.first.providerId
            : 'unknown',
        'CreatedAt': FieldValue.serverTimestamp(),
        'UpdatedAt': FieldValue.serverTimestamp(),
      });
    } else {
      await ref.update({'UpdatedAt': FieldValue.serverTimestamp()});
    }
    } catch (e) {
      // ignore: avoid_print
      print('Firestore profile save skipped: $e');
    }
  }

  // Email and password
  Future<UserCredential> signUpWithEmail({
    required String email,
    required String password,
    required String displayName,
  }) async {
    // Create the account first — this is what actually signs the user in.
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    // The steps below are best-effort: if any fail, the account still exists
    // and the user is signed in, so we must not throw them back out.
    try {
      await cred.user?.updateDisplayName(displayName);
      await cred.user?.sendEmailVerification();
    } catch (e) {
      // ignore: avoid_print
      print('Post-signup step skipped: $e');
    }
    await _saveUserToFirestoreData(cred.user!, displayName: displayName);
    return cred;
  }

  Future<UserCredential> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final cred = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    await _saveUserToFirestoreData(cred.user!);
    return cred;
  }

  Future<void> sendPasswordReset(String email) =>
      _auth.sendPasswordResetEmail(email: email);

  // OTP / Phone number authentication
  Future<void> sentOTP({
    required String phoneNumber,
    required Function(PhoneAuthCredential) onAutoVerified,
    required Function(FirebaseAuthException) onFailed,
    required Function(String, int?) onCodeSent,
    required Function(String) onTimeout,
  }) async {
    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      verificationCompleted: onAutoVerified,
      verificationFailed: onFailed,
      codeSent: onCodeSent,
      codeAutoRetrievalTimeout: onTimeout,
      timeout: const Duration(seconds: 60),
    );
  }

  Future<UserCredential> verifyOTPForSignIn({
    required String verificationId,
    required String otp,
  }) async {
    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: otp,
    );
    final cred = await _auth.signInWithCredential(credential);
    await _saveUserToFirestoreData(cred.user!);
    return cred;
  }

  // Google sign in
  Future<UserCredential?> signInWithGoogle() async {
    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null; // user cancelled

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final cred = await _auth.signInWithCredential(credential);
      await _saveUserToFirestoreData(cred.user!);
      return cred;
    } on FirebaseAuthException catch (e) {
      throw Exception(getAuthErrorMessage(e));
    } catch (e) {
      // TEMP DEBUG: surface the real reason (origin_mismatch, popup blocked…).
      // ignore: avoid_print
      print('Google sign-in error: $e');
      throw Exception('Google sign-in error: $e');
    }
  }

  // Sign out
  Future<void> signOut() async {
    await Future.wait([
      _auth.signOut(),
      _googleSignIn.signOut(),
    ]);
  }

  // Auth exception helper
  // FIX: removed duplicate 'invalid-email' case
  String getAuthErrorMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'The email address is not valid.';
      case 'user-disabled':
        return 'This user has been disabled.';
      case 'user-not-found':
        return 'No user found with this email.';
      case 'wrong-password':
        return 'Incorrect password. Please try again.';
      case 'email-already-in-use':
        return 'Sorry, this email is already in use. Please use a different email.';
      case 'operation-not-allowed':
        return 'Email/password accounts are not enabled.';
      case 'weak-password':
        return 'The password is too weak. Please choose a stronger password.';
      case 'network-request-failed':
        return 'Network error. Please check your internet connection and try again.';
      case 'invalid-verification-code':
        return 'The OTP code is invalid. Please check the code and try again.';
      case 'session-expired':
        return 'The OTP code has expired. Please request a new code and try again.';
      default:
        return e.message ?? 'An unexpected error occurred. Please try again.';
    }
  }
}

