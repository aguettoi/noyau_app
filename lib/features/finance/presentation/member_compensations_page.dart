import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_design_system.dart';
import '../../envelopes/application/providers/remote_envelopes_provider.dart';
import '../application/providers/member_compensations_provider.dart';
import '../application/providers/remote_accounts_provider.dart';
import '../domain/financial_account.dart';
import 'widgets/envelope_allocation_dialog.dart';

class MemberCompensationsPage extends ConsumerWidget {
  const MemberCompensationsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(memberCompensationsProvider);
    final accounts =
        ref.watch(remoteAccountsProvider).valueOrNull ??
        const <FinancialAccount>[];
    final envelopes =
        ref.watch(remoteEnvelopeBalancesProvider).valueOrNull ??
        const <RemoteEnvelopeBalance>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Compensations internes')),
      body: SafeArea(
        child: data.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Text('Impossible de charger les compensations : $e'),
          ),
          data: (items) => ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              const Text(
                'Une compensation suit un financement entre membres. Elle ne crée ni dépense, ni revenu, ni consommation d’enveloppe.',
              ),
              const SizedBox(height: AppSpacing.md),
              if (!items.any(
                (e) => e.status == 'to_pay' || e.status == 'transfer_sent',
              ))
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(AppSpacing.lg),
                    child: Text('Aucune compensation en attente.'),
                  ),
                ),
              for (final item in items.where(
                (e) => e.status == 'to_pay' || e.status == 'transfer_sent',
              ))
                Card(
                  child: ListTile(
                    title: Text(
                      '${item.debtor} doit verser à ${item.creditor}',
                    ),
                    subtitle: Text(
                      '${item.reason}\nRestant : ${item.remaining.toStringAsFixed(2)} MAD',
                    ),
                    trailing: Chip(label: Text(_label(item.status))),
                    onTap: () =>
                        _detail(context, ref, item, accounts, envelopes),
                  ),
                ),
              if (items.any(
                (e) => e.status == 'settled' || e.status == 'abandoned',
              )) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Historique',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                for (final item in items.where(
                  (e) => e.status == 'settled' || e.status == 'abandoned',
                ))
                  Card(
                    child: ListTile(
                      title: Text('${item.debtor} → ${item.creditor}'),
                      subtitle: Text(item.reason),
                      trailing: Chip(label: Text(_label(item.status))),
                      onTap: () =>
                          _detail(context, ref, item, accounts, envelopes),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _label(String s) => switch (s) {
    'to_pay' => 'À verser',
    'transfer_sent' => 'En attente de réception',
    'settled' => 'Soldée',
    'abandoned' => 'Abandonnée',
    _ => s,
  };

  Future<void> _detail(
    BuildContext context,
    WidgetRef ref,
    MemberCompensation item,
    List<FinancialAccount> accounts,
    List<RemoteEnvelopeBalance> envelopes,
  ) => showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text('${item.debtor} → ${item.creditor}'),
      content: Text(
        'Montant initial : ${item.initial.toStringAsFixed(2)} MAD\nRestant : ${item.remaining.toStringAsFixed(2)} MAD\nEn attente de réception : ${item.pendingReceipt.toStringAsFixed(2)} MAD\n${item.reason}',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('Fermer'),
        ),
        if (item.remaining > 0)
          TextButton(
            key: const Key('canonical-compensation-transfer'),
            onPressed: () => _canonicalTransfer(c, ref, item, accounts),
            child: const Text('Effectuer le virement'),
          ),
        if (item.remaining > 0)
          TextButton(
            onPressed: () => _amountAction(
              c,
              ref,
              item,
              'transfer_declared',
              'Virement déclaré hors application',
              max: item.remaining,
            ),
            child: const Text('Déclarer effectué hors application'),
          ),
        if (item.pendingReceipt > 0)
          FilledButton(
            onPressed: () => _amountAction(
              c,
              ref,
              item,
              'receipt_confirmed',
              'Réception confirmée',
              max: item.pendingReceipt,
            ),
            child: const Text('Confirmer réception'),
          ),
        if (item.remaining > 0)
          TextButton(
            onPressed: () => _abandon(c, ref, item, envelopes),
            child: const Text('Abandonner la compensation'),
          ),
      ],
    ),
  );

  Future<void> _canonicalTransfer(
    BuildContext context,
    WidgetRef ref,
    MemberCompensation item,
    List<FinancialAccount> accounts,
  ) async {
    final result =
        await showDialog<(String, String, double, DateTime, String)?>(
          context: context,
          builder: (_) =>
              _CompensationTransferDialog(item: item, accounts: accounts),
        );
    if (result == null || !context.mounted) return;
    final key = newCompensationIdempotencyKey();
    await ref.read(compensationCanonicalTransferProvider)(
      compensationId: item.id,
      sourceAccountId: result.$1,
      destinationAccountId: result.$2,
      amount: result.$3,
      occurredAt: result.$4,
      description: result.$5,
      idempotencyKey: key,
    );
    if (context.mounted) Navigator.pop(context);
  }

  Future<void> _amountAction(
    BuildContext context,
    WidgetRef ref,
    MemberCompensation item,
    String kind,
    String reason, {
    required double max,
  }) async {
    final ctl = TextEditingController(text: max.toStringAsFixed(2));
    final value = await showDialog<double>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(reason),
        content: TextField(
          controller: ctl,
          decoration: const InputDecoration(labelText: 'Montant (MAD)'),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              c,
              double.tryParse(ctl.text.replaceAll(',', '.')),
            ),
            child: const Text('Confirmer'),
          ),
        ],
      ),
    );
    ctl.dispose();
    if (value == null || value <= 0 || value > max || !context.mounted) return;
    await ref.read(compensationActionProvider)(
      compensationId: item.id,
      kind: kind,
      amount: value,
      reason: reason,
      allocations: const [],
    );
    if (context.mounted) Navigator.pop(context);
  }

  Future<void> _abandon(
    BuildContext context,
    WidgetRef ref,
    MemberCompensation item,
    List<RemoteEnvelopeBalance> envelopes,
  ) async {
    final reason = TextEditingController();
    final r = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Abandonner la compensation'),
        content: TextField(
          controller: reason,
          decoration: const InputDecoration(labelText: 'Motif obligatoire'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, reason.text.trim()),
            child: const Text('Continuer'),
          ),
        ],
      ),
    );
    reason.dispose();
    if (r == null || r.isEmpty || !context.mounted) return;
    final allocation = await showDialog<EnvelopeAllocationResult>(
      context: context,
      builder: (_) => EnvelopeAllocationDialog(
        amountCents: (item.remaining * 100).round(),
        envelopes: envelopes,
        allowNoImpact: true,
      ),
    );
    if (allocation == null || !context.mounted) return;
    await ref.read(compensationActionProvider)(
      compensationId: item.id,
      kind: 'abandoned',
      amount: item.remaining,
      reason:
          '$r${allocation.noImpact ? ' — aucun impact supplémentaire sur les enveloppes' : ''}',
      allocations: allocation.allocations,
    );
    if (context.mounted) Navigator.pop(context);
  }
}

