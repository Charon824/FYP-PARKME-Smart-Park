import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'Firebase/firebase_options.dart';
import 'appsColor/app_theme.dart';
import 'models/parkingSlot.dart';
import 'widgets/app_logo.dart';
import 'LoginSystem/Auth_Service.dart';
import 'LoginSystem/welcome.dart';
import 'screens/Home.dart';
import 'screens/booking.dart';
import 'screens/dashboard_screen.dart';
import 'screens/profile.dart';
import 'screens/admin_screen.dart';
import 'screens/navigation.dart';
import 'services/parking_service.dart';
import 'package:device_preview/device_preview.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor:           Colors.transparent,
    statusBarIconBrightness:  Brightness.dark,   // dark icons on light background
  ));
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // NOTE: do NOT touch the database here — the user isn't signed in yet, so a
  // read/write would be denied by the security rules and crash startup (blank
  // screen). Slot seeding happens after login, in MainShell.initState().

  runApp(
    DevicePreview(
      enabled: false,// Set to true to enable Device Preview
      builder: (context) => const ParkMeApp(),
    ),
  );
}

class ParkMeApp extends StatelessWidget {
  const ParkMeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ParkMe',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      home: const _AuthGate(),
    );
  }
}

// ── Auth Gate ──────────────────────────────────────────────────────────────
class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: AuthService().userStream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const _SplashScreen();
        }
        return snap.hasData ? const MainShell() : const Welcome();
      },
    );
  }
}

// ── Splash ─────────────────────────────────────────────────────────────────
class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.primaryNavy,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppLogo(height: 56),
            SizedBox(height: 20),
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation(AppColors.accentBlue),
              strokeWidth: 2.5,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Main Shell with Bottom Navigation ────────────────────────────────────
class MainShell extends StatefulWidget {
  final int initialIndex;
  const MainShell({super.key, this.initialIndex = 0});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  late int _index;

  // Switch the active bottom-nav tab (used by Home's Quick Action buttons).
  void _goToTab(int i) => setState(() => _index = i);

  late final List<Widget> _screens = [
    HomeScreen(onNavigate: _goToTab),
    const BookingScreen(),
    const DashboardScreen(),
    const ProfileScreen(),
  ];

  // Listen for gate scans so we can navigate the user to their slot.
  StreamSubscription<GateScan?>? _scanSub;
  int? _lastScanTs;          // baseline: ignore the scan that already exists on launch
  bool _sawFirstEmission = false; // set even when the node is empty on launch

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    // Now that the user is signed in, seed the 3 slots if the DB is empty.
    // Best-effort: never let it crash the shell.
    ParkingService.instance.seedSlots().catchError((_) {});
    // onError so a malformed Gate/LastScan node can't silently kill the
    // subscription and leave arrivals unhandled for the rest of the session.
    _scanSub = ParkingService.instance.gateScanStream
        .listen(_onGateScan, onError: (_) {});
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    super.dispose();
  }

  void _onGateScan(GateScan? scan) {
    // First emission after launch is the baseline — don't pop a stale scan.
    // An empty Gate/LastScan still counts, otherwise the first real scan on a
    // fresh database would be swallowed as the baseline.
    if (!_sawFirstEmission) {
      _sawFirstEmission = true;
      _lastScanTs = scan?.timestamp;
      return;
    }
    if (scan == null) return;
    if (scan.timestamp == _lastScanTs) return;
    _lastScanTs = scan.timestamp;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    // React only to this user's own tap, and only for "navigate" / "entry".
    if (uid == null || scan.userID != uid) return;
    if (!scan.isNavigate && !scan.isEntry) return;
    if (!mounted) return;

    // Booked card -> open the floor map and guide them to their reserved spot.
    if (scan.isNavigate) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => NavigationScreen(
          slotId: scan.slotID,
          label:  scan.label.isNotEmpty ? scan.label : scan.slotID,
        ),
      ));
      return;
    }

    // Walk-in (entry) -> just show the welcome note.
    final Widget body = scan.isNavigate
        ? Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Your reserved slot:',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.accentBlue.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.accentBlue.withValues(alpha: 0.4)),
              ),
              child: Text(
                scan.label.isNotEmpty ? scan.label : scan.slotID,
                style: const TextStyle(
                    color: AppColors.accentBlue, fontSize: 22, fontWeight: FontWeight.w800),
              ),
            ),
          ])
        : Text(
            scan.message.isNotEmpty
                ? scan.message
                : 'No reservation found — please park in any available bay.',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.4),
          );

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.cardNavy,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          Icon(scan.isNavigate ? Icons.directions_car_rounded : Icons.local_parking_rounded,
              color: AppColors.accentBlue),
          const SizedBox(width: 10),
          const Text('Welcome!',
              style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
        ]),
        content: body,
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final isAdmin = isAdminUser(user);

    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) {
          if (isAdmin && i == 4) {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminScreen()));
          } else {
            setState(() => _index = i);
          }
        },
        backgroundColor:    AppColors.cardNavy,
        indicatorColor:     AppColors.accentBlue.withValues(alpha: 0.25),
        surfaceTintColor:   Colors.transparent,
        shadowColor:        Colors.transparent,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: [
          const NavigationDestination(
            icon:          Icon(Icons.home_outlined,       color: AppColors.textHint),
            selectedIcon:  Icon(Icons.home_rounded,        color: AppColors.accentBlue),
            label: 'Home',
          ),
          const NavigationDestination(
            icon:          Icon(Icons.bookmark_outline,    color: AppColors.textHint),
            selectedIcon:  Icon(Icons.bookmark_rounded,    color: AppColors.accentBlue),
            label: 'Book',
          ),
          const NavigationDestination(
            icon:          Icon(Icons.dashboard_outlined,  color: AppColors.textHint),
            selectedIcon:  Icon(Icons.dashboard_rounded,   color: AppColors.accentBlue),
            label: 'Dashboard',
          ),
          const NavigationDestination(
            icon:          Icon(Icons.person_outline_rounded, color: AppColors.textHint),
            selectedIcon:  Icon(Icons.person_rounded,         color: AppColors.accentBlue),
            label: 'Profile',
          ),
          if (isAdmin)
            const NavigationDestination(
              icon:         Icon(Icons.admin_panel_settings_outlined, color: AppColors.textHint),
              selectedIcon: Icon(Icons.admin_panel_settings_rounded,  color: Colors.orange),
              label: 'Admin',
            ),
        ],
      ),
    );
  }
}
