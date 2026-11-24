import 'package:flutter/material.dart';

/// Tokens visuels partagés de Noyau. Les écrans ne doivent pas créer leur
/// propre palette ni leurs propres métriques d'espacement.
abstract final class AppColors {
  // Brand colors come from the official FINANCIEL PILOTE identity. They are
  // deliberately distinct from business-state colors below.
  static const brandNavy = Color(0xFF12385B);
  static const brandSage = Color(0xFF66785B);
  static const brandGold = Color(0xFFD0A451);

  // Financial and product semantics. A brand color must never be used as a
  // substitute for one of these roles merely because it looks similar.
  static const financialPositive = Color(0xFF087443);
  static const financialNegative = Color(0xFFB4233C);
  static const information = Color(0xFF175C9E);
  static const warning = Color(0xFF8A4B00);
  static const specializedPurple = Color(0xFF5B3DB5);

  // Design Freeze functional palette. These roles are intentionally explicit:
  // charts, KPI and privacy surfaces must not infer them from brand colors.
  static const revenue = Color(0xFF2563EB);
  static const spending = Color(0xFFE54864);
  static const savingsFunctional = Color(0xFF16A34A);
  static const investments = Color(0xFF7C3AED);
  static const creditsAndDebts = Color(0xFFDC3545);
  static const accountsAndLiquidity = Color(0xFF175C9E);
  static const cycleObserved = Color(0xFFD9467D);
  static const cycleEstimated = Color(0xFF8B5CF6);
  static const privacyVisible = Color(0xFF16A34A);
  static const privacyBalanceHidden = Color(0xFFC2410C);
  static const privacyPrivate = Color(0xFFDC3545);

  // Cold, quiet neutrals used by the validated light visual language.
  static const background = Color(0xFFF7F9FC);
  static const surface = Color(0xFFF1F5F9);
  static const surfaceSecondary = Color(0xFFFFFFFF);
  static const surfaceElevated = Color(0xFFFFFFFF);
  static const textPrimary = Color(0xFF101828);
  static const textSecondary = Color(0xFF475467);
  static const textMuted = Color(0xFF667085);
  static const textDisabled = Color(0xFF98A2B3);
  static const divider = Color(0xFFE7ECF2);
  static const borderSubtle = Color(0xFFE3E9F0);
  static const border = Color(0xFFD0D9E4);

  // Compatibility aliases keep existing pages source-compatible during Lot 0.
  static const primary = brandNavy;
  static const secondary = brandSage;
  static const accent = brandGold;
  static const success = financialPositive;
  static const danger = financialNegative;
  static const info = information;
  static const income = revenue;
  static const expense = spending;
  static const transfer = information;
  static const savings = savingsFunctional;
  static const investment = investments;
  static const debt = creditsAndDebts;
  static const receivable = Color(0xFF176B68);
  // Les surfaces de contenu restent neutres : le bleu pétrole structure la
  // navigation et les CTA, sans créer de grands aplats bleu pastel.
  static const primaryContainer = Color(0xFFEEF1F4);
  static const secondaryContainer = Color(0xFFE6EEE6);
  static const accentContainer = Color(0xFFF5E8C8);
  static const accentContainerText = Color(0xFF5B430E);
  static const dangerContainer = Color(0xFFFBE9E8);
  static const dangerContainerText = Color(0xFF7D1B1B);
  static const shadow = Color(0xFF0B1F33);
  static const transparent = Color(0x00000000);

