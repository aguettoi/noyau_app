import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/money/money.dart';
import '../../../core/theme/app_design_system.dart';
import '../../envelopes/application/providers/remote_envelopes_provider.dart';
import '../../finance/application/providers/remote_accounts_provider.dart';
import '../../finance/application/providers/remote_account_balances_provider.dart';
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
                _Workflow(snapshot),
                const SizedBox(height: AppSpacing.md),
                _Todo(snapshot),
                const SizedBox(height: AppSpacing.md),
                _TargetConfiguration(snapshot),
                const SizedBox(height: AppSpacing.md),
                _CurrentTargetPanel(snapshot),
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

class _CurrentTargetPanel extends ConsumerWidget {
  const _CurrentTargetPanel(this.snapshot);
  final MonthlyCloseSnapshot snapshot;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matrix = ref.watch(envelopeAccountMatrixProvider);
    final targets = ref.watch(monthlyCloseTargetsProvider);
    final accounts = ref.watch(remoteAccountsProvider).valueOrNull ?? const [];
    final accountBalances =
        ref.watch(remoteAccountBalancesProvider).valueOrNull ?? const {};
    final envelopes =
        ref.watch(remoteEnvelopeBalancesProvider).valueOrNull ?? const [];
    String accountName(String id) =>
        accounts.where((e) => e.id == id).map((e) => e.name).firstOrNull ??
        'Compte';
    String envelopeName(String id) =>
        envelopes.where((e) => e.id == id).map((e) => e.name).firstOrNull ??
        'Enveloppe';
    return FpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Actuel → cible',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          matrix.when(
            loading: () => const LinearProgressIndicator(),
            error: (_, _) => const SecondaryInfoText(
              'La position compte × enveloppe ne peut pas être chargée.',
            ),
            data: (value) {
              if (!value.reliable) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Position actuelle à fiabiliser',
                      key: Key('matrix-unreliable'),
                    ),
                    Text(
                      'Écart comptes : ${value.accountGap.dirhams.toStringAsFixed(2)} MAD • écart enveloppes : ${value.envelopeGap.dirhams.toStringAsFixed(2)} MAD',
                    ),
                    const SecondaryInfoText(
                      'Aucune répartition historique n’est inventée. Un OWNER doit établir un point de départ explicite après inventaire.',
                    ),
                    if (snapshot.blockers > 0)
                      const SecondaryInfoText(
                        'Initialisation indisponible : fiabilisez d’abord les soldes, rapprochements et espèces.',
                      ),
                    const SizedBox(height: AppSpacing.sm),
                    if (snapshot.owner)
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.tonalIcon(
                          key: const Key('initialize-matrix'),
                          onPressed:
                              accounts.isEmpty ||
                                  envelopes.isEmpty ||
                                  snapshot.blockers > 0
                              ? null
                              : () => _initialize(
                                  context,
                                  ref,
                                  accounts,
                                  envelopes,
                                  accountBalances,
                                ),
                          icon: const Icon(Icons.fact_check_outlined),
                          label: const Text('Établir le point de départ'),
                        ),
                      ),
                  ],
                );
              }
              final configured =
                  targets.valueOrNull ?? const <MonthlyEnvelopeAccountTarget>[];
              final keys = <(String, String)>{
                for (final p in value.positions) (p.accountId, p.envelopeId),
                for (final t in configured) (t.accountId, t.envelopeId),
              };
              final rows = [
                for (final key in keys)
                  EnvelopeAccountTarget(
                    memberId: null,
                    accountId: key.$1,
                    envelopeId: key.$2,
                    current:
                        value.positions
                            .where(
                              (p) =>
                                  p.accountId == key.$1 &&
                                  p.envelopeId == key.$2,
                            )
                            .map((p) => p.amount)
                            .firstOrNull ??
                        const Money.fromMinorUnits(0),
                    target:
                        configured
                            .where(
                              (t) =>
                                  t.accountId == key.$1 &&
                                  t.envelopeId == key.$2,
                            )
                            .map((t) => t.amount)
                            .firstOrNull ??
                        const Money.fromMinorUnits(0),
                  ),
              ];
              final moves = proposeEnvelopeAccountMoves(rows);
              return Column(
                children: [
                  const SecondaryInfoText(
                    'Position actuelle réconciliée avec les comptes et les enveloppes.',
                  ),
                  for (final row in rows)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '${envelopeName(row.envelopeId)} • ${accountName(row.accountId)}',
                      ),
                      subtitle: const Text('ACTUEL  |  CIBLE  |  ÉCART'),
                      trailing: Text(
                        '${row.current.dirhams.toStringAsFixed(2)} | ${row.target.dirhams.toStringAsFixed(2)} | ${row.delta.dirhams.toStringAsFixed(2)}',
                      ),
                    ),
                  const Divider(),
                  Text(
                    '${moves.length} opération(s) proposée(s)',
                    key: const Key('reallocation-count'),
                  ),
                  for (final move in moves)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.swap_horiz),
                      title: Text(
                        '${accountName(move.fromAccountId)} → ${accountName(move.toAccountId)}',
                      ),
                      subtitle: Text(envelopeName(move.envelopeId)),
                      trailing: Text(
                        '${move.amount.dirhams.toStringAsFixed(2)} MAD',
                      ),
                    ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      key: const Key('confirm-reallocation'),
                      onPressed:
                          moves.isEmpty ||
                              snapshot.status == MonthlyCloseStatus.closed ||
                              snapshot.blockers > 0
                          ? null
                          : () => _confirm(context, ref, value, moves),
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('Prévisualiser et confirmer'),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _confirm(
    BuildContext context,
    WidgetRef ref,
    EnvelopeAccountMatrix matrix,
    List<EnvelopeAccountMove> moves,
  ) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirmer les virements ?'),
        content: Text(
          '${moves.length} virement(s) canonique(s) seront enregistrés. Aucun mouvement d’enveloppe supplémentaire ne sera créé.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            key: const Key('execute-reallocation'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirmer'),
          ),
        ],
      ),
    );
    if (accepted != true) return;
    try {
      await ref.read(executeMonthlyReallocationProvider)(
        snapshot.month,
        matrix,
        moves,
      );
      ref.invalidate(envelopeAccountMatrixProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Régularisation enregistrée.')),
        );
      }
    } on Exception {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'La proposition a changé ou ne peut pas être exécutée.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _initialize(
    BuildContext context,
    WidgetRef ref,
    List<dynamic> accounts,
    List<dynamic> envelopes,
    Map<String, Money> accountBalances,
  ) async {
    final result =
        await showDialog<
          ({List<EnvelopeAccountPosition> positions, String note})
        >(
          context: context,
          builder: (context) => _PositionSnapshotDialog(
            accounts: accounts,
            envelopes: envelopes,
            accountBalances: accountBalances,
          ),
        );
    if (result == null) return;
    try {
      await ref.read(setEnvelopeAccountSnapshotProvider)(
        result.positions,
        result.note,
      );
      ref.invalidate(envelopeAccountMatrixProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Point de départ vérifié et enregistré.'),
          ),
        );
      }
    } on Exception {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Les montants doivent réconcilier exactement tous les comptes et toutes les enveloppes.',
            ),
          ),
        );
      }
    }
  }
}

