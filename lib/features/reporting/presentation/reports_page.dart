import 'package:flutter/material.dart';

import '../../../core/localization/foundation_locale.dart';
import 'business_reporting_panel.dart';

class ReportsPage extends StatelessWidget {
  const ReportsPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(FoundationWords.of(context).text('reports'))),
    body: const SafeArea(child: BusinessReportingPanel()),
  );
}