class _CompensationTransferDialog extends StatefulWidget {
  const _CompensationTransferDialog({
    required this.item,
    required this.accounts,
  });
  final MemberCompensation item;
  final List<FinancialAccount> accounts;
  @override
  State<_CompensationTransferDialog> createState() =>
      _CompensationTransferDialogState();
}

class _CompensationTransferDialogState
    extends State<_CompensationTransferDialog> {
  String? source, destination;
  late final TextEditingController amount, description;
  @override
  void initState() {
    super.initState();
    source = widget.item.recommendedAccountId;
    destination = widget.item.actualAccountId;
    amount = TextEditingController(
      text: widget.item.remaining.toStringAsFixed(2),
    );
    description = TextEditingController(
      text:
          'Règlement compensation ${widget.item.debtor} → ${widget.item.creditor}',
    );
  }

  @override
  void dispose() {
    amount.dispose();
    description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final available = widget.accounts
        .where((a) => !a.isArchived && !a.isSystem)
        .toList();
    return AlertDialog(
      title: const Text('Effectuer le virement'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            initialValue: source,
            decoration: const InputDecoration(labelText: 'Compte source'),
            items: available
                .map((a) => DropdownMenuItem(value: a.id, child: Text(a.name)))
                .toList(),
            onChanged: (v) => setState(() => source = v),
          ),
          DropdownButtonFormField<String>(
            initialValue: destination,
            decoration: const InputDecoration(labelText: 'Compte destination'),
            items: available
                .map((a) => DropdownMenuItem(value: a.id, child: Text(a.name)))
                .toList(),
            onChanged: (v) => setState(() => destination = v),
          ),
          TextField(
            controller: amount,
            decoration: const InputDecoration(labelText: 'Montant (MAD)'),
          ),
          TextField(
            controller: description,
            decoration: const InputDecoration(labelText: 'Description'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () {
            final v = double.tryParse(amount.text.replaceAll(',', '.'));
            if (source != null &&
                destination != null &&
                source != destination &&
                v != null &&
                v > 0 &&
                v <= widget.item.remaining) {
              Navigator.pop(context, (
                source!,
                destination!,
                v,
                DateTime.now(),
                description.text.trim(),
              ));
            }
          },
          child: const Text('Enregistrer le virement'),
        ),
      ],
    );
  }
}
