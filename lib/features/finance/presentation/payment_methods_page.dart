import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/finance_locale.dart';

import '../application/providers/active_household_provider.dart';
import '../application/providers/payment_methods_provider.dart';
import '../application/providers/remote_accounts_provider.dart';
import '../application/providers/remote_household_members_provider.dart';
import '../domain/financial_account.dart';
import '../domain/household_member.dart';

class PaymentMethodsPage extends ConsumerWidget {
  const PaymentMethodsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final methods = ref.watch(paymentMethodsProvider);
    final accounts = ref.watch(remoteAccountsProvider);
    final members = ref.watch(remoteHouseholdMembersProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(FinanceWords.of(context).text('payment.title')),
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('payment-methods-add-button'),
        onPressed: accounts.hasValue && members.hasValue
            ? () => _openEditor(
                context,
                ref,
                accounts: accounts.requireValue,
                members: members.requireValue,
              )
            : null,
        icon: const Icon(Icons.add),
        label: Text(FinanceWords.of(context).text('common.add')),
      ),
      body: methods.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: Text(FinanceWords.of(context).text('payment.unavailable')),
        ),
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Text(FinanceWords.of(context).text('payment.empty')),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            itemBuilder: (_, index) {
              final item = items[index];
              return Card(
                child: ListTile(
                  key: ValueKey('payment-method-${item.id}'),
                  onTap: () => _openEditor(
                    context,
                    ref,
                    existing: item,
                    accounts: accounts.valueOrNull ?? const [],
                    members: members.valueOrNull ?? const [],
                  ),
                  title: Text(item.label),
                  subtitle: Text(
                    [
                      _typeLabel(context, item.type),
                      if (item.accountId != null)
                        accounts.valueOrNull
                                ?.where(
                                  (account) => account.id == item.accountId,
                                )
                                .map((account) => account.name)
                                .firstOrNull ??
                            FinanceWords.of(
                              context,
                            ).text('payment.linked_account'),
                      if (item.holderUserId != null)
                        members.valueOrNull
                                ?.where(
                                  (member) => member.id == item.holderUserId,
                                )
                                .map((member) => member.displayName)
                                .firstOrNull ??
                            FinanceWords.of(
                              context,
                            ).text('payment.linked_holder'),
                      item.active
                          ? FinanceWords.of(context).text('common.active')
                          : FinanceWords.of(context).text('common.archived'),
                    ].join(' · '),
                  ),
                  trailing: Switch(
                    value: item.active,
                    onChanged: (value) => _toggle(ref, item, value),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _toggle(WidgetRef ref, PaymentMethod item, bool active) async {
    await ref
        .read(paymentMethodsGatewayProvider)
        .update(
          id: item.id,
          accountId: item.accountId,
          holderUserId: item.holderUserId,
          type: item.type,
          label: item.label,
          active: active,
        );
    ref.invalidate(paymentMethodsProvider);
  }

  Future<void> _openEditor(
    BuildContext context,
    WidgetRef ref, {
    PaymentMethod? existing,
    required List<FinancialAccount> accounts,
    required List<HouseholdMember> members,
  }) async {
    final label = TextEditingController(text: existing?.label ?? '');
    var type = existing?.type ?? 'bank_card';
    var accountId = existing?.accountId ?? '';
    var holderUserId = existing?.holderUserId ?? '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          scrollable: true,
          title: Text(
            FinanceWords.of(context).text(
              existing == null ? 'payment.add_title' : 'payment.edit_title',
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('payment-method-label-field'),
                controller: label,
                decoration: InputDecoration(
                  labelText: FinanceWords.of(context).text('payment.label'),
                ),
              ),
              DropdownButtonFormField<String>(
                key: const Key('payment-method-type-field'),
                initialValue: type,
                items: [
                  DropdownMenuItem(
                    value: 'bank_card',
                    child: Text(
                      FinanceWords.of(context).text('payment.kind.card'),
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'cash',
                    child: Text(
                      FinanceWords.of(context).text('payment.kind.cash'),
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'bank_transfer',
                    child: Text(
                      FinanceWords.of(context).text('payment.kind.transfer'),
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'other',
                    child: Text(
                      FinanceWords.of(context).text('payment.kind.other'),
                    ),
                  ),
                ],
                onChanged: (value) => setState(() => type = value ?? type),
                decoration: InputDecoration(
                  labelText: FinanceWords.of(context).text('payment.type'),
                ),
              ),
              DropdownButtonFormField<String>(
                key: const Key('payment-method-account-field'),
                initialValue: accountId,
                decoration: InputDecoration(
                  labelText: FinanceWords.of(
                    context,
                  ).text('payment.account_optional'),
                ),
                items: [
                  DropdownMenuItem(
                    value: '',
                    child: Text(FinanceWords.of(context).text('common.none')),
                  ),
                  for (final account in accounts)
                    if (!account.isArchived)
                      DropdownMenuItem(
                        value: account.id,
                        child: Text(account.name),
                      ),
                ],
                onChanged: (value) => setState(() => accountId = value ?? ''),
              ),
              DropdownButtonFormField<String>(
                key: const Key('payment-method-holder-field'),
                initialValue: holderUserId,
                decoration: InputDecoration(
                  labelText: FinanceWords.of(
                    context,
                  ).text('payment.holder_optional'),
                ),
                items: [
                  DropdownMenuItem(
                    value: '',
                    child: Text(FinanceWords.of(context).text('common.none')),
                  ),
                  for (final member in members)
                    DropdownMenuItem(
                      value: member.id,
                      child: Text(member.displayName),
                    ),
                ],
                onChanged: (value) =>
                    setState(() => holderUserId = value ?? ''),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(FinanceWords.of(context).text('common.cancel')),
            ),
            FilledButton(
              key: const Key('payment-method-save-button'),
              onPressed: () => Navigator.pop(context, true),
              child: Text(
                FinanceWords.of(
                  context,
                ).text(existing == null ? 'common.create' : 'common.save'),
              ),
            ),
          ],
        ),
      ),
    );
    if (ok != true || label.text.trim().isEmpty || !context.mounted) return;
    final household = await ref.read(activeHouseholdProvider.future);
    final id = household.householdId;
    if (id == null) return;
    final gateway = ref.read(paymentMethodsGatewayProvider);
    if (existing == null) {
      await gateway.create(
        householdId: id,
        accountId: accountId.isEmpty ? null : accountId,
        holderUserId: holderUserId.isEmpty ? null : holderUserId,
        type: type,
        label: label.text.trim(),
      );
    } else {
      await gateway.update(
        id: existing.id,
        accountId: accountId.isEmpty ? null : accountId,
        holderUserId: holderUserId.isEmpty ? null : holderUserId,
        type: type,
        label: label.text.trim(),
        active: existing.active,
      );
    }
    ref.invalidate(paymentMethodsProvider);
  }

  String _typeLabel(BuildContext context, String type) => switch (type) {
    'bank_card' => FinanceWords.of(context).text('payment.kind.card'),
    'cash' => FinanceWords.of(context).text('payment.kind.cash'),
    'bank_transfer' => FinanceWords.of(context).text('payment.kind.transfer'),
    _ => FinanceWords.of(context).text('payment.kind.other'),
  };
}
