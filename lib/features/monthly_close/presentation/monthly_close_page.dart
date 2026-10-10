import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/money/money.dart';
import '../../../core/theme/app_design_system.dart';
import '../../envelopes/application/providers/remote_envelopes_provider.dart';
import '../../finance/application/providers/remote_accounts_provider.dart';
import '../../finance/presentation/accounts_page.dart';
import '../../finance/presentation/member_compensations_page.dart';
import '../../finance/presentation/transactions_page.dart';
import '../application/monthly_close_provider.dart';
import '../domain/monthly_close.dart';

class MonthlyClosePage extends ConsumerWidget {
  const MonthlyClosePage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(monthlyCloseProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Fin de mois')),
      body: SafeArea(
        child: value.when(
          loading: () => const FpLoadingState(label: 'Analyse du mois…'),
          error: (_, _) => const FpErrorState(
            message: 'La préparation de clôture ne peut pas être chargée.',
          ),
          data: (snapshot) => LayoutBuilder(
            builder: (context, box) => ListView(
              key: const Key('monthly-close-page'),
              padding: AppLayout.pagePaddingFor(box.maxWidth),
              children: [
                FpPageHeader(
                  title: 'Clôture mensuelle',
                  subtitle:
                      'Checklist explicable • ${snapshot.month.month.toString().padLeft(2, '0')}/${snapshot.month.year}',
                ),
                const SizedBox(height: AppSpacing.md),
                _Health(snapshot),
                const SizedBox(height: AppSpacing.md),
                _Kpis(snapshot.kpis),
                const SizedBox(height: AppSpacing.md),
                const _Workflow(),
                const SizedBox(height: AppSpacing.md),
                _Todo(snapshot),
                const SizedBox(height: AppSpacing.md),
                _TargetConfiguration(snapshot),
                const SizedBox(height: AppSpacing.md),
                _CloseAction(snapshot),
                if (snapshot.history.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  _History(snapshot.history),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Kpis extends StatelessWidget {
  const _Kpis(this.kpis);
  final ReliabilityKpis? kpis;
  @override
  Widget build(BuildContext context) {
    final value = kpis;
    if (value == null) return const SizedBox.shrink();
    String percent(int count) => '${(value.ratio(count) * 100).round()} %';
    return FpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Fiabilité des saisies',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.xs,
            children: [
              Text('J+0 ${percent(value.sameDay)}'),
              Text('J+1 ${percent(value.withinOneDay)}'),
              Text('J+3 ${percent(value.withinThreeDays)}'),
              Text('${value.late} saisie(s) tardive(s)'),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          const SecondaryInfoText(
            'Attribution : FOYER / NON ATTRIBUÉ lorsque la responsabilité ne peut pas être démontrée.',
          ),
        ],
      ),
    );
  }
}

class _Health extends StatelessWidget {
  const _Health(this.snapshot);
  final MonthlyCloseSnapshot snapshot;
  @override
  Widget build(BuildContext context) => FpCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Santé du mois',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Text(
              '${snapshot.healthPercent} %',
              key: const Key('month-health-percent'),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        LinearProgressIndicator(value: snapshot.healthPercent / 100),
        const SizedBox(height: AppSpacing.sm),
        Text(
          snapshot.ready
              ? 'Prêt sous réserve des avertissements'
              : '${snapshot.blockers} condition(s) bloquante(s) à traiter',
        ),
        Text(
          '${snapshot.warnings} avertissement(s)',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
  );
}

class _Workflow extends StatelessWidget {
  const _Workflow();
  static const labels = [
    'Saisies',
    'Justificatifs',
    'Rapprochements',
    'Inventaire espèces',
    'Traitement des écarts',
    'Compensations',
    'Régularisations',
    'Virements / retraits',
    'Contrôle final',
    'Clôture',
  ];
  @override
  Widget build(BuildContext context) => FpCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Parcours guidé', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (var i = 0; i < labels.length; i++)
              Chip(
                avatar: CircleAvatar(child: Text('${i + 1}')),
                label: Text(labels[i]),
              ),
          ],
        ),
      ],
    ),
  );
}

class _Todo extends StatelessWidget {
  const _Todo(this.snapshot);
  final MonthlyCloseSnapshot snapshot;
  @override
  Widget build(BuildContext context) {
    final active = snapshot.issues.where((issue) => issue.count > 0);
    return FpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'À faire financier',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (active.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: AppSpacing.xs),
              child: SecondaryInfoText('Aucune anomalie actionnable détectée.'),
            ),
          for (final issue in active)
            ListTile(
              key: Key('todo-${issue.code}'),
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                issue.severity == CloseIssueSeverity.blocker
                    ? Icons.block
                    : Icons.warning_amber,
                color: issue.severity == CloseIssueSeverity.blocker
                    ? AppColors.danger
                    : AppColors.warning,
              ),
              title: Text(issue.label),
              subtitle: Text(
                '${issue.count} élément(s) • ${issue.destination}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openDestination(context, issue),
            ),
        ],
      ),
    );
  }

  void _openDestination(BuildContext context, CloseIssue issue) {
    final page = switch (issue.code) {
      'reconciliations' || 'cash' => const AccountsPage(),
      'receipts' => const TransactionsPage(),
      'compensations' => const MemberCompensationsPage(),
      _ => null,
    };
    if (page == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cette destination n’est plus disponible.'),
        ),
      );
      return;
    }
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }
}

