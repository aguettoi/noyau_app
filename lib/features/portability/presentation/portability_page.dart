import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_design_system.dart';
import '../../../core/localization/portability_locale.dart';
import '../../envelopes/presentation/envelope_dashboard_page.dart';
import '../../finance/presentation/accounts_page.dart';
import '../../finance/presentation/imports_page.dart';
import '../../finance/presentation/member_compensations_page.dart';
import '../../finance/presentation/transactions_page.dart';
import '../../organization/presentation/organization_page.dart';
import '../../priorities/presentation/priorities_page.dart';
import '../../savings_goals/presentation/savings_goals_page.dart';
import '../../shopping_list/presentation/shopping_list_page.dart';
import '../../wealth/presentation/wealth_page.dart';
import '../../wealth/application/providers/wealth_provider.dart';
import '../application/portability_provider.dart';
import '../application/portable_file_saver.dart';
import '../application/restitution_export_service.dart';
import '../domain/portability_models.dart';
import '../domain/restitution_models.dart';

class PortabilityPage extends StatelessWidget {
  const PortabilityPage({super.key});
  @override
  Widget build(BuildContext context) {
    final words = PortabilityWords.of(context);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(words.text('title')),
          bottom: TabBar(
            tabs: [
              Tab(text: words.text('search')),
              Tab(text: words.text('exports')),
              Tab(text: words.text('imports')),
            ],
          ),
        ),
        body: const TabBarView(
          children: [_SearchTab(), _ExportsTab(), _ImportsTab()],
        ),
      ),
    );
  }
}