  // Dark mode is independently calibrated rather than derived by inversion.
  static const darkBackground = Color(0xFF09111B);
  static const darkSurface = Color(0xFF111C29);
  static const darkSurfaceSecondary = Color(0xFF182636);
  static const darkSurfaceElevated = Color(0xFF203247);
  static const darkPrimary = Color(0xFF79A9D2);
  static const darkSecondary = Color(0xFF9AAE8C);
  static const darkAccent = Color(0xFFE3BB64);
  static const darkFinancialPositive = Color(0xFF5DDB91);
  static const darkFinancialNegative = Color(0xFFFF8AA0);
  static const darkInformation = Color(0xFF75C0FF);
  static const darkWarning = Color(0xFFFFD080);
  static const darkSpecializedPurple = Color(0xFFB8A1FF);
  static const darkRevenue = Color(0xFF60A5FA);
  static const darkSpending = Color(0xFFFF8FA3);
  static const darkSavingsFunctional = Color(0xFF4ADE80);
  static const darkInvestments = Color(0xFFC4B5FD);
  static const darkCreditsAndDebts = Color(0xFFFF8A95);
  static const darkAccountsAndLiquidity = Color(0xFF75C0FF);
  static const darkCycleObserved = Color(0xFFF472B6);
  static const darkCycleEstimated = Color(0xFFC4B5FD);
  static const darkPrivacyVisible = Color(0xFF4ADE80);
  static const darkPrivacyBalanceHidden = Color(0xFFFDBA74);
  static const darkPrivacyPrivate = Color(0xFFFF8A95);
  static const darkTextPrimary = Color(0xFFF6F8FB);
  static const darkTextSecondary = Color(0xFFC3CEDA);
  static const darkTextMuted = Color(0xFF93A4B7);
  static const darkTextDisabled = Color(0xFF697B8F);
  static const darkDivider = Color(0xFF26384A);
  static const darkBorderSubtle = Color(0xFF2B3D50);
  static const darkBorder = Color(0xFF3B5066);
  static const darkPrimaryContainer = Color(0xFF183A58);
  static const darkSecondaryContainer = Color(0xFF293B2C);
  static const darkAccentContainer = Color(0xFF493A17);
  static const darkDangerContainer = Color(0xFF4A202B);
  static const darkDangerContainerText = Color(0xFFFFD9E0);

  static Color financialPositiveFor(Brightness brightness) =>
      brightness == Brightness.dark ? darkFinancialPositive : financialPositive;

  static Color financialNegativeFor(Brightness brightness) =>
      brightness == Brightness.dark ? darkFinancialNegative : financialNegative;

  static Color informationFor(Brightness brightness) =>
      brightness == Brightness.dark ? darkInformation : information;

  static Color warningFor(Brightness brightness) =>
      brightness == Brightness.dark ? darkWarning : warning;

  static Color specializedPurpleFor(Brightness brightness) =>
      brightness == Brightness.dark ? darkSpecializedPurple : specializedPurple;

  static Color revenueFor(Brightness brightness) =>
      brightness == Brightness.dark ? darkRevenue : revenue;

  static Color spendingFor(Brightness brightness) =>
      brightness == Brightness.dark ? darkSpending : spending;

  static Color savingsFor(Brightness brightness) =>
      brightness == Brightness.dark ? darkSavingsFunctional : savingsFunctional;

  static Color investmentsFor(Brightness brightness) =>
      brightness == Brightness.dark ? darkInvestments : investments;

  static Color creditsAndDebtsFor(Brightness brightness) =>
      brightness == Brightness.dark ? darkCreditsAndDebts : creditsAndDebts;

  static Color accountsAndLiquidityFor(Brightness brightness) =>
      brightness == Brightness.dark
      ? darkAccountsAndLiquidity
      : accountsAndLiquidity;

  static Color cycleObservedFor(Brightness brightness) =>
      brightness == Brightness.dark ? darkCycleObserved : cycleObserved;

  static Color cycleEstimatedFor(Brightness brightness) =>
      brightness == Brightness.dark ? darkCycleEstimated : cycleEstimated;

  static Color privacyVisibleFor(Brightness brightness) =>
      brightness == Brightness.dark ? darkPrivacyVisible : privacyVisible;

  static Color privacyBalanceHiddenFor(Brightness brightness) =>
      brightness == Brightness.dark
      ? darkPrivacyBalanceHidden
      : privacyBalanceHidden;

  static Color privacyPrivateFor(Brightness brightness) =>
      brightness == Brightness.dark ? darkPrivacyPrivate : privacyPrivate;
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
  static const compactPage = EdgeInsets.symmetric(horizontal: md, vertical: sm);
  static const sectionGap = lg;
  static const contentGap = md;
  static const inlineGap = xs;
}

abstract final class AppControlSize {
  static const minimumTouchTarget = 48.0;
  static const compactVisual = 40.0;
  static const standard = 48.0;
  static const large = 56.0;
  static const buttonHeight = standard;
  static const inputHeight = standard;
  static const iconSmall = 18.0;
  static const icon = 24.0;
  static const iconLarge = 32.0;
}

enum AppWindowClass { compact, medium, expanded, large }

/// Contraintes de lecture partagées pour éviter que les écrans desktop
/// deviennent des formulaires étirés. Les pages restent fluides sur les
/// formats intermédiaires et reprennent toute la largeur utile sur mobile.
abstract final class AppLayout {
  static const compactBreakpoint = 600.0;
  static const mediumBreakpoint = 900.0;
  static const expandedBreakpoint = 1200.0;
  static const largeBreakpoint = 1440.0;
  static const contentMaxWidth = 1360.0;
  static const formMaxWidth = 1180.0;
  static const wideDialogMaxWidth = 1240.0;

