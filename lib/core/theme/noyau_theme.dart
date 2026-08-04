import 'package:flutter/material.dart';

import 'app_design_system.dart';

abstract final class NoyauTheme {
  static ThemeData get light => _theme(Brightness.light);
  static ThemeData get dark => _theme(Brightness.dark);

  static ThemeData _theme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme(
      brightness: brightness,
      primary: isDark ? AppColors.darkPrimary : AppColors.primary,
      onPrimary: AppColors.surfaceSecondary,
      primaryContainer: isDark
          ? AppColors.darkPrimaryContainer
          : AppColors.primaryContainer,
      onPrimaryContainer: isDark
          ? AppColors.darkTextPrimary
          : AppColors.primary,
      secondary: isDark ? AppColors.darkSecondary : AppColors.secondary,
      onSecondary: isDark
          ? AppColors.darkBackground
          : AppColors.surfaceSecondary,
      secondaryContainer: isDark
          ? AppColors.darkSecondaryContainer
          : AppColors.secondaryContainer,
      onSecondaryContainer: isDark
          ? AppColors.darkTextPrimary
          : AppColors.secondary,
      tertiary: isDark ? AppColors.darkAccent : AppColors.accent,
      onTertiary: isDark ? AppColors.darkBackground : AppColors.textPrimary,
      tertiaryContainer: isDark
          ? AppColors.darkAccentContainer
          : AppColors.accentContainer,
      onTertiaryContainer: isDark
          ? AppColors.darkTextPrimary
          : AppColors.accentContainerText,
      error: AppColors.danger,
      onError: AppColors.surfaceSecondary,
      errorContainer: isDark
          ? AppColors.darkDangerContainer
          : AppColors.dangerContainer,
      onErrorContainer: isDark
          ? AppColors.darkDangerContainerText
          : AppColors.dangerContainerText,
      surface: isDark ? AppColors.darkSurface : AppColors.surface,
      onSurface: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
      surfaceContainerHighest: isDark
          ? AppColors.darkSurfaceSecondary
          : AppColors.surfaceSecondary,
      onSurfaceVariant: isDark
          ? AppColors.darkTextSecondary
          : AppColors.textSecondary,
      outline: isDark ? AppColors.darkBorder : AppColors.border,
      outlineVariant: isDark ? AppColors.darkDivider : AppColors.divider,
      shadow: AppColors.shadow,
      scrim: AppColors.shadow,
      inverseSurface: isDark
          ? AppColors.surfaceSecondary
          : AppColors.textPrimary,
      onInverseSurface: isDark
          ? AppColors.textPrimary
          : AppColors.darkTextPrimary,
      inversePrimary: isDark ? AppColors.primary : AppColors.darkPrimary,
    );
    final textTheme = AppTypography.textTheme(
      ThemeData.light().textTheme,
      scheme,
    );
    final outline = OutlineInputBorder(
      borderRadius: AppRadius.input,
      borderSide: BorderSide(color: scheme.outline),
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: AppTypography.fontFamily,
      textTheme: textTheme,
      scaffoldBackgroundColor: isDark
          ? AppColors.darkBackground
          : AppColors.background,
      dividerColor: scheme.outlineVariant,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.transparent,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: textTheme.titleLarge,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: isDark
            ? AppColors.darkSurfaceSecondary
            : AppColors.surfaceSecondary,
        shadowColor: AppColors.transparent,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.card),
        clipBehavior: Clip.antiAlias,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isDark
            ? AppColors.darkSurfaceSecondary
            : AppColors.surfaceSecondary,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.dialog),
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium,
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: isDark
            ? AppColors.darkSurfaceSecondary
            : AppColors.surfaceSecondary,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        labelStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        border: outline,
        enabledBorder: outline,
        focusedBorder: outline.copyWith(
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        errorBorder: outline.copyWith(
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: outline.copyWith(
          borderSide: BorderSide(color: scheme.error, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.button),
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          side: BorderSide(color: scheme.outline),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.button),
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.button),
          textStyle: textTheme.labelLarge,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.button),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: isDark
            ? AppColors.darkSurfaceSecondary
            : AppColors.surfaceSecondary,
        indicatorColor: scheme.primaryContainer,
        labelTextStyle: WidgetStatePropertyAll(textTheme.labelLarge),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark
            ? AppColors.darkSurfaceSecondary
            : AppColors.textPrimary,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: isDark
              ? AppColors.darkTextPrimary
              : AppColors.surfaceSecondary,
        ),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.button),
      ),
      focusColor: scheme.primary.withValues(alpha: 0.12),
      splashFactory: InkSparkle.splashFactory,
    );
  }
}