class _TargetConfiguration extends ConsumerWidget {
  const _TargetConfiguration(this.snapshot);
  final MonthlyCloseSnapshot snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final targets = ref.watch(monthlyCloseTargetsProvider);
    final accounts = ref.watch(remoteAccountsProvider).valueOrNull ?? const [];
    final envelopes =
        ref.watch(remoteEnvelopeBalancesProvider).valueOrNull ?? const [];
    String accountName(String id) =>
        accounts
            .where((account) => account.id == id)
            .map((account) => account.name)
            .firstOrNull ??
        'Compte indisponible';
    String envelopeName(String id) =>
        envelopes
            .where((envelope) => envelope.id == id)
            .map((envelope) => envelope.name)
            .firstOrNull ??
        'Enveloppe indisponible';
    return FpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Cibles compte × enveloppe',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              FilledButton.tonalIcon(
                key: const Key('add-monthly-target'),
                onPressed:
                    snapshot.status == MonthlyCloseStatus.closed ||
                        accounts.isEmpty ||
                        envelopes.isEmpty
                    ? null
                    : () => _edit(context, ref, accounts, envelopes),
                icon: const Icon(Icons.add),
                label: const Text('Définir'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          const SecondaryInfoText(
            'Définissez la répartition mensuelle attendue. Cette configuration ne déplace aucun argent.',
          ),
          targets.when(
            loading: () => const LinearProgressIndicator(),
            error: (_, _) => const Padding(
              padding: EdgeInsets.only(top: AppSpacing.sm),
              child: Text('Impossible de charger les cibles mensuelles.'),
            ),
            data: (items) => items.isEmpty
                ? const ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.account_tree_outlined),
                    title: Text('Aucune cible configurée'),
                    subtitle: Text(
                      'Ajoutez une enveloppe et son compte cible.',
                    ),
                  )
                : Column(
                    children: [
                      for (final item in items)
                        ListTile(
                          key: Key('monthly-target-${item.id}'),
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.account_tree_outlined),
                          title: Text(envelopeName(item.envelopeId)),
                          subtitle: Text(accountName(item.accountId)),
                          trailing: Text(
                            '${item.amount.dirhams.toStringAsFixed(2)} MAD',
                          ),
                          onTap: snapshot.status == MonthlyCloseStatus.closed
                              ? null
                              : () => _edit(
                                  context,
                                  ref,
                                  accounts,
                                  envelopes,
                                  existing: item,
                                ),
                        ),
                    ],
                  ),
          ),
          const Divider(),
          const SecondaryInfoText(
            'La proposition de régularisation reste une simulation tant que vous ne confirmez pas un transfert canonique.',
          ),
        ],
      ),
    );
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    List<dynamic> accounts,
    List<dynamic> envelopes, {
    MonthlyEnvelopeAccountTarget? existing,
  }) async {
    var envelopeId = existing?.envelopeId ?? envelopes.first.id as String;
    var accountId = existing?.accountId ?? accounts.first.id as String;
    final amount = TextEditingController(
      text: existing?.amount.dirhams.toStringAsFixed(2) ?? '',
    );
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Cible mensuelle'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  key: const Key('target-envelope'),
                  initialValue: envelopeId,
                  decoration: const InputDecoration(labelText: 'Enveloppe'),
                  items: [
                    for (final envelope in envelopes)
                      DropdownMenuItem<String>(
                        value: envelope.id as String,
                        child: Text(envelope.name as String),
                      ),
                  ],
                  onChanged: (value) => setState(() => envelopeId = value!),
                ),
                const SizedBox(height: AppSpacing.sm),
                DropdownButtonFormField<String>(
                  key: const Key('target-account'),
                  initialValue: accountId,
                  decoration: const InputDecoration(labelText: 'Compte cible'),
                  items: [
                    for (final account in accounts)
                      DropdownMenuItem<String>(
                        value: account.id as String,
                        child: Text(account.name as String),
                      ),
                  ],
                  onChanged: (value) => setState(() => accountId = value!),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  key: const Key('target-amount'),
                  controller: amount,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Montant cible (MAD)',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              key: const Key('save-monthly-target'),
              onPressed: () {
                final parsed = double.tryParse(
                  amount.text.replaceAll(',', '.'),
                );
                if (parsed == null || parsed < 0) return;
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
    if (accepted != true || !context.mounted) return;
    try {
      await ref.read(setMonthlyCloseTargetProvider)(
        month: snapshot.month,
        envelopeId: envelopeId,
        accountId: accountId,
        amount: Money.fromDirhams(
          double.parse(amount.text.replaceAll(',', '.')),
        ),
      );
      ref.invalidate(monthlyCloseTargetsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cible mensuelle enregistrée.')),
        );
      }
    } on Exception {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('La cible n’a pas pu être enregistrée.'),
          ),
        );
      }
    }
  }
}

