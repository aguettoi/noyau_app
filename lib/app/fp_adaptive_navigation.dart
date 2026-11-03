import 'package:flutter/material.dart';

import '../core/localization/foundation_locale.dart';
import '../core/theme/app_design_system.dart';

enum FpUniverse { home, money, household, projects, more }

extension FpUniverseX on FpUniverse {
  String get key => switch (this) {
    FpUniverse.home => 'home',
    FpUniverse.money => 'money',
    FpUniverse.household => 'household',
    FpUniverse.projects => 'projects',
    FpUniverse.more => 'more',
  };
  IconData get icon => switch (this) {
    FpUniverse.home => Icons.home_outlined,
    FpUniverse.money => Icons.account_balance_wallet_outlined,
    FpUniverse.household => Icons.home_work_outlined,
    FpUniverse.projects => Icons.rocket_launch_outlined,
    FpUniverse.more => Icons.more_horiz,
  };
  IconData get selectedIcon => switch (this) {
    FpUniverse.home => Icons.home,
    FpUniverse.money => Icons.account_balance_wallet,
    FpUniverse.household => Icons.home_work,
    FpUniverse.projects => Icons.rocket_launch,
    FpUniverse.more => Icons.more,
  };
}

class FpAdaptiveNavigation extends StatelessWidget {
  const FpAdaptiveNavigation({
    super.key,
    required this.selected,
    required this.onSelected,
    required this.body,
    required this.onAdd,
    this.header,
    this.offlineBanner,
  });
  final FpUniverse selected;
  final ValueChanged<FpUniverse> onSelected;
  final Widget body;
  final VoidCallback onAdd;
  final Widget? header;
  final Widget? offlineBanner;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final desktop = AppLayout.isDesktop(width);
    final words = FoundationWords.of(context);
    final content = Column(
      children: [
        ?offlineBanner,
        ?header,
        Expanded(child: body),
      ],
    );
    if (desktop) {
      return Scaffold(
        body: Row(
          children: [
            Container(
              width: AppLayout.isLarge(width) ? 228 : 104,
              color: AppColors.primary,
              child: SafeArea(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Image.asset(
                            AppAssets.financialPiloteLogo,
                            width: 48,
                            height: 48,
                          ),
                          if (AppLayout.isLarge(width)) ...[
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                'FINANCIEL\nPILOTE',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(color: Colors.white),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    for (final universe in FpUniverse.values)
                      _RailItem(
                        universe: universe,
                        selected: universe == selected,
                        extended: AppLayout.isLarge(width),
                        onTap: () => onSelected(universe),
                      ),
                    const Spacer(),
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: FilledButton.icon(
                        onPressed: onAdd,
                        icon: const Icon(Icons.add),
                        label: Text(words.text('add')),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(child: content),
          ],
        ),
      );
    }
    return Scaffold(
      body: content,
      floatingActionButton: Semantics(
        label: words.text('add'),
        button: true,
        child: FloatingActionButton(
          heroTag: 'fp-universal-add',
          onPressed: onAdd,
          child: const Icon(Icons.add),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: AppSpacing.xs,
        child: SizedBox(
          height: 64,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _MobileItem(
                universe: FpUniverse.home,
                selected: selected == FpUniverse.home,
                onTap: onSelected,
              ),
              _MobileItem(
                universe: FpUniverse.money,
                selected: selected == FpUniverse.money,
                onTap: onSelected,
              ),
              const SizedBox(width: 56),
              _MobileItem(
                universe: FpUniverse.household,
                selected: selected == FpUniverse.household,
                onTap: onSelected,
              ),
              _MobileItem(
                universe: FpUniverse.more,
                selected:
                    selected == FpUniverse.more ||
                    selected == FpUniverse.projects,
                onTap: onSelected,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.universe,
    required this.selected,
    required this.extended,
    required this.onTap,
  });
  final FpUniverse universe;
  final bool selected;
  final bool extended;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final label = FoundationWords.of(context).text(universe.key);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      child: Semantics(
        selected: selected,
        button: true,
        label: label,
        child: Material(
          color: selected ? AppColors.secondary : Colors.transparent,
          borderRadius: AppRadius.button,
          child: InkWell(
            borderRadius: AppRadius.button,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                mainAxisAlignment: extended
                    ? MainAxisAlignment.start
                    : MainAxisAlignment.center,
                children: [
                  Icon(
                    selected ? universe.selectedIcon : universe.icon,
                    color: Colors.white,
                  ),
                  if (extended) ...[
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MobileItem extends StatelessWidget {
  const _MobileItem({
    required this.universe,
    required this.selected,
    required this.onTap,
  });
  final FpUniverse universe;
  final bool selected;
  final ValueChanged<FpUniverse> onTap;
  @override
  Widget build(BuildContext context) {
    final label = FoundationWords.of(context).text(universe.key);
    return Expanded(
      child: InkWell(
        onTap: () => onTap(universe),
        child: Semantics(
          selected: selected,
          button: true,
          label: label,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                selected ? universe.selectedIcon : universe.icon,
                color: selected
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              Text(
                label,
                maxLines: 1,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class FpUniversalAddSheet extends StatelessWidget {
  const FpUniversalAddSheet({
    super.key,
    required this.universe,
    required this.actions,
  });
  final FpUniverse universe;
  final List<FpAddAction> actions;
  @override
  Widget build(BuildContext context) {
    final words = FoundationWords.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: AppSpacing.dialog,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              words.text('quick.title'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              words.text('quick.hint'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.md),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: MediaQuery.sizeOf(context).width < 600 ? 2 : 3,
              childAspectRatio: 2.4,
              crossAxisSpacing: AppSpacing.sm,
              mainAxisSpacing: AppSpacing.sm,
              children: [
                for (final action in actions)
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      action.onTap();
                    },
                    icon: Icon(action.icon),
                    label: Text(words.text(action.labelKey)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class FpAddAction {
  const FpAddAction(this.labelKey, this.icon, this.onTap);
  final String labelKey;
  final IconData icon;
  final VoidCallback onTap;
}