  static EdgeInsets pagePaddingFor(double width) {
    if (width < compactBreakpoint) {
      return const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      );
    }
    if (width < expandedBreakpoint) return const EdgeInsets.all(AppSpacing.lg);
    return const EdgeInsets.symmetric(
      horizontal: AppSpacing.xl,
      vertical: AppSpacing.lg,
    );
  }

  static AppWindowClass windowClass(double width) => switch (width) {
    < compactBreakpoint => AppWindowClass.compact,
    < mediumBreakpoint => AppWindowClass.medium,
    < largeBreakpoint => AppWindowClass.expanded,
    _ => AppWindowClass.large,
  };

  static bool isCompact(double width) => width < compactBreakpoint;
  static bool isDesktop(double width) => width >= expandedBreakpoint;
  static bool isLarge(double width) => width >= largeBreakpoint;
}

class FpPageHeader extends StatelessWidget {
  const FpPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final heading = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          if (subtitle != null) ...[
            const SizedBox(height: AppSpacing.xxs),
            SecondaryInfoText(subtitle!),
          ],
        ],
      );
      if (actions.isEmpty) return heading;
      if (AppLayout.isCompact(constraints.maxWidth)) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            heading,
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: actions,
            ),
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: heading),
          const SizedBox(width: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: actions,
          ),
        ],
      );
    },
  );
}

class FpCard extends StatelessWidget {
  const FpCard({
    super.key,
    required this.child,
    this.padding = AppSpacing.card,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(padding: padding, child: child),
  );
}

class FpKpiCard extends StatelessWidget {
  const FpKpiCard({
    super.key,
    required this.title,
    required this.value,
    this.detail,
    this.icon,
    this.semanticColor,
    this.onTap,
  });

  final String title;
  final String value;
  final String? detail;
  final IconData? icon;
  final Color? semanticColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = semanticColor ?? Theme.of(context).colorScheme.primary;
    return Semantics(
      button: onTap != null,
      label: '$title, $value${detail == null ? '' : ', $detail'}',
      child: Card(
        child: InkWell(
          borderRadius: AppRadius.card,
          onTap: onTap,
          child: Padding(
            padding: AppSpacing.card,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: AppControlSize.iconSmall, color: color),
                      const SizedBox(width: AppSpacing.xs),
                    ],
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: color,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                if (detail != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    detail!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum FpStatus { neutral, success, warning, error, info }

class FpStatusChip extends StatelessWidget {
  const FpStatusChip({
    super.key,
    required this.label,
    this.status = FpStatus.neutral,
  });

  final String label;
  final FpStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (status) {
      FpStatus.success => AppColors.financialPositiveFor(scheme.brightness),
      FpStatus.warning => AppColors.warningFor(scheme.brightness),
      FpStatus.error => scheme.error,
      FpStatus.info => AppColors.informationFor(scheme.brightness),
      FpStatus.neutral => scheme.onSurfaceVariant,
    };
    return Semantics(
      label: label,
      child: Chip(
        avatar: Icon(Icons.circle, size: 10, color: color),
        label: Text(label),
        side: BorderSide(color: color.withValues(alpha: .35)),
        backgroundColor: color.withValues(alpha: .08),
      ),
    );
  }
}

class FpEmptyState extends StatelessWidget {
  const FpEmptyState({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.inbox_outlined,
    this.action,
  });

  final String title;
  final String message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) =>
      _FpStatePanel(icon: icon, title: title, message: message, action: action);
}

class FpErrorState extends StatelessWidget {
  const FpErrorState({
    super.key,
    required this.message,
    this.title = 'Impossible de charger les données',
    this.action,
  });

  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => _FpStatePanel(
    icon: Icons.error_outline,
    iconColor: Theme.of(context).colorScheme.error,
    title: title,
    message: message,
    action: action,
  );
}

class FpLoadingState extends StatelessWidget {
  const FpLoadingState({super.key, this.label = 'Chargement…'});

  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    liveRegion: true,
    child: Center(
      child: Padding(
        padding: AppSpacing.dialog,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: AppSpacing.md),
            Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    ),
  );
}

class _FpStatePanel extends StatelessWidget {
  const _FpStatePanel({
    required this.icon,
    required this.title,
    required this.message,
    this.iconColor,
    this.action,
  });

