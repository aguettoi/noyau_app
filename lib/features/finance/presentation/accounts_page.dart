import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/accounts_locale.dart';
import '../../../core/money/money.dart';
import '../../../core/theme/app_design_system.dart';
import '../../envelopes/application/providers/remote_envelopes_provider.dart';
import '../application/providers/remote_account_balances_provider.dart';
import '../application/providers/account_balance_observation_provider.dart';
import '../domain/cash_inventory.dart';
import '../application/providers/remote_accounts_provider.dart';
import '../application/providers/remote_household_members_provider.dart';
import '../application/providers/remote_transactions_provider.dart';
import '../domain/account_ownership.dart';
import '../domain/household_member.dart';
import '../domain/financial_account.dart';
import '../infrastructure/accounts_supabase_repository.dart';
import 'transactions_page.dart';
import 'widgets/envelope_allocation_dialog.dart';

class AccountsPage extends ConsumerStatefulWidget {
  const AccountsPage({
    super.key,
    this.initialAccountId,
    this.openInitialAccount = false,
  });
  final String? initialAccountId;
  final bool openInitialAccount;

  @override
  ConsumerState<AccountsPage> createState() => _AccountsPageState();
}

Money? _visibleBalance(
  FinancialAccount account,
  Map<String, Money>? ledgerBalances,
) => account.canReadBalance
    ? (ledgerBalances?[account.id] ?? account.openingBalance)
    : null;

class _AccountsPageState extends ConsumerState<AccountsPage> {
  var _creating = false;
  var _initialOpened = false;

