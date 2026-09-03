import 'dart:math' as math;
import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// FloorPlanView — detailed top-down car-park map.
// Used by Home (live availability overview) and Navigation (highlight the booked
// spot + draw a route from the entrance gate to it).
//
//   A1   A2   A3                 (A3 = nearest the staircase)
//   ─────────── aisle ───────────
//   [Gate + RFID]          [Stairs / Mall]
// ─────────────────────────────────────────────────────────────────────────────

class FloorPlanView extends StatefulWidget {
  /// slotId -> status ("Available" / "Reserved" / "Occupied").
  final Map<String, String> statusBySlot;

  /// When set (e.g. "slot 3"), that bay is highlighted and a route is drawn.
  final String? targetSlotId;

  /// Draw the dashed route from the entrance to [targetSlotId].
  final bool showRoute;

  const FloorPlanView({
    super.key,
    this.statusBySlot = const {},
    this.targetSlotId,
    this.showRoute = false,
  });

  @override
  State<FloorPlanView> createState() => _FloorPlanViewState();
}

class _FloorPlanViewState extends State<FloorPlanView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final animate = widget.targetSlotId != null;
    Widget paint(double pulse) => CustomPaint(
      painter: _FloorPlanPainter(
        statusBySlot: widget.statusBySlot,
        targetSlotId: widget.targetSlotId,
        showRoute:    widget.showRoute,
        pulse:        pulse,
        accent:    const Color(0xFF1E66E0),  // a touch deeper for light bg
        available: const Color(0xFF16A34A),
        reserved:  const Color(0xFFD97706),
        occupied:  const Color(0xFFDC2626),
        line:      const Color(0xFF9FB0D0),  // grey stall markings
        aisle:     const Color(0xFFE6ECF7),  // light aisle band
        surface:   const Color(0xFFFFFFFF),  // white boxes
        asphalt:   const Color(0xFFEFF4FC),  // light backdrop
        text:      const Color(0xFF0D1B3E),  // dark navy text
        muted:     const Color(0xFF6B7599),
      ),
    );
    return AspectRatio(
      aspectRatio: 1.27,
      child: animate
          ? AnimatedBuilder(animation: _pulse, builder: (_, __) => paint(_pulse.value))
          : paint(1),
    );
  }
}

class _FloorPlanPainter extends CustomPainter {
  final Map<String, String> statusBySlot;
  final String? targetSlotId;
  final bool showRoute;
  final double pulse;
  final Color accent, available, reserved, occupied, line, aisle, surface, asphalt, text, muted;

  static const _order = ['slot 1', 'slot 2', 'slot 3'];
  static const _codes = ['A1', 'A2', 'A3'];

  _FloorPlanPainter({
    required this.statusBySlot,
    required this.targetSlotId,
    required this.showRoute,
    required this.pulse,
    required this.accent,
    required this.available,
    required this.reserved,
    required this.occupied,
    required this.line,
    required this.aisle,
    required this.surface,
    required this.asphalt,
    required this.text,
    required this.muted,
  });

  Color _statusColor(String s) =>
      s == 'Occupied' ? occupied : (s == 'Reserved' ? reserved : available);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;

    // Asphalt backdrop.
    final frame = RRect.fromRectAndRadius(
        Rect.fromLTWH(2, 2, w - 4, h - 4), const Radius.circular(20));
    canvas.drawRRect(frame, Paint()..color = asphalt);
    canvas.drawRRect(frame, Paint()
      ..style = PaintingStyle.stroke..strokeWidth = 2..color = muted.withValues(alpha: 0.35));

    final bayTop = h * 0.10, bayH = h * 0.25, bayW = w * 0.255;
    final cx = [w * 0.195, w * 0.50, w * 0.805];
    final aisleTop = h * 0.49, aisleH = h * 0.11;
    final aisleMid = aisleTop + aisleH / 2;
    final entranceC = Offset(w * 0.215, h * 0.76);
    final stairsC   = Offset(w * 0.80, h * 0.76);
    final targetIdx = targetSlotId == null ? -1 : _order.indexOf(targetSlotId!);