  final IconData icon;
  final Color? iconColor;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Padding(
        padding: AppSpacing.dialog,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 40,
              color: iconColor ?? Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (action != null) ...[
              const SizedBox(height: AppSpacing.md),
              action!,
            ],
          ],
        ),
      ),
    ),
  );
}

/// Composition partagée des écrans desktop. Elle évite que les listes et les
/// formulaires issus du mobile s'étirent sur toute la fenêtre Windows.
class DesktopPageContainer extends StatelessWidget {
  const DesktopPageContainer({
    super.key,
    required this.child,
    this.maxWidth = AppLayout.contentMaxWidth,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: AppLayout.pagePaddingFor(constraints.maxWidth),
          child: child,
        ),
      ),
    ),
  );
}

class DesktopSection extends StatelessWidget {
  const DesktopSection({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.action,
    this.padding = AppSpacing.md,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? action;
  final double padding;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: EdgeInsets.all(padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleLarge),
                    if (subtitle != null) ...[
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        subtitle!,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
              ?action,
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          child,
        ],
      ),
    ),
  );
}

class ResponsiveGrid extends StatelessWidget {
  const ResponsiveGrid({
    super.key,
    required this.children,
    this.minItemWidth = 300,
    this.spacing = AppSpacing.md,
    this.runSpacing = AppSpacing.md,
  });

  final List<Widget> children;
  final double minItemWidth;
  final double spacing;
  final double runSpacing;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = (constraints.maxWidth / minItemWidth).floor().clamp(1, 4);
      final itemWidth =
          (constraints.maxWidth - spacing * (columns - 1)) / columns;
      return Wrap(
        spacing: spacing,
        runSpacing: runSpacing,
        children: [
          for (final child in children)
            SizedBox(width: itemWidth, child: child),
        ],
      );
    },
  );
}

class CompactListRow extends StatelessWidget {
  const CompactListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(
      context,
    ).colorScheme.surfaceContainerHighest.withValues(alpha: .45),
    borderRadius: AppRadius.input,
    child: ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      minVerticalPadding: AppSpacing.xs,
      leading: leading,
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: trailing,
      onTap: onTap,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.input),
    ),
  );
}

/// Texte de contexte non bloquant : il ne doit jamais prendre l'apparence
/// d'une erreur ou d'un titre de page lorsqu'il accompagne un en-tête métier.
class SecondaryInfoText extends StatelessWidget {
  const SecondaryInfoText(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) => Text(
    message,
    style: Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      decoration: TextDecoration.none,
    ),
  );
}

abstract final class AppRadius {
  static const small = BorderRadius.all(Radius.circular(8));
  static const control = BorderRadius.all(Radius.circular(12));
  static const button = control;
  static const input = control;
  static const card = BorderRadius.all(Radius.circular(16));
  static const largeCard = BorderRadius.all(Radius.circular(20));
  static const modal = largeCard;
  static const dialog = modal;
  static const navigation = BorderRadius.all(Radius.circular(16));
}

abstract final class AppShadows {
  static const none = <BoxShadow>[];
  static const subtle = <BoxShadow>[
    BoxShadow(color: Color(0x0A0B1F33), blurRadius: 12, offset: Offset(0, 3)),
  ];
  static const card = <BoxShadow>[
    BoxShadow(color: Color(0x0F0B1F33), blurRadius: 18, offset: Offset(0, 6)),
  ];
  static const elevated = <BoxShadow>[
    BoxShadow(color: Color(0x160B1F33), blurRadius: 24, offset: Offset(0, 10)),
  ];
  static const modal = <BoxShadow>[
    BoxShadow(color: Color(0x240B1F33), blurRadius: 36, offset: Offset(0, 16)),
  ];
  static const darkSubtle = <BoxShadow>[
    BoxShadow(color: Color(0x3D000000), blurRadius: 12, offset: Offset(0, 3)),
  ];
  static const darkCard = <BoxShadow>[
    BoxShadow(color: Color(0x52000000), blurRadius: 20, offset: Offset(0, 7)),
  ];
  static const darkElevated = <BoxShadow>[
    BoxShadow(color: Color(0x66000000), blurRadius: 28, offset: Offset(0, 12)),
  ];
  static const darkModal = <BoxShadow>[
    BoxShadow(color: Color(0x7A000000), blurRadius: 40, offset: Offset(0, 18)),
  ];
}

