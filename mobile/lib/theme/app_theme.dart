import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// CreasePoint's brand palette (design.md §3): navy + white for structure,
/// Crease Blue as the one interactive accent, green/amber/red for status.
class AppColors {
  AppColors._();

  static const navy900 = Color(0xFF071A2A);
  static const blue500 = Color(0xFF168AF5);
  static const background = Color(0xFFF7F9FB);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceAlt = Color(0xFFEEF4F8);
  static const textPrimary = Color(0xFF091A29);
  static const textSecondary = Color(0xFF667685);
  static const border = Color(0xFFDCE4EA);
  static const success = Color(0xFF22A06B);
  static const warning = Color(0xFFF5A524);
  static const error = Color(0xFFE5484D);

  /// Distinct from [error] — reserved for the LIVE broadcast indicator
  /// itself (design.md §3's color philosophy), not generic failures.
  static const live = Color(0xFFF04444);

  // Dark / "broadcast mode" tokens (design.md §3), used only by
  // [buildLiveTheme] for the Live console — not a general app dark mode.
  static const navyBackground = navy900;
  static const navySurface = Color(0xFF0D2436);
  static const navySurfaceAlt = Color(0xFF122C40);
  static const navyBorder = Color(0xFF20394C);
  static const navyTextSecondary = Color(0xFFAAB8C4);

  // Aliases for the palette's previous field names, so every screen built
  // against the old UmpireHat theme picks up the new colors automatically
  // without a call-site rewrite everywhere a color is referenced.
  static const primary = blue500;
  static const surfaceMuted = surfaceAlt;
  static const ink = textPrimary;
  static const inkMuted = textSecondary;
}

/// The 4px base grid (design.md §5). `xs`/`sm`/`md`/`lg`/`xl` are kept as
/// aliases onto the numbered scale for the same reason as [AppColors]'s
/// aliases — no call-site rewrite needed across existing screens.
class AppSpacing {
  AppSpacing._();

  static const space1 = 4.0;
  static const space2 = 8.0;
  static const space3 = 12.0;
  static const space4 = 16.0;
  static const space5 = 20.0;
  static const space6 = 24.0;
  static const space8 = 32.0;
  static const space10 = 40.0;
  static const space12 = 48.0;

  static const xs = space2;
  static const sm = space3;
  static const md = space5;
  static const lg = space6;
  static const xl = space10;

  static const screenPadding = EdgeInsets.all(24);
}

/// Corner radii by component (design.md §6).
class AppRadius {
  AppRadius._();

  static const small = 8.0;
  static const control = 12.0;
  static const card = 16.0;
  static const sheet = 24.0;
  static const pill = 999.0;
}

TextTheme _creasePointTextTheme(
  TextTheme base,
  Color primaryTextColor,
  Color secondaryTextColor,
) {
  // Design.md §4's type scale, mapped onto Material's TextTheme slots.
  return base.copyWith(
    displaySmall: TextStyle(
      fontSize: 40,
      fontWeight: FontWeight.w700,
      height: 48 / 40,
      color: primaryTextColor,
    ),
    headlineLarge: TextStyle(
      fontSize: 32,
      fontWeight: FontWeight.w700,
      height: 40 / 32,
      color: primaryTextColor,
    ),
    headlineSmall: TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.w600,
      height: 32 / 24,
      color: primaryTextColor,
    ),
    titleLarge: TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.w600,
      height: 32 / 24,
      color: primaryTextColor,
    ),
    titleMedium: TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w600,
      height: 26 / 18,
      color: primaryTextColor,
    ),
    titleSmall: TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w600,
      height: 26 / 18,
      color: primaryTextColor,
    ),
    bodyLarge: TextStyle(
      fontSize: 16,
      height: 24 / 16,
      color: primaryTextColor,
    ),
    bodyMedium: TextStyle(
      fontSize: 14,
      height: 20 / 14,
      color: secondaryTextColor,
    ),
    bodySmall: TextStyle(
      fontSize: 12,
      height: 16 / 12,
      color: secondaryTextColor,
    ),
    // Overline (§4): 12px/500/uppercase — letter-spacing/case are applied
    // at call sites since TextStyle can't auto-uppercase text.
    labelLarge: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w500,
      height: 16 / 12,
      letterSpacing: 0.96,
      color: secondaryTextColor,
    ),
  );
}

ButtonStyle _primaryButtonStyle() => FilledButton.styleFrom(
  backgroundColor: AppColors.blue500,
  foregroundColor: Colors.white,
  minimumSize: const Size.fromHeight(54),
  padding: const EdgeInsets.symmetric(horizontal: 20),
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(AppRadius.control),
  ),
  textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
);

ThemeData buildAppTheme() {
  final colorScheme =
      ColorScheme.fromSeed(
        seedColor: AppColors.blue500,
        brightness: Brightness.light,
      ).copyWith(
        primary: AppColors.blue500,
        surface: AppColors.surface,
        error: AppColors.error,
      );

  final textTheme = _creasePointTextTheme(
    GoogleFonts.interTextTheme(),
    AppColors.textPrimary,
    AppColors.textSecondary,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: AppColors.background,
    textTheme: textTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: GoogleFonts.inter(
        color: AppColors.textPrimary,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(style: _primaryButtonStyle()),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.blue500,
        minimumSize: const Size.fromHeight(54),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        side: const BorderSide(color: AppColors.blue500, width: 1.4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.blue500,
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceAlt,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        borderSide: const BorderSide(color: AppColors.blue500, width: 1.8),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        borderSide: const BorderSide(color: AppColors.error, width: 1.4),
      ),
      labelStyle: const TextStyle(color: AppColors.textSecondary),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.small * 0.75),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 4),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.border, space: 32),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.blue500,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.blue500.withValues(alpha: 0.12),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: states.contains(WidgetState.selected)
              ? AppColors.blue500
              : AppColors.textSecondary,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? AppColors.blue500
              : AppColors.textSecondary,
        ),
      ),
    ),
  );
}

/// The dark "broadcast mode" theme (design.md §3) — used only for the Live
/// console, not as the app's general dark mode.
ThemeData buildLiveTheme() {
  final colorScheme =
      ColorScheme.fromSeed(
        seedColor: AppColors.blue500,
        brightness: Brightness.dark,
      ).copyWith(
        primary: AppColors.blue500,
        surface: AppColors.navySurface,
        error: AppColors.error,
      );

  final textTheme = _creasePointTextTheme(
    GoogleFonts.interTextTheme(
      ThemeData(brightness: Brightness.dark).textTheme,
    ),
    Colors.white,
    AppColors.navyTextSecondary,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: AppColors.navyBackground,
    textTheme: textTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.navyBackground,
      foregroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: GoogleFonts.inter(
        color: Colors.white,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
    ),
    cardTheme: CardThemeData(
      color: AppColors.navySurface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: const BorderSide(color: AppColors.navyBorder),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(style: _primaryButtonStyle()),
    dividerTheme: const DividerThemeData(
      color: AppColors.navyBorder,
      space: 32,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.blue500,
    ),
  );
}
