import 'package:flutter/material.dart';

/// Tokens visuels partagés de Noyau. Les écrans ne doivent pas créer leur
/// propre palette ni leurs propres métriques d'espacement.
abstract final class AppColors {
  static const primary = Color(0xFF163A5F);
  static const secondary = Color(0xFF4F6F52);
  static const accent = Color(0xFFC89B3C);
  static const background = Color(0xFFF7F8F5);
  static const surface = Color(0xFFEEF1F4);
  static const surfaceSecondary = Color(0xFFFFFFFF);
  static const textPrimary = Color(0xFF1E2329);
  static const textSecondary = Color(0xFF69707A);
  static const divider = Color(0xFFD9DEE4);
  static const border = Color(0xFFD0D6DC);
  static const success = Color(0xFF2E7D32);
  static const warning = Color(0xFFF59E0B);
  static const danger = Color(0xFFD32F2F);
  static const info = Color(0xFF2C7FB8);
  static const primaryContainer = Color(0xFFDCE8F3);
  static const secondaryContainer = Color(0xFFDDEADF);
  static const accentContainer = Color(0xFFF5E8C8);
  static const accentContainerText = Color(0xFF5B430E);
  static const dangerContainer = Color(0xFFFBE9E8);
  static const dangerContainerText = Color(0xFF7D1B1B);
  static const shadow = Color(0xFF000000);
  static const transparent = Color(0x00000000);

  static const darkBackground = Color(0xFF111418);
  static const darkSurface = Color(0xFF1A1F24);
  static const darkSurfaceSecondary = Color(0xFF232931);
  static const darkPrimary = Color(0xFF2C5C88);
  static const darkSecondary = Color(0xFF6E9C74);
  static const darkAccent = Color(0xFFD7AE52);
  static const darkTextPrimary = Color(0xFFF3F5F7);
  static const darkTextSecondary = Color(0xFFAEB8C3);
  static const darkDivider = Color(0xFF2D333A);
  static const darkBorder = Color(0xFF343A42);
  static const darkPrimaryContainer = Color(0xFF1F3F5B);
  static const darkSecondaryContainer = Color(0xFF263B2B);
  static const darkAccentContainer = Color(0xFF453817);
  static const darkDangerContainer = Color(0xFF4A2525);
  static const darkDangerContainerText = Color(0xFFFFDAD6);
}

abstract final class AppSpacing {
  static const xxs = 4.0;
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const xxl = 48.0;

  static const page = EdgeInsets.all(lg);
  static const card = EdgeInsets.all(md);
  static const dialog = EdgeInsets.all(lg);
}

abstract final class AppRadius {
  static const button = BorderRadius.all(Radius.circular(14));
  static const input = BorderRadius.all(Radius.circular(14));
  static const card = BorderRadius.all(Radius.circular(18));
  static const dialog = BorderRadius.all(Radius.circular(20));
  static const navigation = BorderRadius.all(Radius.circular(16));
}

abstract final class AppShadows {
  static const subtle = <BoxShadow>[
    BoxShadow(color: Color(0x120E1823), blurRadius: 18, offset: Offset(0, 6)),
  ];
}

abstract final class AppAnimations {
  static const standardDuration = Duration(milliseconds: 220);
  static const standardCurve = Curves.easeInOut;
}

abstract final class AppIcons {
  static const overview = Icons.account_balance_outlined;
  static const accounts = Icons.account_balance_wallet_outlined;
  static const envelopes = Icons.account_balance_wallet_outlined;
  static const import = Icons.upload_file_outlined;
  static const add = Icons.add;
  static const download = Icons.download_outlined;
}

abstract final class AppTypography {
  static const fontFamily = 'Inter';

  static TextTheme textTheme(TextTheme base, ColorScheme colors) => base
      .apply(
        fontFamily: fontFamily,
        bodyColor: colors.onSurface,
        displayColor: colors.onSurface,
      )
      .copyWith(
        headlineSmall: TextStyle(
          fontFamily: fontFamily,
          fontWeight: FontWeight.w700,
          fontSize: 28,
          height: 1.2,
          letterSpacing: -0.5,
          color: colors.onSurface,
        ),
        titleLarge: TextStyle(
          fontFamily: fontFamily,
          fontWeight: FontWeight.w700,
          fontSize: 20,
          height: 1.3,
          color: colors.onSurface,
        ),
        titleMedium: TextStyle(
          fontFamily: fontFamily,
          fontWeight: FontWeight.w600,
          fontSize: 16,
          height: 1.35,
          color: colors.onSurface,
        ),
        bodyLarge: TextStyle(
          fontFamily: fontFamily,
          fontSize: 16,
          height: 1.5,
          color: colors.onSurface,
        ),
        bodyMedium: TextStyle(
          fontFamily: fontFamily,
          fontSize: 14,
          height: 1.45,
          color: colors.onSurface,
        ),
        bodySmall: TextStyle(
          fontFamily: fontFamily,
          fontSize: 12,
          height: 1.4,
          color: colors.onSurfaceVariant,
        ),
        labelLarge: TextStyle(
          fontFamily: fontFamily,
          fontWeight: FontWeight.w600,
          fontSize: 14,
          height: 1.2,
          color: colors.onSurface,
        ),
      );
}
