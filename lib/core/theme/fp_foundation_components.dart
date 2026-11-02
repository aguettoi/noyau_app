import 'package:flutter/material.dart';

import '../localization/foundation_locale.dart';
import 'app_design_system.dart';

enum FpUniversalState { neutral, positive, attention, actionRequired, blocking }

class FpMoneyDisplay extends StatelessWidget {
  const FpMoneyDisplay({
    super.key,
    required this.value,
    this.label,
    this.hidden = false,
    this.style,
  });
  final String value;
  final String? label;
  final bool hidden;
  final TextStyle? style;
  @override
  Widget build(BuildContext context) {
    final words = FoundationWords.of(context);
    final visible = hidden ? '••••' : value;
    return Semantics(
      label: hidden
          ? words.text('private')
          : [label, value].whereType<String>().join(', '),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label != null)
            Text(label!, style: Theme.of(context).textTheme.labelMedium),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hidden)
                const Padding(
                  padding: EdgeInsetsDirectional.only(end: AppSpacing.xs),
                  child: Icon(Icons.lock_outline, size: 18),
                ),
              Text(
                visible,
                style:
                    style ??
                    Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class FpActionCard extends StatelessWidget {
  const FpActionCard({
    super.key,
    required this.title,
    required this.icon,
    this.subtitle,
    this.badge,
    this.onTap,
  });
  final String title;
  final String? subtitle;
  final IconData icon;
  final String? badge;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      borderRadius: AppRadius.card,
      onTap: onTap,
      child: Padding(
        padding: AppSpacing.card,
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: Icon(icon),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            if (badge != null)
              FpStatusChip(label: badge!, status: FpStatus.warning),
            const SizedBox(width: AppSpacing.xs),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    ),
  );
}

class FpProgressCard extends StatelessWidget {
  const FpProgressCard({
    super.key,
    required this.title,
    required this.value,
    required this.progress,
    this.detail,
    this.onTap,
  });
  final String title;
  final String value;
  final double progress;
  final String? detail;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      borderRadius: AppRadius.card,
      onTap: onTap,
      child: Padding(
        padding: AppSpacing.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            FpMoneyDisplay(value: value),
            const SizedBox(height: AppSpacing.sm),
            Semantics(
              value: '${(progress.clamp(0, 1) * 100).round()}%',
              child: LinearProgressIndicator(value: progress.clamp(0, 1)),
            ),
            if (detail != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(detail!, style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
      ),
    ),
  );
}

class FpPrivacyCard extends StatelessWidget {
  const FpPrivacyCard({super.key, this.title, this.message});
  final String? title;
  final String? message;
  @override
  Widget build(BuildContext context) {
    final words = FoundationWords.of(context);
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: ListTile(
        leading: const Icon(Icons.lock_outline),
        title: Text(title ?? words.text('private')),
        subtitle: Text(message ?? words.text('private.help')),
      ),
    );
  }
}

class FpAdvancedDisclosure extends StatelessWidget {
  const FpAdvancedDisclosure({super.key, required this.child, this.title});
  final Widget child;
  final String? title;
  @override
  Widget build(BuildContext context) => ExpansionTile(
    tilePadding: EdgeInsets.zero,
    title: Text(title ?? FoundationWords.of(context).text('advanced')),
    children: [child],
  );
}

class FpSearchFilterBar extends StatelessWidget {
  const FpSearchFilterBar({
    super.key,
    required this.onChanged,
    this.controller,
    this.filters = const [],
  });
  final ValueChanged<String> onChanged;
  final TextEditingController? controller;
  final List<Widget> filters;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: AppSpacing.xs,
    runSpacing: AppSpacing.xs,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 220, maxWidth: 480),
        child: TextField(
          controller: controller,
          onChanged: onChanged,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: FoundationWords.of(context).text('search'),
          ),
        ),
      ),
      ...filters,
    ],
  );
}

class FpFormSection extends StatelessWidget {
  const FpFormSection({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
  });
  final String title;
  final String? subtitle;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: Theme.of(context).textTheme.titleMedium),
      if (subtitle != null) SecondaryInfoText(subtitle!),
      const SizedBox(height: AppSpacing.sm),
      ...children.expand(
        (item) => [item, const SizedBox(height: AppSpacing.sm)],
      ),
    ],
  );
}

class FpOfflineBanner extends StatelessWidget {
  const FpOfflineBanner({
    super.key,
    required this.state,
    this.pendingCount = 0,
  });
  final FpOfflineVisualState state;
  final int pendingCount;
  @override
  Widget build(BuildContext context) {
    if (state == FpOfflineVisualState.online && pendingCount == 0) {
      return const SizedBox.shrink();
    }
    final words = FoundationWords.of(context);
    final (icon, key, color) = switch (state) {
      FpOfflineVisualState.offline => (
        Icons.cloud_off_outlined,
        'offline',
        AppColors.warning,
      ),
      FpOfflineVisualState.reconnecting => (
        Icons.sync,
        'reconnecting',
        AppColors.info,
      ),
      FpOfflineVisualState.actionRequired => (
        Icons.error_outline,
        'actionRequired',
        AppColors.danger,
      ),
      FpOfflineVisualState.online => (
        Icons.cloud_done_outlined,
        'pending',
        AppColors.info,
      ),
    };
    final label = key == 'pending'
        ? words.text(key).replaceAll('{count}', '$pendingCount')
        : words.text(key);
    return Material(
      color: color.withValues(alpha: .12),
      child: Semantics(
        liveRegion: true,
        label: label,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          child: Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: AppSpacing.xs),
              Expanded(child: Text(label)),
            ],
          ),
        ),
      ),
    );
  }
}

enum FpOfflineVisualState { online, offline, reconnecting, actionRequired }

class FpWizard extends StatelessWidget {
  const FpWizard({
    super.key,
    required this.step,
    required this.stepCount,
    required this.title,
    required this.child,
    this.onBack,
    this.onContinue,
  });
  final int step;
  final int stepCount;
  final String title;
  final Widget child;
  final VoidCallback? onBack;
  final VoidCallback? onContinue;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Semantics(
        header: true,
        child: Text(title, style: Theme.of(context).textTheme.headlineSmall),
      ),
      const SizedBox(height: AppSpacing.sm),
      LinearProgressIndicator(
        value: stepCount == 0 ? 0 : (step + 1) / stepCount,
      ),
      const SizedBox(height: AppSpacing.lg),
      Expanded(child: child),
      Row(
        children: [
          if (onBack != null)
            OutlinedButton(
              onPressed: onBack,
              child: Text(FoundationWords.of(context).text('back')),
            ),
          const Spacer(),
          FilledButton(
            onPressed: onContinue,
            child: Text(FoundationWords.of(context).text('continue')),
          ),
        ],
      ),
    ],
  );
}

class FpConfirmation extends StatelessWidget {
  const FpConfirmation({
    super.key,
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.onConfirm,
    this.onCancel,
    this.danger = false,
  });
  final String title;
  final String message;
  final String confirmLabel;
  final VoidCallback onConfirm;
  final VoidCallback? onCancel;
  final bool danger;
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(title),
    content: Text(message),
    actions: [
      TextButton(
        onPressed: onCancel ?? () => Navigator.of(context).pop(),
        child: Text(FoundationWords.of(context).text('close')),
      ),
      FilledButton(
        style: danger
            ? FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              )
            : null,
        onPressed: onConfirm,
        child: Text(confirmLabel),
      ),
    ],
  );
}
