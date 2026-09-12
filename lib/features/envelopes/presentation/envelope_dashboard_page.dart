import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../../core/theme/app_design_system.dart';
import '../../finance/application/csv_import_templates.dart';
import '../../finance/presentation/imports_page.dart';
import '../application/providers/remote_envelopes_provider.dart';

class EnvelopeDashboardPage extends ConsumerWidget {
  const EnvelopeDashboardPage({super.key});

  Future<void> _openTransfer(
    BuildContext context,
    WidgetRef ref,
    List<RemoteEnvelopeBalance> envelopes,
  ) async {
    final transferred = await showDialog<bool>(
      context: context,
      builder: (_) => _EnvelopeTransferDialog(envelopes: envelopes),
    );
    if (transferred == true) {
      _refreshEnvelopes(ref);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Transfert entre enveloppes validé.')),
        );
      }
    }
  }

  Future<void> _openToAllocateDistribution(
    BuildContext context,
    WidgetRef ref,
    RemoteEnvelopeBalance source,
    List<RemoteEnvelopeBalance> destinations,
  ) async {
    final distributed = await showDialog<bool>(
      context: context,
      builder: (_) => _ToAllocateDistributionDialog(
        source: source,
        destinations: destinations,
      ),
    );
    if (distributed == true) {
      _refreshEnvelopes(ref);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Répartition enregistrée.')),
        );
      }
    }
  }

  Future<void> _openEditor(
    BuildContext context,
    WidgetRef ref, {
    RemoteEnvelopeBalance? envelope,
  }) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _EnvelopeEditorDialog(envelope: envelope),
    );
    if (changed == true) {
      _refreshEnvelopes(ref);
    }
  }

  Future<void> _archiveEnvelope(
    BuildContext context,
    WidgetRef ref,
    RemoteEnvelopeBalance envelope,
  ) async {
    final confirmed = await _confirmAction(
      context,
      title: 'Archiver l’enveloppe ?',
      message:
          'Son historique restera conservé et elle ne sera plus proposée pour les nouvelles opérations.',
      confirmLabel: 'Archiver',
    );
    if (!confirmed || !context.mounted) {
      return;
    }
    try {
      await ref.read(updateRemoteEnvelopeProvider)(
        envelopeId: envelope.id,
        name: envelope.name,
        notes: envelope.notes,
        archived: true,
      );
      _refreshEnvelopes(ref);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Enveloppe archivée.')));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Archivage impossible.')));
      }
    }
  }

  Future<void> _reactivateEnvelope(
    BuildContext context,
    WidgetRef ref,
    RemoteEnvelopeBalance envelope,
  ) async {
    try {
      await ref.read(updateRemoteEnvelopeProvider)(
        envelopeId: envelope.id,
        name: envelope.name,
        notes: envelope.notes,
        archived: false,
      );
      _refreshEnvelopes(ref);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Enveloppe réactivée.')));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Réactivation impossible.')),
        );
      }
    }
  }

  Future<void> _deleteEnvelope(
    BuildContext context,
    WidgetRef ref,
    RemoteEnvelopeBalance envelope,
  ) async {
    final confirmed = await _confirmAction(
      context,
      title: 'Supprimer l’enveloppe ?',
      message:
          'Cette action est définitive et n’est autorisée que si l’enveloppe ne possède aucun historique.',
      confirmLabel: 'Supprimer',
      destructive: true,
    );
    if (!confirmed || !context.mounted) {
      return;
    }
    try {
      await ref.read(deleteRemoteEnvelopeProvider)(envelope.id);
      _refreshEnvelopes(ref);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Enveloppe supprimée.')));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Suppression impossible : archivez une enveloppe avec historique.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _undoLastImport(BuildContext context, WidgetRef ref) async {
    try {
      final count = await ref.read(undoLastEnvelopeImportProvider)();
      _refreshEnvelopes(ref);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$count enveloppe(s) du dernier import archivées.'),
          ),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Le dernier import ne peut plus être annulé.'),
          ),
        );
      }
    }
  }

  void _refreshEnvelopes(WidgetRef ref) {
    ref.invalidate(remoteEnvelopeBalancesProvider);
    ref.invalidate(remoteEnvelopeHistoryProvider);
  }

  Future<bool> _confirmAction(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
    bool destructive = false,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                style: destructive
                    ? FilledButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.error,
                      )
                    : null,
                child: Text(confirmLabel),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balances = ref.watch(remoteEnvelopeBalancesProvider);
    final history = ref.watch(remoteEnvelopeHistoryProvider);
    return SafeArea(
      child: balances.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: AppSpacing.page,
            child: Text('Impossible de lire les enveloppes : $error'),
          ),
        ),
        data: (envelopes) {
          final activeEnvelopes = envelopes;
          final ordinaryActiveEnvelopes = activeEnvelopes
              .where((envelope) => !envelope.isSystem)
              .toList(growable: false);
          final toAllocate = history.valueOrNull
              ?.where((envelope) => envelope.systemCode == 'to_allocate')
              .firstOrNull;
          return ListView(
            padding: AppSpacing.page,
            children: [
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Enveloppes',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  FilledButton.icon(
                    key: const Key('envelope-transfer-button'),
                    onPressed: activeEnvelopes.length < 2
                        ? null
                        : () => _openTransfer(context, ref, activeEnvelopes),
                    icon: const Icon(Icons.swap_horiz),
                    label: const Text('Transférer'),
                  ),
                  OutlinedButton.icon(
                    key: const Key('distribute-to-allocate-button'),
                    onPressed:
                        toAllocate == null ||
                            toAllocate.balance.minorUnits <= 0 ||
                            ordinaryActiveEnvelopes.isEmpty
                        ? null
                        : () => _openToAllocateDistribution(
                            context,
                            ref,
                            toAllocate,
                            ordinaryActiveEnvelopes,
                          ),
                    icon: const Icon(Icons.call_split),
                    label: const Text('Répartir'),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  OutlinedButton.icon(
                    key: const Key('new-envelope-button'),
                    onPressed: () => _openEditor(context, ref),
                    icon: const Icon(Icons.add),
                    label: const Text('Nouvelle'),
                  ),
                  TextButton(
                    key: const Key('archived-envelopes-button'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ArchivedEnvelopesPage(),
                      ),
                    ),
                    child: const Text('Enveloppes archivées'),
                  ),
                  IconButton(
                    key: const Key('undo-last-envelope-import-button'),
                    tooltip: 'Annuler le dernier import',
                    onPressed: () => _undoLastImport(context, ref),
                    icon: const Icon(Icons.undo),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              const Text(
                'Soldes calculés exclusivement depuis le journal des enveloppes.',
              ),
              if (toAllocate != null && toAllocate.balance.minorUnits > 0) ...[
                const SizedBox(height: AppSpacing.sm),
                _ToAllocateAlert(
                  balance: toAllocate.balance,
                  onTap: ordinaryActiveEnvelopes.isEmpty
                      ? null
                      : () => _openToAllocateDistribution(
                          context,
                          ref,
                          toAllocate,
                          ordinaryActiveEnvelopes,
                        ),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              if (activeEnvelopes.isEmpty)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.account_balance_wallet_outlined),
                    title: const Text('Aucune enveloppe active'),
                    subtitle: const Text(
                      'Créez ou importez une enveloppe pour commencer.',
                    ),
                    trailing: OutlinedButton(
                      key: const Key('envelope-import-csv-cta'),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => Scaffold(
                            appBar: AppBar(
                              title: const Text('Import des enveloppes'),
                            ),
                            body: const ImportsPage(
                              initialTemplateType: ImportTemplateType.envelopes,
                            ),
                          ),
                        ),
                      ),
                      child: const Text('Importer mes enveloppes'),
                    ),
                  ),
                ),
              ...envelopes.map(
                (envelope) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Card(
                    child: ListTile(
                      onTap: envelope.isSystem
                          ? null
                          : () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    _EnvelopeDetailPage(envelope: envelope),
                              ),
                            ),
                      title: Text(
                        envelope.isArchived
                            ? '${envelope.name} (archivée)'
                            : envelope.name,
                      ),
                      subtitle: Text(
                        'Entrées : ${_money(envelope.inflows)} MAD • Sorties : ${_money(envelope.outflows)} MAD${envelope.lastMovementAt == null ? '' : ' • Dernier mouvement : ${_date(envelope.lastMovementAt!)}'}',
                      ),
                      trailing: envelope.isSystem
                          ? Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text('${_money(envelope.balance)} MAD'),
                                const Text('Système'),
                              ],
                            )
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('${_money(envelope.balance)} MAD'),
                                PopupMenuButton<String>(
                                  key: Key('envelope-actions-${envelope.id}'),
                                  onSelected: (action) {
                                    switch (action) {
                                      case 'edit':
                                        _openEditor(
                                          context,
                                          ref,
                                          envelope: envelope,
                                        );
                                        break;
                                      case 'archive':
                                        _archiveEnvelope(
                                          context,
                                          ref,
                                          envelope,
                                        );
                                        break;
                                      case 'reactivate':
                                        _reactivateEnvelope(
                                          context,
                                          ref,
                                          envelope,
                                        );
                                        break;
                                      case 'delete':
                                        _deleteEnvelope(context, ref, envelope);
                                        break;
                                    }
                                  },
                                  itemBuilder: (_) => envelope.isArchived
                                      ? const [
                                          PopupMenuItem(
                                            value: 'reactivate',
                                            child: Text('Réactiver'),
                                          ),
                                          PopupMenuItem(
                                            value: 'delete',
                                            child: Text('Supprimer'),
                                          ),
                                        ]
                                      : const [
                                          PopupMenuItem(
                                            value: 'edit',
                                            child: Text('Modifier'),
                                          ),
                                          PopupMenuItem(
                                            value: 'archive',
                                            child: Text('Archiver'),
                                          ),
                                          PopupMenuItem(
                                            value: 'delete',
                                            child: Text('Supprimer'),
                                          ),
                                        ],
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ToAllocateAlert extends StatelessWidget {
  const _ToAllocateAlert({required this.balance, required this.onTap});

  final Money balance;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      button: onTap != null,
      label: '${_frenchMoney(balance)} à répartir',
      child: Card(
        key: const Key('to-allocate-alert'),
        color: colors.secondaryContainer,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.card,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 420;
                final content = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${_frenchMoney(balance)} à répartir',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: colors.onSecondaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Des fonds attendent d’être affectés à vos enveloppes.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSecondaryContainer,
                      ),
                    ),
                  ],
                );
                final action = TextButton.icon(
                  key: const Key('to-allocate-alert-action'),
                  onPressed: onTap,
                  icon: const Icon(Icons.call_split),
                  label: const Text('Répartir maintenant'),
                );
                if (compact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      content,
                      const SizedBox(height: AppSpacing.xs),
                      action,
                    ],
                  );
                }
                return Row(
                  children: [
                    const Icon(Icons.account_tree_outlined),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: content),
                    const SizedBox(width: AppSpacing.sm),
                    action,
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _EnvelopeDetailPage extends ConsumerWidget {
  const _EnvelopeDetailPage({required this.envelope});
  final RemoteEnvelopeBalance envelope;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final movements = ref.watch(remoteEnvelopeMovementsProvider(envelope.id));
    return Scaffold(
      appBar: AppBar(title: Text(envelope.name)),
      body: ListView(
        padding: AppSpacing.page,
        children: [
          Text(envelope.name, style: Theme.of(context).textTheme.headlineSmall),
          Text('Solde actuel : ${_money(envelope.balance)} MAD'),
          Text('Entrées : ${_money(envelope.inflows)} MAD'),
          Text('Sorties : ${_money(envelope.outflows)} MAD'),
          if (envelope.lastMovementAt != null)
            Text('Dernier mouvement : ${_date(envelope.lastMovementAt!)}'),
          const SizedBox(height: AppSpacing.md),
          Text('Mouvements', style: Theme.of(context).textTheme.titleMedium),
          ...movements.when(
            loading: () => const [Center(child: CircularProgressIndicator())],
            error: (_, _) => const [
              Text('Impossible de charger les mouvements.'),
            ],
            data: (items) => items.isEmpty
                ? const [Text('Aucun mouvement pour cette enveloppe.')]
                : items
                      .map(
                        (movement) => ListTile(
                          title: Text(movement.description),
                          subtitle: Text(
                            '${movement.displayType} • ${_date(movement.occurredAt)}',
                          ),
                          trailing: Text('${_money(movement.amount)} MAD'),
                        ),
                      )
                      .toList(growable: false),
          ),
        ],
      ),
    );
  }
}

