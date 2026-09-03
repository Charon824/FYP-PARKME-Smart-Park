import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../appsColor/app_theme.dart';
import '../LoginSystem/Auth_Service.dart';
import '../models/parkingSlot.dart';
import '../services/parking_service.dart';
import '../widgets/app_logo.dart';
import 'floor_plan.dart';

class HomeScreen extends StatelessWidget {
  // Called to switch the bottom-nav tab (1 = Book, 2 = Dashboard).
  final void Function(int index)? onNavigate;
  const HomeScreen({super.key, this.onNavigate});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final firstName = user?.displayName?.split(' ').first ?? 'Driver';

    return Scaffold(
      body: Stack(
        children: [
          // ── Background gradient ─────────────────────────────────────
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFF2F8FF), AppColors.primaryNavy, AppColors.secondaryNavy],
              ),
            ),
          ),

          // ── Accent blobs ────────────────────────────────────────────
          Positioned(top: -80, right: -60, child: _blob(260, 0.06)),
          Positioned(top: 40,  right: 20,  child: _blob(130, 0.04)),

          SafeArea(
            child: StreamBuilder<List<ParkingSlot>>(
              stream: ParkingService.instance.slotsStream,
              builder: (context, snap) {
                final slots     = snap.data ?? [];
                final available = slots.where((s) => s.isAvailable).length;
                final reserved  = slots.where((s) => s.isReserved).length;
                final occupied  = slots.where((s) => s.isOccupied).length;
                final total     = slots.length;

                return ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    // ── Top bar ──────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 16, 0),
                      child: Row(
                        children: [
                          // Logo
                          const AppLogo(height: 38),
                          const Spacer(),
                          // Sign out
                          IconButton(
                            icon: const Icon(Icons.logout_rounded, color: AppColors.textHint, size: 20),
                            tooltip: 'Sign Out',
                            onPressed: () async {
                              await AuthService().signOut();
                            },
                          ),
                        ],
                      ),
                    ),

                    // ── Greeting ─────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Good day, $firstName 👋',
                              style: const TextStyle(color: AppColors.textSecondary, fontSize: 14)),
                          const SizedBox(height: 4),
                          const Text('Find your parking spot',
                              style: TextStyle(color: AppColors.textPrimary, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // ── Hero availability card ─────────────────────
                    _HeroCard(available: available, total: total),

                    const SizedBox(height: 16),

                    // ── Stat tiles ────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(children: [
                        Expanded(child: _StatTile('Available', available, Icons.check_circle_outline_rounded, AppColors.available)),
                        const SizedBox(width: 10),
                        Expanded(child: _StatTile('Reserved',  reserved,  Icons.bookmark_outline_rounded,     AppColors.reserved)),
                        const SizedBox(width: 10),
                        Expanded(child: _StatTile('Occupied',  occupied,  Icons.directions_car_outlined,      AppColors.occupied)),
                      ]),
                    ),

                    const SizedBox(height: 24),

                    // ── Quick Actions ─────────────────────────────
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Quick Actions',
                              style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 12),
                          Row(children: [
                            Expanded(child: _QuickAction(
                              icon: Icons.bookmark_add_outlined,
                              label: 'Book a Slot',
                              color: AppColors.accentBlue,
                              onTap: () => onNavigate?.call(1),
                            )),
                            const SizedBox(width: 10),
                            Expanded(child: _QuickAction(
                              icon: Icons.dashboard_outlined,
                              label: 'Live Dashboard',
                              color: const Color(0xFF9C27B0),
                              onTap: () => onNavigate?.call(2),
                            )),
                          ]),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // ── Parking layout map ────────────────────────
                    _FloorPlanCard(slots: slots, onBook: () => onNavigate?.call(1)),

                    const SizedBox(height: 24),

                    // ── Lot info card ─────────────────────────────
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.cardNavy,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.inputBorder),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: AppColors.accentBlue.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.location_on_outlined, color: AppColors.accentBlue, size: 18),
                              ),
                              const SizedBox(width: 10),
                              const Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Sunway University Lot A — Block 1', style: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
                                  Text('Basement · 24 hrs', style: TextStyle(color: AppColors.textHint, fontSize: 11)),
                                ],
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.available.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Text('Open', style: TextStyle(color: AppColors.available, fontSize: 11, fontWeight: FontWeight.w700)),
                              ),
                            ]),
                            const SizedBox(height: 12),
                            const Divider(color: AppColors.divider),
                            const SizedBox(height: 10),
                            Row(children: [
                              _InfoChip(Icons.local_parking_rounded,  '$total Total Slots'),
                              const SizedBox(width: 12),
                              const _InfoChip(Icons.payments_outlined,      'RM 2 / hr'),
                              const SizedBox(width: 12),
                              const _InfoChip(Icons.sensors_rounded,        'Sensor Active'),
                            ]),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 32),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _blob(double size, double alpha) => Container(
    width: size, height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: AppColors.accentBlue.withValues(alpha: alpha),
    ),
  );
}