class _SearchTab extends ConsumerStatefulWidget {
  const _SearchTab();
  @override
  ConsumerState<_SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends ConsumerState<_SearchTab> {
  Timer? debounce;
  String query = '';
  int page = 0;
  bool loading = false;
  String? error;
  final results = <GlobalSearchResult>[];
  @override
  void dispose() {
    debounce?.cancel();
    super.dispose();
  }

  void changed(String value) {
    debounce?.cancel();
    setState(() {
      query = value;
      error = null;
    });
    if (value.trim().length < 2) {
      setState(results.clear);
      return;
    }
    debounce = Timer(
      const Duration(milliseconds: 350),
      () => load(reset: true),
    );
  }

  Future<void> load({bool reset = false}) async {
    if (loading) return;
    setState(() {
      loading = true;
      if (reset) {
        page = 0;
        results.clear();
      }
    });
    try {
      final next = await ref
          .read(globalSearchGatewayProvider)
          .search(query, page: page);
      if (!mounted) return;
      setState(() {
        results.addAll(next);
        page++;
        error = null;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => error = PortabilityWords.of(context).text('search_failed'),
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final words = PortabilityWords.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: TextField(
            key: const Key('global-search-field'),
            onChanged: changed,
            decoration: InputDecoration(
              labelText: words.text('search_label'),
              prefixIcon: const Icon(Icons.search),
            ),
          ),
        ),
        if (loading) const LinearProgressIndicator(),
        if (error != null)
          Padding(padding: const EdgeInsets.all(16), child: Text(error!)),
        Expanded(
          child: query.trim().length < 2
              ? Center(child: Text(words.text('min_chars')))
              : results.isEmpty && !loading
              ? Center(child: Text(words.text('no_result')))
              : ListView.builder(
                  itemCount: results.length + 1,
                  itemBuilder: (_, index) {
                    if (index == results.length) {
                      return TextButton(
                        onPressed: loading ? null : load,
                        child: Text(words.text('show_more')),
                      );
                    }
                    final item = results[index];
                    return ListTile(
                      leading: const Icon(Icons.manage_search),
                      title: Text(item.title),
                      subtitle: Text(
                        words.format('result_summary', {
                          'type': _searchType(words, item.type),
                          'subtitle': item.subtitle,
                        }),
                      ),
                      trailing: item.amount == null
                          ? null
                          : Text(
                              words.format('amount', {
                                'amount': item.amount!.toStringAsFixed(2),
                              }),
                            ),
                      onTap: () => _openResult(context, item),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

String _searchType(PortabilityWords words, SearchResultType type) =>
    words.text('search_type.${type.name}');

void _openResult(BuildContext context, GlobalSearchResult result) {
  final page = switch (result.type) {
    SearchResultType.financialEvent => const TransactionsPage(),
    SearchResultType.account => const AccountsPage(),
    SearchResultType.envelope => const EnvelopeDashboardPage(),
    SearchResultType.obligation ||
    SearchResultType.receivable => const DebtsPage(),
    SearchResultType.compensation => const MemberCompensationsPage(),
    SearchResultType.goal => const SavingsGoalsPage(),
    SearchResultType.shopping => const ShoppingListPage(),
    SearchResultType.priority => const PrioritiesPage(),
    SearchResultType.task => const OrganizationPage(),
    SearchResultType.asset => const WealthPage(),
  };
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
}

class _ExportsTab extends ConsumerStatefulWidget {
  const _ExportsTab();
  @override
  ConsumerState<_ExportsTab> createState() => _ExportsTabState();
}

class _ExportsTabState extends ConsumerState<_ExportsTab> {
  bool busy = false;
  ReportPeriodicity periodicity = ReportPeriodicity.monthly;
  DateTime anchor = DateTime.now();
  Future<void> run(Future<PortableFile> Function() build) async {
    final words = PortabilityWords.of(context);
    setState(() => busy = true);
    try {
      final saved = await savePortableFile(await build());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              words.text(saved ? 'export_ready' : 'export_cancelled'),
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(words.text('export_failed'))));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final words = PortabilityWords.of(context);
    final service = ref.read(householdExportServiceProvider);
    final restitution = ref.read(restitutionExportServiceProvider);
    final period = RestitutionPeriod.forDate(anchor, periodicity);
    final wealth = ref.watch(wealthDataProvider).valueOrNull;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Text(words.text('local_notice')),
        if (busy) const LinearProgressIndicator(),
        ListTile(
          title: Text(words.text('transactions_csv')),
          trailing: const Icon(Icons.download),
          onTap: busy ? null : () => run(service.transactionsCsv),
        ),
        ListTile(
          title: Text(words.text('transactions_xlsx')),
          trailing: const Icon(Icons.table_rows),
          onTap: busy ? null : () => run(service.transactionsXlsx),
        ),
        ListTile(
          title: Text(words.text('household_xlsx')),
          trailing: const Icon(Icons.table_view),
          onTap: busy ? null : () => run(service.householdXlsx),
        ),
        ListTile(
          title: Text(words.text('summary_pdf')),
          trailing: const Icon(Icons.picture_as_pdf),
          onTap: busy ? null : () => run(service.summaryPdf),
        ),
        ListTile(
          title: Text(words.text('archive_zip')),
          subtitle: Text(words.text('archive_detail')),
          trailing: const Icon(Icons.archive),
          onTap: busy ? null : () => run(service.householdArchive),
        ),
        const Divider(),
        Text(
          words.text('business_reports'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(words.text('authorized_scope')),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            DropdownButton<ReportPeriodicity>(
              key: const Key('restitution-periodicity'),
              value: periodicity,
              items: [
                DropdownMenuItem(
                  value: ReportPeriodicity.monthly,
                  child: Text(words.text('monthly')),
                ),
                DropdownMenuItem(
                  value: ReportPeriodicity.quarterly,
                  child: Text(words.text('quarterly')),
                ),
                DropdownMenuItem(
                  value: ReportPeriodicity.semiannual,
                  child: Text(words.text('semiannual')),
                ),
                DropdownMenuItem(
                  value: ReportPeriodicity.annual,
                  child: Text(words.text('annual')),
                ),
              ],
              onChanged: busy
                  ? null
                  : (value) => setState(() => periodicity = value!),
            ),
            OutlinedButton.icon(
              key: const Key('restitution-date'),
              icon: const Icon(Icons.date_range),
              label: Text(period.label),
              onPressed: busy
                  ? null
                  : () async {
                      final chosen = await showDatePicker(
                        context: context,
                        initialDate: anchor,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (chosen != null && mounted) {
                        setState(() => anchor = chosen);
                      }
                    },
            ),
          ],
        ),
        ListTile(
          key: const Key('export-structured-xlsx'),
          title: Text(words.text('structured_xlsx')),
          subtitle: Text(words.text('structured_detail')),
          trailing: const Icon(Icons.grid_on),
          onTap: busy
              ? null
              : () => run(() => restitution.structuredXlsx(period)),
        ),
        ListTile(
          key: const Key('export-period-pdf'),
          title: Text(words.text('pdf_report')),
          subtitle: Text(words.format('pdf_detail', {'period': period.label})),
          trailing: const Icon(Icons.picture_as_pdf),
          onTap: busy ? null : () => run(() => restitution.periodPdf(period)),
        ),
        ListTile(
          key: const Key('export-period-pptx'),
          title: Text(words.text('pptx')),
          subtitle: Text(words.text('pptx_detail')),
          trailing: const Icon(Icons.slideshow),
          onTap: busy ? null : () => run(() => restitution.periodPptx(period)),
        ),
        ListTile(
          key: const Key('export-fiscal-housing'),
          title: Text(words.text('housing_tax')),
          subtitle: Text(words.text('housing_tax_detail')),
          trailing: const Icon(Icons.home_work_outlined),
          onTap: busy
              ? null
              : () => run(() => restitution.fiscalHousingXlsx(period)),
        ),
        if (wealth != null && wealth.financings.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(words.text('amortization')),
          ),
          for (final financing in wealth.financings)
            ListTile(
              key: Key('export-amortization-${financing.id}'),
              title: Text(financing.label),
              subtitle: Text(
                words.format('amortization_detail', {
                  'structure': financing.structure.name,
                }),
              ),
              trailing: const Icon(Icons.table_chart_outlined),
              onTap: busy
                  ? null
                  : () => run(() => restitution.amortizationXlsx(financing)),
            ),
        ],
      ],
    );
  }
}

class _ImportsTab extends ConsumerWidget {
  const _ImportsTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final words = PortabilityWords.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    return ref
        .watch(importHistoryProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Center(child: Text(words.text('imports_failed'))),
          data: (items) => ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              Text(words.text('imports_notice')),
              const SizedBox(height: 12),
              if (items.isEmpty) ListTile(title: Text(words.text('no_import'))),
              for (final item in items)
                ListTile(
                  title: Text(item.fileName),
                  subtitle: Text(
                    words.format('import_detail', {
                      'date': DateFormat.yMMMd(locale).format(item.createdAt),
                      'count': item.detectedRecords,
                      'actor': item.actorId,
                      'error': item.error == null
                          ? ''
                          : words.format('import_error', {
                              'error': item.error!,
                            }),
                    }),
                  ),
                  trailing: Chip(label: Text(item.status)),
                ),
              const Divider(),
              ListTile(
                title: Text(words.text('open_import')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const ImportsPage()),
                ),
              ),
            ],
          ),
        );
  }
}
