import 'package:flutter/material.dart';

class AppColors {
  // ── Core brand (LIGHT THEME) ────────────────────────────────────────────
  // The "navy" names are kept so existing screens don't need renaming — they
  // now hold light-blue surface colors.
  static const Color primaryNavy      = Color(0xFFEAF2FD);  // page background
  static const Color secondaryNavy    = Color(0xFFDCEAFB);  // gradient mid
  static const Color cardNavy         = Color(0xFFFFFFFF);  // cards (white)
  static const Color accentBlue       = Color(0xFF1E90FF);
  static const Color accentBlueDark   = Color(0xFF1565C0);
  static const Color accentBlueLight  = Color(0xFFE3F0FF);

  // ── Text (dark, for light surfaces) ──────────────────────────────────────
  static const Color white            = Color(0xFFFFFFFF);  // genuine white (on blue)
  static const Color offWhite         = Color(0xFFF0F4FF);
  static const Color textPrimary      = Color(0xFF0D1B3E);  // dark navy text
  static const Color textSecondary    = Color(0xFF49587C);
  static const Color textHint         = Color(0xFF8793AE);

  // ── Inputs ──────────────────────────────────────────────────────────────
  static const Color inputFill        = Color(0xFFF4F8FF);
  static const Color inputBorder      = Color(0xFFCBD8EE);
  static const Color inputBorderFocus = Color(0xFF1E90FF);
  static const Color divider          = Color(0xFFDCE6F5);

  // ── Semantic / slot status ───────────────────────────────────────────────
  static const Color success          = Color(0xFF22C55E);
  static const Color error            = Color(0xFFEF4444);
  static const Color available        = Color(0xFF22C55E);   // green  – free slot
  static const Color reserved         = Color(0xFFF59E0B);   // yellow  – booking 
  static const Color occupied         = Color(0xFFEF4444);   // red    – the place that showed have object being there
  static const Color booked           = Color(0xFFF59E0B);   // alias for reserved

  // ── Social auth ─────────────────────────────────────────────────────────
  static const Color googleRed        = Color(0xFFDB4437);
  static const Color facebookBlue     = Color(0xFF1877F2);
  static const Color appleBlack       = Color(0xFF1C1C1E);
}

class AppTheme {
  static ThemeData get theme => ThemeData(
    useMaterial3: true,
    fontFamily: 'Inter',
    scaffoldBackgroundColor: AppColors.primaryNavy,
    colorScheme: const ColorScheme.light(
      primary:   AppColors.accentBlue,
      secondary: AppColors.accentBlueDark,
      surface:   AppColors.cardNavy,
      onSurface: AppColors.textPrimary,
      error:     AppColors.error,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.inputFill,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.inputBorder, width: 1.2),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.inputBorder, width: 1.2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.inputBorderFocus, width: 1.8),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.error, width: 1.2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.error, width: 1.8),
      ),
      hintStyle:        const TextStyle(color: AppColors.textHint, fontSize: 14),
      labelStyle:       const TextStyle(color: AppColors.textSecondary, fontSize: 14),
      prefixIconColor:  AppColors.textHint,
      suffixIconColor:  AppColors.textHint,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.accentBlue,
        foregroundColor: AppColors.white,
        minimumSize:     const Size(double.infinity, 54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 0.3),
        elevation: 0,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.accentBlue,
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      iconTheme:        IconThemeData(color: AppColors.textPrimary),
      titleTextStyle:   TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w600),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor:    AppColors.cardNavy,
      indicatorColor:     AppColors.accentBlue,
      labelTextStyle:     WidgetStateProperty.resolveWith((states) => TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: states.contains(WidgetState.selected)
            ? AppColors.accentBlue
            : AppColors.textHint,
      )),
    ),
  );
}
