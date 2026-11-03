import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_design_system.dart';
import '../../../core/localization/member_compensations_locale.dart';
import '../../envelopes/application/providers/remote_envelopes_provider.dart';
import '../application/providers/member_compensations_provider.dart';
import '../application/providers/remote_accounts_provider.dart';
import '../domain/financial_account.dart';
import 'widgets/envelope_allocation_dialog.dart';

class MemberCompensationsPage extends ConsumerWidget {
  const MemberCompensationsPage({super.key, this.initialCompensationId});
  final String? initialCompensationId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final words = MemberCompensationWords.of(context);
    final data = ref.watch(memberCompensationsProvider);
    final accounts =
        ref.watch(remoteAccountsProvider).valueOrNull ??
        const <FinancialAccount>[];
    final envelopes =
        ref.watch(remoteEnvelopeBalancesProvider).valueOrNull ??
        const <RemoteEnvelopeBalance>[];
    return Scaffold(
      appBar: AppBar(title: Text(words.text('title'))),
      body: SafeArea(
        child: data.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Center(child: Text(words.text('load_error'))),
          data: (items) {
            final ordered = initialCompensationId == null
                ? [...items]
                : items
                      .where((item) => item.id == initialCompensationId)
                      .toList(growable: false);
            return ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                Text(words.text('notice')),
                const SizedBox(height: AppSpacing.md),
                if (!ordered.any(
                  (e) => e.status == 'to_pay' || e.status == 'transfer_sent',
                ))
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Text(words.text('empty')),
                    ),
                  ),
                for (final item in ordered.where(
                  (e) => e.status == 'to_pay' || e.status == 'transfer_sent',
                ))
                  Card(
                    child: ListTile(
                      title: Text(
                        words.format('transfer_due', {
                          'debtor': item.debtor,
                          'creditor': item.creditor,
                        }),
                      ),
                      subtitle: Text(
                        words.format('remaining_reason', {
                          'reason': item.reason,
                          'amount': '${item.remaining.toStringAsFixed(2)} MAD',
                        }),
                      ),
                      trailing: Chip(
                        label: Text(words.text('status.${item.status}')),
                      ),
                      onTap: () =>
                          _detail(context, ref, item, accounts, envelopes),
                    ),
                  ),
                if (ordered.any(
                  (e) => e.status == 'settled' || e.status == 'abandoned',
                )) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    words.text('history'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  for (final item in ordered.where(
                    (e) => e.status == 'settled' || e.status == 'abandoned',
                  ))
                    Card(
                      child: ListTile(
                        title: Text(
                          words.format('parties', {
                            'debtor': item.debtor,
                            'creditor': item.creditor,
                          }),
                        ),
                        subtitle: Text(item.reason),
                        trailing: Chip(
                          label: Text(words.text('status.${item.status}')),
                        ),
                        onTap: () =>
                            _detail(context, ref, item, accounts, envelopes),
                      ),
                    ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _detail(
    BuildContext context,
    WidgetRef ref,
    MemberCompensation item,
    List<FinancialAccount> accounts,
    List<RemoteEnvelopeBalance> envelopes,
  ) => showDialog<void>(
    context: context,
    builder: (c) {
      final words = MemberCompensationWords.of(c);
      return AlertDialog(
        title: Text(
          words.format('parties', {
            'debtor': item.debtor,
            'creditor': item.creditor,
          }),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(words.format('debtor', {'name': item.debtor})),
            Text(words.format('creditor', {'name': item.creditor})),
            Text(
              words.format('initial_amount', {
                'amount': '${item.initial.toStringAsFixed(2)} MAD',
              }),
            ),
            Text(
              words.format('remaining_amount', {
                'amount': '${item.remaining.toStringAsFixed(2)} MAD',
              }),
            ),
            Text(
              words.format('pending_amount', {
                'amount': '${item.pendingReceipt.toStringAsFixed(2)} MAD',
              }),
            ),
            Text(words.format('reason', {'reason': item.reason})),
            Text(
              words.format('state', {
                'state': words.text('status.${item.status}'),
              }),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text(words.text('close')),
          ),
          if (item.remaining > 0)
            TextButton(
              key: const Key('canonical-compensation-transfer'),
              onPressed: () => _canonicalTransfer(c, ref, item, accounts),
              child: Text(words.text('make_transfer')),
            ),
          if (item.remaining > 0)
            TextButton(
              onPressed: () => _amountAction(
                c,
                ref,
                item,
                'transfer_declared',
                words.text('external_title'),
                'Virement déclaré hors application',
                max: item.remaining,
              ),
              child: Text(words.text('declare_external')),
            ),
          if (item.pendingReceipt > 0)
            FilledButton(
              onPressed: () => _amountAction(
                c,
                ref,
                item,
                'receipt_confirmed',
                words.text('receipt_title'),
                'Réception confirmée',
                max: item.pendingReceipt,
              ),
              child: Text(words.text('confirm_receipt')),
            ),
          if (item.remaining > 0)
            TextButton(
              onPressed: () => _abandon(c, ref, item, envelopes),
              child: Text(words.text('abandon')),
            ),
        ],
      );
    },
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
    String title,
    String canonicalReason, {
    required double max,
  }) async {
    final ctl = TextEditingController(text: max.toStringAsFixed(2));
    final value = await showDialog<double>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctl,
          decoration: InputDecoration(
            labelText: MemberCompensationWords.of(c).text('amount'),
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text(MemberCompensationWords.of(c).text('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              c,
              double.tryParse(ctl.text.replaceAll(',', '.')),
            ),
            child: Text(MemberCompensationWords.of(c).text('confirm')),
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
      reason: canonicalReason,
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
        title: Text(MemberCompensationWords.of(c).text('abandon')),
        content: TextField(
          controller: reason,
          decoration: InputDecoration(
            labelText: MemberCompensationWords.of(c).text('required_reason'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text(MemberCompensationWords.of(c).text('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, reason.text.trim()),
            child: Text(MemberCompensationWords.of(c).text('continue')),
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
    description = TextEditingController();
  }

  @override
  void dispose() {
    amount.dispose();
    description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final words = MemberCompensationWords.of(context);
    if (description.text.isEmpty) {
      description.text = words.format('default_description', {
        'debtor': widget.item.debtor,
        'creditor': widget.item.creditor,
      });
    }
    final available = widget.accounts
        .where((a) => !a.isArchived && !a.isSystem)
        .toList();
    return AlertDialog(
      title: Text(words.text('make_transfer')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            initialValue: source,
            decoration: InputDecoration(
              labelText: words.text('source_account'),
            ),
            items: available
                .map((a) => DropdownMenuItem(value: a.id, child: Text(a.name)))
                .toList(),
            onChanged: (v) => setState(() => source = v),
          ),
          DropdownButtonFormField<String>(
            initialValue: destination,
            decoration: InputDecoration(
              labelText: words.text('destination_account'),
            ),
            items: available
                .map((a) => DropdownMenuItem(value: a.id, child: Text(a.name)))
                .toList(),
            onChanged: (v) => setState(() => destination = v),
          ),
          TextField(
            controller: amount,
            decoration: InputDecoration(labelText: words.text('amount')),
          ),
          TextField(
            controller: description,
            decoration: InputDecoration(labelText: words.text('description')),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(words.text('cancel')),
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
          child: Text(words.text('save_transfer')),
        ),
      ],
    );
  }
}
