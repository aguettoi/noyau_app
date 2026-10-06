import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_design_system.dart';
import '../application/providers/member_compensations_provider.dart';

class MemberCompensationsPage extends ConsumerWidget {
  const MemberCompensationsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(memberCompensationsProvider);
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
              if (items.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(AppSpacing.lg),
                    child: Text('Aucune compensation active.'),
                  ),
                ),
              for (final item in items)
                Card(
                  child: ListTile(
                    title: Text(
                      '${item.debtor} doit verser à ${item.creditor}',
                    ),
                    subtitle: Text(
                      '${item.reason}\nRestant : ${item.remaining.toStringAsFixed(2)} MAD',
                    ),
                    trailing: Chip(label: Text(_label(item.status))),
                    onTap: () => _detail(context, ref, item),
                  ),
                ),
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
  ) => showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('${item.debtor} → ${item.creditor}'),
      content: Text(
        'Montant initial : ${item.initial.toStringAsFixed(2)} MAD\nRestant : ${item.remaining.toStringAsFixed(2)} MAD\n${item.reason}',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Fermer'),
        ),
        if (item.status == 'to_pay')
          TextButton(
            onPressed: () => _action(
              dialogContext,
              ref,
              item,
              'transfer_declared',
              'Virement déclaré hors application',
            ),
            child: const Text('Virement effectué'),
          ),
        if (item.status == 'transfer_sent')
          FilledButton(
            onPressed: () => _action(
              dialogContext,
              ref,
              item,
              'receipt_confirmed',
              'Réception confirmée',
            ),
            child: const Text('Reçu'),
          ),
        if (item.remaining > 0)
          TextButton(
            onPressed: () => _action(
              dialogContext,
              ref,
              item,
              'abandoned',
              'Compensation abandonnée',
              allocations: const [],
            ),
            child: const Text('Abandonner'),
          ),
      ],
    ),
  );
  Future<void> _action(
    BuildContext context,
    WidgetRef ref,
    MemberCompensation item,
    String kind,
    String reason, {
    List<Map<String, Object?>> allocations = const [],
  }) async {
    await ref.read(compensationActionProvider)(
      compensationId: item.id,
      kind: kind,
      amount: item.remaining,
      reason: reason,
      allocations: allocations,
    );
    if (context.mounted) Navigator.pop(context);
  }
}
