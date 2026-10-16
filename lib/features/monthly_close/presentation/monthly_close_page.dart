import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/money/money.dart';
import '../../../core/theme/app_design_system.dart';
import '../../envelopes/application/providers/remote_envelopes_provider.dart';
import '../../envelopes/presentation/envelope_recommendations_page.dart';
import '../../budget_intelligence/presentation/budget_scenarios_page.dart';
import '../../finance/application/providers/remote_accounts_provider.dart';
import '../../finance/application/providers/remote_account_balances_provider.dart';
import '../../finance/application/providers/remote_household_members_provider.dart';
import '../../finance/domain/financial_account.dart';
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
    final members =
        ref.watch(remoteHouseholdMembersProvider).valueOrNull ?? const [];
    final envelopes =
        ref.watch(remoteEnvelopeBalancesProvider).valueOrNull ?? const [];
    String accountName(String id) =>
        accounts.where((e) => e.id == id).map((e) => e.name).firstOrNull ??
        'Compte';
    String envelopeName(String id) =>
        envelopes.where((e) => e.id == id).map((e) => e.name).firstOrNull ??
        'Enveloppe';
    dynamic account(String id) => accounts.where((e) => e.id == id).first;
    String actor(String accountId) {
      final value = account(accountId);
      if (value.holders.isEmpty) return 'FOYER';
      return value.holders
          .map(
            (holder) =>
                members
                    .where((member) => member.id == holder.userId)
                    .map((member) => member.displayName.toUpperCase())
                    .firstOrNull ??
                'MEMBRE DU FOYER',
          )
          .join(' & ');
    }

    String actionLabel(PhysicalTransferAction transfer) {
      final from = account(transfer.fromAccountId);
      final to = account(transfer.toAccountId);
      if (from.type == FinancialAccountType.cash &&
          to.type != FinancialAccountType.cash) {
        return 'Dépôt espèces';
      }
      if (from.type != FinancialAccountType.cash &&
          to.type == FinancialAccountType.cash) {
        return 'Retrait / alimentation espèces';
      }
      return 'Virement';
    }

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
              final configured =
                  targets.valueOrNull ?? const <MonthlyEnvelopeAccountTarget>[];
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
              final simulation = simulateGlobalTransfers(rows);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SecondaryInfoText(
                    'Position actuelle réconciliée avec les comptes et les enveloppes.',
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      key: const Key('opening-position-history'),
                      onPressed: () => _showOpeningHistory(
                        context,
                        ref,
                        accountName,
                        envelopeName,
                      ),
                      icon: const Icon(Icons.history),
                      label: const Text('Traçabilité du point de départ'),
                    ),
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
                    '${simulation.physicalTransfers.length} action(s) physique(s)',
                    key: const Key('reallocation-count'),
                  ),
                  Text(
                    'Besoins bruts : ${simulation.grossAmount.dirhams.toStringAsFixed(2)} MAD • à déplacer après netting : ${simulation.netAmount.dirhams.toStringAsFixed(2)} MAD',
                  ),
                  Text(
                    '${simulation.avoidedPhysicalMoves} mouvement(s) physique(s) évité(s)',
                    key: const Key('avoided-physical-moves'),
                  ),
                  if (simulation.physicalTransfers.isEmpty &&
                      simulation.analyticalMoves.isNotEmpty)
                    const SecondaryInfoText(
                      'Les écarts se compensent intégralement : aucun mouvement physique, mais la ventilation analytique sera mise à jour.',
                    ),
                  for (final transfer in simulation.physicalTransfers)
                    ExpansionTile(
                      key: Key(
                        'physical-transfer-${transfer.fromAccountId}-${transfer.toAccountId}',
                      ),
                      tilePadding: EdgeInsets.zero,
                      leading: Icon(
                        account(transfer.fromAccountId).type ==
                                    FinancialAccountType.cash ||
                                account(transfer.toAccountId).type ==
                                    FinancialAccountType.cash
                            ? Icons.payments_outlined
                            : Icons.swap_horiz,
                      ),
                      title: Text(
                        '${actor(transfer.fromAccountId)} — ${actionLabel(transfer)}',
                      ),
                      subtitle: Text(
                        '${accountName(transfer.fromAccountId)} → ${accountName(transfer.toAccountId)}',
                      ),
                      trailing: Text(
                        '${transfer.amount.dirhams.toStringAsFixed(2)} MAD',
                      ),
                      children: [
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text('Composition analytique'),
                        ),
                        for (final detail in transfer.justifications)
                          ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.only(left: 16),
                            title: Text(envelopeName(detail.envelopeId)),
                            subtitle: Text(
                              '${accountName(detail.fromAccountId)} → ${accountName(detail.toAccountId)}',
                            ),
                            trailing: Text(
                              '${detail.amount.dirhams.toStringAsFixed(2)} MAD',
                            ),
                          ),
                      ],
                    ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      key: const Key('confirm-reallocation'),
                      onPressed:
                          simulation.analyticalMoves.isEmpty ||
                              snapshot.status == MonthlyCloseStatus.closed ||
                              snapshot.blockers > 0
                          ? null
                          : () => _confirm(context, ref, value, simulation),
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
    GlobalTransferSimulation simulation,
  ) async {
    var economicDate = DateTime.now();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Confirmer la régularisation ?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${simulation.physicalTransfers.length} mouvement(s) physique(s) canonique(s) et ${simulation.analyticalMoves.length} justification(s) analytique(s). Aucun mouvement d’enveloppe ne sera créé.',
              ),
              const SizedBox(height: AppSpacing.sm),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Date économique'),
                subtitle: Text(
                  '${economicDate.day.toString().padLeft(2, '0')}/${economicDate.month.toString().padLeft(2, '0')}/${economicDate.year}',
                ),
                trailing: const Icon(Icons.calendar_month),
                onTap: () async {
                  final selected = await showDatePicker(
                    context: context,
                    initialDate: economicDate,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (selected != null) setState(() => economicDate = selected);
                },
              ),
            ],
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
      ),
    );
    if (accepted != true) return;
    try {
      await ref.read(executeMonthlyReallocationProvider)(
        snapshot.month,
        matrix,
        simulation,
        economicDate,
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

  Future<void> _showOpeningHistory(
    BuildContext context,
    WidgetRef ref,
    String Function(String) accountName,
    String Function(String) envelopeName,
  ) async {
    final history = await ref.read(openingPositionHistoryProvider.future);
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Traçabilité du point de départ'),
        content: SizedBox(
          width: 680,
          child: history.isEmpty
              ? const Text('Aucun point de départ enregistré.')
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final entry in history)
                      ListTile(
                        title: Text(
                          '${envelopeName(entry.position.envelopeId)} • ${accountName(entry.position.accountId)} • ${entry.position.amount.dirhams.toStringAsFixed(2)} MAD',
                        ),
                        subtitle: Text(
                          '${_provenanceLabel(entry.position.provenance)}\n${entry.createdAt.toLocal()} • acteur ${entry.actorId}\nbatch ${entry.batchId} • ${entry.note}',
                        ),
                      ),
                  ],
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  String _provenanceLabel(PositionProvenance value) => switch (value) {
    PositionProvenance.sourceProof => 'Prouvé par la source',
    PositionProvenance.humanConfirmation => 'Confirmation métier',
    PositionProvenance.openingInventoryArbitration => 'Arbitrage d’inventaire',
    PositionProvenance.balancingDeduction => 'Déduit par équilibrage',
  };

  Future<void> _initialize(
    BuildContext context,
    WidgetRef ref,
    List<dynamic> accounts,
    List<dynamic> envelopes,
    Map<String, Money> accountBalances,
  ) async {
    InitialPositionPreview preview;
    try {
      preview = await ref.read(initialPositionPreviewProvider.future);
    } catch (_) {
      preview = const InitialPositionPreview(
        positions: [],
        sourceFingerprint: '',
      );
    }
    List<MonthlyEnvelopeAccountTarget> structuralTargets;
    try {
      structuralTargets = await ref.read(monthlyCloseTargetsProvider.future);
    } catch (_) {
      structuralTargets = const [];
    }
    if (!context.mounted) return;
    final result =
        await showDialog<
          ({List<EnvelopeAccountPosition> positions, String note})
        >(
          context: context,
          builder: (context) => _PositionSnapshotDialog(
            accounts: accounts,
            envelopes: envelopes,
            accountBalances: accountBalances,
            initialPositions: preview.positions,
            structuralTargets: structuralTargets,
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
    required this.initialPositions,
    required this.structuralTargets,
  });
  final List<dynamic> accounts, envelopes;
  final Map<String, Money> accountBalances;
  final List<EnvelopeAccountPosition> initialPositions;
  final List<MonthlyEnvelopeAccountTarget> structuralTargets;
  @override
  State<_PositionSnapshotDialog> createState() =>
      _PositionSnapshotDialogState();
}

class _PositionSnapshotDialogState extends State<_PositionSnapshotDialog> {
  final rows = <_PositionDraft>[];
  final note = TextEditingController();
  final _matrixHorizontal = ScrollController();
  final _matrixVertical = ScrollController();
  var _groupByAccount = false;
  var _updatingDeductions = false;
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
    _updatingDeductions = true;
    for (final proof in widget.initialPositions) {
      final row = _row(proof.accountId, proof.envelopeId);
      row.provenance = proof.provenance;
      row.provenanceReference = proof.provenanceReference;
      row.locked = true;
      row.fixed = true;
      row.amount.text = proof.amount.dirhams.toStringAsFixed(2);
    }
    _updatingDeductions = false;
    _applyUniqueDeductions();
  }

  void _changed() {
    if (_updatingDeductions) return;
    _applyUniqueDeductions();
    setState(() {});
  }

  void _applyUniqueDeductions() {
    _updatingDeductions = true;
    for (final row in rows.where(
      (item) =>
          item.provenance == PositionProvenance.balancingDeduction &&
          !item.fixed,
    )) {
      row.amount.clear();
      row.provenance = PositionProvenance.openingInventoryArbitration;
      row.provenanceReference = null;
      row.locked = false;
    }
    final known = <EnvelopeAccountPosition>[];
    for (final row in rows) {
      final amount = _cents(row);
      if (amount <= 0) continue;
      known.add(
        EnvelopeAccountPosition(
          accountId: row.accountId,
          envelopeId: row.envelopeId,
          amount: Money.fromMinorUnits(amount),
          provenance: row.provenance,
          provenanceReference: row.provenanceReference,
        ),
      );
    }
    final completed = deduceUniqueInitialPositions(
      accountBalances: widget.accountBalances,
      envelopeBalances: {
        for (final envelope in widget.envelopes)
          envelope.id as String: envelope.balance as Money,
      },
      known: known,
    );
    for (final value in completed.where(
      (item) => item.provenance == PositionProvenance.balancingDeduction,
    )) {
      final row = _row(value.accountId, value.envelopeId);
      row.provenance = value.provenance;
      row.provenanceReference = value.provenanceReference;
      row.locked = true;
      row.amount.text = value.amount.dirhams.toStringAsFixed(2);
    }
    _updatingDeductions = false;
  }

  @override
  void dispose() {
    for (final row in rows) {
      row.amount.removeListener(_changed);
      row.amount.dispose();
    }
    note.removeListener(_changed);
    note.dispose();
    _matrixHorizontal.dispose();
    _matrixVertical.dispose();
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
                'Les positions prouvées sont préremplies depuis la source certifiée. Les autres restent à confirmer : le compte recommandé n’est jamais considéré comme une preuve.',
              ),
              const SizedBox(height: AppSpacing.sm),
              _summary(),
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonalIcon(
                  key: const Key('propose-inventory-ventilation'),
                  onPressed: () => _previewInventoryVentilation(context),
                  icon: const Icon(Icons.auto_fix_high_outlined),
                  label: const Text('Proposer une ventilation'),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: false,
                    icon: Icon(Icons.account_balance_wallet_outlined),
                    label: Text('Par enveloppe'),
                  ),
                  ButtonSegment(
                    value: true,
                    icon: Icon(Icons.account_balance_outlined),
                    label: Text('Par compte'),
                  ),
                ],
                selected: {_groupByAccount},
                onSelectionChanged: (value) {
                  final groupByAccount = value.single;
                  setState(() => _groupByAccount = groupByAccount);
                  if (!groupByAccount) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (_matrixHorizontal.hasClients) {
                        _matrixHorizontal.jumpTo(0);
                      }
                    });
                  }
                },
              ),
              const SizedBox(height: AppSpacing.sm),
              if (_groupByAccount)
                _accountComposition()
              else if (box.maxWidth >= 760)
                _desktopMatrix()
              else
                _mobileMatrix(),
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
                key: const Key('matrix-inventory-note'),
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

  Widget _summary() {
    final relevant = widget.envelopes
        .where((e) => (e.balance as Money).minorUnits != 0)
        .toList();
    final completed = relevant
        .where(
          (e) =>
              _envelopeTotal(e.id as String) == (e.balance as Money).minorUnits,
        )
        .length;
    final envelopeTotal = widget.envelopes.fold<int>(
      0,
      (sum, e) => sum + (e.balance as Money).minorUnits,
    );
    final allocated = rows.fold<int>(0, (sum, row) => sum + _cents(row));
    return FpCard(
      child: Wrap(
        spacing: AppSpacing.lg,
        runSpacing: AppSpacing.xs,
        children: [
          Text(
            '$completed / ${relevant.length} enveloppes inventoriées',
            key: const Key('matrix-progress'),
          ),
          Text('Total affecté : ${_money(allocated)}'),
          Text('Total restant : ${_money(envelopeTotal - allocated)}'),
          Text(
            _balanced ? 'État : équilibré' : 'État : non équilibré',
            key: const Key('matrix-balance-state'),
          ),
        ],
      ),
    );
  }

  InventoryVentilationProposal _inventoryVentilationProposal() {
    final fixed = <EnvelopeAccountPosition>[
      for (final row in rows)
        if (_cents(row) > 0)
          EnvelopeAccountPosition(
            accountId: row.accountId,
            envelopeId: row.envelopeId,
            amount: Money.fromMinorUnits(_cents(row)),
            provenance: row.provenance,
            provenanceReference: row.provenanceReference,
          ),
    ];
    final targetAccounts = <String, Set<String>>{};
    for (final target in widget.structuralTargets) {
      if (target.amount.minorUnits <= 0) continue;
      targetAccounts
          .putIfAbsent(target.envelopeId, () => <String>{})
          .add(target.accountId);
    }
    final rules = <InventoryVentilationRule>[];
    for (final envelope in widget.envelopes) {
      final envelopeId = envelope.id as String;
      final kind = envelope.effectiveRecommendationKind as String;
      final recommended = envelope.recommendedAccountId as String?;
      final scenarioAccounts =
          (targetAccounts[envelopeId]?.toList() ?? <String>[])..sort();
      final admissible = switch (kind) {
        'single_account' when recommended != null => <String>[recommended],
        'scenario_split' || 'member_beneficiary' => <String>[
          ...scenarioAccounts,
          if (recommended != null && !scenarioAccounts.contains(recommended))
            recommended,
        ],
        _ => const <String>[],
      };
      if (admissible.isEmpty) continue;
      final preferred = <String>[
        ...?(recommended == null ? null : <String>[recommended]),
        ...scenarioAccounts.where((id) => id != recommended),
      ];
      rules.add(
        InventoryVentilationRule(
          envelopeId: envelopeId,
          admissibleAccountIds: admissible,
          preferredAccountIds: preferred,
          reason: kind == 'single_account'
              ? 'Compte structurel habituel'
              : kind == 'scenario_split'
              ? 'Répartition multi-comptes du scénario applicable'
              : 'Comptes admissibles selon le bénéficiaire',
        ),
      );
    }
    return proposeInventoryVentilation(
      accountBalances: widget.accountBalances,
      envelopeBalances: {
        for (final envelope in widget.envelopes)
          envelope.id as String: envelope.balance as Money,
      },
      fixedPositions: fixed,
      rules: rules,
    );
  }

  Future<void> _previewInventoryVentilation(BuildContext context) async {
    final proposal = _inventoryVentilationProposal();
    String accountName(String id) =>
        widget.accounts
            .where((account) => account.id == id)
            .map((account) => account.name as String)
            .firstOrNull ??
        'Compte';
    String envelopeName(String id) =>
        widget.envelopes
            .where((envelope) => envelope.id == id)
            .map((envelope) => envelope.name as String)
            .firstOrNull ??
        'Enveloppe';
    final apply = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Proposition de ventilation d’inventaire'),
        content: SizedBox(
          width: 720,
          child: ListView(
            shrinkWrap: true,
            children: [
              Text(
                'Avant : ${_money(proposal.initialResidual.minorUnits)} restant à expliquer.',
                key: const Key('ventilation-before'),
              ),
              Text(
                proposal.balanced
                    ? 'Après proposition : comptes et enveloppes équilibrés.'
                    : 'Après proposition : ${_money(proposal.remainingEnvelopeAmount.minorUnits)} non résolu.',
                key: const Key('ventilation-after'),
              ),
              const SizedBox(height: AppSpacing.sm),
              if (proposal.candidates.isEmpty)
                const SecondaryInfoText(
                  'Aucune proposition sûre ne peut être construite avec les règles disponibles.',
                ),
              for (final candidate in proposal.candidates)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '${envelopeName(candidate.position.envelopeId)} • ${accountName(candidate.position.accountId)}',
                  ),
                  subtitle: Text(
                    '${candidate.reason}\nArbitrage d’inventaire proposé',
                  ),
                  trailing: Text(_money(candidate.position.amount.minorUnits)),
                ),
              if (proposal.unresolvedResiduals.isNotEmpty) ...[
                const Divider(),
                Text(
                  'Montants restant à expliquer',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: AppSpacing.xs),
                for (final residual in proposal.unresolvedResiduals)
                  Card(
                    key: Key('ventilation-unresolved-${residual.envelopeId}'),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${envelopeName(residual.envelopeId)} — ${_money(residual.amount.minorUnits)} non résolus',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            residual.admissibleAccountIds.isEmpty
                                ? 'Comptes admissibles : aucun'
                                : 'Comptes admissibles : ${residual.admissibleAccountIds.map(accountName).join(' / ')}',
                          ),
                          if (residual.admissibleAccountIds.isNotEmpty)
                            Text(
                              'Capacités restantes : ${residual.admissibleAccountIds.map((id) => '${accountName(id)} ${_money(residual.remainingAccountCapacities[id]!.minorUnits)}').join(' • ')}',
                            ),
                          Text('Pourquoi : ${residual.reason}'),
                          Text('Action attendue : ${residual.expectedAction}'),
                        ],
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            key: const Key('cancel-inventory-ventilation'),
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            key: const Key('apply-inventory-ventilation'),
            onPressed: proposal.candidates.isEmpty
                ? null
                : () => Navigator.pop(dialogContext, true),
            child: const Text('Appliquer la proposition au brouillon'),
          ),
        ],
      ),
    );
    if (apply != true || !mounted) return;
    _updatingDeductions = true;
    for (final candidate in proposal.candidates) {
      final row = _row(
        candidate.position.accountId,
        candidate.position.envelopeId,
      );
      if (_cents(row) > 0 || row.locked) continue;
      row.amount.text = candidate.position.amount.dirhams.toStringAsFixed(2);
      row.provenance = PositionProvenance.openingInventoryArbitration;
      row.provenanceReference = candidate.position.provenanceReference;
    }
    _updatingDeductions = false;
    _applyUniqueDeductions();
    setState(() {});
  }

  Widget _desktopMatrix() {
    final envelopeWidth = _desktopColumnWidth(
      <String>[
        'Enveloppe',
        for (final envelope in widget.envelopes) envelope.name as String,
        for (final envelope in widget.envelopes)
          if (envelope.recommendedAccountId != null)
            'Compte structurel recommandé : ${_recommendedAccountName(envelope) ?? ''}',
      ],
      min: 280,
      max: 380,
    );
    final accountWidth = _desktopColumnWidth(
      <String>[
        for (final account in widget.accounts) account.name as String,
        'Arbitrage d’inventaire',
        'Confirmation métier',
      ],
      min: 190,
      max: 230,
    );
    const totalWidth = 135.0;
    final tableWidth =
        envelopeWidth + widget.accounts.length * accountWidth + 3 * totalWidth;
    final viewportHeight = (MediaQuery.sizeOf(context).height * .56).clamp(
      360.0,
      620.0,
    );
    Widget cell(Widget child, double width) => SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: child,
      ),
    );
    final header = Container(
      key: const Key('matrix-sticky-header'),
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: Row(
        children: [
          cell(const Text('Enveloppe'), envelopeWidth),
          for (final account in widget.accounts)
            cell(Text(account.name as String), accountWidth),
          cell(const Text('Affecté'), totalWidth),
          cell(const Text('Solde enveloppe'), totalWidth),
          cell(const Text('Écart'), totalWidth),
        ],
      ),
    );
    return SizedBox(
      height: viewportHeight,
      child: Scrollbar(
        controller: _matrixHorizontal,
        thumbVisibility: true,
        child: SingleChildScrollView(
          key: const Key('matrix-horizontal-scroll'),
          controller: _matrixHorizontal,
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: tableWidth,
            child: Column(
              children: [
                SizedBox(height: 58, child: header),
                Expanded(
                  child: Scrollbar(
                    controller: _matrixVertical,
                    thumbVisibility: true,
                    child: ListView.builder(
                      key: const Key('matrix-vertical-scroll'),
                      controller: _matrixVertical,
                      itemCount: widget.envelopes.length,
                      itemBuilder: (context, index) {
                        final envelope = widget.envelopes[index];
                        return Container(
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: Theme.of(context).dividerColor,
                              ),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                key: Key(
                                  'matrix-envelope-heading-${envelope.id}',
                                ),
                                width: envelopeWidth,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.sm,
                                    vertical: AppSpacing.xs,
                                  ),
                                  child: _envelopeHeading(envelope),
                                ),
                              ),
                              for (final account in widget.accounts)
                                cell(
                                  (envelope.balance as Money).minorUnits == 0
                                      ? const Text('—')
                                      : _amountCell(
                                          _row(
                                            account.id as String,
                                            envelope.id as String,
                                          ),
                                          envelope.name as String,
                                          account.name as String,
                                        ),
                                  accountWidth,
                                ),
                              cell(
                                Text(
                                  _money(_envelopeTotal(envelope.id as String)),
                                ),
                                totalWidth,
                              ),
                              cell(
                                Text(
                                  _money(
                                    (envelope.balance as Money).minorUnits,
                                  ),
                                ),
                                totalWidth,
                              ),
                              cell(
                                Text(
                                  _money(
                                    _envelopeTotal(envelope.id as String) -
                                        (envelope.balance as Money).minorUnits,
                                  ),
                                ),
                                totalWidth,
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  double _desktopColumnWidth(
    Iterable<String> labels, {
    required double min,
    required double max,
  }) {
    final style = Theme.of(context).textTheme.bodyMedium ?? const TextStyle();
    final textScaler = MediaQuery.textScalerOf(context);
    var widest = 0.0;
    for (final label in labels) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: style),
        textDirection: Directionality.of(context),
        textScaler: textScaler,
        maxLines: 1,
      )..layout();
      widest = math.max(widest, painter.width);
    }
    return (widest + AppSpacing.md * 2).clamp(min, max).toDouble();
  }

  Widget _mobileMatrix() => Column(
    children: [
      for (final e in widget.envelopes)
        Card(
          child: Padding(
            padding: AppSpacing.card,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _envelopeHeading(e),
                if ((e.balance as Money).minorUnits == 0)
                  const SecondaryInfoText(
                    'Solde nul : aucune saisie nécessaire.',
                  )
                else
                  for (final a in widget.accounts)
                    Row(
                      children: [
                        Expanded(child: Text(a.name as String)),
                        SizedBox(
                          width: 130,
                          child: _amountCell(
                            _row(a.id as String, e.id as String),
                            e.name as String,
                            a.name as String,
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

  Widget _envelopeHeading(dynamic envelope) {
    final recommendedId = envelope.recommendedAccountId as String?;
    final recommended = _recommendedAccountName(envelope);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          envelope.name as String,
          style: const TextStyle(fontWeight: FontWeight.w700),
          softWrap: true,
        ),
        if (recommended != null)
          Wrap(
            spacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Compte structurel recommandé : $recommended',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              TextButton(
                key: Key('use-recommended-${envelope.id}'),
                onPressed: (envelope.balance as Money).minorUnits == 0
                    ? null
                    : () => _useRecommendedAccount(envelope, recommendedId!),
                child: const Text('Utiliser ce compte'),
              ),
            ],
          ),
      ],
    );
  }

  String? _recommendedAccountName(dynamic envelope) {
    final recommendedId = envelope.recommendedAccountId as String?;
    if (recommendedId == null) return null;
    return widget.accounts
        .where((account) => account.id == recommendedId)
        .map((account) => account.name as String)
        .firstOrNull;
  }

  void _useRecommendedAccount(dynamic envelope, String accountId) {
    for (final row in rows.where((r) => r.envelopeId == envelope.id)) {
      if (row.locked) continue;
      row.amount.text = row.accountId == accountId
          ? ((envelope.balance as Money).minorUnits / 100).toStringAsFixed(2)
          : '';
    }
  }

  Widget _accountComposition() => Column(
    children: [
      for (final account in widget.accounts)
        Card(
          key: Key('matrix-account-${account.id}'),
          child: Padding(
            padding: AppSpacing.card,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  account.name as String,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                for (final envelope in widget.envelopes)
                  if (_cents(
                        _row(account.id as String, envelope.id as String),
                      ) !=
                      0)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(envelope.name as String),
                      trailing: Text(
                        _money(
                          _cents(
                            _row(account.id as String, envelope.id as String),
                          ),
                        ),
                      ),
                    ),
                const Divider(),
                Text(
                  'Expliqué ${_money(_accountTotal(account.id as String))} / solde ${_money(widget.accountBalances[account.id as String]?.minorUnits ?? 0)} / écart ${_money(_accountTotal(account.id as String) - (widget.accountBalances[account.id as String]?.minorUnits ?? 0))}',
                ),
              ],
            ),
          ),
        ),
    ],
  );

  Widget _amountCell(
    _PositionDraft row,
    String envelopeName,
    String accountName,
  ) => Semantics(
    label: '$envelopeName, $accountName, montant en MAD',
    textField: true,
    child: Tooltip(
      message: '$envelopeName • $accountName',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: Key('matrix-${row.envelopeId}-${row.accountId}'),
            controller: row.amount,
            readOnly: row.locked,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: accountName,
              suffixText: 'MAD',
              isDense: true,
            ),
          ),
          if (row.locked && _cents(row) > 0)
            Text(
              _positionProvenanceLabel(row.provenance),
              style: Theme.of(context).textTheme.labelSmall,
            ),
          if (!row.locked && _cents(row) > 0)
            DropdownButtonHideUnderline(
              child: DropdownButton<PositionProvenance>(
                key: Key('provenance-${row.envelopeId}-${row.accountId}'),
                isDense: true,
                isExpanded: true,
                value: row.provenance,
                items: const [
                  DropdownMenuItem(
                    value: PositionProvenance.openingInventoryArbitration,
                    child: Text('Arbitrage d’inventaire'),
                  ),
                  DropdownMenuItem(
                    value: PositionProvenance.humanConfirmation,
                    child: Text('Confirmation métier'),
                  ),
                ],
                onChanged: (value) => setState(() {
                  row.provenance =
                      value ?? PositionProvenance.openingInventoryArbitration;
                  row.provenanceReference =
                      row.provenance == PositionProvenance.humanConfirmation
                      ? 'Confirmation explicite lors de l’inventaire'
                      : 'Arbitrage explicite lors de l’inventaire';
                }),
              ),
            ),
        ],
      ),
    ),
  );

  String _positionProvenanceLabel(PositionProvenance value) => switch (value) {
    PositionProvenance.sourceProof => 'Prouvé par la source',
    PositionProvenance.humanConfirmation => 'Confirmation métier',
    PositionProvenance.balancingDeduction => 'Déduit par équilibrage',
    PositionProvenance.openingInventoryArbitration => 'Arbitrage d’inventaire',
  };

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
  Future<void> _save(BuildContext context) async {
    if (!_balanced) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirmer l’inventaire initial ?'),
        content: const Text(
          'Cette déclaration analytique sera historisée. Elle ne modifiera aucun compte, aucune enveloppe et ne créera aucune opération financière.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Continuer la vérification'),
          ),
          FilledButton(
            key: const Key('confirm-matrix-snapshot'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirmer définitivement'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final positions = <EnvelopeAccountPosition>[];
    for (final row in rows) {
      final raw = row.amount.text.trim();
      final amount = raw.isEmpty
          ? 0.0
          : double.tryParse(raw.replaceAll(',', '.'));
      if (amount == null || amount < 0) return;
      if (amount == 0) continue;
      positions.add(
        EnvelopeAccountPosition(
          accountId: row.accountId,
          envelopeId: row.envelopeId,
          amount: Money.fromDirhams(amount),
          provenance: row.provenance,
          provenanceReference: row.provenanceReference,
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
  PositionProvenance provenance =
      PositionProvenance.openingInventoryArbitration;
  String? provenanceReference = 'Arbitrage explicite lors de l’inventaire';
  bool locked = false;
  bool fixed = false;
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

class _Workflow extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) => FpCard(
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
            onTap: i < 6 ? () => _open(context, ref, i) : null,
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

  Future<void> _open(BuildContext context, WidgetRef ref, int index) async {
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
      await Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => page));
      if (context.mounted) {
        ref.invalidate(monthlyCloseProvider);
      }
    }
  }
}

class _Todo extends ConsumerWidget {
  const _Todo(this.snapshot);
  final MonthlyCloseSnapshot snapshot;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
              onTap: () => _openDestination(context, ref, issue),
            ),
        ],
      ),
    );
  }

  Future<void> _openDestination(
    BuildContext context,
    WidgetRef ref,
    CloseIssue issue,
  ) async {
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
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => page));
    if (context.mounted) {
      ref.invalidate(monthlyCloseProvider);
    }
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
                      ? 'Source : recommandations structurelles des enveloppes. Aucun scénario/budget applicable pour ${snapshot.month.month.toString().padLeft(2, '0')}/${snapshot.month.year}.'
                      : 'Source : Budget ${snapshot.month.month.toString().padLeft(2, '0')}/${snapshot.month.year} — Scénario ${preview.scenarioName}.',
                ),
                if (preview.scenarioName == null)
                  TextButton.icon(
                    key: const Key('configure-budget-scenario'),
                    onPressed: () => _openBudget(context, ref),
                    icon: const Icon(Icons.event_note_outlined),
                    label: const Text('Configurer le budget applicable'),
                  ),
                if (preview.missingMappings.isNotEmpty) ...[
                  Text(
                    'Paramétrage minimal manquant : ${preview.missingMappings.join(', ')}.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  TextButton.icon(
                    key: const Key('configure-envelope-targets'),
                    onPressed: () => _openEnvelopeConfiguration(context, ref),
                    icon: const Icon(Icons.tune),
                    label: const Text('Configurer les enveloppes'),
                  ),
                ],
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

  Future<void> _openEnvelopeConfiguration(
    BuildContext context,
    WidgetRef ref,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const EnvelopeRecommendationsPage(),
      ),
    );
    ref.invalidate(automaticTargetPreviewProvider);
    ref.invalidate(monthlyCloseTargetsProvider);
  }

  Future<void> _openBudget(BuildContext context, WidgetRef ref) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const BudgetScenariosPage()),
    );
    ref.invalidate(automaticTargetPreviewProvider);
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