class ArchivedEnvelopesPage extends ConsumerWidget {
  const ArchivedEnvelopesPage({super.key});

  Future<void> _reactivate(
    BuildContext context,
    WidgetRef ref,
    RemoteEnvelopeBalance envelope,
  ) async {
    try {
      await ref.read(updateRemoteEnvelopeProvider)(
        envelopeId: envelope.id,
        name: envelope.name,
        notes: envelope.notes,
        archived: false,
      );
      ref.invalidate(remoteEnvelopeHistoryProvider);
      ref.invalidate(remoteEnvelopeBalancesProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Enveloppe réactivée.')));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Réactivation impossible.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(remoteEnvelopeHistoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Enveloppes archivées')),
      body: history.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Lecture impossible : $error')),
        data: (envelopes) {
          final archived = envelopes
              .where((envelope) => envelope.isArchived && !envelope.isSystem)
              .toList(growable: false);
          if (archived.isEmpty) {
            return const Center(child: Text('Aucune enveloppe archivée.'));
          }
          return ListView.separated(
            padding: AppSpacing.page,
            itemCount: archived.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (_, index) {
              final envelope = archived[index];
              return Card(
                child: ListTile(
                  title: Text(envelope.name),
                  subtitle: Text(
                    'Solde conservé : ${_money(envelope.balance)} MAD',
                  ),
                  trailing: FilledButton(
                    onPressed: () => _reactivate(context, ref, envelope),
                    child: const Text('Réactiver'),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _EnvelopeTransferDialog extends ConsumerStatefulWidget {
  const _EnvelopeTransferDialog({required this.envelopes});
  final List<RemoteEnvelopeBalance> envelopes;

  @override
  ConsumerState<_EnvelopeTransferDialog> createState() =>
      _EnvelopeTransferDialogState();
}

class _ToAllocateDistributionDialog extends ConsumerStatefulWidget {
  const _ToAllocateDistributionDialog({
    required this.source,
    required this.destinations,
  });

  final RemoteEnvelopeBalance source;
  final List<RemoteEnvelopeBalance> destinations;

  @override
  ConsumerState<_ToAllocateDistributionDialog> createState() =>
      _ToAllocateDistributionDialogState();
}

class _DistributionDraft {
  _DistributionDraft() : amount = TextEditingController();
  String? envelopeId;
  final TextEditingController amount;
  void dispose() => amount.dispose();
}

class _ToAllocateDistributionDialogState
    extends ConsumerState<_ToAllocateDistributionDialog> {
  final _rows = <_DistributionDraft>[_DistributionDraft()];
  final _description = TextEditingController(text: 'Répartition de À répartir');
  late final String _idempotencyKey;
  var _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _idempotencyKey = newEnvelopeDistributionIdempotencyKey();
  }

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    _description.dispose();
    super.dispose();
  }

  int get _allocatedCents =>
      _rows.fold(0, (sum, row) => sum + (_madToCents(row.amount.text) ?? 0));
  int get _availableCents => widget.source.balance.minorUnits;
  bool get _overAllocated => _allocatedCents > _availableCents;
  bool get _hasDuplicateDestination {
    final values = _rows
        .map((row) => row.envelopeId)
        .whereType<String>()
        .toList(growable: false);
    return values.toSet().length != values.length;
  }

  Future<void> _submit() async {
    final allocations = <EnvelopeDistributionLine>[];
    for (final row in _rows) {
      final cents = _madToCents(row.amount.text);
      if (row.envelopeId == null || cents == null || cents <= 0) {
        setState(
          () => _error =
              'Choisissez une enveloppe et un montant positif pour chaque ligne.',
        );
        return;
      }
      allocations.add(
        EnvelopeDistributionLine(
          envelopeId: row.envelopeId!,
          amount: Money.fromMinorUnits(cents),
        ),
      );
    }
    if (_overAllocated || _hasDuplicateDestination || allocations.isEmpty) {
      setState(
        () => _error = _overAllocated
            ? 'Le total affecté dépasse le solde disponible.'
            : _hasDuplicateDestination
            ? 'Une enveloppe ne peut être choisie qu’une fois.'
            : 'Ajoutez au moins une destination.',
      );
      return;
    }
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Confirmer la répartition'),
            content: SizedBox(
              width: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('À répartir • ${_money(widget.source.balance)} MAD'),
                  const SizedBox(height: AppSpacing.sm),
                  for (final line in allocations)
                    Text(
                      '→ ${widget.destinations.firstWhere((item) => item.id == line.envelopeId).name} : ${_money(line.amount)} MAD',
                    ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Total distribué : ${_money(Money.fromMinorUnits(_allocatedCents))} MAD',
                  ),
                  Text(
                    'Reste dans À répartir : ${_money(Money.fromMinorUnits(_availableCents - _allocatedCents))} MAD',
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Confirmer'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(distributeToAllocateEnvelopeProvider)(
        destinations: allocations,
        occurredAt: DateTime.now(),
        description: _description.text.trim(),
        idempotencyKey: _idempotencyKey,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = 'Répartition impossible : $error');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Répartir le solde disponible'),
    content: SizedBox(
      width: 560,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Solde disponible : ${_money(widget.source.balance)} MAD'),
            const SizedBox(height: AppSpacing.sm),
            for (var index = 0; index < _rows.length; index++)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final row = _rows[index];
                    final destination = DropdownButtonFormField<String>(
                      key: Key('to-allocate-destination-$index'),
                      initialValue: row.envelopeId,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Enveloppe'),
                      items: widget.destinations
                          .map(
                            (item) => DropdownMenuItem(
                              value: item.id,
                              child: Text(
                                item.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: _submitting
                          ? null
                          : (value) => setState(() => row.envelopeId = value),
                    );
                    final amount = TextField(
                      key: Key('to-allocate-amount-$index'),
                      controller: row.amount,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Montant (MAD)',
                      ),
                      onChanged: (_) => setState(() {}),
                    );
                    final remove = IconButton(
                      key: Key('remove-to-allocate-row-$index'),
                      onPressed: _submitting || _rows.length == 1
                          ? null
                          : () => setState(() {
                              final removed = _rows.removeAt(index);
                              removed.dispose();
                            }),
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Supprimer',
                    );
                    return constraints.maxWidth < 420
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              destination,
                              const SizedBox(height: AppSpacing.sm),
                              amount,
                              Align(
                                alignment: Alignment.centerRight,
                                child: remove,
                              ),
                            ],
                          )
                        : Row(
                            children: [
                              Expanded(flex: 3, child: destination),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(flex: 2, child: amount),
                              remove,
                            ],
                          );
                  },
                ),
              ),
            TextButton.icon(
              key: const Key('add-to-allocate-destination-button'),
              onPressed: _submitting
                  ? null
                  : () => setState(() => _rows.add(_DistributionDraft())),
              icon: const Icon(Icons.add),
              label: const Text('Ajouter une enveloppe'),
            ),
            Text(
              'Disponible : ${_money(Money.fromMinorUnits(_availableCents))} MAD',
            ),
            Text(
              'Affecté : ${_money(Money.fromMinorUnits(_allocatedCents))} MAD',
            ),
            Text(
              'Reste : ${_money(Money.fromMinorUnits(_availableCents - _allocatedCents))} MAD',
            ),
            if (_overAllocated || _hasDuplicateDestination || _error != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Text(
                  _error ??
                      (_overAllocated
                          ? 'Le total affecté dépasse le solde disponible.'
                          : 'Une enveloppe ne peut être choisie qu’une fois.'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _submitting ? null : () => Navigator.pop(context),
        child: const Text('Annuler'),
      ),
      FilledButton(
        key: const Key('confirm-to-allocate-distribution-button'),
        onPressed: _submitting || _overAllocated || _hasDuplicateDestination
            ? null
            : _submit,
        child: Text(_submitting ? 'Répartition…' : 'Confirmer'),
      ),
    ],
  );
}

class _EnvelopeTransferDialogState
    extends ConsumerState<_EnvelopeTransferDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _description = TextEditingController();
  String? _sourceId;
  String? _destinationId;
  var _submitting = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || !_formKey.currentState!.validate()) {
      return;
    }
    final cents = _madToCents(_amount.text);
    if (cents == null || cents <= 0) {
      setState(() => _error = 'Saisissez un montant strictement positif.');
      return;
    }
    if (_sourceId == _destinationId) {
      setState(
        () => _error =
            'Les enveloppes source et destination doivent être différentes.',
      );
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(createRemoteEnvelopeTransferProvider)(
        sourceEnvelopeId: _sourceId!,
        destinationEnvelopeId: _destinationId!,
        amount: Money.fromMinorUnits(cents),
        occurredAt: DateTime.now(),
        description: _description.text.trim(),
      );
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Transfert impossible : $error');
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Transférer entre enveloppes'),
    content: SizedBox(
      width: 440,
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _EnvelopeDropdown(
                key: const Key('transfer-source-envelope-field'),
                label: 'Enveloppe source *',
                envelopes: widget.envelopes,
                value: _sourceId,
                onChanged: _submitting
                    ? null
                    : (id) => setState(() => _sourceId = id),
              ),
              const SizedBox(height: AppSpacing.sm),
              _EnvelopeDropdown(
                key: const Key('transfer-destination-envelope-field'),
                label: 'Enveloppe destination *',
                envelopes: widget.envelopes,
                value: _destinationId,
                onChanged: _submitting
                    ? null
                    : (id) => setState(() => _destinationId = id),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                key: const Key('transfer-envelope-amount-field'),
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Montant (MAD) *'),
                validator: (value) => (_madToCents(value ?? '') ?? 0) <= 0
                    ? 'Saisissez un montant positif valide.'
                    : null,
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                key: const Key('transfer-envelope-description-field'),
                controller: _description,
                decoration: const InputDecoration(labelText: 'Description *'),
                validator: (value) => (value?.trim().isEmpty ?? true)
                    ? 'La description est obligatoire.'
                    : null,
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _submitting ? null : () => Navigator.pop(context),
        child: const Text('Annuler'),
      ),
      FilledButton(
        key: const Key('confirm-envelope-transfer-button'),
        onPressed: _submitting ? null : _submit,
        child: Text(_submitting ? 'Validation…' : 'Transférer'),
      ),
    ],
  );
}

class _EnvelopeDropdown extends StatelessWidget {
  const _EnvelopeDropdown({
    super.key,
    required this.label,
    required this.envelopes,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final List<RemoteEnvelopeBalance> envelopes;
  final String? value;
  final ValueChanged<String?>? onChanged;
  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    key: key,
    initialValue: value,
    decoration: InputDecoration(labelText: label),
    items: envelopes
        .map(
          (item) => DropdownMenuItem(
            value: item.id,
            child: Text(item.isSystem ? '${item.name} (Système)' : item.name),
          ),
        )
        .toList(growable: false),
    onChanged: onChanged,
    validator: (value) => value == null ? 'Choisissez une enveloppe.' : null,
  );
}

String _money(Money amount) => amount.dirhams.toStringAsFixed(2);
String _frenchMoney(Money amount) {
  final cents = amount.minorUnits;
  final sign = cents < 0 ? '-' : '';
  final absoluteCents = cents.abs();
  final whole = (absoluteCents ~/ 100).toString().replaceAllMapped(
    RegExp(r'(?=(\d{3})+(?!\d))'),
    (_) => '\u202f',
  );
  final fractional = (absoluteCents % 100).toString().padLeft(2, '0');
  return '$sign$whole,$fractional MAD';
}

String _date(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
int? _madToCents(String value) {
  final normalized = value.trim().replaceAll(',', '.');
  if (!RegExp(r'^\d+(?:\.\d{1,2})?$').hasMatch(normalized)) return null;
  final parts = normalized.split('.');
  final whole = int.tryParse(parts.first);
  if (whole == null) return null;
  return whole * 100 +
      (parts.length == 1 ? 0 : int.parse(parts.last.padRight(2, '0')));
}

class _EnvelopeEditorDialog extends ConsumerStatefulWidget {
  const _EnvelopeEditorDialog({this.envelope});
  final RemoteEnvelopeBalance? envelope;

  @override
  ConsumerState<_EnvelopeEditorDialog> createState() =>
      _EnvelopeEditorDialogState();
}

class _EnvelopeEditorDialogState extends ConsumerState<_EnvelopeEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _opening;
  final _notes = TextEditingController();
  var _saving = false;
  String? _error;

  bool get _editing => widget.envelope != null;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.envelope?.name ?? '');
    _opening = TextEditingController();
    _notes.text = widget.envelope?.notes ?? '';
  }

  @override
  void dispose() {
    _name.dispose();
    _opening.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    final cents = _editing ? 0 : _madToCents(_opening.text);
    if (cents == null || cents < 0) {
      setState(() => _error = 'Saisissez un solde initial positif ou nul.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (_editing) {
        await ref.read(updateRemoteEnvelopeProvider)(
          envelopeId: widget.envelope!.id,
          name: _name.text,
          notes: _notes.text,
          archived: false,
        );
      } else {
        await ref.read(createRemoteEnvelopeProvider)(
          name: _name.text,
          openingBalance: Money.fromMinorUnits(cents),
          notes: _notes.text,
        );
      }
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Enregistrement impossible. Réessayez.');
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(_editing ? 'Modifier l’enveloppe' : 'Nouvelle enveloppe'),
    content: SizedBox(
      width: 420,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              key: const Key('envelope-name-field'),
              controller: _name,
              decoration: const InputDecoration(labelText: 'Nom *'),
              validator: (value) => value?.trim().isEmpty ?? true
                  ? 'Le nom est obligatoire.'
                  : null,
            ),
            if (!_editing)
              TextFormField(
                key: const Key('envelope-opening-balance-field'),
                controller: _opening,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Solde initial (MAD)',
                ),
              ),
            TextFormField(
              key: const Key('envelope-notes-field'),
              controller: _notes,
              decoration: const InputDecoration(labelText: 'Notes'),
              maxLines: 2,
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('Annuler'),
      ),
      FilledButton(
        key: const Key('save-envelope-button'),
        onPressed: _saving ? null : _save,
        child: Text(_saving ? 'Enregistrement…' : 'Enregistrer'),
      ),
    ],
  );
}