    // ── Bays ─────────────────────────────────────────────────────────
    for (int i = 0; i < 3; i++) {
      final isTarget = i == targetIdx;
      final status   = statusBySlot[_order[i]] ?? '';
      final col = isTarget ? accent : (status.isEmpty ? muted : _statusColor(status));
      final rect = Rect.fromCenter(
          center: Offset(cx[i], bayTop + bayH / 2), width: bayW, height: bayH);
      final rr = RRect.fromRectAndRadius(rect, const Radius.circular(13));

      canvas.drawRRect(rr, Paint()
        ..color = col.withValues(alpha: isTarget ? 0.16 + 0.16 * pulse : 0.13));
      canvas.drawRRect(rr, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = isTarget ? 3 : 2
        ..color = col.withValues(alpha: isTarget ? 0.75 + 0.25 * pulse : 0.6));

      // Painted stall lines at the bay opening (top corners).
      final lp = Paint()..strokeWidth = 3..color = line.withValues(alpha: 0.35);
      canvas.drawLine(Offset(rect.left + 16, rect.top),
          Offset(rect.left + 16, rect.top + bayH * 0.28), lp);
      canvas.drawLine(Offset(rect.right - 16, rect.top),
          Offset(rect.right - 16, rect.top + bayH * 0.28), lp);

      // Icon per state.
      final iconC = Offset(cx[i], bayTop + bayH * 0.30);
      if (isTarget) {
        _pin(canvas, iconC, accent);
      } else if (status == 'Occupied') {
        _car(canvas, iconC, occupied);
      } else if (status == 'Reserved') {
        _clock(canvas, iconC, reserved);
      } else {
        _check(canvas, iconC, available);
      }

      _text(canvas, _codes[i], Offset(cx[i], bayTop + bayH * 0.62),
          color: col, size: bayH * 0.22, bold: true);
      _text(canvas, isTarget ? 'YOUR SPOT' : (status.isEmpty ? '' : status.toUpperCase()),
          Offset(cx[i], bayTop + bayH * 0.84), color: col, size: bayH * 0.085, bold: true);
    }

