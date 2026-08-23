import 'package:flutter/material.dart';

// ============================================
// STSYS Dark Theme — Figma-based design tokens
// ============================================

class StsysTheme {
  // --- Color Palette (from Figma) ---
  static const Color background = Color(0xFF131313);
  static const Color surfaceContainerLowest = Color(0xFF0E0E0E);
  static const Color surfaceContainerLow = Color(0xFF1C1B1B);
  static const Color surfaceContainer = Color(0xFF201F1F);
  static const Color surfaceContainerHigh = Color(0xFF2A2A2A);
  static const Color surfaceContainerHighest = Color(0xFF353534);
  static const Color surfaceBright = Color(0xFF393939);
  static const Color surfaceDim = Color(0xFF131313);

  static const Color primary = Color(0xFFFFB693);
  static const Color primaryContainer = Color(0xFFFF6B00);
  static const Color primaryFixed = Color(0xFFFFDBCC);
  static const Color primaryFixedDim = Color(0xFFFFB693);
  static const Color onPrimary = Color(0xFF561F00);
  static const Color onPrimaryContainer = Color(0xFF572000);

  static const Color secondary = Color(0xFF8BCEFF);
  static const Color secondaryContainer = Color(0xFF0CB3FF);
  static const Color secondaryFixed = Color(0xFFC9E6FF);
  static const Color secondaryFixedDim = Color(0xFF8BCEFF);
  static const Color onSecondary = Color(0xFF00344E);
  static const Color onSecondaryContainer = Color(0xFF004261);

  static const Color tertiary = Color(0xFF9CCAff);
  static const Color tertiaryContainer = Color(0xFF059EFF);
  static const Color tertiaryFixed = Color(0xFFD0E4FF);
  static const Color tertiaryFixedDim = Color(0xFF9CCAff);
  static const Color onTertiary = Color(0xFF003257);
  static const Color onTertiaryContainer = Color(0xFF003357);
  static const Color onTertiaryFixed = Color(0xFF001D35);
  static const Color onTertiaryFixedVariant = Color(0xFF00497B);

  static const Color error = Color(0xFFFFB4AB);
  static const Color errorContainer = Color(0xFF93000A);
  static const Color onError = Color(0xFF690005);
  static const Color onErrorContainer = Color(0xFFFFDAD6);

  static const Color surface = Color(0xFF131313);
  static const Color onSurface = Color(0xFFE5E2E1);
  static const Color surfaceVariant = Color(0xFF353534);
  static const Color onSurfaceVariant = Color(0xFFE2BFB0);
  static const Color surfaceTint = Color(0xFFFFB693);
  static const Color inverseSurface = Color(0xFFE5E2E1);
  static const Color onInverseSurface = Color(0xFF313030);
  static const Color inversePrimary = Color(0xFFA04100);

  static const Color outline = Color(0xFFA98A7D);
  static const Color outlineVariant = Color(0xFF5A4136);

  // --- Tactical Gradient ---
  static const LinearGradient tacticalGradient = LinearGradient(
    colors: [primary, primaryContainer],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // --- Score Colors ---
  static Color getScoreColor(double score) {
    if (score >= 95) return const Color(0xFFFFD700); // Elite - Gold
    if (score >= 85) return const Color(0xFF4CAF50); // Expert - Green
    if (score >= 70) return const Color(0xFF2196F3); // Advanced - Blue
    if (score >= 50) return const Color(0xFFFF9800); // Intermediate - Orange
    return const Color(0xFFF44336); // Beginner - Red
  }

  // --- Dark Theme Data ---
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      colorScheme: const ColorScheme.dark(
        brightness: Brightness.dark,
        primary: primary,
        onPrimary: onPrimary,
        primaryContainer: primaryContainer,
        onPrimaryContainer: onPrimaryContainer,
        secondary: secondary,
        onSecondary: onSecondary,
        secondaryContainer: secondaryContainer,
        onSecondaryContainer: onSecondaryContainer,
        tertiary: tertiary,
        onTertiary: onTertiary,
        tertiaryContainer: tertiaryContainer,
        onTertiaryContainer: onTertiaryContainer,
        error: error,
        onError: onError,
        errorContainer: errorContainer,
        onErrorContainer: onErrorContainer,
        surface: surface,
        onSurface: onSurface,
        surfaceContainerHighest: surfaceContainerHighest,
        surfaceContainerHigh: surfaceContainerHigh,
        surfaceContainer: surfaceContainer,
        surfaceContainerLow: surfaceContainerLow,
        surfaceContainerLowest: surfaceContainerLowest,
        outline: outline,
        outlineVariant: outlineVariant,
        inverseSurface: inverseSurface,
        onInverseSurface: onInverseSurface,
        shadow: Colors.black,
        scrim: Colors.black,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: onSurface,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'Manrope',
          fontSize: 20,
          fontWeight: FontWeight.w900,
          color: primary,
          letterSpacing: -0.5,
        ),
      ),
      cardTheme: CardThemeData(
        color: surfaceContainerLow,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: background,
        selectedItemColor: primary,
        unselectedItemColor: Color(0xFFE5E2E1),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryContainer,
          foregroundColor: onPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
        ),
      ),
      iconTheme: const IconThemeData(
        color: onSurface,
        size: 24,
      ),
      dividerTheme: DividerThemeData(
        color: outlineVariant.withValues(alpha: 0.3),
        thickness: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceContainerHighest,
        contentTextStyle: const TextStyle(color: onSurface),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        behavior: SnackBarBehavior.floating,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: onSurface,
        unselectedLabelColor: Color(0xFFE5E2E1),
      ),
    );
  }
}

