import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_design_system.dart';
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
import '../application/portability_provider.dart';
import '../application/portable_file_saver.dart';
import '../domain/portability_models.dart';

class PortabilityPage extends StatelessWidget {
  const PortabilityPage({super.key});
  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 3,
    child: Scaffold(
      appBar: AppBar(
        title: Text('Recherche et portabilité'),
        bottom: TabBar(
          tabs: [
            Tab(text: 'Recherche'),
            Tab(text: 'Exports'),
            Tab(text: 'Imports'),
          ],
        ),
      ),
      body: const TabBarView(
        children: [_SearchTab(), _ExportsTab(), _ImportsTab()],
      ),
    ),
  );
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
        setState(() => error = 'Recherche momentanément indisponible.');
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: TextField(
          key: const Key('global-search-field'),
          onChanged: changed,
          decoration: const InputDecoration(
            labelText: 'Rechercher dans le foyer',
            prefixIcon: Icon(Icons.search),
          ),
        ),
      ),
      if (loading) const LinearProgressIndicator(),
      if (error != null)
        Padding(padding: const EdgeInsets.all(16), child: Text(error!)),
      Expanded(
        child: query.trim().length < 2
            ? const Center(child: Text('Saisissez au moins 2 caractères.'))
            : results.isEmpty && !loading
            ? const Center(child: Text('Aucun résultat.'))
            : ListView.builder(
                itemCount: results.length + 1,
                itemBuilder: (_, index) {
                  if (index == results.length) {
                    return TextButton(
                      onPressed: loading ? null : load,
                      child: const Text('Afficher plus'),
                    );
                  }
                  final item = results[index];
                  return ListTile(
                    leading: const Icon(Icons.manage_search),
                    title: Text(item.title),
                    subtitle: Text('${item.type.name} • ${item.subtitle}'),
                    trailing: item.amount == null
                        ? null
                        : Text('${item.amount!.toStringAsFixed(2)} MAD'),
                    onTap: () => _openResult(context, item),
                  );
                },
              ),
      ),
    ],
  );
}

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
  Future<void> run(Future<PortableFile> Function() build) async {
    setState(() => busy = true);
    try {
      await savePortableFile(await build());
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Export prêt.')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("L'export n'a pas pu être généré.")),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = ref.read(householdExportServiceProvider);
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        const Text(
          'Les exports sont générés localement et ne sont téléversés vers aucun service tiers.',
        ),
        if (busy) const LinearProgressIndicator(),
        ListTile(
          title: const Text('Transactions CSV'),
          trailing: const Icon(Icons.download),
          onTap: busy ? null : () => run(service.transactionsCsv),
        ),
        ListTile(
          title: const Text('Transactions XLSX'),
          trailing: const Icon(Icons.table_rows),
          onTap: busy ? null : () => run(service.transactionsXlsx),
        ),
        ListTile(
          title: const Text('Données du foyer XLSX'),
          trailing: const Icon(Icons.table_view),
          onTap: busy ? null : () => run(service.householdXlsx),
        ),
        ListTile(
          title: const Text('Synthèse foyer PDF'),
          trailing: const Icon(Icons.picture_as_pdf),
          onTap: busy ? null : () => run(service.summaryPdf),
        ),
        ListTile(
          title: const Text('Export complet ZIP'),
          subtitle: const Text(
            'JSON lisible, transactions CSV et métadonnées des justificatifs privés',
          ),
          trailing: const Icon(Icons.archive),
          onTap: busy ? null : () => run(service.householdArchive),
        ),
      ],
    );
  }
}

class _ImportsTab extends ConsumerWidget {
  const _ImportsTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(importHistoryProvider)
      .when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(
          child: Text("Impossible de charger l'historique des imports."),
        ),
        data: (items) => ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            const Text(
              'Un import non appliqué peut être abandonné. Après matérialisation, toute correction reste append-only et passe par les reversals canoniques.',
            ),
            const SizedBox(height: 12),
            if (items.isEmpty)
              const ListTile(title: Text('Aucun import enregistré.')),
            for (final item in items)
              ListTile(
                title: Text(item.fileName),
                subtitle: Text(
                  '${DateFormat.yMMMd('fr').format(item.createdAt)} • ${item.detectedRecords} ligne(s) • acteur ${item.actorId}${item.error == null ? '' : ' • ${item.error}'}',
                ),
                trailing: Chip(label: Text(item.status)),
              ),
            const Divider(),
            ListTile(
              title: const Text('Ouvrir l’assistant Import'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const ImportsPage()),
              ),
            ),
          ],
        ),
      );
}
