import 'package:flutter/material.dart';

import '../../../core/theme/app_design_system.dart';
import '../../operational_kpis/presentation/operational_kpi_panel.dart';
import '../application/providers/remote_financial_dashboard_provider.dart';
import 'dashboard_home_locale.dart';
import 'dashboard_v2_panels.dart';

class DashboardAnalyticsPage extends StatelessWidget {
  const DashboardAnalyticsPage({super.key, required this.snapshot});
  final FinancialDashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(DashboardHomeWords.of(context).text('analytics')),
    ),
    body: ListView(
      padding: AppSpacing.page,
      children: [
        DashboardV2Panels(
          snapshot: snapshot,
          open: (destination) => Navigator.of(context).pop(destination),
        ),
        const SizedBox(height: AppSpacing.md),
        const OperationalKpiPanel(),
      ],
    ),
  );
}
