import 'package:flutter/material.dart';
import '../appsColor/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AppLogo
// Shows the ParkMe logo image (assets/icons/parkme_logo.png). If that file is
// missing it falls back to the built-in "ParkMe" wordmark, so the app never
// breaks before you add the image.
//
// The logo image is at parkme_v2/images/Apps Logo.png (declared in pubspec.yaml).
// Use a TRANSPARENT PNG so it looks right on the dark headers.
// ─────────────────────────────────────────────────────────────────────────────

class AppLogo extends StatelessWidget {
  final double height;
  final bool onDark; // text colour for the fallback wordmark

  const AppLogo({super.key, this.height = 34, this.onDark = true});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'images/Apps Logo.png',
      height: height,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      errorBuilder: (_, __, ___) => _wordmark(),
    );
  }

  Widget _wordmark() {
    final base = onDark ? AppColors.white : AppColors.primaryNavy;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        padding: EdgeInsets.all(height * 0.16),
        decoration: BoxDecoration(
          color: AppColors.accentBlue.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(height * 0.28),
          border: Border.all(color: AppColors.accentBlue.withValues(alpha: 0.3)),
        ),
        child: Icon(Icons.local_parking_rounded,
            color: AppColors.accentBlue, size: height * 0.62),
      ),
      SizedBox(width: height * 0.26),
      RichText(text: TextSpan(children: [
        TextSpan(text: 'Park', style: TextStyle(
            color: base, fontSize: height * 0.60, fontWeight: FontWeight.w800)),
        TextSpan(text: 'Me', style: TextStyle(
            color: AppColors.accentBlue, fontSize: height * 0.60, fontWeight: FontWeight.w800)),
      ])),
    ]);
  }
}