// ── Hero availability card ────────────────────────────────────────────────
class _HeroCard extends StatelessWidget {
  final int available, total;
  const _HeroCard({required this.available, required this.total});

  @override
  Widget build(BuildContext context) {
    final pct = total == 0 ? 0.0 : available / total;
    final isLow = available <= 1;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isLow
              ? [const Color(0xFFBF360C), const Color(0xFFE53935)]
              : [AppColors.accentBlue, const Color(0xFF1040B0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: (isLow ? AppColors.occupied : AppColors.accentBlue).withValues(alpha: 0.35),
            blurRadius: 20, offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(children: [
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$available Slot${available == 1 ? '' : 's'} Available',
              style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              isLow ? '⚠️  Almost full — book quickly!' : 'out of $total total slots',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12),
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 7,
                backgroundColor: Colors.white.withValues(alpha: 0.2),
                valueColor: const AlwaysStoppedAnimation(Colors.white),
              ),
            ),
          ],
        )),
        const SizedBox(width: 16),
        Container(
          width: 60, height: 60,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(16),
          ),
          alignment: Alignment.center,
          child: Text('${(pct * 100).round()}%',
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
        ),
      ]),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label; final int count; final IconData icon; final Color color;
  const _StatTile(this.label, this.count, this.icon, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardNavy,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.inputBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 8),
        Text('$count', style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.w800)),
        Text(label, style: const TextStyle(color: AppColors.textHint, fontSize: 10)),
      ]),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon; final String label; final Color color; final VoidCallback onTap;
  const _QuickAction({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon; final String label;
  const _InfoChip(this.icon, this.label);

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: AppColors.textHint, size: 13),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
    ]);
  }
}

// ── Parking layout map (Home) ───────────────────────────────────────────────
// Live top-down map so users can see availability and that A3 is nearest the
// staircase / mall entrance — handy when booking for elderly passengers.
class _FloorPlanCard extends StatelessWidget {
  final List<ParkingSlot> slots;
  final VoidCallback onBook;
  const _FloorPlanCard({required this.slots, required this.onBook});

  @override
  Widget build(BuildContext context) {
    final statusBySlot = {for (final s in slots) s.slotID: s.statusLabel};
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        decoration: BoxDecoration(
          color: AppColors.cardNavy,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.inputBorder),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.map_outlined, color: AppColors.accentBlue, size: 18),
            const SizedBox(width: 8),
            const Text('Parking Layout',
                style: TextStyle(color: AppColors.white, fontSize: 14, fontWeight: FontWeight.w700)),
            const Spacer(),
            // Quick legend
            _legendDot(AppColors.available, 'Free'),
            const SizedBox(width: 8),
            _legendDot(AppColors.reserved, 'Booked'),
            const SizedBox(width: 8),
            _legendDot(AppColors.occupied, 'Full'),
          ]),
          const SizedBox(height: 8),
          FloorPlanView(statusBySlot: statusBySlot),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: AppColors.available.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.available.withValues(alpha: 0.3)),
            ),
            child: const Row(children: [
              Icon(Icons.elderly_rounded, color: AppColors.available, size: 18),
              SizedBox(width: 8),
              Expanded(child: Text(
                'A3 is the closest bay to the staircase & mall entrance — book it for elderly or less-mobile passengers.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 11, height: 1.3))),
            ]),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onBook,
              icon: const Icon(Icons.bookmark_add_outlined, size: 18, color: AppColors.accentBlue),
              label: const Text('Book a spot',
                  style: TextStyle(color: AppColors.accentBlue, fontWeight: FontWeight.w700)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: AppColors.accentBlue.withValues(alpha: 0.4)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _legendDot(Color c, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 8, height: 8, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
    const SizedBox(width: 3),
    Text(label, style: const TextStyle(color: AppColors.textHint, fontSize: 9, fontWeight: FontWeight.w600)),
  ]);
}



