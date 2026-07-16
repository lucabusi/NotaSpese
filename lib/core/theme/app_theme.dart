import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design System tokens (Specifiche.md §Design System, mockup "Blu professionale").
abstract final class AppColors {
  static const Color primary = Color(0xFF2563EB);
  static const Color primaryContainer = Color(0xFFEAF0FE);
  static const Color background = Color(0xFFF4F6FA);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color onSurface = Color(0xFF0F1729);
  static const Color textSecondary = Color(0xFF5B6675);
  static const Color textSecondaryLight = Color(0xFF8A94A3);
  static const Color textTertiary = Color(0xFF97A1B0);
  static const Color textTertiaryLight = Color(0xFFA3ACBA);
  static const Color outline = Color(0xFFEDF0F5);
  static const Color outlineStrong = Color(0xFFDFE4EC);
  static const Color success = Color(0xFF13935A);
  static const Color successContainer = Color(0xFFE9F7EF);
  static const Color archivio = Color(0xFF8A8030);
  static const Color archivioContainer = Color(0xFFFBF3DA);
  static const Color surfaceDark = Color(0xFF0A0C11);
}

/// Corner radius tokens (card 16-18, buttons/fields 13-14, chip 12, sheet 26).
abstract final class AppRadius {
  static const double card = 16;
  static const double button = 14;
  static const double field = 13;
  static const double chip = 12;
  static const double bottomSheet = 26;
}

/// Material 3 theme: Plus Jakarta Sans + Material Symbols Rounded.
abstract final class AppTheme {
  static ThemeData light() {
    final ColorScheme scheme =
        ColorScheme.fromSeed(seedColor: AppColors.primary).copyWith(
      primary: AppColors.primary,
      primaryContainer: AppColors.primaryContainer,
      onPrimaryContainer: AppColors.primary,
      surface: AppColors.surface,
      onSurface: AppColors.onSurface,
      onSurfaceVariant: AppColors.textSecondary,
      outline: AppColors.outlineStrong,
      outlineVariant: AppColors.outline,
    );

    final TextTheme textTheme =
        GoogleFonts.plusJakartaSansTextTheme().apply(
      bodyColor: AppColors.onSurface,
      displayColor: AppColors.onSurface,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      textTheme: textTheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.onSurface,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: const BorderSide(color: AppColors.outline),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.field),
          borderSide: const BorderSide(color: AppColors.outlineStrong),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.field),
          borderSide: const BorderSide(color: AppColors.outlineStrong),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.chip),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.bottomSheet),
          ),
        ),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.primaryContainer,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        shape: CircleBorder(),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.surfaceDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.field),
        ),
      ),
    );
  }
}

/// Tabular figures for amounts (importi con cifre a larghezza fissa).
const List<FontFeature> amountFontFeatures = [FontFeature.tabularFigures()];
