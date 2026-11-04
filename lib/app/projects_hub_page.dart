import 'package:flutter/material.dart';

import 'fp_universe_hub.dart';

/// D1.2-F presentation-only entry point for decisions and long-term projects.
/// Every destination delegates to an existing canonical feature.
class ProjectsHubPage extends StatelessWidget {
  const ProjectsHubPage({
    super.key,
    required this.onOpenGoals,
    required this.onOpenPriorities,
    required this.onOpenSimulations,
    required this.onOpenFinancings,
    required this.onOpenWealth,
  });

  final VoidCallback onOpenGoals;
  final VoidCallback onOpenPriorities;
  final VoidCallback onOpenSimulations;
  final VoidCallback onOpenFinancings;
  final VoidCallback onOpenWealth;

  @override
  Widget build(BuildContext context) => FpUniverseHub(
    titleKey: 'projects',
    subtitleKey: 'projects.subtitle',
    destinations: [
      FpUniverseDestination(
        labelKey: 'goals',
        icon: Icons.savings_outlined,
        open: onOpenGoals,
      ),
      FpUniverseDestination(
        labelKey: 'priorities',
        icon: Icons.low_priority,
        open: onOpenPriorities,
      ),
      FpUniverseDestination(
        labelKey: 'simulations',
        icon: Icons.science_outlined,
        open: onOpenSimulations,
      ),
      FpUniverseDestination(
        labelKey: 'financings',
        icon: Icons.compare_arrows,
        open: onOpenFinancings,
      ),
      FpUniverseDestination(
        labelKey: 'wealth',
        icon: Icons.account_balance_outlined,
        open: onOpenWealth,
      ),
    ],
  );
}
