import 'package:flutter/material.dart';
import '../appsColor/app_theme.dart';
import 'floor_plan.dart';

// ─────────────────────────────────────────────────────────────────────────────
// NavigationScreen
// Opens automatically when a booked card is scanned at the gate. Shows the floor
// plan (entrance, bays, staircase) and a route from the entrance to the user's
// reserved spot.
// ─────────────────────────────────────────────────────────────────────────────

class NavigationScreen extends StatelessWidget {
  final String slotId;   // e.g. "slot 1"
  final String label;    // e.g. "Level 1, A1"

  const NavigationScreen({super.key, required this.slotId, required this.label});

  static const _order = ['slot 1', 'slot 2', 'slot 3'];
  static const _codes = ['A1', 'A2', 'A3'];

  int get _idx { final i = _order.indexOf(slotId); return i < 0 ? 0 : i; }
  String get _code => _codes[_idx];

  String get _routeHint {
    switch (_idx) {
      case 0: return 'Enter the gate, drive straight — A1 is on the left.';
      case 1: return 'Enter the gate, drive straight ahead — A2 is in the middle.';
      default: return 'Enter the gate, drive to the right — A3 is the bay nearest the staircase / mall entrance.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryNavy,
      appBar: AppBar(
        backgroundColor: AppColors.cardNavy,
        title: const Text('Navigation',
            style: TextStyle(color: AppColors.white, fontWeight: FontWeight.w700)),
        iconTheme: const IconThemeData(color: AppColors.white),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // ── Header ────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.accentBlue, Color(0xFF1040B0)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(
                  color: AppColors.accentBlue.withValues(alpha: 0.35),
                  blurRadius: 18, offset: const Offset(0, 8))],
              ),
              child: Row(children: [
                const Icon(Icons.assistant_navigation, color: Colors.white, size: 34),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Your reserved spot',
                      style: TextStyle(color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 2),
                  Text(label, style: const TextStyle(
                      color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                ])),
              ]),
            ),
            const SizedBox(height: 16),

            // ── Floor plan with route ─────────────────────────────────
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.cardNavy,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.inputBorder),
              ),
              child: FloorPlanView(targetSlotId: slotId, showRoute: true),
            ),
            const SizedBox(height: 14),

            // ── Route hint ────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.accentBlue.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.accentBlue.withValues(alpha: 0.3)),
              ),
              child: Row(children: [
                const Icon(Icons.turn_slight_right_rounded,
                    color: AppColors.accentBlue, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text(_routeHint,
                    style: const TextStyle(color: AppColors.white, fontSize: 13))),
              ]),
            ),
            const SizedBox(height: 12),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.maybePop(context),
                icon: const Icon(Icons.check_rounded),
                label: Text('Got it — heading to $_code',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
