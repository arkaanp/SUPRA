import 'package:flutter/material.dart';

/// Supra design tokens.
///
/// Brand color is a deep teal (air/sky). AQI, traffic and rain use semantic
/// colors so a commuter can read conditions at a glance.
class SupraTheme {
  static const Color brand = Color(0xFF0F766E);
  static const Color brandDark = Color(0xFF0B5F63);
  static const Color surface = Color(0xFFF7F9FB);
  static const Color onSurface = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF64748B);
  static const Color divider = Color(0xFFE2E8F0);

  // AQI semantic colors (US EPA bands).
  static const Color aqiGood = Color(0xFF22C55E);
  static const Color aqiModerate = Color(0xFFEAB308);
  static const Color aqiUsg = Color(0xFFF97316);
  static const Color aqiUnhealthy = Color(0xFFEF4444);
  static const Color aqiVeryUnhealthy = Color(0xFF8B5CF6);
  static const Color aqiHazardous = Color(0xFF7F1D1D);

  // Traffic / rain semantic colors.
  static const Color trafficFree = Color(0xFF22C55E);
  static const Color trafficModerate = Color(0xFFF59E0B);
  static const Color trafficHeavy = Color(0xFFEF4444);
  static const Color rain = Color(0xFF3B82F6);

  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: brand,
        primary: brand,
        surface: surface,
      ),
      scaffoldBackgroundColor: surface,
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        foregroundColor: onSurface,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: brand,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: brand),
        ),
        hintStyle: const TextStyle(color: textSecondary, fontSize: 15),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        type: BottomNavigationBarType.fixed,
        selectedItemColor: brand,
        unselectedItemColor: textSecondary,
        elevation: 0,
        backgroundColor: Colors.white,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return brand;
          return const Color(0xFFCBD5E1);
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return brand.withValues(alpha: 0.35);
          }
          return const Color(0xFFE2E8F0);
        }),
      ),
    );
  }
}
