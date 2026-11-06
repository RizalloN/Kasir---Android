import 'package:flutter/material.dart';
import '../models/user_role.dart';

class AppTheme {
  // Brand Core - Warm Artisan Espresso & Roasted Crema
  static const Color espressoDark = Color(0xFF140D09); // Deep Roast Canvas (Login/Splash)
  static const Color primary = Color(0xFF21150F); // Signature Roasted Espresso
  static const Color primaryLight = Color(0xFF3A261B); // Warm Mocha

  // Brand Accents - Caramel Copper & Roaster Gold
  static const Color accentAmber = Color(0xFFB45309); // Rich Caramel Copper (WCAG AA contrast)
  static const Color accentGold = Color(0xFFD4AF37); // Artisan Emblem Gold
  static const Color accentAmberLight = Color(0xFFFEF3C7); // Soft Crema Tint
  static const Color accentCopperSoft = Color(0xFFFDF3E7); // Warm Latte Foam

  // Neutral Surfaces - Warm Alabaster & Sandstone (Tinted from Espresso Hue)
  static const Color surfaceLight = Color(0xFFFAF7F2); // Oat Milk Canvas
  static const Color surfaceSubtle = Color(0xFFF2ECE4); // Secondary Panel / Input Fill
  static const Color cardBg = Color(0xFFFFFFFF); // Elevated Surface
  static const Color borderSubtle = Color(0xFFE5DDD3); // 1px Warm Hairline
  static const Color borderStrong = Color(0xFFD2C5B6); // Emphasized Control Border

  // Typography Colors - Warm Umber Hierarchy (Contrast >= 4.5:1)
  static const Color textMain = Color(0xFF1C130D); // Primary Ink (>14:1)
  static const Color textSecondary = Color(0xFF4E3F35); // Secondary Copy (>8:1)
  static const Color textMuted = Color(0xFF6F5E53); // Supporting Meta (>5.2:1)

  // Semantic Status Tokens
  static const Color successGreen = Color(0xFF15803D);
  static const Color successGreenLight = Color(0xFFDCFCE7);
  static const Color warningOrange = Color(0xFFC2410C);
  static const Color warningLight = Color(0xFFFFEDD5);
  static const Color dangerRed = Color(0xFFDC2626);
  static const Color dangerLight = Color(0xFFFEE2E2);

  // Role Semantic Tokens (Harmonious Hospitality Palette)
  static const Color roleBarista = Color(0xFFB45309); // Cinnamon Crema
  static const Color roleBaristaBg = Color(0xFFFEF3C7);
  static const Color roleAdmin = Color(0xFF0F766E); // Botanical Teal
  static const Color roleAdminBg = Color(0xFFCCFBF1);
  static const Color ownerIndigo = Color(0xFF78350F); // Reserve Roaster Bronze (Legacy alias preserved)
  static const Color ownerIndigoLight = Color(0xFFFEF3C7);
  static const Color roleOwner = Color(0xFF6D3B1A); // Royal Reserve Espresso-Gold
  static const Color roleOwnerBg = Color(0xFFF7E8D8);

  // Tabular numerals for prices, counters, and metrics
  static const List<FontFeature> tabularFigures = [FontFeature.tabularFigures()];

  static Color roleColor(UserRole role) {
    switch (role) {
      case UserRole.barista:
        return roleBarista;
      case UserRole.admin:
        return roleAdmin;
      case UserRole.owner:
        return roleOwner;
    }
  }

  static Color roleBg(UserRole role) {
    switch (role) {
      case UserRole.barista:
        return roleBaristaBg;
      case UserRole.admin:
        return roleAdminBg;
      case UserRole.owner:
        return roleOwnerBg;
    }
  }

  static IconData roleIcon(UserRole role) {
    switch (role) {
      case UserRole.barista:
        return Icons.local_cafe_rounded;
      case UserRole.admin:
        return Icons.storefront_rounded;
      case UserRole.owner:
        return Icons.workspace_premium_rounded;
    }
  }

  static void showToast(
    BuildContext context, {
    required String message,
    bool isError = false,
    bool isWarning = false,
    IconData? icon,
    Duration duration = const Duration(seconds: 2),
  }) {
    if (!context.mounted) return;
    final Color bg = isError
        ? dangerRed
        : (isWarning ? warningOrange : primary);
    final IconData resolvedIcon = icon ??
        (isError
            ? Icons.error_outline_rounded
            : (isWarning ? Icons.warning_amber_rounded : Icons.check_circle_outline_rounded));

    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: bg,
        elevation: 4,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: duration,
        content: Row(
          children: [
            Icon(resolvedIcon, color: Colors.white, size: 19),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static ThemeData get lightTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.light,
      primary: primary,
      onPrimary: Colors.white,
      secondary: accentAmber,
      onSecondary: Colors.white,
      surface: cardBg,
      onSurface: textMain,
      error: dangerRed,
      onError: Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: surfaceLight,
      fontFamily: 'Roboto',
      dividerColor: borderSubtle,
      splashColor: accentAmber.withValues(alpha: 0.08),
      highlightColor: accentAmber.withValues(alpha: 0.04),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: accentAmber,
        selectionColor: accentAmber.withValues(alpha: 0.22),
        selectionHandleColor: accentAmber,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: cardBg,
        foregroundColor: textMain,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        shape: Border(
          bottom: BorderSide(color: borderSubtle, width: 1),
        ),
        titleTextStyle: TextStyle(
          color: textMain,
          fontSize: 17,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
      ),
      cardTheme: CardThemeData(
        color: cardBg,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: borderSubtle, width: 1),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: cardBg,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: borderSubtle,
        thickness: 1,
        space: 1,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: borderSubtle,
          disabledForegroundColor: textMuted,
          elevation: 0,
          minimumSize: const Size(48, 46),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.1,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textMain,
          minimumSize: const Size(48, 46),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          side: const BorderSide(color: borderStrong, width: 1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: cardBg,
        selectedColor: primary,
        disabledColor: surfaceSubtle,
        side: const BorderSide(color: borderSubtle, width: 1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        labelStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: textMain,
        ),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: primary,
        unselectedLabelColor: textMuted,
        indicatorColor: accentAmber,
        dividerColor: borderSubtle,
        labelStyle: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.1,
        ),
        unselectedLabelStyle: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceSubtle,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        hintStyle: const TextStyle(
          fontSize: 13,
          color: textMuted,
          fontWeight: FontWeight.w400,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: borderSubtle, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: borderSubtle, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: accentAmber, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: dangerRed, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: dangerRed, width: 1.5),
        ),
      ),
    );
  }
}
