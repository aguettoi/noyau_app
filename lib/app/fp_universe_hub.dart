import 'package:flutter/material.dart';

import '../core/localization/foundation_locale.dart';
import '../core/theme/app_design_system.dart';
import '../core/theme/fp_foundation_components.dart';

class FpUniverseDestination {
  const FpUniverseDestination({
    required this.labelKey,
    required this.icon,
    required this.open,
    this.description,
  });
  final String labelKey;
  final IconData icon;
  final VoidCallback open;
  final String? description;
}

class FpUniverseHub extends StatelessWidget {
  const FpUniverseHub({
    super.key,
    required this.titleKey,
    required this.subtitleKey,
    required this.destinations,
  });
  final String titleKey;
  final String subtitleKey;
  final List<FpUniverseDestination> destinations;
  @override
  Widget build(BuildContext context) {
    final words = FoundationWords.of(context);
    return SafeArea(
      child: ListView(
        children: [
          DesktopPageContainer(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FpPageHeader(
                  title: words.text(titleKey),
                  subtitle: words.text(subtitleKey),
                ),
                const SizedBox(height: AppSpacing.lg),
                FpSearchFilterBar(onChanged: (_) {}),
                const SizedBox(height: AppSpacing.lg),
                ResponsiveGrid(
                  minItemWidth: 280,
                  children: [
                    for (final item in destinations)
                      FpActionCard(
                        title: words.text(item.labelKey),
                        subtitle: item.description,
                        icon: item.icon,
                        onTap: item.open,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