  Future<void> _openCreateDialog(
    List<FinancialAccount> accounts,
    AsyncValue<List<HouseholdMember>> members,
  ) async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => _CreateAccountDialog(
        existingAccounts: accounts,
        members: members.valueOrNull ?? const [],
        membersLoading: members.isLoading,
        membersError: members.hasError,
        onCreate: _createRemoteAccount,
      ),
    );
    if (created == true && mounted) {
      ref.invalidate(remoteAccountsProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AccountsWords.of(context).text('accounts.created')),
        ),
      );
    }
  }

  Future<void> _createRemoteAccount(CreateRemoteAccountRequest request) async {
    if (_creating) {
      return;
    }
    setState(() => _creating = true);
    try {
      await ref.read(supabaseAccountsRepositoryProvider).create(request);
    } finally {
      if (mounted) {
        setState(() => _creating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final accountsAsync = ref.watch(remoteAccountsProvider);
    final balancesAsync = ref.watch(remoteAccountBalancesProvider);
    final membersAsync = ref.watch(remoteHouseholdMembersProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(AccountsWords.of(context).text('accounts.title')),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _creating || !accountsAsync.hasValue
            ? null
            : () => _openCreateDialog(accountsAsync.requireValue, membersAsync),
        icon: _creating
            ? const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add),
        label: Text(AccountsWords.of(context).text('accounts.add')),
      ),
      body: accountsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: AppSpacing.page,
            child: Text(
              AccountsWords.of(
                context,
              ).format('accounts.read_error', {'error': error}),
            ),
          ),
        ),
        data: (items) {
          final ordered = widget.initialAccountId == null
              ? [...items]
              : items
                    .where((account) => account.id == widget.initialAccountId)
                    .toList(growable: false);
          if (widget.openInitialAccount &&
              !_initialOpened &&
              ordered.length == 1) {
            _initialOpened = true;
            final account = ordered.single;
            final balance = _visibleBalance(account, balancesAsync.valueOrNull);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        _AccountDetailPage(account: account, balance: balance),
                  ),
                );
              }
            });
          }
          return ListView(
            children: [
              DesktopPageContainer(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _AccountsHero(
                      accountCount: ordered.length,
                      hasHiddenBalances: ordered.any(
                        (account) => !account.canReadBalance,
                      ),
                      totalBalance: ordered.fold<Money>(
                        const Money.fromMinorUnits(0),
                        (total, account) {
                          return total +
                              (_visibleBalance(
                                    account,
                                    balancesAsync.valueOrNull,
                                  ) ??
                                  const Money.fromMinorUnits(0));
                        },
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    DesktopSection(
                      title: AccountsWords.of(context).text('accounts.yours'),
                      subtitle: ordered.isEmpty
                          ? AccountsWords.of(
                              context,
                            ).text('accounts.add_or_import')
                          : AccountsWords.of(context).format(
                              ordered.length == 1
                                  ? 'accounts.tracked_one'
                                  : 'accounts.tracked_many',
                              {'count': ordered.length},
                            ),
                      child: ordered.isEmpty
                          ? CompactListRow(
                              title: AccountsWords.of(
                                context,
                              ).text('accounts.empty'),
                              subtitle: AccountsWords.of(
                                context,
                              ).text('accounts.empty_hint'),
                              leading: const Icon(
                                Icons.account_balance_outlined,
                              ),
                            )
                          : LayoutBuilder(
                              builder: (context, constraints) {
                                final grid = constraints.maxWidth >= 900;
                                return grid
                                    ? ResponsiveGrid(
                                        minItemWidth: 390,
                                        children: ordered
                                            .map(
                                              (account) => _AccountRow(
                                                account: account,
                                                balance: _visibleBalance(
                                                  account,
                                                  balancesAsync.valueOrNull,
                                                ),
                                                members:
                                                    membersAsync.valueOrNull ??
                                                    const [],
                                              ),
                                            )
                                            .toList(growable: false),
                                      )
                                    : Column(
                                        children: ordered
                                            .map(
                                              (account) => Padding(
                                                padding: const EdgeInsets.only(
                                                  bottom: AppSpacing.xs,
                                                ),
                                                child: _AccountRow(
                                                  account: account,
                                                  balance: _visibleBalance(
                                                    account,
                                                    balancesAsync.valueOrNull,
                                                  ),
                                                  members:
                                                      membersAsync
                                                          .valueOrNull ??
                                                      const [],
                                                ),
                                              ),
                                            )
                                            .toList(growable: false),
                                      );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AccountsHero extends StatelessWidget {
  const _AccountsHero({
    required this.accountCount,
    required this.totalBalance,
    required this.hasHiddenBalances,
  });
  final int accountCount;
  final Money totalBalance;
  final bool hasHiddenBalances;

  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.primaryContainer,
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: AppSpacing.sm,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AccountsWords.of(context).text('accounts.overview'),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                AccountsWords.of(context).format(
                  accountCount == 1
                      ? 'accounts.linked_one'
                      : 'accounts.linked_many',
                  {'count': accountCount},
                ),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                AccountsWords.of(context).text('accounts.visible_total'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Text(
                // i18n-dynamic-only: formatted amount and canonical currency
                '${totalBalance.dirhams.toStringAsFixed(2)} MAD',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (hasHiddenBalances)
                Text(
                  AccountsWords.of(context).text('accounts.partial_balances'),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({
    required this.account,
    required this.balance,
    required this.members,
  });
  final FinancialAccount account;
  final Money? balance;
  final List<HouseholdMember> members;

  @override
  Widget build(BuildContext context) => CompactListRow(
    leading: Icon(_accountIcon(account.type), color: AppColors.secondary),
    title: account.name,
    subtitle:
        '${_accountTypeLabel(context, account.type)} • ${_holdersLabel(context, account, members)} • ${AccountsWords.of(context).text(account.isArchived ? 'accounts.archived' : 'accounts.active')}',
    trailing: Text(
      balance == null
          ? AccountsWords.of(context).text('accounts.hidden_balance')
          : '${balance!.dirhams.toStringAsFixed(2)} MAD',
      style: Theme.of(context).textTheme.labelLarge,
    ),
    onTap: () => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _AccountDetailPage(account: account, balance: balance),
      ),
    ),
  );
}

IconData _accountIcon(FinancialAccountType type) => switch (type) {
  FinancialAccountType.bank => Icons.account_balance_outlined,
  FinancialAccountType.cash => Icons.payments_outlined,
  FinancialAccountType.savings => Icons.savings_outlined,
  FinancialAccountType.debt => Icons.credit_score_outlined,
};

class _AccountDetailPage extends ConsumerWidget {
  const _AccountDetailPage({required this.account, required this.balance});
  final FinancialAccount account;
  final Money? balance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visibleBalance = balance;
    final history = visibleBalance == null
        ? null
        : ref.watch(accountTransactionHistoryProvider(account.id));
    final observation = visibleBalance == null
        ? null
        : ref.watch(latestAccountBalanceObservationProvider(account.id));
    final canReconcile =
        account.type == FinancialAccountType.bank ||
        account.type == FinancialAccountType.cash;
    return Scaffold(
      appBar: AppBar(title: Text(account.name)),
      body: ListView(
        padding: AppSpacing.page,
        children: [
          Text(account.name, style: Theme.of(context).textTheme.headlineSmall),
          Text(
            visibleBalance == null
                ? AccountsWords.of(context).text('accounts.hidden_balance')
                : AccountsWords.of(context).format('accounts.current_balance', {
                    'amount':
                        '${visibleBalance.dirhams.toStringAsFixed(2)} MAD',
                  }),
          ),
          if (canReconcile &&
              visibleBalance != null &&
              observation != null) ...[
            const SizedBox(height: AppSpacing.md),
            _AccountReconciliationCard(
              account: account,
              theoreticalBalance: visibleBalance,
              observation: observation,
              onRecord: () => _openObservationDialog(context, ref),
              onHistory: () => _openReconciliationHistory(context, ref),
            ),
          ],
          if (history != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              AccountsWords.of(context).text('accounts.operations'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            ...history.when(
              loading: () => const [Center(child: CircularProgressIndicator())],
              error: (_, _) => [
                Text(AccountsWords.of(context).text('accounts.history_error')),
              ],
              data: (items) => items.isEmpty
                  ? [
                      Text(
                        AccountsWords.of(context).text('accounts.no_operation'),
                      ),
                    ]
                  : items
                        .map(
                          (item) => ListTile(
                            title: Text(item.description),
                            subtitle: Text(
                              // i18n-dynamic-only: localized labels plus user data
                              '${_formatObservationDate(item.occurredAt)} • ${_accountHistoryLabel(context, item.type)}'
                              '${item.paymentMethodName == null ? '' : ' • ${item.paymentMethodName}'}'
                              '${item.envelopes.isEmpty ? '' : ' • ${item.envelopes.map((e) => e.name).join(', ')}'}'
                              '${item.isReversed
                                  ? ' • ${AccountsWords.of(context).text('accounts.history.reversed')}'
                                  : item.isReversal
                                  ? ' • ${AccountsWords.of(context).text('accounts.history.reversal')}'
                                  : ''}',
                            ),
                            trailing: Text(
                              // i18n-dynamic-only: sign, amount and canonical currency
                              '${item.sourceAccountId == account.id ? '−' : '+'}${item.amount.dirhams.abs().toStringAsFixed(2)} MAD',
                            ),
                          ),
                        )
                        .toList(growable: false),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _openObservationDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final visibleBalance = balance;
    if (visibleBalance == null) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _RecordAccountBalanceDialog(
        account: account,
        theoreticalBalance: visibleBalance,
        onRecord:
            ({
              required observedAt,
              required actualBalance,
              required reason,
              required inputMode,
              required denominationDetail,
              required idempotencyKey,
            }) => account.type == FinancialAccountType.cash
            ? ref.read(recordCashInventoryProvider)(
                accountId: account.id,
                observedAt: observedAt,
                actualBalance: actualBalance,
                reason: reason,
                inputMode: inputMode,
                denominationDetail: denominationDetail,
                idempotencyKey: idempotencyKey,
              )
            : ref.read(recordAccountBalanceObservationProvider)(
                accountId: account.id,
                observedAt: observedAt,
                actualBalance: actualBalance,
                reason: reason,
              ),
      ),
    );
    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AccountsWords.of(context).text('accounts.observation_saved'),
          ),
        ),
      );
    }
  }

  Future<void> _openReconciliationHistory(
    BuildContext context,
    WidgetRef ref,
  ) => showDialog<void>(
    context: context,
    builder: (_) => _ReconciliationHistoryDialog(account: account),
  );
}

class _AccountReconciliationCard extends StatelessWidget {
  const _AccountReconciliationCard({
    required this.account,
    required this.theoreticalBalance,
    required this.observation,
    required this.onRecord,
    required this.onHistory,
  });

  final FinancialAccount account;
  final Money theoreticalBalance;
  final AsyncValue<AccountBalanceObservation?> observation;
  final VoidCallback onRecord;
  final VoidCallback onHistory;

  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.secondaryContainer,
    child: Padding(
      padding: AppSpacing.card,
      child: observation.when(
        loading: () => const SizedBox(
          height: 48,
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (_, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              account.type == FinancialAccountType.cash
                  ? AccountsWords.of(context).text('accounts.cash_inventory')
                  : AccountsWords.of(
                      context,
                    ).text('accounts.bank_reconciliation'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              AccountsWords.of(
                context,
              ).text('accounts.latest_observation_error'),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: AppSpacing.sm,
                children: [
                  TextButton(
                    onPressed: onHistory,
                    child: Text(
                      AccountsWords.of(context).text('accounts.view_history'),
                    ),
                  ),
                  OutlinedButton(
                    onPressed: onRecord,
                    child: Text(
                      AccountsWords.of(context).text('accounts.observe_actual'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        data: (latest) {
          // A canonical observation freezes its own GL value. Do not recompute
          // its historical difference from a ledger that may have changed.
          final difference = latest == null
              ? null
              : latest.remainingDifference ??
                    latest.differenceSnapshot ??
                    latest.actualBalance - theoreticalBalance;
          final reconciled =
              latest?.status == 'resolved' ||
              latest?.status == 'reconciled' ||
              difference?.minorUnits == 0;
          final title = account.type == FinancialAccountType.cash
              ? AccountsWords.of(context).text('accounts.cash_inventory')
              : AccountsWords.of(context).text('accounts.bank_reconciliation');
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                AccountsWords.of(context).format(
                  'accounts.theoretical_balance',
                  {'amount': _frenchMoney(theoreticalBalance)},
                ),
              ),
              if (latest == null)
                Text(
                  AccountsWords.of(context).text('accounts.no_actual_balance'),
                )
              else ...[
                Text(
                  AccountsWords.of(context).format(
                    'accounts.observed_actual_balance',
                    {'amount': _frenchMoney(latest.actualBalance)},
                  ),
                ),
                if (latest.theoreticalBalanceSnapshot != null)
                  Text(
                    AccountsWords.of(context).format(
                      'accounts.frozen_theoretical',
                      {
                        'amount': _frenchMoney(
                          latest.theoreticalBalanceSnapshot!,
                        ),
                      },
                    ),
                  ),
                Text(
                  AccountsWords.of(context).format('accounts.difference', {
                    'amount': _frenchMoney(difference!),
                  }),
                ),
                Text(
                  reconciled == true
                      ? AccountsWords.of(
                          context,
                        ).text('accounts.state.reconciled')
                      : latest.status == 'partially_resolved'
                      ? AccountsWords.of(context).text('accounts.state.partial')
                      : latest.status == 'explained_pending'
                      ? AccountsWords.of(
                          context,
                        ).text('accounts.state.temporary')
                      : latest.status == 'legacy_unfrozen'
                      ? AccountsWords.of(context).text('accounts.state.legacy')
                      : AccountsWords.of(
                          context,
                        ).text('accounts.state.unexplained'),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: reconciled == true
                        ? AppColors.secondary
                        : Theme.of(context).colorScheme.error,
                  ),
                ),
                Text(
                  AccountsWords.of(context).format('accounts.observed_at', {
                    'date': _formatObservationDate(latest.observedAt),
                  }),
                ),
                Text(
                  AccountsWords.of(
                    context,
                  ).format('accounts.performed_by', {'name': latest.actorName}),
                ),
                Text(
                  AccountsWords.of(
                    context,
                  ).format('accounts.comment', {'comment': latest.reason}),
                ),
                if (latest.status == 'legacy_unfrozen')
                  Text(AccountsWords.of(context).text('accounts.legacy_hint')),
              ],
              const SizedBox(height: AppSpacing.sm),
              Text(
                AccountsWords.of(
                  context,
                ).text('accounts.account_envelope_distinction'),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  spacing: AppSpacing.sm,
                  children: [
                    TextButton(
                      key: const Key('view-reconciliation-history-button'),
                      onPressed: onHistory,
                      child: Text(
                        AccountsWords.of(context).text('accounts.view_history'),
                      ),
                    ),
                    OutlinedButton.icon(
                      key: const Key(
                        'record-account-balance-observation-button',
                      ),
                      onPressed: onRecord,
                      icon: const Icon(Icons.fact_check_outlined),
                      label: Text(
                        account.type == FinancialAccountType.cash
                            ? AccountsWords.of(
                                context,
                              ).text('accounts.count_cash')
                            : AccountsWords.of(
                                context,
                              ).text('accounts.observe_actual'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

class _ReconciliationHistoryDialog extends ConsumerWidget {
  const _ReconciliationHistoryDialog({required this.account});
  final FinancialAccount account;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(accountReconciliationHistoryProvider(account.id));
    return AlertDialog(
      title: Text(
        account.type == FinancialAccountType.cash
            ? AccountsWords.of(context).text('accounts.cash_history')
            : AccountsWords.of(context).text('accounts.reconciliation_history'),
      ),
      content: SizedBox(
        width: 620,
        child: history.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Text(
            AccountsWords.of(context).text('accounts.observations_error'),
          ),
          data: (cases) => cases.isEmpty
              ? Text(AccountsWords.of(context).text('accounts.no_observation'))
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: cases.length,
                  separatorBuilder: (_, _) => const Divider(),
                  itemBuilder: (_, index) => _ReconciliationCaseTile(
                    account: account,
                    item: cases[index],
                  ),
                ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(AccountsWords.of(context).text('accounts.close')),
        ),
      ],
    );
  }
}

class _ReconciliationCaseTile extends ConsumerWidget {
  const _ReconciliationCaseTile({required this.account, required this.item});
  final FinancialAccount account;
  final AccountReconciliationCase item;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final observation = item.observation;
    final remainder =
        item.remainingDifference ?? observation.differenceSnapshot;
    return ListTile(
      title: Text(
        observation.theoreticalBalanceSnapshot == null
            ? AccountsWords.of(context).format('accounts.legacy_case_title', {
                'date': _formatObservationDate(observation.observedAt),
              })
            : '${_formatObservationDate(observation.observedAt)} — ${item.status}',
      ),
      subtitle: Text(
        AccountsWords.of(context).format('accounts.case_summary', {
          'actual': _frenchMoney(observation.actualBalance),
          'remaining': remainder == null
              ? AccountsWords.of(context).text('accounts.legacy_reconfirm')
              : _frenchMoney(remainder),
          'reason': observation.reason,
        }),
      ),
      isThreeLine: true,
      trailing: observation.theoreticalBalanceSnapshot == null
          ? Text(
              AccountsWords.of(
                context,
              ).text('accounts.new_observation_required'),
            )
          : TextButton(
              onPressed: () => _detail(context, ref),
              child: Text(AccountsWords.of(context).text('accounts.details')),
            ),
    );
  }

  Future<void> _detail(BuildContext context, WidgetRef ref) => showDialog<void>(
    context: context,
    builder: (_) => _ReconciliationDetailDialog(account: account, item: item),
  );
}

class _ReconciliationDetailDialog extends ConsumerStatefulWidget {
  const _ReconciliationDetailDialog({
    required this.account,
    required this.item,
  });
  final FinancialAccount account;
  final AccountReconciliationCase item;
  @override
  ConsumerState<_ReconciliationDetailDialog> createState() =>
      _ReconciliationDetailDialogState();
}

class _ReconciliationDetailDialogState
    extends ConsumerState<_ReconciliationDetailDialog> {
  final _comment = TextEditingController();
  var _temporary = false;
  var _saving = false;
  late final String _key;
  @override
  void initState() {
    super.initState();
    _key =
        '${DateTime.now().microsecondsSinceEpoch}-${widget.item.observation.id}';
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final i = widget.item;
    final o = i.observation;
    final remaining = i.remainingDifference ?? o.differenceSnapshot!;
    final hasTemporary = i.resolutions.any((item) => item.kind == 'temporary');
    return AlertDialog(
      title: Text(
        AccountsWords.of(context).text('accounts.observation_details'),
      ),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                AccountsWords.of(context).format('accounts.actual_balance', {
                  'amount': _frenchMoney(o.actualBalance),
                }),
              ),
              Text(
                AccountsWords.of(context).format(
                  'accounts.frozen_theoretical',
                  {'amount': _frenchMoney(o.theoreticalBalanceSnapshot!)},
                ),
              ),
              Text(
                AccountsWords.of(context).format(
                  'accounts.initial_difference',
                  {'amount': _frenchMoney(o.differenceSnapshot!)},
                ),
              ),
              Text(
                AccountsWords.of(context).format('accounts.remaining', {
                  'amount': _frenchMoney(
                    i.remainingDifference ?? o.differenceSnapshot!,
                  ),
                }),
              ),
              Text(
                AccountsWords.of(
                  context,
                ).format('accounts.author', {'name': o.actorName}),
              ),
              Text(
                AccountsWords.of(
                  context,
                ).format('accounts.observation_reason', {'reason': o.reason}),
              ),
              const SizedBox(height: AppSpacing.sm),
              ...i.resolutions.map(
                (r) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(_resolutionLabel(context, r.kind)),
                  subtitle: Text(
                    // i18n-dynamic-only: user comment, actor and formatted date
                    '${r.comment}\n${r.actorName} • ${_formatObservationDate(r.createdAt)}',
                  ),
                  trailing:
                      r.kind == 'regularization' && r.financialEventId != null
                      ? TextButton(
                          onPressed: _saving
                              ? null
                              : () => _reverseRegularization(r),
                          child: Text(
                            AccountsWords.of(context).text('accounts.reverse'),
                          ),
                        )
                      : r.effectiveAmount.minorUnits == 0
                      ? null
                      : Text(_frenchMoney(r.effectiveAmount)),
                ),
              ),
              const Divider(),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  AccountsWords.of(
                    context,
                  ).text('accounts.temporary_difference'),
                ),
                value: _temporary,
                onChanged: _saving
                    ? null
                    : (v) => setState(() => _temporary = v),
              ),
              TextField(
                controller: _comment,
                maxLength: 280,
                decoration: InputDecoration(
                  labelText: AccountsWords.of(
                    context,
                  ).text('accounts.documentary_explanation'),
                  hintText: AccountsWords.of(
                    context,
                  ).text('accounts.documentary_hint'),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(AccountsWords.of(context).text('accounts.close')),
        ),
        if (remaining.minorUnits != 0)
          TextButton(
            onPressed: _saving ? null : _regularize,
            child: Text(
              AccountsWords.of(context).text('accounts.regularize_explicitly'),
            ),
          ),
        if (remaining.minorUnits != 0)
          TextButton(
            onPressed: _saving ? null : _attachFinancialEvent,
            child: Text(
              AccountsWords.of(
                context,
              ).text('accounts.link_existing_operation'),
            ),
          ),
        if (remaining.minorUnits != 0)
          TextButton(
            onPressed: _saving ? null : _recordMissingOperation,
            child: Text(
              AccountsWords.of(
                context,
              ).text('accounts.record_missing_operation'),
            ),
          ),
        if (remaining.minorUnits != 0 && hasTemporary)
          TextButton(
            onPressed: _saving ? null : _attachFollowUp,
            child: Text(
              AccountsWords.of(
                context,
              ).text('accounts.link_followup_observation'),
            ),
          ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(
            AccountsWords.of(
              context,
            ).text(_saving ? 'accounts.saving' : 'accounts.save_explanation'),
          ),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (_comment.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      await ref.read(addAccountReconciliationExplanationProvider)(
        accountId: widget.account.id,
        observationId: widget.item.observation.id,
        kind: _temporary ? 'temporary' : 'documentary',
        comment: _comment.text,
        idempotencyKey: _key,
      );
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _attachFinancialEvent() async {
    final eventId = await showDialog<String>(
      context: context,
      builder: (_) => _SelectAccountEventDialog(account: widget.account),
    );
    if (eventId == null || !mounted) return;
    setState(() => _saving = true);
    try {
      await ref.read(linkAccountReconciliationFinancialEventProvider)(
        accountId: widget.account.id,
        observationId: widget.item.observation.id,
        financialEventId: eventId,
        comment: 'Opération canonique rattachée depuis le rapprochement',
        idempotencyKey: '$_key-event-$eventId',
      );
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _regularize() async {
    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(
          AccountsWords.of(context).text('accounts.regularize_difference'),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              AccountsWords.of(
                context,
              ).format('accounts.regularization_amount', {
                'amount': _frenchMoney(
                  widget.item.remainingDifference ??
                      widget.item.observation.differenceSnapshot!,
                ),
              }),
            ),
            Text(
              AccountsWords.of(context).text('accounts.regularization_warning'),
            ),
            TextField(
              controller: reason,
              decoration: InputDecoration(
                labelText: AccountsWords.of(
                  context,
                ).text('accounts.detailed_reason'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(AccountsWords.of(context).text('accounts.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(AccountsWords.of(context).text('accounts.confirm')),
          ),
        ],
      ),
    );
    if (confirmed != true || reason.text.trim().isEmpty) return;
    final amount =
        widget.item.remainingDifference ??
        widget.item.observation.differenceSnapshot!;
    final envelopes = await ref.read(remoteEnvelopeBalancesProvider.future);
    if (!mounted) return;
    final allocation = await showDialog<EnvelopeAllocationResult>(
      context: context,
      builder: (_) => EnvelopeAllocationDialog(
        amountCents: amount.minorUnits.abs(),
        envelopes: envelopes,
        allowNoImpact: true,
      ),
    );
    if (allocation == null || !mounted) return;
    setState(() => _saving = true);
    try {
      await ref.read(regularizeAccountReconciliationProvider)(
        accountId: widget.account.id,
        observationId: widget.item.observation.id,
        amount: Money.fromMinorUnits(amount.minorUnits.abs()),
        reasonCode: 'unexplained',
        reason: reason.text,
        allocations: allocation.allocations,
        idempotencyKey: '$_key-regularization',
      );
      if (mounted) Navigator.pop(context);
    } finally {
      reason.dispose();
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _reverseRegularization(
    AccountReconciliationResolution resolution,
  ) async {
    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(
          AccountsWords.of(context).text('accounts.reverse_regularization'),
        ),
        content: TextField(
          controller: reason,
          decoration: InputDecoration(
            labelText: AccountsWords.of(
              context,
            ).text('accounts.required_reason'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(AccountsWords.of(context).text('accounts.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(AccountsWords.of(context).text('accounts.reverse')),
          ),
        ],
      ),
    );
    if (confirmed != true || reason.text.trim().isEmpty) {
      reason.dispose();
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(reverseAccountReconciliationRegularizationProvider)(
        accountId: widget.account.id,
        financialEventId: resolution.financialEventId!,
        reason: reason.text,
        idempotencyKey: '$_key-reversal-${resolution.id}',
      );
      if (mounted) Navigator.pop(context);
    } finally {
      reason.dispose();
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _attachFollowUp() async {
    final observationId = await showDialog<String>(
      context: context,
      builder: (_) =>
          _SelectFollowUpDialog(account: widget.account, current: widget.item),
    );
    if (observationId == null || !mounted) return;
    setState(() => _saving = true);
    try {
      await ref.read(resolveAccountReconciliationFollowUpProvider)(
        accountId: widget.account.id,
        observationId: widget.item.observation.id,
        followUpObservationId: observationId,
        comment: 'Constat de suivi confirmé explicitement',
        idempotencyKey: '$_key-follow-up-$observationId',
      );
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _recordMissingOperation() async {
    final destination = await showDialog<WidgetBuilder>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          AccountsWords.of(context).text('accounts.record_missing_operation'),
        ),
        content: Text(
          AccountsWords.of(context).text('accounts.canonical_flow_hint'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(
              context,
              (_) => const TransactionsPage(returnAfterCreate: true),
            ),
            child: Text(
              AccountsWords.of(
                context,
              ).text('accounts.expense_income_transfer'),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(
              context,
              (_) => const TransactionsPage(returnAfterCreate: true),
            ),
            child: Text(AccountsWords.of(context).text('accounts.debt')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(
              context,
              (_) => const ReceivablesPage(returnAfterCreate: true),
            ),
            child: Text(
              AccountsWords.of(
                context,
              ).text('accounts.receivable_or_repayment'),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AccountsWords.of(context).text('accounts.cancel')),
          ),
        ],
      ),
    );
    if (destination == null || !mounted) return;
    final created = await Navigator.of(
      context,
    ).push(MaterialPageRoute<bool>(builder: destination));
    if (!mounted) return;
    ref.invalidate(accountTransactionHistoryProvider(widget.account.id));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          AccountsWords.of(context).text('accounts.select_created_operation'),
        ),
      ),
    );
    if (created == true) {
      await _attachFinancialEvent();
    }
  }
}

class _SelectAccountEventDialog extends ConsumerWidget {
  const _SelectAccountEventDialog({required this.account});
  final FinancialAccount account;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(accountTransactionHistoryProvider(account.id));
    return AlertDialog(
      title: Text(
        AccountsWords.of(context).text('accounts.link_existing_operation'),
      ),
      content: SizedBox(
        width: 560,
        child: items.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) =>
              Text(AccountsWords.of(context).text('accounts.operations_error')),
          data: (list) =>
              list.where((item) => item.financialEventId != null).isEmpty
              ? Text(
                  AccountsWords.of(
                    context,
                  ).text('accounts.no_canonical_operation'),
                )
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final item in list.where(
                      (item) => item.financialEventId != null,
                    ))
                      ListTile(
                        title: Text(item.description),
                        subtitle: Text(_formatObservationDate(item.occurredAt)),
                        trailing: Text(_frenchMoney(item.amount)),
                        onTap: () =>
                            Navigator.pop(context, item.financialEventId),
                      ),
                  ],
                ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(AccountsWords.of(context).text('accounts.cancel')),
        ),
      ],
    );
  }
}

class _SelectFollowUpDialog extends ConsumerWidget {
  const _SelectFollowUpDialog({required this.account, required this.current});
  final FinancialAccount account;
  final AccountReconciliationCase current;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(accountReconciliationHistoryProvider(account.id));
    return AlertDialog(
      title: Text(
        AccountsWords.of(context).text('accounts.link_followup_observation'),
      ),
      content: SizedBox(
        width: 560,
        child: history.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Text(
            AccountsWords.of(context).text('accounts.observations_error'),
          ),
          data: (cases) {
            final compatible = cases
                .where(
                  (item) =>
                      item.observation.id != current.observation.id &&
                      item.observation.observedAt.isAfter(
                        current.observation.observedAt,
                      ) &&
                      item.observation.differenceSnapshot?.minorUnits == 0,
                )
                .toList();
            return compatible.isEmpty
                ? Text(
                    AccountsWords.of(
                      context,
                    ).text('accounts.no_later_observation'),
                  )
                : ListView(
                    shrinkWrap: true,
                    children: [
                      for (final item in compatible)
                        ListTile(
                          title: Text(
                            _formatObservationDate(item.observation.observedAt),
                          ),
                          subtitle: Text(
                            AccountsWords.of(
                              context,
                            ).format('accounts.actual_short', {
                              'amount': _frenchMoney(
                                item.observation.actualBalance,
                              ),
                            }),
                          ),
                          onTap: () =>
                              Navigator.pop(context, item.observation.id),
                        ),
                    ],
                  );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(AccountsWords.of(context).text('accounts.cancel')),
        ),
      ],
    );
  }
}

String _resolutionLabel(BuildContext context, String kind) => switch (kind) {
  'documentary' => AccountsWords.of(
    context,
  ).text('accounts.documentary_explanation'),
  'temporary' => AccountsWords.of(
    context,
  ).text('accounts.resolution.temporary'),
  'financial_event' => AccountsWords.of(
    context,
  ).text('accounts.resolution.event'),
  'follow_up' => AccountsWords.of(
    context,
  ).text('accounts.link_followup_observation'),
  'reversal' => AccountsWords.of(context).text('accounts.resolution.reversal'),
  _ => AccountsWords.of(context).text('accounts.resolution.default'),
};

class _RecordAccountBalanceDialog extends StatefulWidget {
  const _RecordAccountBalanceDialog({
    required this.account,
    required this.theoreticalBalance,
    required this.onRecord,
  });

  final FinancialAccount account;
  final Money theoreticalBalance;
  final Future<void> Function({
    required DateTime observedAt,
    required Money actualBalance,
    required String reason,
    required CashCountInputMode inputMode,
    required List<Map<String, Object?>> denominationDetail,
    required String idempotencyKey,
  })
  onRecord;

  @override
  State<_RecordAccountBalanceDialog> createState() =>
      _RecordAccountBalanceDialogState();
}

class _RecordAccountBalanceDialogState
    extends State<_RecordAccountBalanceDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _actualBalance;
  final _reason = TextEditingController();
  var _observedAt = DateTime.now();
  var _submitting = false;
  String? _error;
  var _inputMode = CashCountInputMode.direct;
  late final Map<int, TextEditingController> _quantities;
  late final String _idempotencyKey;

  @override
  void initState() {
    super.initState();
    _actualBalance = TextEditingController(
      text: widget.account.type == FinancialAccountType.cash
          ? ''
          : widget.theoreticalBalance.dirhams.toStringAsFixed(2),
    )..addListener(_refreshDifference);
    _quantities = {
      for (final item in cashDenominationsByCurrency['MAD']!)
        item.valueMinor: TextEditingController()..addListener(_refreshCount),
    };
    _idempotencyKey = _newCashInventoryIdempotencyKey();
  }

  void _refreshCount() {
    if (_inputMode != CashCountInputMode.denominations) return;
    _actualBalance.text = _cashCountsTotal.dirhams.toStringAsFixed(2);
  }

  void _refreshDifference() => setState(() {});

  @override
  void dispose() {
    _actualBalance.removeListener(_refreshDifference);
    _actualBalance.dispose();
    _reason.dispose();
    for (final controller in _quantities.values) {
      controller.removeListener(_refreshCount);
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _observedAt,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_observedAt),
    );
    if (time == null || !mounted) return;
    setState(() {
      _observedAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _submit() async {
    if (_submitting || !_formKey.currentState!.validate()) return;
    final cents = _madToCents(_actualBalance.text.trim());
    if (cents == null) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.onRecord(
        observedAt: _observedAt,
        actualBalance: Money.fromMinorUnits(cents),
        reason: _reason.text.trim(),
        inputMode: _inputMode,
        denominationDetail: cashCountPayload(_cashCounts),
        idempotencyKey: _idempotencyKey,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) setState(() => _error = 'Constat impossible : $error');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      AccountsWords.of(context).text(
        widget.account.type == FinancialAccountType.cash
            ? 'accounts.count_cash'
            : 'accounts.observe_bank',
      ),
    ),
    content: SizedBox(
      width: 440,
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AccountsWords.of(context).format(
                  'accounts.theoretical_balance',
                  {'amount': _frenchMoney(widget.theoreticalBalance)},
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              if (widget.account.type == FinancialAccountType.cash) ...[
                SegmentedButton<CashCountInputMode>(
                  key: const Key('cash-inventory-mode'),
                  segments: [
                    ButtonSegment(
                      value: CashCountInputMode.direct,
                      label: Text(
                        AccountsWords.of(
                          context,
                        ).text('accounts.direct_amount'),
                      ),
                    ),
                    ButtonSegment(
                      value: CashCountInputMode.denominations,
                      label: Text(
                        AccountsWords.of(
                          context,
                        ).text('accounts.count_denominations'),
                      ),
                    ),
                  ],
                  selected: {_inputMode},
                  onSelectionChanged: _submitting
                      ? null
                      : (selection) => setState(() {
                          _inputMode = selection.single;
                          if (_inputMode == CashCountInputMode.denominations) {
                            _refreshCount();
                          }
                        }),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              if (_inputMode == CashCountInputMode.denominations) ...[
                for (final item in cashDenominationsByCurrency['MAD']!)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            // i18n-dynamic-only: localized denomination plus dynamic label
                            '${AccountsWords.of(context).text(item.kind == CashDenominationKind.banknote ? 'accounts.denomination.banknote' : 'accounts.denomination.coin')} ${item.label}',
                          ),
                        ),
                        SizedBox(
                          width: 100,
                          child: TextFormField(
                            key: Key('cash-denomination-${item.valueMinor}'),
                            controller: _quantities[item.valueMinor],
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: AccountsWords.of(
                                context,
                              ).text('accounts.quantity'),
                            ),
                            validator: (value) {
                              if ((value ?? '').trim().isEmpty) return null;
                              final quantity = int.tryParse(value!.trim());
                              return quantity == null || quantity < 0
                                  ? 'Entier ≥ 0'
                                  : null;
                            },
                          ),
                        ),
                        SizedBox(
                          width: 110,
                          child: Text(
                            _frenchMoney(
                              Money.fromMinorUnits(
                                item.valueMinor *
                                    (_quantity(item.valueMinor) ?? 0),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                Text(
                  AccountsWords.of(context).format(
                    'accounts.denominations_total',
                    {'amount': _frenchMoney(_cashCountsTotal)},
                  ),
                  key: const Key('cash-denomination-total'),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              TextFormField(
                key: const Key('actual-account-balance-field'),
                controller: _actualBalance,
                readOnly: _inputMode == CashCountInputMode.denominations,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                decoration: InputDecoration(
                  labelText: widget.account.type == FinancialAccountType.cash
                      ? AccountsWords.of(
                          context,
                        ).text('accounts.cash_amount_required')
                      : AccountsWords.of(
                          context,
                        ).text('accounts.bank_amount_required'),
                ),
                validator: (value) => _madToCents(value?.trim() ?? '') == null
                    ? 'Saisissez un montant MAD valide.'
                    : null,
              ),
              if (_madToCents(_actualBalance.text.trim())
                  case final cents?) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  AccountsWords.of(context).format('accounts.counted_amount', {
                    'amount': _frenchMoney(Money.fromMinorUnits(cents)),
                  }),
                ),
                Text(
                  AccountsWords.of(context).format('accounts.difference', {
                    'amount': _frenchMoney(
                      Money.fromMinorUnits(cents) - widget.theoreticalBalance,
                    ),
                  }),
                ),
                Text(
                  cents == widget.theoreticalBalance.minorUnits
                      ? AccountsWords.of(
                          context,
                        ).text('accounts.status.reliable')
                      : AccountsWords.of(
                          context,
                        ).text('accounts.status.to_process'),
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton.icon(
                onPressed: _submitting ? null : _pickDateTime,
                icon: const Icon(Icons.schedule_outlined),
                label: Text(
                  AccountsWords.of(context).format('accounts.date_time', {
                    'date': _formatObservationDate(_observedAt),
                  }),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                key: const Key('account-balance-observation-reason-field'),
                controller: _reason,
                maxLength: 280,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: _requiresReason
                      ? 'Commentaire / justification *'
                      : 'Commentaire / justification (facultatif)',
                ),
                validator: (value) {
                  final reason = value?.trim() ?? '';
                  if (_requiresReason && reason.isEmpty) {
                    return AccountsWords.of(
                      context,
                    ).text('accounts.comment_required');
                  }
                  if (reason.length > 280) {
                    return AccountsWords.of(
                      context,
                    ).text('accounts.comment_max');
                  }
                  return null;
                },
              ),
              Text(
                AccountsWords.of(
                  context,
                ).text('accounts.observation_no_posting'),
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
        onPressed: _submitting ? null : () => Navigator.of(context).pop(),
        child: Text(AccountsWords.of(context).text('accounts.cancel')),
      ),
      FilledButton(
        key: const Key('record-account-balance-observation-submit-button'),
        onPressed: _submitting ? null : _submit,
        child: Text(
          AccountsWords.of(
            context,
          ).text(_submitting ? 'accounts.saving' : 'accounts.save_observation'),
        ),
      ),
    ],
  );

  bool get _requiresReason {
    final cents = _madToCents(_actualBalance.text.trim());
    return cents != null && cents != widget.theoreticalBalance.minorUnits;
  }

  int? _quantity(int valueMinor) {
    final value = _quantities[valueMinor]?.text.trim() ?? '';
    return value.isEmpty ? 0 : int.tryParse(value);
  }

  List<CashDenominationCount> get _cashCounts => [
    for (final item in cashDenominationsByCurrency['MAD']!)
      if ((_quantity(item.valueMinor) ?? -1) >= 0)
        CashDenominationCount(
          denomination: item,
          quantity: _quantity(item.valueMinor)!,
        ),
  ];

  Money get _cashCountsTotal => totalCashCount(_cashCounts);
}

String _frenchMoney(Money amount) =>
    '${amount.dirhams.toStringAsFixed(2).replaceAll('.', ',')} MAD';

String _formatObservationDate(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year} • ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

String _newCashInventoryIdempotencyKey() {
  final random = Random.secure();
  final values = List<int>.generate(16, (_) => random.nextInt(256));
  values[6] = (values[6] & 0x0f) | 0x40;
  values[8] = (values[8] & 0x3f) | 0x80;
  String group(int start, int end) => values
      .sublist(start, end)
      .map((value) => value.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${group(0, 4)}-${group(4, 6)}-${group(6, 8)}-${group(8, 10)}-${group(10, 16)}';
}

String _accountHistoryLabel(BuildContext context, Object type) =>
    switch (type.toString()) {
      'LedgerTransactionType.expense' => AccountsWords.of(
        context,
      ).text('accounts.history.expense'),
      'LedgerTransactionType.debtSettlement' => AccountsWords.of(
        context,
      ).text('accounts.history.debt_payment'),
      'LedgerTransactionType.accountTransfer' => AccountsWords.of(
        context,
      ).text('accounts.history.bank_transfer'),
      _ => AccountsWords.of(context).text('accounts.history.operation'),
    };

String _accountTypeLabel(BuildContext context, FinancialAccountType type) =>
    switch (type) {
      FinancialAccountType.bank => AccountsWords.of(
        context,
      ).text('accounts.type.bank'),
      FinancialAccountType.cash => AccountsWords.of(
        context,
      ).text('accounts.type.cash'),
      FinancialAccountType.savings => AccountsWords.of(
        context,
      ).text('accounts.type.savings'),
      FinancialAccountType.debt => AccountsWords.of(
        context,
      ).text('accounts.type.loan'),
    };

String _holdersLabel(
  BuildContext context,
  FinancialAccount account,
  List<HouseholdMember> householdMembers,
) {
  final namesByUserId = {
    for (final member in householdMembers) member.id: member.displayName,
  };
  final holderNames = account.holders
      .map(
        (holder) =>
            namesByUserId[holder.userId] ??
            _fallbackHolderLabel(context, holder),
      )
      .toList(growable: false);
  return holderNames.isEmpty
      ? AccountsWords.of(context).text('accounts.no_linked_holder')
      : holderNames.join(' & ');
}

String _fallbackHolderLabel(BuildContext context, AccountHolder holder) {
  final name = holder.displayName.trim();
  return name.isEmpty || name == 'Membre du foyer'
      ? AccountsWords.of(context).text('accounts.household_member')
      : name;
}

class _CreateAccountDialog extends StatefulWidget {
  const _CreateAccountDialog({
    required this.existingAccounts,
    required this.members,
    required this.membersLoading,
    required this.membersError,
    required this.onCreate,
  });

  final List<FinancialAccount> existingAccounts;
  final List<HouseholdMember> members;
  final bool membersLoading;
  final bool membersError;
  final Future<void> Function(CreateRemoteAccountRequest request) onCreate;

  @override
  State<_CreateAccountDialog> createState() => _CreateAccountDialogState();
}

class _CreateAccountDialogState extends State<_CreateAccountDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  FinancialAccountType? _type;
  var _ownershipType = AccountOwnershipType.household;
  final _holderUserIds = <String>{};
  var _archived = false;
  var _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selectAllHouseholdMembers();
  }

  void _selectAllHouseholdMembers() {
    _holderUserIds
      ..clear()
      ..addAll(widget.members.map((member) => member.id));
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || !_formKey.currentState!.validate() || _type == null) {
      if (_type == null) {
        setState(() => _error = 'Choisissez un type de compte.');
      }
      return;
    }
    if (_ownershipType == AccountOwnershipType.individual &&
        _holderUserIds.length != 1) {
      setState(
        () => _error = AccountsWords.of(
          context,
        ).text('accounts.holder.exactly_one'),
      );
      return;
    }
    if (_ownershipType == AccountOwnershipType.shared &&
        _holderUserIds.length < 2) {
      setState(
        () => _error = AccountsWords.of(
          context,
        ).text('accounts.holder.at_least_two'),
      );
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.onCreate(
        CreateRemoteAccountRequest(
          name: _nameController.text.trim(),
          type: _type!,
          openingBalanceCents: 0,
          archived: _archived,
          ownershipType: _ownershipType,
          holderUserIds: List.unmodifiable(_holderUserIds),
        ),
      );
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = AccountsWords.of(
            context,
          ).format('accounts.creation_error', {'error': error}),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(AccountsWords.of(context).text('accounts.add_title')),
    content: SizedBox(
      width: 420,
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const Key('account-name-field'),
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: AccountsWords.of(
                    context,
                  ).text('accounts.name_required'),
                ),
                validator: (value) {
                  final name = value?.trim() ?? '';
                  if (name.isEmpty) {
                    return AccountsWords.of(
                      context,
                    ).text('accounts.name_empty');
                  }
                  if (widget.existingAccounts.any(
                    (account) =>
                        account.name.trim().toLowerCase() == name.toLowerCase(),
                  )) {
                    return AccountsWords.of(
                      context,
                    ).text('accounts.duplicate_name');
                  }
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<FinancialAccountType>(
                key: const Key('account-type-field'),
                decoration: InputDecoration(
                  labelText: AccountsWords.of(
                    context,
                  ).text('accounts.type_required'),
                ),
                items: [
                  DropdownMenuItem(
                    value: FinancialAccountType.bank,
                    child: Text(
                      AccountsWords.of(context).text('accounts.type.bank'),
                    ),
                  ),
                  DropdownMenuItem(
                    value: FinancialAccountType.cash,
                    child: Text(
                      AccountsWords.of(context).text('accounts.type.cash'),
                    ),
                  ),
                  DropdownMenuItem(
                    value: FinancialAccountType.savings,
                    child: Text(
                      AccountsWords.of(context).text('accounts.type.savings'),
                    ),
                  ),
                  DropdownMenuItem(
                    value: FinancialAccountType.debt,
                    child: Text(
                      AccountsWords.of(context).text('accounts.type.loan'),
                    ),
                  ),
                ],
                onChanged: _submitting
                    ? null
                    : (value) => setState(() => _type = value),
              ),
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<AccountOwnershipType>(
                key: const Key('account-ownership-field'),
                initialValue: _ownershipType,
                decoration: InputDecoration(
                  labelText: AccountsWords.of(
                    context,
                  ).text('accounts.ownership_required'),
                ),
                items: [
                  DropdownMenuItem(
                    value: AccountOwnershipType.household,
                    child: Text(
                      AccountsWords.of(
                        context,
                      ).text('accounts.ownership.household'),
                    ),
                  ),
                  DropdownMenuItem(
                    value: AccountOwnershipType.individual,
                    child: Text(
                      AccountsWords.of(
                        context,
                      ).text('accounts.ownership.individual'),
                    ),
                  ),
                  DropdownMenuItem(
                    value: AccountOwnershipType.shared,
                    child: Text(
                      AccountsWords.of(
                        context,
                      ).text('accounts.ownership.shared'),
                    ),
                  ),
                ],
                onChanged: _submitting
                    ? null
                    : (value) => setState(() {
                        _ownershipType = value!;
                        if (_ownershipType == AccountOwnershipType.household) {
                          _selectAllHouseholdMembers();
                        } else {
                          _holderUserIds.clear();
                        }
                      }),
              ),
              const SizedBox(height: AppSpacing.sm),
              if (widget.membersLoading)
                Text(AccountsWords.of(context).text('accounts.members_loading'))
              else if (widget.membersError)
                Text(AccountsWords.of(context).text('accounts.members_error'))
              else if (widget.members.isEmpty)
                Text(AccountsWords.of(context).text('accounts.members_empty'))
              else
                ...widget.members.map(
                  (member) => CheckboxListTile(
                    key: Key('account-holder-${member.id}'),
                    value: _holderUserIds.contains(member.id),
                    title: Text(member.displayName),
                    controlAffinity: ListTileControlAffinity.leading,
                    onChanged: _submitting
                        ? null
                        : (selected) => setState(() {
                            if (selected == true) {
                              if (_ownershipType ==
                                  AccountOwnershipType.individual) {
                                _holderUserIds
                                  ..clear()
                                  ..add(member.id);
                              } else {
                                _holderUserIds.add(member.id);
                              }
                            } else {
                              _holderUserIds.remove(member.id);
                            }
                          }),
                  ),
                ),
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<bool>(
                key: const Key('account-status-field'),
                initialValue: false,
                decoration: InputDecoration(
                  labelText: AccountsWords.of(context).text('accounts.status'),
                ),
                items: [
                  DropdownMenuItem(
                    value: false,
                    child: Text(
                      AccountsWords.of(context).text('accounts.active'),
                    ),
                  ),
                  DropdownMenuItem(
                    value: true,
                    child: Text(
                      AccountsWords.of(context).text('accounts.archived'),
                    ),
                  ),
                ],
                onChanged: _submitting
                    ? null
                    : (value) => setState(() => _archived = value!),
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
        onPressed: _submitting ? null : () => Navigator.of(context).pop(),
        child: Text(AccountsWords.of(context).text('accounts.cancel')),
      ),
      FilledButton(
        key: const Key('create-remote-account-button'),
        onPressed: _submitting ? null : _submit,
        child: Text(
          AccountsWords.of(
            context,
          ).text(_submitting ? 'accounts.creating' : 'accounts.create'),
        ),
      ),
    ],
  );
}

int? _madToCents(String value) {
  if (!RegExp(r'^-?\d+(?:[.,]\d{1,2})?$').hasMatch(value)) return null;
  final normalized = value.replaceAll(',', '.');
  final negative = normalized.startsWith('-');
  final parts = (negative ? normalized.substring(1) : normalized).split('.');
  final whole = int.tryParse(parts.first);
  if (whole == null) return null;
  final fraction = parts.length == 1
      ? 0
      : int.parse(parts.last.padRight(2, '0'));
  final cents = whole * 100 + fraction;
  return negative ? -cents : cents;
}