abstract final class AppAnimations {
  static const instant = Duration.zero;
  static const fast = Duration(milliseconds: 120);
  static const standardDuration = Duration(milliseconds: 220);
  static const standard = standardDuration;
  static const slow = Duration(milliseconds: 320);
  static const standardCurve = Curves.easeInOut;

  static Duration resolve(BuildContext context, Duration duration) {
    final media = MediaQuery.maybeOf(context);
    if (media?.disableAnimations == true ||
        media?.accessibleNavigation == true) {
      return instant;
    }
    return duration;
  }
}

abstract final class AppBorders {
  static BorderSide subtle(ColorScheme scheme) =>
      BorderSide(color: scheme.outlineVariant.withValues(alpha: .82));
  static BorderSide standard(ColorScheme scheme) =>
      BorderSide(color: scheme.outline);
  static BorderSide selected(ColorScheme scheme) =>
      BorderSide(color: scheme.primary, width: 1.5);
  static BorderSide focus(ColorScheme scheme) =>
      BorderSide(color: scheme.primary, width: 2);
  static BorderSide error(ColorScheme scheme) =>
      BorderSide(color: scheme.error, width: 1.5);
}

abstract final class AppIcons {
  static const overview = Icons.account_balance_outlined;
  static const accounts = Icons.account_balance_wallet_outlined;
  static const envelopes = Icons.account_balance_wallet_outlined;
  static const import = Icons.upload_file_outlined;
  static const add = Icons.add;
  static const download = Icons.download_outlined;
}

abstract final class AppAssets {
  static const financialPiloteLogo =
      'assets/branding/financial_pilote_logo.png';
}

abstract final class AppTypography {
  static const fontFamily = 'Inter';

  static const financialFigures = <FontFeature>[FontFeature.tabularFigures()];

  static TextTheme textTheme(TextTheme base, ColorScheme colors) => base
      .apply(
        fontFamily: fontFamily,
        bodyColor: colors.onSurface,
        displayColor: colors.onSurface,
      )
      .copyWith(
        displaySmall: TextStyle(
          fontFamily: fontFamily,
          fontWeight: FontWeight.w700,
          fontSize: 40,
          height: 1.08,
          letterSpacing: -1,
          color: colors.onSurface,
          fontFeatures: financialFigures,
        ),
        headlineLarge: TextStyle(
          fontFamily: fontFamily,
          fontWeight: FontWeight.w700,
          fontSize: 32,
          height: 1.15,
          letterSpacing: -0.7,
          color: colors.onSurface,
        ),
        headlineMedium: TextStyle(
          fontFamily: fontFamily,
          fontWeight: FontWeight.w700,
          fontSize: 28,
          height: 1.18,
          letterSpacing: -0.5,
          color: colors.onSurface,
        ),
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
        labelMedium: TextStyle(
          fontFamily: fontFamily,
          fontWeight: FontWeight.w600,
          fontSize: 12,
          height: 1.25,
          color: colors.onSurfaceVariant,
        ),
      );

  static TextStyle displayFinancial(ColorScheme colors) => TextStyle(
    fontFamily: fontFamily,
    fontWeight: FontWeight.w700,
    fontSize: 40,
    height: 1.08,
    letterSpacing: -1,
    color: colors.onSurface,
    fontFeatures: financialFigures,
  );

  static TextStyle financialAmountLarge(ColorScheme colors) => TextStyle(
    fontFamily: fontFamily,
    fontWeight: FontWeight.w700,
    fontSize: 32,
    height: 1.12,
    letterSpacing: -0.6,
    color: colors.onSurface,
    fontFeatures: financialFigures,
  );

  static TextStyle financialAmountMedium(ColorScheme colors) => TextStyle(
    fontFamily: fontFamily,
    fontWeight: FontWeight.w700,
    fontSize: 24,
    height: 1.16,
    letterSpacing: -0.3,
    color: colors.onSurface,
    fontFeatures: financialFigures,
  );

  static TextStyle financialAmountSmall(ColorScheme colors) => TextStyle(
    fontFamily: fontFamily,
    fontWeight: FontWeight.w700,
    fontSize: 18,
    height: 1.2,
    color: colors.onSurface,
    fontFeatures: financialFigures,
  );

  static TextStyle caption(ColorScheme colors) => TextStyle(
    fontFamily: fontFamily,
    fontWeight: FontWeight.w400,
    fontSize: 11,
    height: 1.35,
    color: colors.onSurfaceVariant,
  );
}