// ============================================
// Reusable Text Styles
// ============================================
class StsysText {
  // Headlines
  static const headline = TextStyle(
    fontFamily: 'Manrope',
    fontWeight: FontWeight.w900,
    color: StsysTheme.onSurface,
  );

  static const headlineBold = TextStyle(
    fontFamily: 'Manrope',
    fontWeight: FontWeight.w800,
    color: StsysTheme.onSurface,
  );

  // Body
  static const body = TextStyle(
    fontFamily: 'Inter',
    fontWeight: FontWeight.w400,
    color: StsysTheme.onSurface,
  );

  static const bodyBold = TextStyle(
    fontFamily: 'Inter',
    fontWeight: FontWeight.w600,
    color: StsysTheme.onSurface,
  );

  // Labels (uppercase, tracking)
  static const label = TextStyle(
    fontFamily: 'Inter',
    fontWeight: FontWeight.w500,
    fontSize: 10,
    letterSpacing: 1.5,
    color: StsysTheme.onSurfaceVariant,
  );

  static const labelBold = TextStyle(
    fontFamily: 'Inter',
    fontWeight: FontWeight.w700,
    fontSize: 10,
    letterSpacing: 1.5,
    color: StsysTheme.onSurfaceVariant,
  );

  // Score display
  static TextStyle scoreDisplay(double score) {
    return TextStyle(
      fontFamily: 'Manrope',
      fontWeight: FontWeight.w900,
      fontSize: 72,
      color: StsysTheme.getScoreColor(score),
    );
  }
}

// ============================================
// Reusable Surface Container Cards
// ============================================
class SurfaceCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final double borderRadius;
  final Color? backgroundColor;
  final Color? borderColor;
  final double borderWidth;
  final VoidCallback? onTap;

  const SurfaceCard({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius = 12,
    this.backgroundColor,
    this.borderColor,
    this.borderWidth = 0,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: backgroundColor ?? StsysTheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(borderRadius),
        border: borderColor != null
            ? Border.all(color: borderColor!, width: borderWidth)
            : null,
      ),
      child: child,
    );

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        child: card,
      );
    }
    return card;
  }
}

// ============================================
// Tactical Gradient Button
// ============================================
class TacticalButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isActive;
  final IconData? icon;
  final EdgeInsets? padding;

  const TacticalButton({
    super.key,
    required this.label,
    this.onPressed,
    this.isActive = false,
    this.icon,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: padding ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: isActive ? StsysTheme.tacticalGradient : null,
          color: isActive ? null : StsysTheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
          border: isActive
              ? null
              : Border.all(
                  color: StsysTheme.outlineVariant.withValues(alpha: 0.2),
                  width: 1,
                ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                color: isActive
                    ? StsysTheme.onPrimary
                    : StsysTheme.onSurface.withValues(alpha: 0.6),
                size: 18,
              ),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Manrope',
                fontWeight: FontWeight.w800,
                fontSize: 12,
                letterSpacing: 1,
                color: isActive
                    ? StsysTheme.onPrimary
                    : StsysTheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================
// Status Badge (CONNECTED / DISCONNECTED)
// ============================================
class StatusBadge extends StatelessWidget {
  final bool isConnected;
  final String? deviceName;

  const StatusBadge({
    super.key,
    required this.isConnected,
    this.deviceName,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isConnected
            ? StsysTheme.primary.withValues(alpha: 0.15)
            : StsysTheme.error.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isConnected
              ? StsysTheme.primary.withValues(alpha: 0.3)
              : StsysTheme.error.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: isConnected ? StsysTheme.primary : StsysTheme.error,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            isConnected ? (deviceName ?? 'CONNECTED') : 'DISCONNECTED',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
              color: isConnected ? StsysTheme.primary : StsysTheme.error,
            ),
          ),
        ],
      ),
    );
  }
}