class _PositionSnapshotDialog extends StatefulWidget {
  const _PositionSnapshotDialog({
    required this.accounts,
    required this.envelopes,
    required this.accountBalances,
  });
  final List<dynamic> accounts, envelopes;
  final Map<String, Money> accountBalances;
  @override
  State<_PositionSnapshotDialog> createState() =>
      _PositionSnapshotDialogState();
}

class _PositionSnapshotDialogState extends State<_PositionSnapshotDialog> {
  final rows = <_PositionDraft>[];
  final note = TextEditingController();
  @override
  void initState() {
    super.initState();
    note.addListener(_changed);
    for (final envelope in widget.envelopes) {
      for (final account in widget.accounts) {
        final row = _PositionDraft(account.id as String, envelope.id as String);
        row.amount.addListener(_changed);
        rows.add(row);
      }
    }
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    for (final row in rows) {
      row.amount.removeListener(_changed);
      row.amount.dispose();
    }
    note.removeListener(_changed);
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog.fullscreen(
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Point de départ compte × enveloppe'),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close),
        ),
        actions: [
          FilledButton(
            key: const Key('save-matrix-snapshot'),
            onPressed: _balanced ? () => _save(context) : null,
            child: const Text('Vérifier et enregistrer'),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) => ListView(
            padding: AppLayout.pagePaddingFor(box.maxWidth),
            children: [
              const SecondaryInfoText(
                'Saisissez la matrice globale réellement vérifiée. Les totaux des lignes et colonnes doivent correspondre aux soldes canoniques.',
              ),
              const SizedBox(height: AppSpacing.sm),
              if (box.maxWidth >= 760) _desktopMatrix() else _mobileMatrix(),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.xs,
                children: [
                  for (final a in widget.accounts)
                    Text(
                      '${a.name}: réparti ${_money(_accountTotal(a.id as String))} / solde ${_money(widget.accountBalances[a.id as String]?.minorUnits ?? 0)} / écart ${_money(_accountTotal(a.id as String) - (widget.accountBalances[a.id as String]?.minorUnits ?? 0))}',
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: note,
                decoration: const InputDecoration(
                  labelText: 'Note d’inventaire obligatoire',
                ),
              ),
              if (!_balanced)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Text(
                    'Validation indisponible : corrigez les écarts de lignes et de colonnes.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _desktopMatrix() => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: DataTable(
      columns: [
        const DataColumn(label: Text('Enveloppe')),
        for (final a in widget.accounts)
          DataColumn(label: Text(a.name as String)),
        const DataColumn(label: Text('Total réparti')),
        const DataColumn(label: Text('Solde enveloppe')),
        const DataColumn(label: Text('Écart')),
      ],
      rows: [
        for (final e in widget.envelopes)
          DataRow(
            cells: [
              DataCell(Text(e.name as String)),
              for (final a in widget.accounts)
                DataCell(
                  SizedBox(
                    width: 105,
                    child: _amountField(_row(a.id as String, e.id as String)),
                  ),
                ),
              DataCell(Text(_money(_envelopeTotal(e.id as String)))),
              DataCell(Text(_money((e.balance as Money).minorUnits))),
              DataCell(
                Text(
                  _money(
                    _envelopeTotal(e.id as String) -
                        (e.balance as Money).minorUnits,
                  ),
                ),
              ),
            ],
          ),
      ],
    ),
  );

  Widget _mobileMatrix() => Column(
    children: [
      for (final e in widget.envelopes)
        Card(
          child: Padding(
            padding: AppSpacing.card,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.name as String,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                for (final a in widget.accounts)
                  Row(
                    children: [
                      Expanded(child: Text(a.name as String)),
                      SizedBox(
                        width: 130,
                        child: _amountField(
                          _row(a.id as String, e.id as String),
                        ),
                      ),
                    ],
                  ),
                Text(
                  'Réparti ${_money(_envelopeTotal(e.id as String))} / solde ${_money((e.balance as Money).minorUnits)} • écart ${_money(_envelopeTotal(e.id as String) - (e.balance as Money).minorUnits)}',
                ),
              ],
            ),
          ),
        ),
    ],
  );

  Widget _amountField(_PositionDraft row) => TextField(
    key: Key('matrix-${row.envelopeId}-${row.accountId}'),
    controller: row.amount,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: const InputDecoration(labelText: 'MAD', isDense: true),
  );

  _PositionDraft _row(String accountId, String envelopeId) => rows.firstWhere(
    (r) => r.accountId == accountId && r.envelopeId == envelopeId,
  );
  int _cents(_PositionDraft row) =>
      ((double.tryParse(row.amount.text.trim().replaceAll(',', '.')) ?? 0) *
              100)
          .round();
  int _envelopeTotal(String id) => rows
      .where((r) => r.envelopeId == id)
      .fold(0, (sum, r) => sum + _cents(r));
  int _accountTotal(String id) =>
      rows.where((r) => r.accountId == id).fold(0, (sum, r) => sum + _cents(r));
  String _money(int cents) => '${(cents / 100).toStringAsFixed(2)} MAD';
  bool get _balanced =>
      note.text.trim().isNotEmpty &&
      widget.envelopes.every(
        (e) =>
            _envelopeTotal(e.id as String) == (e.balance as Money).minorUnits,
      ) &&
      widget.accounts.every(
        (a) =>
            _accountTotal(a.id as String) ==
            (widget.accountBalances[a.id as String]?.minorUnits ?? 0),
      );
  void _save(BuildContext context) {
    if (!_balanced) return;
    final positions = <EnvelopeAccountPosition>[];
    for (final row in rows) {
      final amount = double.tryParse(row.amount.text.replaceAll(',', '.'));
      if (amount == null || amount < 0) return;
      if (amount == 0) continue;
      positions.add(
        EnvelopeAccountPosition(
          accountId: row.accountId,
          envelopeId: row.envelopeId,
          amount: Money.fromDirhams(amount),
        ),
      );
    }
    Navigator.pop(context, (positions: positions, note: note.text.trim()));
  }
}

class _PositionDraft {
  _PositionDraft(this.accountId, this.envelopeId);
  String accountId, envelopeId;
  final amount = TextEditingController();
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
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.xxs,
          children: [
            for (final entry in snapshot.healthBreakdown.entries)
              Text(
                '${_healthLabel(entry.key)} : ${entry.value} %',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
        const SecondaryInfoText(
          'Le score décrit la qualité du mois. Le statut Prêt à clôturer dépend séparément des conditions bloquantes.',
        ),
        Text(
          '${snapshot.warnings} avertissement(s)',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
  );
}

String _healthLabel(String key) => switch (key) {
  'entries' => 'Saisies',
  'receipts' => 'Justificatifs',
  'reconciliations' => 'Rapprochements',
  'cash' => 'Espèces',
  'differences' => 'Écarts',
  'compensations' => 'Compensations',
  _ => 'Régularisation',
};

class _Workflow extends StatelessWidget {
  const _Workflow(this.snapshot);
  final MonthlyCloseSnapshot snapshot;
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
        for (var i = 0; i < labels.length; i++)
          ListTile(
            key: Key('workflow-step-${i + 1}'),
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(child: Text('${i + 1}')),
            title: Text(labels[i]),
            subtitle: Text(_stepState(i)),
            trailing: i < 6 ? const Icon(Icons.chevron_right) : null,
            onTap: i < 6 ? () => _open(context, i) : null,
          ),
      ],
    ),
  );

  String _stepState(int index) {
    if (index >= 6 && snapshot.blockers > 0) {
      return 'BLOQUÉ — fiabilisez d’abord les soldes et écarts.';
    }
    final codes = switch (index) {
      1 => const {'receipts'},
      2 => const {'reconciliations'},
      3 => const {'cash'},
      4 => const {'differences'},
      5 => const {'compensations'},
      _ => const <String>{},
    };
    if (codes.isEmpty) {
      return index == 9 && snapshot.ready ? 'TERMINÉ' : 'EN COURS';
    }
    return snapshot.issues.any((issue) => codes.contains(issue.code))
        ? 'À FAIRE'
        : 'TERMINÉ';
  }

  void _open(BuildContext context, int index) {
    final issue = snapshot.issues
        .where(
          (e) => switch (index) {
            1 => e.code == 'receipts',
            2 => e.code == 'reconciliations',
            3 => e.code == 'cash',
            4 => e.code == 'differences',
            5 => e.code == 'compensations',
            _ => false,
          },
        )
        .firstOrNull;
    final page = switch (index) {
      0 ||
      1 => TransactionsPage(initialFinancialEventId: issue?.financialEventId),
      2 || 3 || 4 => AccountsPage(
        initialAccountId: issue?.accountId,
        openInitialAccount: true,
      ),
      5 => MemberCompensationsPage(
        initialCompensationId: issue?.compensationId,
      ),
      _ => null,
    };
    if (page != null) {
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
    }
  }
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
      'reconciliations' || 'cash' => AccountsPage(
        initialAccountId: issue.accountId,
        openInitialAccount: true,
      ),
      'receipts' => TransactionsPage(
        initialFinancialEventId: issue.financialEventId,
      ),
      'compensations' => MemberCompensationsPage(
        initialCompensationId: issue.compensationId,
      ),
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
    final automatic = ref.watch(automaticTargetPreviewProvider);
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
                label: const Text('Dérogation'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          automatic.when(
            loading: () => const LinearProgressIndicator(),
            error: (_, _) => const SecondaryInfoText(
              'La cible automatique ne peut pas être calculée.',
            ),
            data: (preview) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SecondaryInfoText(
                  preview.scenarioName == null
                      ? 'Cible calculée depuis les recommandations canoniques des enveloppes.'
                      : 'Cible calculée automatiquement • Source : scénario/budget ${preview.scenarioName}.',
                ),
                if (preview.missingMappings.isNotEmpty)
                  Text(
                    'Paramétrage minimal manquant : ${preview.missingMappings.join(', ')}.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if (snapshot.owner)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      key: const Key('refresh-automatic-targets'),
                      onPressed: preview.targets.isEmpty
                          ? null
                          : () => _refreshAutomatic(context, ref),
                      icon: const Icon(Icons.auto_fix_high),
                      label: const Text('Actualiser la cible calculée'),
                    ),
                  ),
              ],
            ),
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
                      'Actualisez la cible calculée ou ajoutez une dérogation motivée.',
                    ),
                  )
                : Column(
                    children: [
                      for (final item in items)
                        ListTile(
                          key: Key('monthly-target-${item.id}'),
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            item.automatic
                                ? Icons.auto_awesome
                                : Icons.edit_note,
                          ),
                          title: Text(envelopeName(item.envelopeId)),
                          subtitle: Text(
                            '${accountName(item.accountId)}${item.sourceLabel == null ? '' : '\n${item.sourceLabel}'}',
                          ),
                          isThreeLine: item.sourceLabel != null,
                          trailing: Text(
                            '${item.amount.dirhams.toStringAsFixed(2)} MAD',
                          ),
                          onTap:
                              snapshot.status == MonthlyCloseStatus.closed ||
                                  item.automatic
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
    final reason = TextEditingController(text: existing?.overrideReason ?? '');
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
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  key: const Key('target-override-reason'),
                  controller: reason,
                  decoration: const InputDecoration(
                    labelText: 'Motif de la dérogation *',
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
                if (parsed == null ||
                    parsed < 0 ||
                    reason.text.trim().isEmpty) {
                  return;
                }
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
        reason: reason.text.trim(),
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

  Future<void> _refreshAutomatic(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(refreshAutomaticTargetsProvider)(snapshot.month);
      ref.invalidate(monthlyCloseTargetsProvider);
      ref.invalidate(automaticTargetPreviewProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cibles automatiques actualisées.')),
        );
      }
    } on Exception {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Les cibles automatiques n’ont pas pu être actualisées.',
            ),
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