class _CloseAction extends ConsumerWidget {
  const _CloseAction(this.snapshot);
  final MonthlyCloseSnapshot snapshot;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final busy = ref.watch(monthlyCloseMutationBusyProvider);
    return FpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Contrôle final',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            snapshot.blockers > 0
                ? 'Clôture impossible tant que les conditions bloquantes subsistent.'
                : snapshot.warnings > 0
                ? 'Clôture possible par un OWNER avec motif de dérogation.'
                : 'Tous les contrôles obligatoires sont satisfaits.',
          ),
          const SizedBox(height: AppSpacing.sm),
          if (snapshot.status == MonthlyCloseStatus.closed)
            FilledButton.icon(
              key: const Key('reopen-month-button'),
              onPressed: snapshot.owner && !busy
                  ? () => _reopen(context, ref)
                  : null,
              icon: busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.lock_open_outlined),
              label: const Text('Réouvrir le mois'),
            )
          else
            FilledButton.icon(
              key: const Key('close-month-button'),
              onPressed: snapshot.blockers > 0 || busy
                  ? null
                  : () => _confirm(context, ref),
              icon: const Icon(Icons.lock_outline),
              label: const Text('Clôturer le mois'),
            ),
        ],
      ),
    );
  }

  Future<void> _reopen(BuildContext context, WidgetRef ref) async {
    final reason = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Réouvrir le mois ?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'La clôture reste dans l’historique. Les contrôles seront recalculés et une nouvelle clôture sera nécessaire.',
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              key: const Key('reopen-reason'),
              controller: reason,
              decoration: const InputDecoration(labelText: 'Motif obligatoire'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, reason.text.trim().isNotEmpty),
            child: const Text('Confirmer la réouverture'),
          ),
        ],
      ),
    );
    if (accepted != true || snapshot.periodId == null) return;
    ref.read(monthlyCloseMutationBusyProvider.notifier).state = true;
    try {
      await ref.read(reopenMonthlyCloseProvider)(
        snapshot.periodId!,
        reason.text.trim(),
      );
      ref.invalidate(monthlyCloseProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Le mois a été réouvert.')),
        );
      }
    } on Exception {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('La réouverture a échoué.')),
        );
      }
    } finally {
      ref.read(monthlyCloseMutationBusyProvider.notifier).state = false;
    }
  }

  Future<void> _confirm(BuildContext context, WidgetRef ref) async {
    final reason = TextEditingController();
    final override = snapshot.warnings > 0;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          override ? 'Dérogation de clôture' : 'Confirmer la clôture',
        ),
        content: override
            ? TextField(
                key: const Key('close-override-reason'),
                controller: reason,
                decoration: const InputDecoration(
                  labelText: 'Motif obligatoire',
                ),
              )
            : const Text(
                'La clôture sera historisée et une réouverture exigera un motif.',
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              !override || reason.text.trim().isNotEmpty,
            ),
            child: const Text('Confirmer'),
          ),
        ],
      ),
    );
    if (accepted != true) return;
    await ref
        .read(monthlyCloseGatewayProvider)
        .close(
          snapshot.month,
          overrideWarnings: override,
          reason: reason.text.trim(),
        );
    ref.invalidate(monthlyCloseProvider);
  }
}

class _History extends StatelessWidget {
  const _History(this.entries);
  final List<MonthlyCloseAuditEntry> entries;
  @override
  Widget build(BuildContext context) => FpCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Historique', style: Theme.of(context).textTheme.titleMedium),
        for (final entry in entries)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.history),
            title: Text(entry.kind),
            subtitle: Text(
              '${entry.actor} • ${entry.at.toLocal()}${entry.reason == null ? '' : '\n${entry.reason}'}',
            ),
          ),
      ],
    ),
  );
}