    // ── "Nearest stairs" tag under A3 ────────────────────────────────
    final tagY = bayTop + bayH + h * 0.04;
    final tag = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx[2], tagY), width: w * 0.27, height: h * 0.05),
        const Radius.circular(20));
    canvas.drawRRect(tag, Paint()..color = available.withValues(alpha: 0.14));
    canvas.drawRRect(tag, Paint()
      ..style = PaintingStyle.stroke..strokeWidth = 1.2
      ..color = available.withValues(alpha: 0.5));
    _text(canvas, '♿  NEAREST THE STAIRS', Offset(cx[2], tagY),
        color: available, size: h * 0.022, bold: true);

    // ── Aisle ────────────────────────────────────────────────────────
    final aisleRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.05, aisleTop, w * 0.90, aisleH), const Radius.circular(12));
    canvas.drawRRect(aisleRect, Paint()..color = aisle);
    final dash = Paint()
      ..strokeWidth = 3..color = muted.withValues(alpha: 0.5)..strokeCap = StrokeCap.round;
    _dashed(canvas, Offset(w * 0.08, aisleMid), Offset(w * 0.92, aisleMid), dash,
        dash: 14, gap: 12);
    final chev = Paint()
      ..style = PaintingStyle.stroke..strokeWidth = 3
      ..color = muted.withValues(alpha: 0.55)
      ..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round;
    for (final fx in [0.34, 0.52, 0.70]) {
      final x = w * fx;
      canvas.drawPath(Path()
        ..moveTo(x, aisleMid - 7)..lineTo(x + 10, aisleMid)..lineTo(x, aisleMid + 7), chev);
    }

    // ── Entrance (gate + RFID) ───────────────────────────────────────
    _box(canvas, entranceC, w * 0.31, h * 0.20);
    _text(canvas, 'ENTRANCE', Offset(entranceC.dx, entranceC.dy - h * 0.072),
        color: muted, size: h * 0.022, bold: true);
    _barrier(canvas, Offset(entranceC.dx - w * 0.10, entranceC.dy + h * 0.06), w * 0.16);
    _rfid(canvas, Offset(entranceC.dx + w * 0.10, entranceC.dy + h * 0.01), w * 0.05);

    // ── Staircase / Mall ─────────────────────────────────────────────
    _box(canvas, stairsC, w * 0.31, h * 0.20);
    _text(canvas, 'STAIRS · MALL', Offset(stairsC.dx, stairsC.dy - h * 0.072),
        color: muted, size: h * 0.022, bold: true);
    _stairs(canvas, Offset(stairsC.dx - w * 0.07, stairsC.dy + h * 0.055), w * 0.11);
    _text(canvas, '♿', Offset(stairsC.dx + w * 0.085, stairsC.dy + h * 0.01),
        color: available, size: h * 0.05, bold: true);

    // ── Route entrance → aisle → target column → bay ─────────────────
    if (showRoute && targetIdx >= 0) {
      final tx = cx[targetIdx];
      final bayBottom = bayTop + bayH;
      final pe = Offset(entranceC.dx, entranceC.dy - h * 0.10);
      final pts = [
        pe, Offset(entranceC.dx, aisleMid),
        Offset(tx, aisleMid), Offset(tx, bayBottom + 6),
      ];
      final glow = Paint()
        ..style = PaintingStyle.stroke..strokeWidth = 13
        ..color = accent.withValues(alpha: 0.22)
        ..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round;
      final solid = Paint()
        ..style = PaintingStyle.stroke..strokeWidth = 4
        ..color = accent..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round;
      final path = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (final p in pts.skip(1)) { path.lineTo(p.dx, p.dy); }
      canvas.drawPath(path, glow);
      for (int i = 0; i < pts.length - 1; i++) {
        _dashed(canvas, pts[i], pts[i + 1], solid, dash: 12, gap: 9);
      }
      _arrow(canvas, Offset(tx, bayBottom + 4), const Offset(0, -1), accent);
    }

    // ── Legend ───────────────────────────────────────────────────────
    final ly = h * 0.955;
    double lx = w * 0.05;
    void item(Color c, String label, {bool isLine = false}) {
      if (isLine) {
        _dashed(canvas, Offset(lx, ly), Offset(lx + 22, ly),
            Paint()..strokeWidth = 4..color = c, dash: 7, gap: 5);
        lx += 28;
      } else {
        canvas.drawCircle(Offset(lx + 5, ly), 5, Paint()..color = c);
        lx += 14;
      }
      _textL(canvas, label, Offset(lx, ly), color: muted, size: h * 0.022);
      lx += label.length * (h * 0.0125) + w * 0.03;
    }
    item(available, 'Free');
    item(reserved, 'Booked');
    item(occupied, 'Occupied');
    item(accent, 'Your spot');
    item(accent, 'Route', isLine: true);
  }

  // ── Icons ──────────────────────────────────────────────────────────
  void _car(Canvas c, Offset o, Color col) {
    final body = RRect.fromRectAndRadius(
        Rect.fromCenter(center: o, width: 46, height: 28), const Radius.circular(7));
    c.drawRRect(body, Paint()..color = col.withValues(alpha: 0.9));
    c.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(center: o, width: 28, height: 16), const Radius.circular(4)),
        Paint()..color = Colors.white.withValues(alpha: 0.3));
  }

  void _check(Canvas c, Offset o, Color col) {
    c.drawCircle(o, 15, Paint()
      ..style = PaintingStyle.stroke..strokeWidth = 3..color = col);
    final p = Paint()
      ..style = PaintingStyle.stroke..strokeWidth = 3..color = col
      ..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round;
    c.drawPath(Path()
      ..moveTo(o.dx - 7, o.dy)..lineTo(o.dx - 1, o.dy + 6)..lineTo(o.dx + 8, o.dy - 6), p);
  }

  void _clock(Canvas c, Offset o, Color col) {
    c.drawCircle(o, 15, Paint()
      ..style = PaintingStyle.stroke..strokeWidth = 3..color = col);
    final p = Paint()
      ..style = PaintingStyle.stroke..strokeWidth = 3..color = col..strokeCap = StrokeCap.round;
    c.drawLine(o, Offset(o.dx, o.dy - 8), p);
    c.drawLine(o, Offset(o.dx + 6, o.dy + 2), p);
  }

  void _pin(Canvas c, Offset o, Color col) {
    final path = Path()
      ..moveTo(o.dx, o.dy - 18)
      ..cubicTo(o.dx + 12, o.dy - 18, o.dx + 18, o.dy - 9, o.dx + 18, o.dy - 2)
      ..cubicTo(o.dx + 18, o.dy + 10, o.dx, o.dy + 22, o.dx, o.dy + 22)
      ..cubicTo(o.dx, o.dy + 22, o.dx - 18, o.dy + 10, o.dx - 18, o.dy - 2)
      ..cubicTo(o.dx - 18, o.dy - 9, o.dx - 12, o.dy - 18, o.dx, o.dy - 18)
      ..close();
    c.drawPath(path, Paint()..color = col);
    c.drawCircle(Offset(o.dx, o.dy - 1), 6, Paint()..color = Colors.white);
  }

  void _barrier(Canvas c, Offset postBase, double boomLen) {
    // Post.
    c.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(postBase.dx - 6, postBase.dy - 30, 12, 40), const Radius.circular(3)),
        Paint()..color = muted);
    // Raised striped boom.
    c.save();
    c.translate(postBase.dx, postBase.dy - 26);
    c.rotate(-32 * math.pi / 180);
    final boomRR =
        RRect.fromRectAndRadius(Rect.fromLTWH(0, -6, boomLen, 12), const Radius.circular(3));
    c.drawRRect(boomRR, Paint()..color = Colors.white);
    final stripe = Paint()..color = occupied;
    final seg = boomLen / 5;
    for (int i = 0; i < 5; i += 2) {
      c.drawRect(Rect.fromLTWH(i * seg, -6, seg, 12), stripe);
    }
    c.drawRRect(boomRR, Paint()                       // outline so it shows on white
      ..style = PaintingStyle.stroke..strokeWidth = 1.4..color = muted.withValues(alpha: 0.6));
    c.restore();
  }

  void _rfid(Canvas c, Offset o, double s) {
    final box = RRect.fromRectAndRadius(
        Rect.fromCenter(center: o, width: s, height: s * 1.25), const Radius.circular(6));
    c.drawRRect(box, Paint()..color = accent.withValues(alpha: 0.18));
    c.drawRRect(box, Paint()
      ..style = PaintingStyle.stroke..strokeWidth = 2..color = accent);
    final p = Paint()
      ..style = PaintingStyle.stroke..strokeWidth = 2.4..color = accent..strokeCap = StrokeCap.round;
    c.drawArc(Rect.fromCircle(center: Offset(o.dx - s * 0.18, o.dy + s * 0.12), radius: s * 0.30),
        -1.2, 1.4, false, p);
    c.drawArc(Rect.fromCircle(center: Offset(o.dx - s * 0.18, o.dy + s * 0.12), radius: s * 0.15),
        -1.2, 1.4, false, p);
  }

  void _stairs(Canvas c, Offset base, double s) {
    final p = Paint()
      ..style = PaintingStyle.stroke..strokeWidth = 3..color = available
      ..strokeJoin = StrokeJoin.round..strokeCap = StrokeCap.round;
    final step = s / 4;
    final path = Path()..moveTo(base.dx, base.dy);
    for (int i = 0; i < 4; i++) {
      path.lineTo(base.dx + i * step, base.dy - i * step);
      path.lineTo(base.dx + (i + 1) * step, base.dy - i * step);
    }
    c.drawPath(path, p);
  }

  // ── Primitives ──────────────────────────────────────────────────────
  void _box(Canvas c, Offset center, double w, double h) {
    final rr = RRect.fromRectAndRadius(
        Rect.fromCenter(center: center, width: w, height: h), const Radius.circular(12));
    c.drawRRect(rr, Paint()..color = surface);
    c.drawRRect(rr, Paint()
      ..style = PaintingStyle.stroke..strokeWidth = 1.4..color = line.withValues(alpha: 0.18));
  }

  void _dashed(Canvas c, Offset a, Offset b, Paint p, {double dash = 9, double gap = 6}) {
    final total = (b - a).distance;
    if (total == 0) return;
    final dir = (b - a) / total;
    double d = 0;
    while (d < total) {
      c.drawLine(a + dir * d, a + dir * math.min(d + dash, total), p);
      d += dash + gap;
    }
  }

  void _arrow(Canvas c, Offset tip, Offset dir, Color col) {
    const len = 13.0;
    final base = tip - dir * len;
    final perp = Offset(-dir.dy, dir.dx);
    c.drawPath(Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo((base + perp * 7).dx, (base + perp * 7).dy)
      ..lineTo((base - perp * 7).dx, (base - perp * 7).dy)
      ..close(), Paint()..color = col);
  }

  void _text(Canvas c, String s, Offset center,
      {required Color color, required double size, bool bold = false}) {
    if (s.isEmpty) return;
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(
        color: color, fontSize: size, fontWeight: bold ? FontWeight.w800 : FontWeight.w500)),
      textAlign: TextAlign.center, textDirection: TextDirection.ltr)..layout();
    tp.paint(c, center - Offset(tp.width / 2, tp.height / 2));
  }

  // Left-aligned text (for legend).
  void _textL(Canvas c, String s, Offset left,
      {required Color color, required double size}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(
        color: color, fontSize: size, fontWeight: FontWeight.w600)),
      textDirection: TextDirection.ltr)..layout();
    tp.paint(c, Offset(left.dx, left.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(_FloorPlanPainter old) =>
      old.pulse != pulse ||
      old.targetSlotId != targetSlotId ||
      old.statusBySlot.length != statusBySlot.length;
}
