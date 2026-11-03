import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/money/money.dart';
import '../../../core/localization/transactions_locale.dart';
import '../../../core/theme/app_design_system.dart';
import '../../envelopes/application/providers/remote_envelopes_provider.dart';
import '../application/providers/remote_account_balances_provider.dart';
import '../application/providers/remote_accounts_provider.dart';
import '../application/providers/remote_transactions_provider.dart';
import '../application/providers/payment_methods_provider.dart';
import '../application/providers/financial_event_provider.dart';
import '../application/providers/financial_history_actions_provider.dart';
import '../application/providers/member_compensations_provider.dart';
import '../application/providers/remote_household_members_provider.dart';
import '../application/providers/remote_debts_provider.dart';
import '../application/financial_event_contract.dart';
import '../domain/financial_account.dart';
import '../domain/household_member.dart';
import '../domain/transaction_draft.dart';
import '../domain/transaction_history_item.dart';
import 'member_compensations_page.dart';
import 'widgets/transaction_quick_filters.dart';

class TransactionsPage extends ConsumerStatefulWidget {
  const TransactionsPage({
    super.key,
    this.returnAfterCreate = false,
    this.returnCreatedEventId = false,
    this.prefill,
    this.forceExpense = false,
    this.initialFinancialEventId,
  });

  final bool returnAfterCreate;
  final bool returnCreatedEventId;
  final TransactionFormPrefill? prefill;
  final bool forceExpense;
  final String? initialFinancialEventId;

  @override
  ConsumerState<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends ConsumerState<TransactionsPage> {
  var _creating = false;
  String _expenseIdempotencyKey = _newIdempotencyKey();
  String _cashIncomeIdempotencyKey = _newIdempotencyKey();
  String _accountTransferIdempotencyKey = _newIdempotencyKey();

  Future<void> _openCreateDialog(
    List<FinancialAccount> accounts,
    List<RemoteEnvelopeBalance> envelopes,
    List<PaymentMethod> paymentMethods,
  ) async {
    final created = await showDialog<String>(
      context: context,
      builder: (_) => _CreateTransactionDialog(
        accounts: accounts
            .where((account) => !account.isArchived && !account.isSystem)
            .toList(growable: false),
        envelopes: envelopes,
        paymentMethods: paymentMethods,
        onCreate: _create,
        onCreateDebt: _createDebt,
        prefill: widget.prefill,
        forceExpense: widget.forceExpense,
      ),
    );
    if (created != null && mounted) {
      ref.invalidate(remoteTransactionsProvider);
      ref.invalidate(remoteAccountBalancesProvider);
      ref.invalidate(remoteAccountsProvider);
      ref.invalidate(remoteEnvelopeBalancesProvider);
      ref.invalidate(remoteEnvelopeHistoryProvider);
      ref.invalidate(remoteEnvelopeMovementsProvider);
      ref.invalidate(remoteDebtBalancesProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            TransactionsWords.of(context).text('transactions.created_success'),
          ),
        ),
      );
      if (widget.returnAfterCreate) {
        Navigator.of(context).pop(widget.returnCreatedEventId ? created : true);
      }
    }
  }

  Future<String?> _create(FinancialTransactionDraft draft) async {
    if (_creating) {
      return null;
    }
    setState(() => _creating = true);
    try {
      if (draft.type == LedgerTransactionType.expense) {
        final repository = await ref.read(
          financialEventRepositoryProvider.future,
        );
        final eventId = await repository.createCashExpense(
          occurredAt: draft.occurredAt,
          description: draft.description,
          amount: draft.amount,
          sourceAccountId: draft.sourceAccountId!,
          actualPaymentMethodId: draft.actualPaymentMethodId,
          allocations: draft.envelopeAllocations
              .map(
                (allocation) => FinancialEventAllocation(
                  envelopeId: allocation.envelopeId,
                  amount: allocation.amount.dirhams,
                ),
              )
              .toList(growable: false),
          idempotencyKey: _expenseIdempotencyKey,
          notes: draft.notes,
        );
        _expenseIdempotencyKey = _newIdempotencyKey();
        return eventId;
      } else if (draft.type == LedgerTransactionType.income) {
        final repository = await ref.read(
          financialEventRepositoryProvider.future,
        );
        final eventId = await repository.createCashIncome(
          occurredAt: draft.occurredAt,
          description: draft.description,
          amount: draft.amount,
          destinationAccountId: draft.destinationAccountId!,
          allocations: draft.envelopeAllocations
              .map(
                (allocation) => FinancialEventAllocation(
                  envelopeId: allocation.envelopeId,
                  amount: allocation.amount.dirhams,
                ),
              )
              .toList(growable: false),
          idempotencyKey: _cashIncomeIdempotencyKey,
          notes: draft.notes,
        );
        _cashIncomeIdempotencyKey = _newIdempotencyKey();
        return eventId;
      } else if (draft.type == LedgerTransactionType.transfer) {
        final repository = await ref.read(
          financialEventRepositoryProvider.future,
        );
        final eventId = await repository.createAccountTransfer(
          occurredAt: draft.occurredAt,
          description: draft.description,
          amount: draft.amount,
          sourceAccountId: draft.sourceAccountId!,
          destinationAccountId: draft.destinationAccountId!,
          idempotencyKey: _accountTransferIdempotencyKey,
          notes: draft.notes,
        );
        _accountTransferIdempotencyKey = _newIdempotencyKey();
        return eventId;
      }
      throw StateError(
        'Ce type de transaction ne possède aucun flux canonique.',
      );
    } finally {
      if (mounted) {
        setState(() => _creating = false);
      }
    }
  }

  Future<String?> _createDebt(_DebtExpenseSubmission submission) async {
    if (_creating) return null;
    setState(() => _creating = true);
    try {
      final repository = await ref.read(
        financialEventRepositoryProvider.future,
      );
      final eventId = await repository.createDebtExpense(
        occurredAt: submission.occurredAt,
        description: submission.description,
        amount: submission.amount,
        allocations: submission.allocations,
        creditorName: submission.creditorName,
        notes: submission.notes,
        idempotencyKey: _expenseIdempotencyKey,
      );
      _expenseIdempotencyKey = _newIdempotencyKey();
      return eventId;
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final transactions = ref.watch(remoteTransactionsProvider);
    final accounts = ref.watch(remoteAccountsProvider);
    final envelopes = ref.watch(remoteEnvelopeBalancesProvider);
    final paymentMethods = ref.watch(paymentMethodsProvider);
    final canOpen = accounts.hasValue && envelopes.hasValue && !_creating;
    return Scaffold(
      appBar: AppBar(
        title: Text(TransactionsWords.of(context).text('transactions.title')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => const DebtsPage())),
            child: Text(
              TransactionsWords.of(context).text('transactions.debts'),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ReceivablesPage()),
            ),
            child: Text(
              TransactionsWords.of(context).text('transactions.receivables'),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('add-transaction-button'),
        onPressed: canOpen
            ? () => _openCreateDialog(
                accounts.requireValue,
                envelopes.requireValue,
                paymentMethods.valueOrNull ?? const [],
              )
            : null,
        icon: _creating
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add),
        label: Text(TransactionsWords.of(context).text('transactions.add')),
      ),
      body: transactions.when(
        loading: () => Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: AppSpacing.page,
            child: Text(
              TransactionsWords.of(
                context,
              ).format('transactions.load_error', {'error': error}),
            ),
          ),
        ),
        data: (items) => _TransactionList(
          items: items,
          initialFinancialEventId: widget.initialFinancialEventId,
        ),
      ),
    );
  }
}

class _TransactionList extends ConsumerStatefulWidget {
  const _TransactionList({required this.items, this.initialFinancialEventId});

  final List<TransactionHistoryItem> items;
  final String? initialFinancialEventId;

  @override
  ConsumerState<_TransactionList> createState() => _TransactionListState();
}

class _TransactionListState extends ConsumerState<_TransactionList> {
  final _query = TextEditingController();
  String? _accountId, _envelopeId, _methodId, _eventType, _reversalState;
  DateTime? _from, _to;
  var _page = 0;
  bool _filtering = false;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  TransactionHistoryFilter get _filter => TransactionHistoryFilter(
    query: _query.text.trim().isEmpty ? null : _query.text.trim(),
    from: _from,
    to: _to == null ? null : DateTime(_to!.year, _to!.month, _to!.day + 1),
    accountId: _accountId,
    envelopeId: _envelopeId,
    paymentMethodId: _methodId,
    eventType: _eventType,
    reversalState: _reversalState,
    page: _page,
  );

  @override
  Widget build(BuildContext context) {
    final filtered = _filtering
        ? ref.watch(filteredTransactionsProvider(_filter))
        : AsyncData(
            widget.initialFinancialEventId == null
                ? widget.items
                : widget.items
                      .where(
                        (item) =>
                            item.financialEventId ==
                            widget.initialFinancialEventId,
                      )
                      .toList(),
          );
    final accounts = ref.watch(remoteAccountsProvider).valueOrNull ?? const [];
    final envelopes =
        ref.watch(remoteEnvelopeBalancesProvider).valueOrNull ?? const [];
    final methods = ref.watch(paymentMethodsProvider).valueOrNull ?? const [];
    return ListView(
      padding: AppSpacing.page,
      children: [
        Text(
          TransactionsWords.of(context).text('transactions.ledger'),
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(TransactionsWords.of(context).text('transactions.ledger_hint')),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          key: const Key('transaction-search-field'),
          controller: _query,
          decoration: InputDecoration(
            labelText: TransactionsWords.of(
              context,
            ).text('transactions.search'),
            suffixIcon: IconButton(
              onPressed: () => setState(() {
                _filtering = true;
                _page = 0;
              }),
              icon: const Icon(Icons.search),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        TransactionQuickFilters(
          selected: _eventType,
          options: [
            TransactionQuickFilter(
              value: null,
              label: TransactionsWords.of(
                context,
              ).text('transactions.filter.all'),
            ),
            TransactionQuickFilter(
              value: 'cash_expense',
              label: TransactionsWords.of(
                context,
              ).text('transactions.type.expense'),
            ),
            TransactionQuickFilter(
              value: 'cash_income',
              label: TransactionsWords.of(
                context,
              ).text('transactions.type.income'),
            ),
            TransactionQuickFilter(
              value: 'account_transfer',
              label: TransactionsWords.of(
                context,
              ).text('transactions.type.account_transfer'),
            ),
          ],
          onChanged: (value) => setState(() {
            _eventType = value;
            _filtering = value != null;
            _page = 0;
          }),
        ),
        const SizedBox(height: AppSpacing.xs),
        ExpansionTile(
          key: const Key('transaction-advanced-filters'),
          tilePadding: EdgeInsets.zero,
          title: Text(
            TransactionsWords.of(context).text('transactions.advanced_filters'),
          ),
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _filterDropdown(
                  TransactionsWords.of(
                    context,
                  ).text('transactions.filter.account'),
                  _accountId,
                  [
                    for (final a in accounts)
                      DropdownMenuItem(value: a.id, child: Text(a.name)),
                  ],
                  (v) => setState(() {
                    _accountId = v;
                    _filtering = true;
                    _page = 0;
                  }),
                ),
                _filterDropdown(
                  TransactionsWords.of(
                    context,
                  ).text('transactions.filter.envelope'),
                  _envelopeId,
                  [
                    for (final e in envelopes)
                      DropdownMenuItem(value: e.id, child: Text(e.name)),
                  ],
                  (v) => setState(() {
                    _envelopeId = v;
                    _filtering = true;
                    _page = 0;
                  }),
                ),
                _filterDropdown(
                  TransactionsWords.of(
                    context,
                  ).text('transactions.filter.method'),
                  _methodId,
                  [
                    for (final m in methods)
                      DropdownMenuItem(value: m.id, child: Text(m.label)),
                  ],
                  (v) => setState(() {
                    _methodId = v;
                    _filtering = true;
                    _page = 0;
                  }),
                ),
                _filterDropdown(
                  TransactionsWords.of(
                    context,
                  ).text('transactions.filter.type'),
                  _eventType,
                  [
                    DropdownMenuItem(
                      value: 'cash_expense',
                      child: Text(
                        TransactionsWords.of(
                          context,
                        ).text('transactions.type.expense'),
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'cash_income',
                      child: Text(
                        TransactionsWords.of(
                          context,
                        ).text('transactions.type.income'),
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'account_transfer',
                      child: Text(
                        TransactionsWords.of(
                          context,
                        ).text('transactions.type.account_transfer'),
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'envelope_transfer',
                      child: Text(
                        TransactionsWords.of(
                          context,
                        ).text('transactions.type.envelope_transfer'),
                      ),
                    ),
                  ],
                  (v) => setState(() {
                    _eventType = v;
                    _filtering = true;
                    _page = 0;
                  }),
                ),
                _filterDropdown(
                  TransactionsWords.of(
                    context,
                  ).text('transactions.filter.status'),
                  _reversalState,
                  [
                    DropdownMenuItem(
                      value: 'active',
                      child: Text(
                        TransactionsWords.of(
                          context,
                        ).text('transactions.status.active'),
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'reversed',
                      child: Text(
                        TransactionsWords.of(
                          context,
                        ).text('transactions.status.reversed'),
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'reversal',
                      child: Text(
                        TransactionsWords.of(
                          context,
                        ).text('transactions.status.reversals'),
                      ),
                    ),
                  ],
                  (v) => setState(() {
                    _reversalState = v;
                    _filtering = true;
                    _page = 0;
                  }),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _from ?? DateTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now(),
                    );
                    if (d != null) {
                      setState(() {
                        _from = d;
                        _filtering = true;
                      });
                    }
                  },
                  icon: const Icon(Icons.date_range),
                  label: Text(
                    _from == null
                        ? TransactionsWords.of(
                            context,
                          ).text('transactions.from')
                        : _formatDate(_from!),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _to ?? DateTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now(),
                    );
                    if (d != null) {
                      setState(() {
                        _to = d;
                        _filtering = true;
                      });
                    }
                  },
                  icon: const Icon(Icons.event),
                  label: Text(
                    _to == null
                        ? TransactionsWords.of(context).text('transactions.to')
                        : _formatDate(_to!),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() {
                    _query.clear();
                    _accountId = null;
                    _envelopeId = null;
                    _methodId = null;
                    _eventType = null;
                    _reversalState = null;
                    _from = null;
                    _to = null;
                    _page = 0;
                    _filtering = false;
                  }),
                  child: Text(
                    TransactionsWords.of(
                      context,
                    ).text('transactions.clear_filters'),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        ...filtered.when(
          loading: () => [Center(child: CircularProgressIndicator())],
          error: (e, _) => [
            Text(
              TransactionsWords.of(
                context,
              ).format('transactions.search_error', {'error': e}),
            ),
          ],
          data: (items) => [
            if (items.isEmpty)
              Card(
                child: ListTile(
                  leading: Icon(Icons.receipt_long_outlined),
                  title: Text(
                    TransactionsWords.of(context).text('transactions.empty'),
                  ),
                  subtitle: Text(
                    TransactionsWords.of(
                      context,
                    ).text('transactions.empty_hint'),
                  ),
                ),
              ),
            ...items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Card(
                  child: ListTile(
                    onTap: () => showDialog<void>(
                      context: context,
                      builder: (_) => _TransactionDetailDialog(item: item),
                    ),
                    leading: Icon(_iconFor(item.type)),
                    title: Text(item.description),
                    subtitle: Text(_historySubtitle(context, item)),
                    trailing: Text(
                      // i18n-dynamic-only
                      '${item.amount.dirhams.toStringAsFixed(2)} MAD',
                    ),
                  ),
                ),
              ),
            ),
            if (_filtering)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _page == 0
                        ? null
                        : () => setState(() => _page--),
                    child: Text(
                      TransactionsWords.of(
                        context,
                      ).text('transactions.previous'),
                    ),
                  ),
                  TextButton(
                    onPressed: items.length < 50
                        ? null
                        : () => setState(() => _page++),
                    child: Text(
                      TransactionsWords.of(context).text('transactions.next'),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }

  Widget _filterDropdown(
    String label,
    String? value,
    List<DropdownMenuItem<String>> items,
    ValueChanged<String?> changed,
  ) => SizedBox(
    width: 190,
    child: DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        DropdownMenuItem(
          value: null,
          child: Text(
            TransactionsWords.of(context).text('transactions.filter.all'),
          ),
        ),
        ...items,
      ],
      onChanged: changed,
    ),
  );
}

class _CreateTransactionDialog extends StatefulWidget {
  const _CreateTransactionDialog({
    required this.accounts,
    required this.envelopes,
    required this.paymentMethods,
    required this.onCreate,
    required this.onCreateDebt,
    this.prefill,
    this.forceExpense = false,
  });

  final List<FinancialAccount> accounts;
  final List<RemoteEnvelopeBalance> envelopes;
  final List<PaymentMethod> paymentMethods;
  final Future<String?> Function(FinancialTransactionDraft draft) onCreate;
  final Future<String?> Function(_DebtExpenseSubmission submission)
  onCreateDebt;
  final TransactionFormPrefill? prefill;
  final bool forceExpense;

  @override
  State<_CreateTransactionDialog> createState() =>
      _CreateTransactionDialogState();
}

class _CreateTransactionDialogState extends State<_CreateTransactionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _description = TextEditingController();
  final _amount = TextEditingController();
  final _creditor = TextEditingController();
  final _notes = TextEditingController();
  final List<_AllocationRow> _splitRows = [];
  LedgerTransactionType _type = LedgerTransactionType.expense;
  BalanceDirection _direction = BalanceDirection.increase;
  String? _sourceAccountId;
  String? _actualPaymentMethodId;
  String? _destinationAccountId;
  String? _singleEnvelopeId;
  var _splitExpense = false;
  var _expenseIsDebt = false;
  var _showAdvanced = false;
  var _submitting = false;
  String? _error;
  DateTime _economicDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    final prefill = widget.prefill;
    if (prefill != null) {
      _description.text = prefill.description;
      _amount.text = prefill.amount?.dirhams.toStringAsFixed(2) ?? '';
      _notes.text = prefill.notes ?? '';
      _singleEnvelopeId = prefill.envelopeId;
    }
  }

  @override
  void dispose() {
    _description.dispose();
    _amount.dispose();
    _creditor.dispose();
    _notes.dispose();
    for (final row in _splitRows) {
      row.dispose();
    }
    super.dispose();
  }

  bool get _isExpense => _type == LedgerTransactionType.expense;
  bool get _isIncome => _type == LedgerTransactionType.income;
  bool get _needsSource =>
      _type != LedgerTransactionType.income && !(_isExpense && _expenseIsDebt);
  bool get _needsDestination =>
      _type == LedgerTransactionType.income ||
      _type == LedgerTransactionType.transfer;
  bool get _needsDirection => _type == LedgerTransactionType.adjustment;
  int get _amountCents => _madToCents(_amount.text) ?? 0;
  int get _splitCents => _splitRows.fold(
    0,
    (sum, row) => sum + (_madToCents(row.amount.text) ?? 0),
  );
  int get _remainingCents => _amountCents - _splitCents;

  RemoteEnvelopeBalance? get _selectedEnvelope {
    final id = _singleEnvelopeId;
    if (id == null) return null;
    return widget.envelopes.where((item) => item.id == id).firstOrNull;
  }

  List<PaymentMethod> get _availablePaymentMethods => widget.paymentMethods
      .where(
        (method) =>
            method.active &&
            (method.accountId == null || method.accountId == _sourceAccountId),
      )
      .toList(growable: false);

  void _selectEnvelope(String? id) {
    setState(() {
      _singleEnvelopeId = id;
      final envelope = _selectedEnvelope;
      final recommendedAccount = envelope?.recommendedAccountId;
      if (recommendedAccount != null &&
          widget.accounts.any((account) => account.id == recommendedAccount)) {
        _sourceAccountId = recommendedAccount;
      }
      final recommendedMethod = envelope?.recommendedPaymentMethodId;
      if (recommendedMethod != null &&
          widget.paymentMethods.any(
            (method) => method.id == recommendedMethod && method.active,
          )) {
        final method = widget.paymentMethods.firstWhere(
          (item) => item.id == recommendedMethod,
        );
        if (method.accountId == null || method.accountId == _sourceAccountId) {
          _actualPaymentMethodId = recommendedMethod;
        }
      }
    });
  }

  Future<void> _pickEconomicDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _economicDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (selected != null && mounted) {
      setState(() => _economicDate = selected);
    }
  }

  List<EnvelopeAllocationDraft> _allocations() {
    if (_isIncome) {
      return _splitRows
          .map(
            (row) => EnvelopeAllocationDraft(
              envelopeId: row.envelopeId ?? '',
              amount: Money.fromMinorUnits(_madToCents(row.amount.text) ?? 0),
            ),
          )
          .toList(growable: false);
    }
    if (!_isExpense) {
      return const [];
    }
    if (!_splitExpense) {
      return _singleEnvelopeId == null
          ? const []
          : [
              EnvelopeAllocationDraft(
                envelopeId: _singleEnvelopeId!,
                amount: Money.fromMinorUnits(_amountCents),
              ),
            ];
    }
    return _splitRows
        .where((row) => row.envelopeId != null)
        .map(
          (row) => EnvelopeAllocationDraft(
            envelopeId: row.envelopeId!,
            amount: Money.fromMinorUnits(_madToCents(row.amount.text) ?? 0),
          ),
        )
        .toList(growable: false);
  }

  void _changeType(LedgerTransactionType type) {
    setState(() {
      _type = type;
      _error = null;
      _singleEnvelopeId = null;
      _splitExpense = false;
      for (final row in _splitRows) {
        row.dispose();
      }
      _splitRows.clear();
    });
  }

  void _addSplitRow() => setState(() => _splitRows.add(_AllocationRow()));

  void _removeSplitRow(_AllocationRow row) {
    setState(() {
      _splitRows.remove(row);
      row.dispose();
    });
  }

  Future<void> _submit() async {
    if (_submitting || !_formKey.currentState!.validate()) {
      return;
    }
    if (_amountCents <= 0) {
      setState(
        () => _error = TransactionsWords.of(
          context,
        ).text('transactions.positive_amount_error'),
      );
      return;
    }
    if (_isExpense && _splitExpense && _remainingCents != 0) {
      setState(
        () => _error = TransactionsWords.of(
          context,
        ).text('transactions.split_total_error'),
      );
      return;
    }
    if (_isIncome && _splitCents > _amountCents) {
      setState(
        () => _error = TransactionsWords.of(
          context,
        ).text('transactions.income_allocation_error'),
      );
      return;
    }
    if (_isExpense && _expenseIsDebt) {
      final allocations = _allocations()
          .map(
            (allocation) => FinancialEventAllocation(
              envelopeId: allocation.envelopeId,
              amount: allocation.amount.dirhams,
            ),
          )
          .toList(growable: false);
      try {
        FinancialEventContract.validateEnvelopeSplit(
          totalAmount: _amountCents / 100,
          allocations: allocations,
        );
      } on StateError catch (error) {
        setState(() => _error = error.message);
        return;
      }
      setState(() {
        _submitting = true;
        _error = null;
      });
      try {
        final eventId = await widget.onCreateDebt(
          _DebtExpenseSubmission(
            occurredAt: _economicDateAtNoon(_economicDate),
            description: _description.text.trim(),
            amount: Money.fromMinorUnits(_amountCents),
            allocations: allocations,
            creditorName: _creditor.text.trim(),
            notes: _notes.text.trim(),
          ),
        );
        if (mounted && eventId != null) Navigator.of(context).pop(eventId);
      } catch (error) {
        if (mounted) {
          setState(() => _error = _financialErrorMessage(context, error));
        }
      } finally {
        if (mounted) setState(() => _submitting = false);
      }
      return;
    }
    final draft = FinancialTransactionDraft(
      type: _type,
      occurredAt: _economicDateAtNoon(_economicDate),
      description: _description.text.trim(),
      amount: Money.fromMinorUnits(_amountCents),
      sourceAccountId: _needsSource ? _sourceAccountId : null,
      actualPaymentMethodId: _isExpense && !_expenseIsDebt
          ? _actualPaymentMethodId
          : null,
      destinationAccountId: _needsDestination ? _destinationAccountId : null,
      direction: _direction,
      envelopeAllocations: _allocations(),
      notes: _notes.text.trim(),
    );
    final validationError = draft.validate();
    if (validationError != null) {
      setState(() => _error = validationError);
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final eventId = await widget.onCreate(draft);
      if (mounted) {
        if (eventId != null) Navigator.of(context).pop(eventId);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = _financialErrorMessage(context, error));
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      TransactionsWords.of(context).text('transactions.create_title'),
    ),
    content: SizedBox(
      width: 480,
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          key: const Key('create-transaction-form-scroll'),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.forceExpense)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    TransactionsWords.of(
                      context,
                    ).text('transactions.expense_type'),
                  ),
                )
              else
                DropdownButtonFormField<LedgerTransactionType>(
                  key: const Key('transaction-type-field'),
                  isExpanded: true,
                  initialValue: _type,
                  decoration: InputDecoration(
                    labelText: TransactionsWords.of(
                      context,
                    ).text('transactions.type_required'),
                  ),
                  items:
                      const [
                            LedgerTransactionType.expense,
                            LedgerTransactionType.income,
                            LedgerTransactionType.transfer,
                          ]
                          .map(
                            (type) => DropdownMenuItem(
                              value: type,
                              child: Text(_labelFor(context, type)),
                            ),
                          )
                          .toList(growable: false),
                  onChanged: _submitting ? null : (type) => _changeType(type!),
                ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                key: const Key('transaction-description-field'),
                controller: _description,
                decoration: InputDecoration(
                  labelText: TransactionsWords.of(
                    context,
                  ).text('transactions.label_required'),
                ),
                validator: (value) => (value?.trim().isEmpty ?? true)
                    ? TransactionsWords.of(
                        context,
                      ).text('transactions.label_empty')
                    : null,
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                key: const Key('transaction-amount-field'),
                controller: _amount,
                onChanged: (_) => setState(() {}),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: TransactionsWords.of(
                    context,
                  ).text('transactions.amount_required'),
                ),
                validator: (value) => (_madToCents(value ?? '') ?? 0) <= 0
                    ? TransactionsWords.of(
                        context,
                      ).text('transactions.amount_invalid')
                    : null,
              ),
              if (_needsSource) ...[
                const SizedBox(height: AppSpacing.sm),
                _AccountSelector(
                  key: const Key('transaction-source-account-field'),
                  label: _type == LedgerTransactionType.transfer
                      ? TransactionsWords.of(
                          context,
                        ).text('transactions.source_account_required')
                      : TransactionsWords.of(
                          context,
                        ).text('transactions.account_required'),
                  accounts: widget.accounts,
                  value: _sourceAccountId,
                  onChanged: _submitting
                      ? null
                      : (id) => setState(() {
                          _sourceAccountId = id;
                          final selected = widget.paymentMethods
                              .where(
                                (method) => method.id == _actualPaymentMethodId,
                              )
                              .firstOrNull;
                          if (selected?.accountId != null &&
                              selected!.accountId != id) {
                            _actualPaymentMethodId = null;
                          }
                        }),
                ),
              ],
              if (_isExpense && !_expenseIsDebt && _needsSource) ...[
                const SizedBox(height: AppSpacing.sm),
                DropdownButtonFormField<String?>(
                  key: const Key('transaction-payment-method-field'),
                  initialValue: _actualPaymentMethodId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: TransactionsWords.of(
                      context,
                    ).text('transactions.payment_method_used'),
                  ),
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text(
                        TransactionsWords.of(
                          context,
                        ).text('transactions.unset'),
                      ),
                    ),
                    ..._availablePaymentMethods.map(
                      (method) => DropdownMenuItem<String?>(
                        value: method.id,
                        child: Text(
                          method.label,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                  onChanged: _submitting
                      ? null
                      : (value) =>
                            setState(() => _actualPaymentMethodId = value),
                ),
              ],
              if (_needsDestination) ...[
                const SizedBox(height: AppSpacing.sm),
                _AccountSelector(
                  key: const Key('transaction-destination-account-field'),
                  label: _type == LedgerTransactionType.transfer
                      ? 'Compte destination *'
                      : TransactionsWords.of(
                          context,
                        ).text('transactions.receiving_account_required'),
                  accounts: widget.accounts,
                  value: _destinationAccountId,
                  onChanged: _submitting
                      ? null
                      : (id) => setState(() => _destinationAccountId = id),
                ),
              ],
              if (_needsDirection) ...[
                const SizedBox(height: AppSpacing.sm),
                DropdownButtonFormField<BalanceDirection>(
                  initialValue: _direction,
                  decoration: InputDecoration(
                    labelText: TransactionsWords.of(
                      context,
                    ).text('transactions.direction_required'),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: BalanceDirection.increase,
                      child: Text(
                        TransactionsWords.of(
                          context,
                        ).text('transactions.increase_balance'),
                      ),
                    ),
                    DropdownMenuItem(
                      value: BalanceDirection.decrease,
                      child: Text(
                        TransactionsWords.of(
                          context,
                        ).text('transactions.decrease_balance'),
                      ),
                    ),
                  ],
                  onChanged: _submitting
                      ? null
                      : (value) => setState(() => _direction = value!),
                ),
              ],
              if (_isIncome) ...[
                const SizedBox(height: AppSpacing.md),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    TransactionsWords.of(
                      context,
                    ).text('transactions.income_split'),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                ..._splitRows.asMap().entries.map(
                  (entry) => _SplitAllocationInput(
                    key: Key('income-allocation-row-${entry.key}'),
                    row: entry.value,
                    envelopes: widget.envelopes,
                    amountFieldKey: Key('income-envelope-amount-${entry.key}'),
                    onChanged: () => setState(() {}),
                    onRemove: () => _removeSplitRow(entry.value),
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const Key('add-income-envelope-row'),
                    onPressed: _submitting ? null : _addSplitRow,
                    icon: const Icon(Icons.add),
                    label: Text(
                      TransactionsWords.of(
                        context,
                      ).text('transactions.add_envelope'),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    TransactionsWords.of(
                      context,
                    ).format('transactions.income_summary', {
                      'income': _formatCents(_amountCents),
                      'allocated': _formatCents(_splitCents),
                      'remaining': _formatCents(_remainingCents),
                    }),
                  ),
                ),
                if (_remainingCents > 0)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      TransactionsWords.of(context).format(
                        'transactions.auto_unallocated',
                        {'amount': _formatCents(_remainingCents)},
                      ),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                if (_splitCents > _amountCents)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      TransactionsWords.of(
                        context,
                      ).text('transactions.income_allocation_error'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
              if (_isExpense) ...[
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<bool>(
                  key: const Key('expense-payment-mode-field'),
                  isExpanded: true,
                  initialValue: _expenseIsDebt,
                  decoration: InputDecoration(
                    labelText: TransactionsWords.of(
                      context,
                    ).text('transactions.payment_required'),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: false,
                      child: Text(
                        TransactionsWords.of(
                          context,
                        ).text('transactions.paid_now'),
                      ),
                    ),
                    DropdownMenuItem(
                      value: true,
                      child: Text(
                        TransactionsWords.of(
                          context,
                        ).text('transactions.pay_later_debt'),
                      ),
                    ),
                  ],
                  onChanged: _submitting
                      ? null
                      : (value) =>
                            setState(() => _expenseIsDebt = value ?? false),
                ),
                if (_expenseIsDebt) ...[
                  const SizedBox(height: AppSpacing.sm),
                  TextFormField(
                    key: const Key('debt-creditor-field'),
                    controller: _creditor,
                    decoration: InputDecoration(
                      labelText: TransactionsWords.of(
                        context,
                      ).text('transactions.creditor'),
                    ),
                  ),
                ],
                SwitchListTile(
                  key: const Key('transaction-split-switch'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    TransactionsWords.of(
                      context,
                    ).text('transactions.split_envelopes'),
                  ),
                  value: _splitExpense,
                  onChanged: _submitting
                      ? null
                      : (value) => setState(() {
                          _splitExpense = value;
                          _singleEnvelopeId = null;
                          if (value && _splitRows.isEmpty) {
                            _splitRows.add(_AllocationRow());
                          }
                        }),
                ),
                if (!_splitExpense)
                  _EnvelopeSelector(
                    key: const Key('transaction-envelope-field'),
                    label: TransactionsWords.of(
                      context,
                    ).text('transactions.envelope_required'),
                    envelopes: widget.envelopes,
                    value: _singleEnvelopeId,
                    onChanged: _submitting ? null : _selectEnvelope,
                  )
                else ...[
                  ..._splitRows.map(
                    (row) => _SplitAllocationInput(
                      key: ValueKey(row),
                      row: row,
                      envelopes: widget.envelopes,
                      onChanged: () => setState(() {}),
                      onRemove: _splitRows.length == 1
                          ? null
                          : () => _removeSplitRow(row),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const Key('add-envelope-split-row'),
                      onPressed: _submitting ? null : _addSplitRow,
                      icon: const Icon(Icons.add),
                      label: Text(
                        TransactionsWords.of(
                          context,
                        ).text('transactions.add_envelope'),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      TransactionsWords.of(
                        context,
                      ).format('transactions.split_summary', {
                        'allocated': _formatCents(_splitCents),
                        'remaining': _formatCents(_remainingCents),
                      }),
                    ),
                  ),
                ],
                if (!_splitExpense && _selectedEnvelope != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _recommendationMessage(
                        context: context,
                        envelope: _selectedEnvelope!,
                        actualAccountId: _sourceAccountId,
                        actualPaymentMethodId: _actualPaymentMethodId,
                      ),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ],
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  key: const Key('transaction-more-options'),
                  onPressed: () =>
                      setState(() => _showAdvanced = !_showAdvanced),
                  icon: Icon(_showAdvanced ? Icons.expand_less : Icons.tune),
                  label: Text(
                    TransactionsWords.of(context).text(
                      _showAdvanced
                          ? 'transactions.fewer_options'
                          : 'transactions.more_options',
                    ),
                  ),
                ),
              ),
              if (_showAdvanced) ...[
                TextFormField(
                  key: const Key('transaction-notes-field'),
                  controller: _notes,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: TransactionsWords.of(
                      context,
                    ).text('transactions.notes'),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                ListTile(
                  key: const Key('transaction-economic-date-field'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    TransactionsWords.of(
                      context,
                    ).text('transactions.economic_date_required'),
                  ),
                  subtitle: Text(_formatDate(_economicDate)),
                  trailing: const Icon(Icons.calendar_today_outlined),
                  onTap: _submitting ? null : _pickEconomicDate,
                ),
              ],
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
        child: Text(TransactionsWords.of(context).text('transactions.cancel')),
      ),
      FilledButton(
        key: const Key('create-transaction-button'),
        onPressed:
            _submitting ||
                (_isExpense &&
                    ((!_splitExpense && _singleEnvelopeId == null) ||
                        (_splitExpense && _remainingCents != 0))) ||
                (_isIncome && _splitCents > _amountCents)
            ? null
            : _submit,
        child: Text(
          TransactionsWords.of(context).text(
            _submitting ? 'transactions.validating' : 'transactions.validate',
          ),
        ),
      ),
    ],
  );
}

class _AllocationRow {
  final amount = TextEditingController();
  String? envelopeId;

  void dispose() => amount.dispose();
}

class _SplitAllocationInput extends StatelessWidget {
  const _SplitAllocationInput({
    super.key,
    required this.row,
    required this.envelopes,
    this.amountFieldKey,
    this.excludedEnvelopeIds = const {},
    required this.onChanged,
    required this.onRemove,
  });

  final _AllocationRow row;
  final List<RemoteEnvelopeBalance> envelopes;
  final Key? amountFieldKey;
  final Set<String> excludedEnvelopeIds;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;

  static const _removeButtonWidth = 44.0;
  static const _horizontalLayoutMinimumWidth = 480.0;

  @override
  Widget build(BuildContext context) {
    final envelopeField = _EnvelopeSelector(
      label: TransactionsWords.of(
        context,
      ).text('transactions.envelope_required'),
      envelopes: envelopes
          .where(
            (envelope) =>
                !excludedEnvelopeIds.contains(envelope.id) ||
                envelope.id == row.envelopeId,
          )
          .toList(growable: false),
      value: row.envelopeId,
      onChanged: (id) {
        row.envelopeId = id;
        onChanged();
      },
    );
    final amountField = TextFormField(
      key: amountFieldKey,
      controller: row.amount,
      onChanged: (_) => onChanged(),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: TransactionsWords.of(
          context,
        ).text('transactions.mad_required'),
      ),
    );
    final removeButton = IconButton(
      onPressed: onRemove,
      constraints: const BoxConstraints.tightFor(
        width: _removeButtonWidth,
        height: 46,
      ),
      padding: EdgeInsets.zero,
      icon: const Icon(Icons.remove_circle_outline),
      tooltip: TransactionsWords.of(
        context,
      ).text('transactions.remove_envelope'),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // The dialog nominally requests 480 px, but AlertDialog can reduce
        // its content width after insets and window resizing. Below this
        // width the two input decorations and the 44 px action no longer
        // have enough room on one line.
        if (constraints.maxWidth < _horizontalLayoutMinimumWidth) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              envelopeField,
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  Expanded(child: amountField),
                  const SizedBox(width: AppSpacing.xs),
                  removeButton,
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
          );
        }
        return Row(
          children: [
            Expanded(flex: 3, child: envelopeField),
            const SizedBox(width: AppSpacing.xs),
            Expanded(flex: 2, child: amountField),
            const SizedBox(width: AppSpacing.xs),
            removeButton,
          ],
        );
      },
    );
  }
}

class _AccountSelector extends StatelessWidget {
  const _AccountSelector({
    super.key,
    required this.label,
    required this.accounts,
    required this.value,
    required this.onChanged,
    this.decoration,
  });
  final String label;
  final List<FinancialAccount> accounts;
  final String? value;
  final ValueChanged<String?>? onChanged;
  final InputDecoration? decoration;
  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    isExpanded: true,
    key: key,
    initialValue: value,
    decoration: decoration ?? InputDecoration(labelText: label),
    items: accounts
        .map(
          (account) =>
              DropdownMenuItem(value: account.id, child: Text(account.name)),
        )
        .toList(growable: false),
    onChanged: onChanged,
    validator: (value) => value == null ? 'Choisissez un compte.' : null,
  );
}

class _EnvelopeSelector extends StatelessWidget {
  const _EnvelopeSelector({
    Key? key,
    required this.label,
    required this.envelopes,
    required this.value,
    required this.onChanged,
  }) : _fieldKey = key;

  final Key? _fieldKey;
  final String label;
  final List<RemoteEnvelopeBalance> envelopes;
  final String? value;
  final ValueChanged<String?>? onChanged;
  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    key: _fieldKey,
    initialValue: value,
    decoration: InputDecoration(labelText: label),
    items: envelopes
        .where((envelope) => !envelope.isSystem)
        .map(
          (envelope) =>
              DropdownMenuItem(value: envelope.id, child: Text(envelope.name)),
        )
        .toList(growable: false),
    isExpanded: true,
    onChanged: onChanged,
    validator: (value) => value == null ? 'Choisissez une enveloppe.' : null,
  );
}

String _labelFor(BuildContext context, LedgerTransactionType type) =>
    switch (type) {
      LedgerTransactionType.expense => TransactionsWords.of(
        context,
      ).text('transactions.type.expense'),
      LedgerTransactionType.income => TransactionsWords.of(
        context,
      ).text('transactions.type.income'),
      LedgerTransactionType.transfer => TransactionsWords.of(
        context,
      ).text('transactions.type.transfer'),
      LedgerTransactionType.adjustment => TransactionsWords.of(
        context,
      ).text('transactions.type.adjustment'),
      LedgerTransactionType.openingBalance => TransactionsWords.of(
        context,
      ).text('transactions.type.opening'),
      LedgerTransactionType.correction => TransactionsWords.of(
        context,
      ).text('transactions.type.correction'),
      LedgerTransactionType.debtExpense => TransactionsWords.of(
        context,
      ).text('transactions.type.debt_expense'),
      LedgerTransactionType.incomeReceivable => TransactionsWords.of(
        context,
      ).text('transactions.type.income_receivable'),
      LedgerTransactionType.recovery ||
      LedgerTransactionType.recoveryReceivable => TransactionsWords.of(
        context,
      ).text('transactions.type.recovery'),
      LedgerTransactionType.debtSettlement => TransactionsWords.of(
        context,
      ).text('transactions.type.debt_settlement'),
      LedgerTransactionType.receivableSettlement => TransactionsWords.of(
        context,
      ).text('transactions.type.receivable_settlement'),
      LedgerTransactionType.recoverySettlement => TransactionsWords.of(
        context,
      ).text('transactions.type.recovery_settlement'),
      LedgerTransactionType.allocation => TransactionsWords.of(
        context,
      ).text('transactions.type.allocation'),
      LedgerTransactionType.accountTransfer => TransactionsWords.of(
        context,
      ).text('transactions.type.account_transfer'),
      LedgerTransactionType.envelopeTransfer => TransactionsWords.of(
        context,
      ).text('transactions.type.envelope_transfer'),
      LedgerTransactionType.unknown => TransactionsWords.of(
        context,
      ).text('transactions.type.unknown'),
    };
IconData _iconFor(LedgerTransactionType type) => switch (type) {
  LedgerTransactionType.expense => Icons.south_east,
  LedgerTransactionType.income => Icons.north_east,
  LedgerTransactionType.transfer => Icons.swap_horiz,
  LedgerTransactionType.adjustment => Icons.tune,
  LedgerTransactionType.openingBalance => Icons.flag_outlined,
  LedgerTransactionType.correction => Icons.history,
  LedgerTransactionType.debtExpense => Icons.receipt_long_outlined,
  LedgerTransactionType.incomeReceivable => Icons.schedule_outlined,
  LedgerTransactionType.recovery => Icons.replay_outlined,
  LedgerTransactionType.recoveryReceivable => Icons.replay_outlined,
  LedgerTransactionType.debtSettlement => Icons.payments_outlined,
  LedgerTransactionType.receivableSettlement =>
    Icons.account_balance_wallet_outlined,
  LedgerTransactionType.recoverySettlement => Icons.download_done_outlined,
  LedgerTransactionType.allocation => Icons.move_to_inbox_outlined,
  LedgerTransactionType.accountTransfer => Icons.swap_horiz,
  LedgerTransactionType.envelopeTransfer => Icons.swap_horiz,
  LedgerTransactionType.unknown => Icons.receipt_outlined,
};
String _formatLocalizedDate(BuildContext context, DateTime date) =>
    MaterialLocalizations.of(context).formatCompactDate(date);

String _formatDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

String _formatDateTime(DateTime date) =>
    '${_formatDate(date)} • ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
String _formatCents(int cents) => (cents / 100).toStringAsFixed(2);

DateTime _economicDateAtNoon(DateTime value) =>
    DateTime(value.year, value.month, value.day, 12);

String _recommendationMessage({
  required BuildContext context,
  required RemoteEnvelopeBalance envelope,
  required String? actualAccountId,
  required String? actualPaymentMethodId,
}) {
  final accountDifferent =
      envelope.recommendedAccountId != null &&
      envelope.recommendedAccountId != actualAccountId;
  final methodDifferent =
      envelope.recommendedPaymentMethodId != null &&
      envelope.recommendedPaymentMethodId != actualPaymentMethodId;
  if (!accountDifferent && !methodDifferent) {
    return TransactionsWords.of(
      context,
    ).text('transactions.recommendation.payment_match');
  }
  if (accountDifferent && methodDifferent) {
    return TransactionsWords.of(
      context,
    ).text('transactions.recommendation.account_method_mismatch');
  }
  return accountDifferent
      ? TransactionsWords.of(
          context,
        ).text('transactions.recommendation.account_mismatch')
      : TransactionsWords.of(
          context,
        ).text('transactions.recommendation.method_mismatch');
}

String _historySubtitle(BuildContext context, TransactionHistoryItem item) {
  final needsRegularization =
      (item.type == LedgerTransactionType.expense ||
          item.type == LedgerTransactionType.income) &&
      !item.hasEnvelopeMovement;
  return '${_labelFor(context, item.type)} • ${_formatLocalizedDate(context, item.occurredAt)}${needsRegularization ? ' • ${TransactionsWords.of(context).text('transactions.needs_regularization')}' : ''}';
}

int? _madToCents(String value) {
  final normalized = value.trim().replaceAll(',', '.');
  if (!RegExp(r'^\d+(?:\.\d{1,2})?$').hasMatch(normalized)) return null;
  final parts = normalized.split('.');
  final whole = int.tryParse(parts.first);
  if (whole == null) return null;
  return whole * 100 +
      (parts.length == 1 ? 0 : int.parse(parts.last.padRight(2, '0')));
}

class _TransactionDetailDialog extends ConsumerStatefulWidget {
  const _TransactionDetailDialog({required this.item});
  final TransactionHistoryItem item;

  @override
  ConsumerState<_TransactionDetailDialog> createState() =>
      _TransactionDetailDialogState();
}

class _TransactionDetailDialogState
    extends ConsumerState<_TransactionDetailDialog> {
  bool _busy = false;
  TransactionHistoryItem get item => widget.item;

  Future<void> _createCompensation() async {
    final members = await ref.read(remoteHouseholdMembersProvider.future);
    final accounts = await ref.read(remoteAccountsProvider.future);
    final actual = accounts
        .where((a) => a.id == item.sourceAccountId)
        .firstOrNull;
    final recommendedId = item.recommendationSnapshot
        .map((e) => e['recommended_account_id']?.toString())
        .whereType<String>()
        .firstOrNull;
    final recommended = accounts
        .where((a) => a.id == recommendedId)
        .firstOrNull;
    final actualOwners = actual?.holders.map((e) => e.userId).toSet() ?? {};
    final recommendedOwners =
        recommended?.holders.map((e) => e.userId).toSet() ?? {};
    if (!mounted) return;
    if (actualOwners.length == 1 &&
        recommendedOwners.length == 1 &&
        actualOwners.single == recommendedOwners.single) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              TransactionsWords.of(
                context,
              ).text('transactions.compensation.same_member'),
            ),
          ),
        );
      }
      return;
    }
    String? debtor = recommendedOwners.length == 1
        ? recommendedOwners.single
        : null;
    String? creditor = actualOwners.length == 1 ? actualOwners.single : null;
    final result = await showDialog<(String, String, double, String)?>(
      context: context,
      builder: (c) {
        final amount = TextEditingController(
          text: item.amount.dirhams.toStringAsFixed(2),
        );
        final reason = TextEditingController(
          text: TransactionsWords.of(
            context,
          ).text('transactions.compensation.default_reason'),
        );
        return StatefulBuilder(
          builder: (c, setLocal) => AlertDialog(
            title: Text(
              TransactionsWords.of(
                context,
              ).text('transactions.create_compensation'),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: debtor,
                  decoration: InputDecoration(
                    labelText: TransactionsWords.of(
                      context,
                    ).text('transactions.compensation.debtor'),
                  ),
                  items: members
                      .map(
                        (m) => DropdownMenuItem(
                          value: m.id,
                          child: Text(m.displayName),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setLocal(() => debtor = v),
                ),
                DropdownButtonFormField<String>(
                  initialValue: creditor,
                  decoration: InputDecoration(
                    labelText: TransactionsWords.of(
                      context,
                    ).text('transactions.compensation.creditor'),
                  ),
                  items: members
                      .map(
                        (m) => DropdownMenuItem(
                          value: m.id,
                          child: Text(m.displayName),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setLocal(() => creditor = v),
                ),
                TextField(
                  controller: amount,
                  decoration: InputDecoration(
                    labelText: TransactionsWords.of(
                      context,
                    ).text('transactions.amount_mad'),
                  ),
                ),
                TextField(
                  controller: reason,
                  decoration: InputDecoration(
                    labelText: TransactionsWords.of(
                      context,
                    ).text('transactions.reason'),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: Text(
                  TransactionsWords.of(context).text('transactions.cancel'),
                ),
              ),
              FilledButton(
                onPressed: () {
                  final value = double.tryParse(
                    amount.text.replaceAll(',', '.'),
                  );
                  if (debtor != null &&
                      creditor != null &&
                      debtor != creditor &&
                      value != null &&
                      value > 0 &&
                      value <= item.amount.dirhams) {
                    Navigator.pop(c, (
                      debtor!,
                      creditor!,
                      value,
                      reason.text.trim(),
                    ));
                  }
                },
                child: Text(
                  TransactionsWords.of(
                    context,
                  ).text('transactions.create_compensation'),
                ),
              ),
            ],
          ),
        );
      },
    );
    if (result == null || item.financialEventId == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(createMemberCompensationProvider)(
        sourceEventId: item.financialEventId!,
        debtorUserId: result.$1,
        creditorUserId: result.$2,
        amount: result.$3,
        reason: result.$4,
        envelopeId: item.envelopes.length == 1
            ? item.envelopes.single.id
            : null,
        actualAccountId: item.sourceAccountId,
        recommendedAccountId: recommendedId,
        actualPaymentMethodId: item.paymentMethodId,
        recommendedPaymentMethodId: item.recommendationSnapshot
            .map((e) => e['recommended_payment_method_id']?.toString())
            .whereType<String>()
            .firstOrNull,
      );
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reverse() async {
    final result = await showDialog<(String, String)?>(
      context: context,
      builder: (_) => const _DailyReversalDialog(),
    );
    if (result == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(financialHistoryActionsProvider)
          .reverse(
            eventId: item.financialEventId!,
            occurredAt: DateTime.now(),
            reasonCode: result.$1,
            reason: result.$2,
            idempotencyKey: newFinancialHistoryIdempotencyKey(),
          );
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              TransactionsWords.of(
                context,
              ).format('transactions.reversal_error', {'error': e}),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _upload() async {
    final picked = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
    );
    if (picked == null || picked.files.single.bytes == null) return;
    final f = picked.files.single;
    final ext = (f.extension ?? '').toLowerCase();
    final mime = switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      'pdf' => 'application/pdf',
      _ => null,
    };
    if (mime == null || f.size > 10485760) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              TransactionsWords.of(
                context,
              ).text('transactions.attachment_format_error'),
            ),
          ),
        );
      }
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(financialHistoryActionsProvider)
          .upload(
            eventId: item.financialEventId!,
            filename: f.name,
            mimeType: mime,
            bytes: f.bytes!,
          );
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              TransactionsWords.of(
                context,
              ).format('transactions.attachment_add_error', {'error': e}),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accounts =
        ref.watch(remoteAccountsProvider).valueOrNull ??
        const <FinancialAccount>[];
    final actual = accounts
        .where((a) => a.id == item.sourceAccountId)
        .firstOrNull;
    final recommendedId = item.recommendationSnapshot
        .map((e) => e['recommended_account_id']?.toString())
        .whereType<String>()
        .firstOrNull;
    final recommended = accounts
        .where((a) => a.id == recommendedId)
        .firstOrNull;
    final sameEconomicMember =
        actual != null &&
        recommended != null &&
        actual.holders.length == 1 &&
        recommended.holders.length == 1 &&
        actual.holders.single.userId == recommended.holders.single.userId;
    final compensations =
        ref.watch(memberCompensationsProvider).valueOrNull ??
        const <MemberCompensation>[];
    final activeMembers =
        ref.watch(remoteHouseholdMembersProvider).valueOrNull ??
        const <HouseholdMember>[];
    final existing = item.financialEventId == null
        ? null
        : compensations
              .where((c) => c.sourceFinancialEventId == item.financialEventId)
              .firstOrNull;
    final mismatch = item.recommendationSnapshot.any(
      (e) =>
          e['actual_account_matches'] == false ||
          e['actual_payment_method_matches'] == false,
    );
    return AlertDialog(
      title: Text(TransactionsWords.of(context).text('transactions.detail')),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.description,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                TransactionsWords.of(context).format(
                  'transactions.detail.type',
                  {'value': _labelFor(context, item.type)},
                ),
              ),
              Text(
                TransactionsWords.of(context).format(
                  'transactions.detail.date',
                  {'value': _formatLocalizedDate(context, item.occurredAt)},
                ),
              ),
              Text(
                TransactionsWords.of(context).format(
                  'transactions.detail.amount',
                  {'value': '${item.amount.dirhams.toStringAsFixed(2)} MAD'},
                ),
              ),
              Text(
                TransactionsWords.of(
                  context,
                ).format('transactions.detail.account', {
                  'value':
                      item.sourceAccountName ??
                      item.destinationAccountName ??
                      TransactionsWords.of(
                        context,
                      ).text('transactions.not_provided'),
                }),
              ),
              Text(
                TransactionsWords.of(
                  context,
                ).format('transactions.detail.method', {
                  'value':
                      item.paymentMethodName ??
                      TransactionsWords.of(
                        context,
                      ).text('transactions.method_not_provided'),
                }),
              ),
              if (item.envelopes.isNotEmpty)
                Text(
                  TransactionsWords.of(context).format(
                    'transactions.detail.envelopes',
                    {'value': item.envelopes.map((e) => e.name).join(', ')},
                  ),
                ),
              if (item.actorId != null)
                Text(
                  TransactionsWords.of(context).format(
                    'transactions.detail.performed_by',
                    {'value': item.actorId!},
                  ),
                ),
              if (item.recommendationSnapshot.isNotEmpty)
                Text(
                  item.recommendationSnapshot.every(
                        (e) =>
                            e['actual_account_matches'] == true &&
                            e['actual_payment_method_matches'] == true,
                      )
                      ? TransactionsWords.of(
                          context,
                        ).text('transactions.recommendation.match')
                      : TransactionsWords.of(
                          context,
                        ).text('transactions.recommendation.mismatch'),
                ),
              Text(
                TransactionsWords.of(
                  context,
                ).format('transactions.detail.status', {
                  'value': item.isReversed
                      ? TransactionsWords.of(
                          context,
                        ).text('transactions.state.reversed')
                      : item.isReversal
                      ? TransactionsWords.of(
                          context,
                        ).text('transactions.state.reversal')
                      : TransactionsWords.of(
                          context,
                        ).text('transactions.state.posted'),
                }),
              ),
              if (item.reversalReason != null)
                Text(
                  TransactionsWords.of(context).format(
                    'transactions.detail.reason',
                    {'value': item.reversalReason!},
                  ),
                ),
              Text(
                item.hasEnvelopeMovement
                    ? TransactionsWords.of(
                        context,
                      ).text('transactions.envelope_recorded')
                    : TransactionsWords.of(
                        context,
                      ).text('transactions.no_envelope_movement'),
              ),
              const Divider(),
              Text(
                TransactionsWords.of(context).text('transactions.attachments'),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              if (item.attachments.isEmpty)
                Text(
                  TransactionsWords.of(
                    context,
                  ).text('transactions.no_attachment'),
                ),
              for (final a in item.attachments)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    a.mimeType == 'application/pdf'
                        ? Icons.picture_as_pdf
                        : Icons.image,
                  ),
                  title: Text(a.filename),
                  subtitle: Text(
                    TransactionsWords.of(
                      context,
                    ).format('transactions.attachment_meta', {
                      'size': (a.fileSize / 1024).toStringAsFixed(1),
                      'date': _formatLocalizedDate(context, a.uploadedAt),
                    }),
                  ),
                  onTap: () async {
                    final u = await ref
                        .read(financialHistoryActionsProvider)
                        .signedUrl(a.storagePath);
                    if (!context.mounted) return;
                    await launchUrl(Uri.parse(u));
                  },
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: _busy
                        ? null
                        : () async {
                            await ref
                                .read(financialHistoryActionsProvider)
                                .delete(a.id);
                            if (context.mounted) Navigator.pop(context);
                          },
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        if (existing != null)
          TextButton.icon(
            key: const Key('view-expense-compensation'),
            onPressed: () {
              Navigator.pop(context);
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const MemberCompensationsPage(),
                ),
              );
            },
            icon: const Icon(Icons.open_in_new),
            label: Text(
              TransactionsWords.of(
                context,
              ).text('transactions.view_compensation'),
            ),
          )
        else if (item.type == LedgerTransactionType.expense &&
            item.financialEventId != null &&
            mismatch &&
            activeMembers.length > 1 &&
            !sameEconomicMember)
          TextButton.icon(
            key: const Key('create-compensation-from-expense'),
            onPressed: _busy ? null : _createCompensation,
            icon: const Icon(Icons.swap_horiz),
            label: Text(
              TransactionsWords.of(
                context,
              ).text('transactions.create_compensation'),
            ),
          ),
        if (item.financialEventId != null)
          TextButton.icon(
            onPressed: _busy ? null : _upload,
            icon: const Icon(Icons.attach_file),
            label: Text(
              TransactionsWords.of(context).text('transactions.add_attachment'),
            ),
          ),
        if (item.financialEventId != null &&
            !item.isReversed &&
            !item.isReversal &&
            const [
              LedgerTransactionType.expense,
              LedgerTransactionType.income,
              LedgerTransactionType.accountTransfer,
              LedgerTransactionType.envelopeTransfer,
            ].contains(item.type))
          TextButton.icon(
            key: const Key('reverse-daily-operation-button'),
            onPressed: _busy ? null : _reverse,
            icon: const Icon(Icons.undo),
            label: Text(
              TransactionsWords.of(
                context,
              ).text('transactions.cancel_operation'),
            ),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(TransactionsWords.of(context).text('transactions.close')),
        ),
      ],
    );
  }
}

class _DailyReversalDialog extends StatefulWidget {
  const _DailyReversalDialog();
  @override
  State<_DailyReversalDialog> createState() => _DailyReversalDialogState();
}

class _DailyReversalDialogState extends State<_DailyReversalDialog> {
  String _code = 'wrong_amount';
  final _reason = TextEditingController();
  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      TransactionsWords.of(context).text('transactions.cancel_operation'),
    ),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _code,
          decoration: InputDecoration(
            labelText: TransactionsWords.of(
              context,
            ).text('transactions.reason'),
          ),
          items: [
            DropdownMenuItem(
              value: 'wrong_amount',
              child: Text(
                TransactionsWords.of(
                  context,
                ).text('transactions.reversal.reason.wrong_amount'),
              ),
            ),
            DropdownMenuItem(
              value: 'wrong_account',
              child: Text(
                TransactionsWords.of(
                  context,
                ).text('transactions.reversal.reason.wrong_account'),
              ),
            ),
            DropdownMenuItem(
              value: 'wrong_envelope',
              child: Text(
                TransactionsWords.of(
                  context,
                ).text('transactions.reversal.reason.wrong_envelope'),
              ),
            ),
            DropdownMenuItem(
              value: 'duplicate',
              child: Text(
                TransactionsWords.of(
                  context,
                ).text('transactions.reversal.reason.duplicate'),
              ),
            ),
            DropdownMenuItem(
              value: 'cancelled',
              child: Text(
                TransactionsWords.of(
                  context,
                ).text('transactions.reversal.reason.cancelled'),
              ),
            ),
            DropdownMenuItem(
              value: 'other',
              child: Text(
                TransactionsWords.of(
                  context,
                ).text('transactions.reversal.reason.other'),
              ),
            ),
          ],
          onChanged: (v) => setState(() => _code = v!),
        ),
        TextField(
          key: const Key('daily-reversal-reason-field'),
          controller: _reason,
          onChanged: (_) => setState(() {}),
          maxLength: 500,
          decoration: InputDecoration(
            labelText: TransactionsWords.of(
              context,
            ).text('transactions.reversal.explanation_required'),
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(TransactionsWords.of(context).text('transactions.back')),
      ),
      FilledButton(
        key: const Key('daily-reversal-submit-button'),
        onPressed: _reason.text.trim().isEmpty
            ? null
            : () => Navigator.pop(context, (_code, _reason.text.trim())),
        child: Text(
          TransactionsWords.of(context).text('transactions.reversal.confirm'),
        ),
      ),
    ],
  );
}

class _DebtExpenseSubmission {
  const _DebtExpenseSubmission({
    required this.occurredAt,
    required this.description,
    required this.amount,
    required this.allocations,
    this.creditorName,
    this.notes,
  });

  final DateTime occurredAt;
  final String description;
  final Money amount;
  final List<FinancialEventAllocation> allocations;
  final String? creditorName;
  final String? notes;
}

class DebtsPage extends ConsumerWidget {
  const DebtsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final debts = ref.watch(remoteDebtBalancesProvider);
    final accounts = ref.watch(remoteAccountsProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(TransactionsWords.of(context).text('transactions.debts')),
      ),
      body: debts.when(
        loading: () => Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: Text(
            TransactionsWords.of(context).text('transactions.debts_load_error'),
          ),
        ),
        data: (items) => ListView(
          padding: AppSpacing.page,
          children: [
            Text(
              TransactionsWords.of(context).text('transactions.debts'),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            if (items.isEmpty)
              Card(
                child: ListTile(
                  title: Text(
                    TransactionsWords.of(
                      context,
                    ).text('transactions.no_open_debt'),
                  ),
                ),
              ),
            ...items.map(
              (debt) => Card(
                child: ListTile(
                  title: Text(debt.description),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: AppSpacing.sm,
                        children: [
                          Text(
                            debt.creditorName ??
                                TransactionsWords.of(
                                  context,
                                ).text('transactions.creditor_unknown'),
                          ),
                          _StatusBadge(
                            label: _displayObligationStatus(
                              settled: debt.settledAmount,
                              writtenOff: debt.writtenOffAmount,
                              remaining: debt.remainingAmount,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Wrap(
                        spacing: AppSpacing.md,
                        runSpacing: AppSpacing.xs,
                        children: [
                          _AmountIndicator(
                            label: TransactionsWords.of(
                              context,
                            ).text('transactions.amount.initial'),
                            amount: debt.initialAmount,
                          ),
                          _AmountIndicator(
                            label: TransactionsWords.of(
                              context,
                            ).text('transactions.amount.settled'),
                            amount: debt.settledAmount,
                          ),
                          _AmountIndicator(
                            label: TransactionsWords.of(
                              context,
                            ).text('transactions.amount.written_off'),
                            amount: debt.writtenOffAmount,
                          ),
                          _AmountIndicator(
                            label: TransactionsWords.of(
                              context,
                            ).text('transactions.amount.remaining'),
                            amount: debt.remainingAmount,
                            prominent: true,
                          ),
                        ],
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => _openDebtHistory(context, ref, debt),
                          icon: const Icon(Icons.history_outlined),
                          label: Text(
                            TransactionsWords.of(
                              context,
                            ).text('transactions.history'),
                          ),
                        ),
                      ),
                    ],
                  ),
                  isThreeLine: true,
                  trailing: debt.remainingAmount.minorUnits <= 0
                      ? null
                      : SizedBox(
                          width: 250,
                          child: Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () =>
                                      _openDebtWriteoff(context, ref, debt),
                                  child: Text(
                                    TransactionsWords.of(
                                      context,
                                    ).text('transactions.write_off'),
                                    softWrap: false,
                                    overflow: TextOverflow.visible,
                                  ),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.xs),
                              Expanded(
                                child: FilledButton(
                                  onPressed: accounts.hasValue
                                      ? () => _openDebtSettlement(
                                          context,
                                          ref,
                                          debt,
                                          accounts.requireValue,
                                        )
                                      : null,
                                  child: Text(
                                    TransactionsWords.of(
                                      context,
                                    ).text('transactions.settle'),
                                    softWrap: false,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openDebtSettlement(
    BuildContext context,
    WidgetRef ref,
    RemoteDebtBalance debt,
    List<FinancialAccount> accounts,
  ) async {
    final completed = await showDialog<bool>(
      context: context,
      builder: (_) => _DebtSettlementDialog(debt: debt, accounts: accounts),
    );
    if (completed == true) {
      ref.invalidate(remoteDebtBalancesProvider);
      ref.invalidate(remoteTransactionsProvider);
      ref.invalidate(remoteAccountBalancesProvider);
      ref.invalidate(remoteAccountsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              TransactionsWords.of(context).text('transactions.debt_paid'),
            ),
          ),
        );
      }
    }
  }

  Future<void> _openDebtWriteoff(
    BuildContext context,
    WidgetRef ref,
    RemoteDebtBalance debt,
  ) async {
    final completed = await showDialog<bool>(
      context: context,
      builder: (_) => _WriteoffDialog(
        kind: _WriteoffKind.debt,
        obligationId: debt.id,
        description: debt.description,
        counterparty: debt.creditorName,
        remaining: debt.remainingAmount,
      ),
    );
    if (completed == true) {
      ref.invalidate(remoteDebtBalancesProvider);
      ref.invalidate(remoteTransactionsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              TransactionsWords.of(
                context,
              ).text('transactions.debt_written_off'),
            ),
          ),
        );
      }
    }
  }

  Future<void> _openDebtHistory(
    BuildContext context,
    WidgetRef ref,
    RemoteDebtBalance debt,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _SettlementHistoryDialog(
        obligationId: debt.id,
        kind: _SettlementHistoryKind.debt,
        title: debt.description,
      ),
    );
    ref.invalidate(obligationSettlementHistoryProvider(debt.id));
    ref.invalidate(remoteDebtBalancesProvider);
    ref.invalidate(remoteTransactionsProvider);
    ref.invalidate(remoteAccountBalancesProvider);
  }
}

class ReceivablesPage extends ConsumerWidget {
  const ReceivablesPage({super.key, this.returnAfterCreate = false});

  final bool returnAfterCreate;

  Future<void> _openNewReceivable(BuildContext context, WidgetRef ref) async {
    final choice = await showDialog<_ReceivableCreationKind>(
      context: context,
      builder: (_) => const _ReceivableCreationChoiceDialog(),
    );
    if (!context.mounted || choice == null) return;
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => switch (choice) {
        _ReceivableCreationKind.income => const _IncomeReceivableDialog(),
        _ReceivableCreationKind.recovery => const _RecoveryReceivableDialog(),
      },
    );
    if (created == true) {
      ref.invalidate(remoteReceivableBalancesProvider);
      ref.invalidate(remoteTransactionsProvider);
      ref.invalidate(eligibleRecoverySourcesProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              TransactionsWords.of(
                context,
              ).text('transactions.receivable_created'),
            ),
          ),
        );
        if (returnAfterCreate) {
          Navigator.of(context).pop(true);
        }
      }
    }
  }

  Future<void> _openSettlement(
    BuildContext context,
    WidgetRef ref,
    RemoteReceivableBalance receivable,
    List<FinancialAccount> accounts,
    List<RemoteEnvelopeBalance> envelopes,
  ) async {
    final completed = await showDialog<bool>(
      context: context,
      builder: (_) => _ReceivableSettlementDialog(
        receivable: receivable,
        accounts: accounts,
        envelopes: envelopes,
      ),
    );
    if (completed == true) {
      ref.invalidate(remoteReceivableBalancesProvider);
      ref.invalidate(remoteTransactionsProvider);
      ref.invalidate(remoteAccountBalancesProvider);
      ref.invalidate(remoteAccountsProvider);
      ref.invalidate(remoteEnvelopeBalancesProvider);
      ref.invalidate(remoteEnvelopeHistoryProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              TransactionsWords.of(
                context,
              ).text('transactions.receivable_collected'),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final receivables = ref.watch(remoteReceivableBalancesProvider);
    final accounts = ref.watch(remoteAccountsProvider);
    final envelopes = ref.watch(remoteEnvelopeBalancesProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          TransactionsWords.of(context).text('transactions.receivables'),
        ),
      ),
      body: receivables.when(
        loading: () => Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: Text(
            TransactionsWords.of(
              context,
            ).text('transactions.receivables_load_error'),
          ),
        ),
        data: (items) => ListView(
          padding: AppSpacing.page,
          children: [
            Text(
              TransactionsWords.of(context).text('transactions.receivables'),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            if (items.isEmpty)
              Card(
                child: ListTile(
                  title: Text(
                    TransactionsWords.of(
                      context,
                    ).text('transactions.no_receivable'),
                  ),
                ),
              ),
            ...items.map(
              (item) => Card(
                child: ListTile(
                  title: Text(item.description),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: AppSpacing.sm,
                        children: [
                          Text(
                            // i18n-dynamic-only
                            '${item.displayKind} · ${item.counterpartyName ?? TransactionsWords.of(context).text('transactions.counterparty_unknown')}',
                          ),
                          _StatusBadge(
                            label: _displayObligationStatus(
                              settled: item.settledAmount,
                              writtenOff: item.writtenOffAmount,
                              remaining: item.remainingAmount,
                              isReceivable: true,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Wrap(
                        spacing: AppSpacing.md,
                        runSpacing: AppSpacing.xs,
                        children: [
                          _AmountIndicator(
                            label: TransactionsWords.of(
                              context,
                            ).text('transactions.amount.initial'),
                            amount: item.initialAmount,
                          ),
                          _AmountIndicator(
                            label: TransactionsWords.of(
                              context,
                            ).text('transactions.amount.collected'),
                            amount: item.settledAmount,
                          ),
                          _AmountIndicator(
                            label: TransactionsWords.of(
                              context,
                            ).text('transactions.amount.written_off'),
                            amount: item.writtenOffAmount,
                          ),
                          _AmountIndicator(
                            label: TransactionsWords.of(
                              context,
                            ).text('transactions.amount.remaining'),
                            amount: item.remainingAmount,
                            prominent: true,
                          ),
                        ],
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => _openHistory(context, ref, item),
                          icon: const Icon(Icons.history_outlined),
                          label: Text(
                            TransactionsWords.of(
                              context,
                            ).text('transactions.history'),
                          ),
                        ),
                      ),
                    ],
                  ),
                  isThreeLine: true,
                  trailing:
                      item.remainingAmount.minorUnits <= 0 || !accounts.hasValue
                      ? null
                      : SizedBox(
                          width: 250,
                          child: Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () =>
                                      _openWriteoff(context, ref, item),
                                  child: Text(
                                    TransactionsWords.of(
                                      context,
                                    ).text('transactions.write_off'),
                                    softWrap: false,
                                    overflow: TextOverflow.visible,
                                  ),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.xs),
                              Expanded(
                                child: FilledButton(
                                  onPressed: () => _openSettlement(
                                    context,
                                    ref,
                                    item,
                                    accounts.requireValue
                                        .where(
                                          (account) =>
                                              !account.isArchived &&
                                              !account.isSystem,
                                        )
                                        .toList(growable: false),
                                    envelopes.valueOrNull ?? const [],
                                  ),
                                  child: Text(
                                    TransactionsWords.of(
                                      context,
                                    ).text('transactions.collect'),
                                    softWrap: false,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('new-receivable-button'),
        onPressed: () => _openNewReceivable(context, ref),
        icon: const Icon(Icons.add),
        label: Text(
          TransactionsWords.of(context).text('transactions.create_receivable'),
        ),
      ),
    );
  }

  Future<void> _openWriteoff(
    BuildContext context,
    WidgetRef ref,
    RemoteReceivableBalance receivable,
  ) async {
    final completed = await showDialog<bool>(
      context: context,
      builder: (_) => _WriteoffDialog(
        kind: receivable.kind == 'recovery'
            ? _WriteoffKind.recovery
            : _WriteoffKind.income,
        obligationId: receivable.id,
        description: receivable.description,
        counterparty: receivable.counterpartyName,
        remaining: receivable.remainingAmount,
      ),
    );
    if (completed == true) {
      ref.invalidate(remoteReceivableBalancesProvider);
      ref.invalidate(remoteTransactionsProvider);
      ref.invalidate(eligibleRecoverySourcesProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              TransactionsWords.of(
                context,
              ).text('transactions.receivable_written_off'),
            ),
          ),
        );
      }
    }
  }

  Future<void> _openHistory(
    BuildContext context,
    WidgetRef ref,
    RemoteReceivableBalance receivable,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _SettlementHistoryDialog(
        obligationId: receivable.id,
        kind: receivable.kind == 'recovery'
            ? _SettlementHistoryKind.recovery
            : _SettlementHistoryKind.income,
        title: receivable.description,
      ),
    );
    ref.invalidate(obligationSettlementHistoryProvider(receivable.id));
    ref.invalidate(remoteReceivableBalancesProvider);
    ref.invalidate(remoteTransactionsProvider);
    ref.invalidate(remoteAccountBalancesProvider);
    ref.invalidate(remoteEnvelopeBalancesProvider);
    ref.invalidate(remoteEnvelopeHistoryProvider);
  }
}

String _displayObligationStatus({
  required Money settled,
  required Money writtenOff,
  required Money remaining,
  bool isReceivable = false,
}) {
  final hasSettled = settled.minorUnits > 0;
  final hasWrittenOff = writtenOff.minorUnits > 0;
  final settlementKey = isReceivable
      ? 'transactions.status.collected_feminine'
      : 'transactions.status.settled_feminine';

  if (remaining.minorUnits <= 0) {
    if (hasSettled && hasWrittenOff) return 'transactions.status.mixed_closed';
    if (hasSettled) return 'transactions.status.settled';
    if (hasWrittenOff) return 'transactions.status.written_off';
  }

  if (hasSettled && hasWrittenOff) {
    return 'transactions.status.partially_mixed|$settlementKey';
  }
  if (hasWrittenOff) return 'transactions.status.partially_written_off';
  if (hasSettled) return 'transactions.status.partially_settled|$settlementKey';
  return 'transactions.status.open';
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final parts = label.split('|');
    final labelText = parts.length == 1
        ? TransactionsWords.of(context).text(parts.first)
        : TransactionsWords.of(context).format(parts.first, {
            'settlement': TransactionsWords.of(context).text(parts.last),
          });
    final complete =
        parts.first == 'transactions.status.settled' ||
        parts.first == 'transactions.status.written_off' ||
        parts.first == 'transactions.status.mixed_closed';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: complete
            ? colors.surfaceContainerHighest
            : colors.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(labelText, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}

class _AmountIndicator extends StatelessWidget {
  const _AmountIndicator({
    required this.label,
    required this.amount,
    this.prominent = false,
  });
  final String label;
  final Money amount;
  final bool prominent;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: Theme.of(context).textTheme.labelSmall),
      Text(
        // i18n-dynamic-only
        '${_formatCents(amount.minorUnits)} MAD',
        style: prominent
            ? Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)
            : Theme.of(context).textTheme.bodySmall,
      ),
    ],
  );
}

enum _ReceivableCreationKind { income, recovery }

class _ReceivableCreationChoiceDialog extends StatelessWidget {
  const _ReceivableCreationChoiceDialog();

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      TransactionsWords.of(context).text('transactions.new_receivable'),
    ),
    content: SizedBox(
      width: 460,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            key: const Key('income-receivable-choice'),
            leading: const Icon(Icons.schedule_outlined),
            title: Text(
              TransactionsWords.of(
                context,
              ).text('transactions.type.income_receivable'),
            ),
            subtitle: Text(
              TransactionsWords.of(
                context,
              ).text('transactions.income_receivable_hint'),
            ),
            onTap: () =>
                Navigator.of(context).pop(_ReceivableCreationKind.income),
          ),
          const Divider(height: AppSpacing.md),
          ListTile(
            key: const Key('recovery-receivable-choice'),
            leading: const Icon(Icons.replay_outlined),
            title: Text(
              TransactionsWords.of(
                context,
              ).text('transactions.repayment_to_recover'),
            ),
            subtitle: Text(
              TransactionsWords.of(
                context,
              ).text('transactions.recovery_receivable_hint'),
            ),
            onTap: () =>
                Navigator.of(context).pop(_ReceivableCreationKind.recovery),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(TransactionsWords.of(context).text('transactions.cancel')),
      ),
    ],
  );
}

abstract class _ReceivableDialogState<T extends ConsumerStatefulWidget>
    extends ConsumerState<T> {
  final formKey = GlobalKey<FormState>();
  final description = TextEditingController();
  final amount = TextEditingController();
  final debtor = TextEditingController();
  final notes = TextEditingController();
  final idempotencyKey = _newIdempotencyKey();
  DateTime? dueAt;
  var submitting = false;
  String? error;

  @override
  void dispose() {
    description.dispose();
    amount.dispose();
    debtor.dispose();
    notes.dispose();
    super.dispose();
  }

  InputDecoration fieldDecoration(String label) => InputDecoration(
    labelText: label,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
  );

  Future<void> selectDueDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: dueAt ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (selected != null && mounted) setState(() => dueAt = selected);
  }

  Widget dueDateField() => OutlinedButton.icon(
    onPressed: submitting ? null : selectDueDate,
    icon: const Icon(Icons.calendar_today_outlined, size: 18),
    label: Text(
      dueAt == null
          ? TransactionsWords.of(context).text('transactions.due_optional')
          : TransactionsWords.of(
              context,
            ).format('transactions.due_value', {'value': _formatDate(dueAt!)}),
    ),
  );

  Widget standardFields() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextFormField(
        key: const Key('receivable-description-field'),
        controller: description,
        decoration: fieldDecoration(
          TransactionsWords.of(context).text('transactions.label_required'),
        ),
        validator: (value) => value?.trim().isEmpty ?? true
            ? TransactionsWords.of(context).text('transactions.label_empty')
            : null,
      ),
      const SizedBox(height: AppSpacing.sm),
      TextFormField(
        key: const Key('receivable-amount-field'),
        controller: amount,
        decoration: fieldDecoration(
          TransactionsWords.of(context).text('transactions.amount_required'),
        ),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: onAmountChanged,
        validator: (value) => (_madToCents(value ?? '') ?? 0) <= 0
            ? TransactionsWords.of(context).text('transactions.amount_invalid')
            : null,
      ),
      const SizedBox(height: AppSpacing.sm),
      TextFormField(
        key: const Key('receivable-debtor-field'),
        controller: debtor,
        decoration: fieldDecoration(
          TransactionsWords.of(context).text('transactions.debtor_required'),
        ),
        validator: (value) => value?.trim().isEmpty ?? true
            ? TransactionsWords.of(context).text('transactions.debtor_missing')
            : null,
      ),
      const SizedBox(height: AppSpacing.sm),
      dueDateField(),
      const SizedBox(height: AppSpacing.sm),
      TextFormField(
        key: const Key('receivable-notes-field'),
        controller: notes,
        decoration: fieldDecoration(
          TransactionsWords.of(context).text('transactions.notes'),
        ),
        maxLines: 2,
      ),
    ],
  );

  Widget errorMessage() => error == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: AppSpacing.sm),
          child: Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        );

  int? get parsedAmount => _madToCents(amount.text);

  void onAmountChanged(String _) {}
}

class _IncomeReceivableDialog extends ConsumerStatefulWidget {
  const _IncomeReceivableDialog();

  @override
  ConsumerState<_IncomeReceivableDialog> createState() =>
      _IncomeReceivableDialogState();
}

class _IncomeReceivableDialogState
    extends _ReceivableDialogState<_IncomeReceivableDialog> {
  Future<void> _submit() async {
    if (submitting || !formKey.currentState!.validate()) return;
    final cents = parsedAmount;
    if (cents == null || cents <= 0) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _ReceivableConfirmationDialog(
        title: TransactionsWords.of(
          context,
        ).text('transactions.create_receivable_confirmation'),
        type: TransactionsWords.of(
          context,
        ).text('transactions.income_to_collect'),
        debtor: debtor.text.trim(),
        amount: Money.fromMinorUnits(cents),
        detail: TransactionsWords.of(
          context,
        ).text('transactions.income_receivable_confirmation'),
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      submitting = true;
      error = null;
    });
    try {
      final repository = await ref.read(
        financialEventRepositoryProvider.future,
      );
      await repository.createIncomeReceivable(
        occurredAt: DateTime.now(),
        description: description.text.trim(),
        amount: Money.fromMinorUnits(cents),
        debtorName: debtor.text.trim(),
        dueAt: dueAt,
        notes: notes.text,
        idempotencyKey: idempotencyKey,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (exception) {
      if (mounted) {
        setState(() => error = _financialErrorMessage(context, exception));
      }
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      TransactionsWords.of(context).text('transactions.type.income_receivable'),
    ),
    content: SizedBox(
      width: 500,
      child: SingleChildScrollView(
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                TransactionsWords.of(
                  context,
                ).text('transactions.income_receivable_form_hint'),
              ),
              const SizedBox(height: AppSpacing.md),
              standardFields(),
              errorMessage(),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: submitting ? null : () => Navigator.of(context).pop(),
        child: Text(TransactionsWords.of(context).text('transactions.cancel')),
      ),
      FilledButton(
        key: const Key('create-income-receivable-button'),
        onPressed: submitting ? null : _submit,
        child: Text(
          submitting
              ? TransactionsWords.of(context).text('transactions.creating')
              : TransactionsWords.of(
                  context,
                ).text('transactions.create_receivable'),
        ),
      ),
    ],
  );
}

class _RecoveryReceivableDialog extends ConsumerStatefulWidget {
  const _RecoveryReceivableDialog();

  @override
  ConsumerState<_RecoveryReceivableDialog> createState() =>
      _RecoveryReceivableDialogState();
}

class _RecoveryReceivableDialogState
    extends _ReceivableDialogState<_RecoveryReceivableDialog> {
  RecoveryExpenseSource? source;

  bool get _amountExceedsMaximum {
    final cents = parsedAmount;
    return source != null &&
        cents != null &&
        cents > source!.maximumAmount.minorUnits;
  }

  @override
  void onAmountChanged(String _) => setState(() {});

  Future<void> _submit() async {
    if (submitting || !formKey.currentState!.validate()) return;
    final cents = parsedAmount;
    if (source == null) {
      setState(
        () => error = TransactionsWords.of(
          context,
        ).text('transactions.recovery.choose_source'),
      );
      return;
    }
    if (cents == null ||
        cents <= 0 ||
        cents > source!.maximumAmount.minorUnits) {
      setState(
        () => error = TransactionsWords.of(
          context,
        ).text('transactions.recovery.maximum_error'),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _ReceivableConfirmationDialog(
        title: TransactionsWords.of(
          context,
        ).text('transactions.recovery.create_title'),
        type: TransactionsWords.of(
          context,
        ).text('transactions.repayment_to_recover'),
        debtor: debtor.text.trim(),
        amount: Money.fromMinorUnits(cents),
        sourceDescription: source!.description,
        detail: TransactionsWords.of(
          context,
        ).text('transactions.recovery.confirmation'),
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      submitting = true;
      error = null;
    });
    try {
      final repository = await ref.read(
        financialEventRepositoryProvider.future,
      );
      await repository.createRecoveryReceivable(
        sourceEventId: source!.eventId,
        sourceEnvelopeId: source!.envelopeId,
        occurredAt: DateTime.now(),
        description: description.text.trim(),
        amount: Money.fromMinorUnits(cents),
        maximumAmount: source!.maximumAmount,
        debtorName: debtor.text.trim(),
        dueAt: dueAt,
        notes: notes.text,
        idempotencyKey: idempotencyKey,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (exception) {
      if (mounted) {
        setState(() => error = _financialErrorMessage(context, exception));
      }
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sources = ref.watch(eligibleRecoverySourcesProvider);
    return AlertDialog(
      title: Text(
        TransactionsWords.of(context).text('transactions.type.recovery'),
      ),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                sources.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(AppSpacing.sm),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (_, _) => Text(
                    TransactionsWords.of(
                      context,
                    ).text('transactions.eligible_expenses_error'),
                  ),
                  data: (items) =>
                      DropdownButtonFormField<RecoveryExpenseSource>(
                        key: const Key('recovery-source-field'),
                        isExpanded: true,
                        initialValue: source,
                        decoration: fieldDecoration(
                          TransactionsWords.of(
                            context,
                          ).text('transactions.expense_to_refund_required'),
                        ),
                        items: items
                            .map(
                              (item) => DropdownMenuItem(
                                value: item,
                                child: Text(
                                  _recoverySourceLabel(context, item),
                                ),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: submitting
                            ? null
                            : (value) => setState(() => source = value),
                        validator: (value) => value == null
                            ? TransactionsWords.of(
                                context,
                              ).text('transactions.recovery.choose_source')
                            : null,
                      ),
                ),
                if (source != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    TransactionsWords.of(context).format(
                      'transactions.recovery.source_amount',
                      {'value': _formatFrenchMoney(source!.sourceAmount)},
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    TransactionsWords.of(context).format(
                      'transactions.recovery.committed_amount',
                      {'value': _formatFrenchMoney(source!.committedAmount)},
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    TransactionsWords.of(context).format(
                      'transactions.recovery.maximum_amount',
                      {'value': _formatFrenchMoney(source!.maximumAmount)},
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                standardFields(),
                if (_amountExceedsMaximum)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: Text(
                      TransactionsWords.of(
                        context,
                      ).text('transactions.recovery.maximum_error'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                errorMessage(),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: submitting ? null : () => Navigator.of(context).pop(),
          child: Text(
            TransactionsWords.of(context).text('transactions.cancel'),
          ),
        ),
        FilledButton(
          key: const Key('create-recovery-receivable-button'),
          onPressed: submitting || _amountExceedsMaximum ? null : _submit,
          child: Text(
            submitting
                ? TransactionsWords.of(context).text('transactions.creating')
                : TransactionsWords.of(
                    context,
                  ).text('transactions.create_receivable'),
          ),
        ),
      ],
    );
  }
}

class _ReceivableConfirmationDialog extends StatelessWidget {
  const _ReceivableConfirmationDialog({
    required this.title,
    required this.type,
    required this.debtor,
    required this.amount,
    required this.detail,
    this.sourceDescription,
  });

  final String title;
  final String type;
  final String debtor;
  final Money amount;
  final String detail;
  final String? sourceDescription;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(title),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            TransactionsWords.of(
              context,
            ).format('transactions.detail.type', {'value': type}),
          ),
          if (sourceDescription != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              TransactionsWords.of(context).format(
                'transactions.detail.source_expense',
                {'value': sourceDescription!},
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xs),
          Text(
            TransactionsWords.of(
              context,
            ).format('transactions.detail.debtor', {'value': debtor}),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            TransactionsWords.of(context).format('transactions.detail.amount', {
              'value': _formatFrenchMoney(amount),
            }),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(detail),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(false),
        child: Text(TransactionsWords.of(context).text('transactions.cancel')),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(true),
        child: Text(
          TransactionsWords.of(context).text('transactions.create_receivable'),
        ),
      ),
    ],
  );
}

enum _SettlementHistoryKind { debt, income, recovery }

class _SettlementHistoryDialog extends ConsumerWidget {
  const _SettlementHistoryDialog({
    required this.obligationId,
    required this.kind,
    required this.title,
  });

  final String obligationId;
  final _SettlementHistoryKind kind;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(
      obligationSettlementHistoryProvider(obligationId),
    );
    return AlertDialog(
      title: Text(TransactionsWords.of(context).text('transactions.history')),
      content: SizedBox(
        width: 620,
        child: history.when(
          loading: () => Center(child: CircularProgressIndicator()),
          error: (_, _) => Text(
            TransactionsWords.of(
              context,
            ).text('transactions.history_load_error'),
          ),
          data: (historyItems) => SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AppSpacing.md),
                if (historyItems.creation != null) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _formatDateTime(historyItems.creation!.recordedAt),
                          ),
                          Text(
                            kind == _SettlementHistoryKind.debt
                                ? TransactionsWords.of(
                                    context,
                                  ).text('transactions.detail.created_debt')
                                : kind == _SettlementHistoryKind.recovery
                                ? TransactionsWords.of(
                                    context,
                                  ).text('transactions.detail.created_recovery')
                                : TransactionsWords.of(context).text(
                                    'transactions.detail.created_receivable',
                                  ),
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          Text(
                            TransactionsWords.of(
                              context,
                            ).format('transactions.detail.created_by', {
                              'value': historyItems.creation!.actor.displayName,
                            }),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                ],
                if (historyItems.settlements.isEmpty &&
                    historyItems.writeoffs.isEmpty)
                  Text(
                    TransactionsWords.of(
                      context,
                    ).text('transactions.detail.no_settlement'),
                  ),
                for (final item in historyItems.settlements) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_formatDateTime(item.recordedAt)),
                          Text(
                            TransactionsWords.of(context).format(
                              kind == _SettlementHistoryKind.debt
                                  ? 'transactions.detail.settlement'
                                  : 'transactions.detail.collection',
                              {'value': _formatFrenchMoney(item.grossAmount)},
                            ),
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          if (item.accountName != null)
                            Text(
                              TransactionsWords.of(context).format(
                                'transactions.detail.account',
                                {'value': item.accountName!},
                              ),
                            ),
                          Text(
                            TransactionsWords.of(context).format(
                              'transactions.detail.performed_by',
                              {'value': item.actor.displayName},
                            ),
                          ),
                          if (item.envelopeMovements.isNotEmpty)
                            for (final movement in item.envelopeMovements)
                              Text(
                                // i18n-dynamic-only
                                '${movement.envelopeName} +${_formatFrenchMoney(movement.amount)}',
                              ),
                          Text(
                            TransactionsWords.of(
                              context,
                            ).format('transactions.reversal.already_net', {
                              'reversed': _formatFrenchMoney(
                                item.reversedAmount,
                              ),
                              'net': _formatFrenchMoney(item.netAmount),
                            }),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          if (kind == _SettlementHistoryKind.recovery &&
                              item.reversibleAmount.minorUnits > 0)
                            Text(
                              TransactionsWords.of(context).text(
                                'transactions.reversal.recovery_negative_warning',
                              ),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          if (item.reversibleAmount.minorUnits > 0)
                            Wrap(
                              spacing: AppSpacing.xs,
                              children: [
                                OutlinedButton(
                                  onPressed: () => _openReversal(
                                    context,
                                    ref,
                                    item,
                                    isFull: false,
                                  ),
                                  child: Text(
                                    TransactionsWords.of(
                                      context,
                                    ).text('transactions.correct'),
                                  ),
                                ),
                                FilledButton(
                                  onPressed: () => _openReversal(
                                    context,
                                    ref,
                                    item,
                                    isFull: true,
                                  ),
                                  child: Text(
                                    TransactionsWords.of(
                                      context,
                                    ).text('transactions.cancel'),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                  for (final reversal in item.reversals) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Card(
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              TransactionsWords.of(context).text(
                                kind == _SettlementHistoryKind.debt
                                    ? 'transactions.detail.corrected_settlement'
                                    : 'transactions.detail.corrected_collection',
                              ),
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(_formatDateTime(reversal.recordedAt)),
                            Text(
                              TransactionsWords.of(context).format(
                                'transactions.reversal.amount',
                                {'value': _formatFrenchMoney(reversal.amount)},
                              ),
                            ),
                            Text(
                              TransactionsWords.of(context).format(
                                'transactions.detail.corrected_by',
                                {'value': reversal.actor.displayName},
                              ),
                            ),
                            for (final movement in reversal.envelopeMovements)
                              Text(
                                // i18n-dynamic-only
                                '${movement.envelopeName} -${_formatFrenchMoney(movement.amount)}',
                              ),
                            Text(
                              TransactionsWords.of(context).format(
                                'transactions.detail.reason',
                                {'value': reversal.reason},
                              ),
                            ),
                            if (reversal.notes != null &&
                                reversal.notes!.trim().isNotEmpty)
                              Text(
                                TransactionsWords.of(context).format(
                                  'transactions.detail.notes',
                                  {'value': reversal.notes!},
                                ),
                              ),
                            Text(
                              TransactionsWords.of(
                                context,
                              ).format('transactions.reversal.net_after', {
                                'value': _formatFrenchMoney(
                                  reversal.netAmountAfter,
                                ),
                              }),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xs),
                ],
                for (final writeoff in historyItems.writeoffs) ...[
                  Card(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_formatDateTime(writeoff.recordedAt)),
                          Text(
                            TransactionsWords.of(
                              context,
                            ).text('transactions.detail.writeoff'),
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          Text(
                            TransactionsWords.of(context).format(
                              'transactions.detail.written_off_amount',
                              {'value': _formatFrenchMoney(writeoff.amount)},
                            ),
                          ),
                          Text(
                            TransactionsWords.of(context).format(
                              'transactions.detail.performed_by',
                              {'value': writeoff.actor.displayName},
                            ),
                          ),
                          Text(
                            TransactionsWords.of(context).format(
                              'transactions.detail.reason',
                              {'value': writeoff.reason},
                            ),
                          ),
                          if (writeoff.notes != null &&
                              writeoff.notes!.trim().isNotEmpty)
                            Text(
                              TransactionsWords.of(context).format(
                                'transactions.detail.notes',
                                {'value': writeoff.notes!},
                              ),
                            ),
                          if (writeoff.reversals.isNotEmpty)
                            Text(
                              TransactionsWords.of(context).format(
                                'transactions.reversal.writeoff_balances',
                                {
                                  'reversed': _formatFrenchMoney(
                                    writeoff.reversedAmount,
                                  ),
                                  'reversible': _formatFrenchMoney(
                                    writeoff.reversibleAmount,
                                  ),
                                },
                              ),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          if (writeoff.reversibleAmount.minorUnits > 0)
                            Padding(
                              padding: const EdgeInsets.only(
                                top: AppSpacing.xs,
                              ),
                              child: OutlinedButton(
                                key: Key('reverse-writeoff-${writeoff.id}'),
                                onPressed: () => _openWriteoffReversal(
                                  context,
                                  ref,
                                  writeoff,
                                ),
                                child: Text(
                                  TransactionsWords.of(
                                    context,
                                  ).text('transactions.cancel_writeoff'),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  for (final reversal in writeoff.reversals) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Card(
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              TransactionsWords.of(context).text(
                                'transactions.reversal.writeoff_history_title',
                              ),
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(_formatDateTime(reversal.recordedAt)),
                            Text(
                              TransactionsWords.of(context).format(
                                'transactions.reversal.amount',
                                {'value': _formatFrenchMoney(reversal.amount)},
                              ),
                            ),
                            Text(
                              TransactionsWords.of(context).format(
                                'transactions.detail.corrected_by',
                                {'value': reversal.actor.displayName},
                              ),
                            ),
                            Text(
                              TransactionsWords.of(context).format(
                                'transactions.detail.reason',
                                {'value': reversal.reason},
                              ),
                            ),
                            if (reversal.notes != null &&
                                reversal.notes!.trim().isNotEmpty)
                              Text(
                                TransactionsWords.of(context).format(
                                  'transactions.detail.notes',
                                  {'value': reversal.notes!},
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xs),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(TransactionsWords.of(context).text('transactions.close')),
        ),
      ],
    );
  }

  Future<void> _openReversal(
    BuildContext context,
    WidgetRef ref,
    RemoteSettlementHistoryItem item, {
    required bool isFull,
  }) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) =>
          _SettlementReversalDialog(item: item, kind: kind, isFull: isFull),
    );
    if (changed == true) {
      ref.invalidate(obligationSettlementHistoryProvider(obligationId));
      ref.invalidate(remoteDebtBalancesProvider);
      ref.invalidate(remoteReceivableBalancesProvider);
      ref.invalidate(remoteTransactionsProvider);
      ref.invalidate(remoteAccountBalancesProvider);
      ref.invalidate(remoteEnvelopeBalancesProvider);
      ref.invalidate(remoteEnvelopeHistoryProvider);
    }
  }

  Future<void> _openWriteoffReversal(
    BuildContext context,
    WidgetRef ref,
    RemoteObligationWriteoffHistoryItem writeoff,
  ) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _WriteoffReversalDialog(
        kind: switch (kind) {
          _SettlementHistoryKind.debt => _WriteoffKind.debt,
          _SettlementHistoryKind.income => _WriteoffKind.income,
          _SettlementHistoryKind.recovery => _WriteoffKind.recovery,
        },
        writeoff: writeoff,
      ),
    );
    if (changed == true) {
      ref.invalidate(obligationSettlementHistoryProvider(obligationId));
      ref.invalidate(remoteDebtBalancesProvider);
      ref.invalidate(remoteReceivableBalancesProvider);
      ref.invalidate(remoteTransactionsProvider);
      ref.invalidate(remoteAccountBalancesProvider);
      ref.invalidate(remoteEnvelopeBalancesProvider);
      ref.invalidate(remoteEnvelopeHistoryProvider);
    }
  }
}

class _SettlementReversalDialog extends ConsumerStatefulWidget {
  const _SettlementReversalDialog({
    required this.item,
    required this.kind,
    required this.isFull,
  });

  final RemoteSettlementHistoryItem item;
  final _SettlementHistoryKind kind;
  final bool isFull;

  @override
  ConsumerState<_SettlementReversalDialog> createState() =>
      _SettlementReversalDialogState();
}

class _SettlementReversalDialogState
    extends ConsumerState<_SettlementReversalDialog> {
  late final TextEditingController _amount;
  final _reason = TextEditingController();
  final _notes = TextEditingController();
  late final List<TextEditingController> _movementAmounts;
  final _idempotencyKey = _newIdempotencyKey();
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(
      text: _formatFrenchMoney(
        widget.item.reversibleAmount,
      ).replaceAll(' MAD', '').replaceAll(' ', '').replaceAll(',', '.'),
    );
    _movementAmounts = widget.item.envelopeMovements
        .map((movement) => TextEditingController(text: '0'))
        .toList();
  }

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    _notes.dispose();
    for (final controller in _movementAmounts) {
      controller.dispose();
    }
    super.dispose();
  }

  int get _amountCents => _madToCents(_amount.text) ?? 0;

  Future<void> _submit() async {
    final amount = Money.fromMinorUnits(_amountCents);
    if (_amountCents <= 0 ||
        _amountCents > widget.item.reversibleAmount.minorUnits ||
        _reason.text.trim().isEmpty) {
      setState(
        () => _error = TransactionsWords.of(
          context,
        ).text('transactions.reversal.input_error'),
      );
      return;
    }
    final allocations = <FinancialEventAllocation>[];
    if (widget.kind == _SettlementHistoryKind.income) {
      for (
        var index = 0;
        index < widget.item.envelopeMovements.length;
        index++
      ) {
        final cents = _madToCents(_movementAmounts[index].text) ?? 0;
        if (cents > 0) {
          allocations.add(
            FinancialEventAllocation(
              envelopeId: widget.item.envelopeMovements[index].id,
              amount: Money.fromMinorUnits(cents).dirhams,
            ),
          );
        }
      }
      final total = allocations.fold<int>(
        0,
        (sum, allocation) =>
            sum + Money.fromDirhams(allocation.amount).minorUnits,
      );
      if (total != _amountCents) {
        setState(
          () => _error = TransactionsWords.of(
            context,
          ).text('transactions.reversal.allocation_exact_error'),
        );
        return;
      }
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final repository = await ref.read(
        financialEventRepositoryProvider.future,
      );
      switch (widget.kind) {
        case _SettlementHistoryKind.debt:
          await repository.reverseDebtSettlement(
            sourceSettlementId: widget.item.id,
            occurredAt: DateTime.now(),
            amount: amount,
            reason: _reason.text,
            notes: _notes.text,
            idempotencyKey: _idempotencyKey,
          );
        case _SettlementHistoryKind.income:
          await repository.reverseIncomeReceivableSettlement(
            sourceSettlementId: widget.item.id,
            occurredAt: DateTime.now(),
            amount: amount,
            reason: _reason.text,
            envelopeReversals: allocations,
            notes: _notes.text,
            idempotencyKey: _idempotencyKey,
          );
        case _SettlementHistoryKind.recovery:
          await repository.reverseRecoverySettlement(
            sourceSettlementId: widget.item.id,
            occurredAt: DateTime.now(),
            amount: amount,
            reason: _reason.text,
            notes: _notes.text,
            idempotencyKey: _idempotencyKey,
          );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() => _error = _financialErrorMessage(context, error));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      TransactionsWords.of(context).text(
        widget.isFull
            ? 'transactions.reversal.cancel_settlement'
            : 'transactions.reversal.correct_settlement',
      ),
    ),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              TransactionsWords.of(context).format(
                'transactions.reversal.reversible',
                {'value': _formatFrenchMoney(widget.item.reversibleAmount)},
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              controller: _amount,
              enabled: !_submitting && !widget.isFull,
              decoration: InputDecoration(
                labelText: TransactionsWords.of(
                  context,
                ).text('transactions.reversal.amount_required'),
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              controller: _reason,
              enabled: !_submitting,
              decoration: InputDecoration(
                labelText: TransactionsWords.of(
                  context,
                ).text('transactions.reason_required'),
              ),
            ),
            if (widget.kind == _SettlementHistoryKind.income) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                TransactionsWords.of(
                  context,
                ).text('transactions.reversal.exact_allocation'),
              ),
              for (
                var index = 0;
                index < widget.item.envelopeMovements.length;
                index++
              )
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: TextFormField(
                    controller: _movementAmounts[index],
                    enabled: !_submitting,
                    decoration: InputDecoration(
                      labelText:
                          '${widget.item.envelopeMovements[index].envelopeName} (MAD)',
                      helperText: TransactionsWords.of(context)
                          .format('transactions.maximum', {
                            'value': _formatFrenchMoney(
                              widget.item.envelopeMovements[index].amount,
                            ),
                          }),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                ),
            ],
            if (widget.kind == _SettlementHistoryKind.recovery) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                TransactionsWords.of(
                  context,
                ).text('transactions.reversal.recovery_envelope'),
              ),
              Text(
                TransactionsWords.of(
                  context,
                ).text('transactions.reversal.negative_balance'),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              controller: _notes,
              enabled: !_submitting,
              decoration: InputDecoration(
                labelText: TransactionsWords.of(
                  context,
                ).text('transactions.notes'),
              ),
              maxLines: 2,
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
    actions: [
      TextButton(
        onPressed: _submitting ? null : () => Navigator.pop(context),
        child: Text(TransactionsWords.of(context).text('transactions.cancel')),
      ),
      FilledButton(
        onPressed: _submitting ? null : _submit,
        child: Text(_submitting ? 'Validation…' : 'Confirmer'),
      ),
    ],
  );
}

enum _WriteoffKind { debt, income, recovery }

class _WriteoffReversalDialog extends ConsumerStatefulWidget {
  const _WriteoffReversalDialog({required this.kind, required this.writeoff});

  final _WriteoffKind kind;
  final RemoteObligationWriteoffHistoryItem writeoff;

  @override
  ConsumerState<_WriteoffReversalDialog> createState() =>
      _WriteoffReversalDialogState();
}

class _WriteoffReversalDialogState
    extends ConsumerState<_WriteoffReversalDialog> {
  late final TextEditingController _amount;
  final _reason = TextEditingController();
  final _notes = TextEditingController();
  final _idempotencyKey = _newIdempotencyKey();
  String? _error;
  var _submitting = false;

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(
      text: widget.writeoff.reversibleAmount.dirhams.toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    _notes.dispose();
    super.dispose();
  }

  int get _amountCents => _madToCents(_amount.text) ?? 0;

  Future<void> _submit() async {
    if (_submitting) return;
    final amount = Money.fromMinorUnits(_amountCents);
    if (amount.minorUnits <= 0 ||
        amount.minorUnits > widget.writeoff.reversibleAmount.minorUnits) {
      setState(
        () => _error = TransactionsWords.of(
          context,
        ).text('transactions.reversal.writeoff_limit_error'),
      );
      return;
    }
    if (_reason.text.trim().isEmpty) {
      setState(
        () => _error = TransactionsWords.of(
          context,
        ).text('transactions.reason_missing'),
      );
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final repository = await ref.read(
        financialEventRepositoryProvider.future,
      );
      switch (widget.kind) {
        case _WriteoffKind.debt:
          await repository.reverseDebtWriteoff(
            sourceAdjustmentId: widget.writeoff.id,
            occurredAt: DateTime.now(),
            amount: amount,
            reason: _reason.text,
            notes: _notes.text,
            idempotencyKey: _idempotencyKey,
          );
        case _WriteoffKind.income:
          await repository.reverseIncomeReceivableWriteoff(
            sourceAdjustmentId: widget.writeoff.id,
            occurredAt: DateTime.now(),
            amount: amount,
            reason: _reason.text,
            notes: _notes.text,
            idempotencyKey: _idempotencyKey,
          );
        case _WriteoffKind.recovery:
          await repository.reverseRecoveryWriteoff(
            sourceAdjustmentId: widget.writeoff.id,
            occurredAt: DateTime.now(),
            amount: amount,
            reason: _reason.text,
            notes: _notes.text,
            idempotencyKey: _idempotencyKey,
          );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() => _error = _financialErrorMessage(context, error));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      TransactionsWords.of(context).text('transactions.cancel_writeoff'),
    ),
    content: SizedBox(
      width: 500,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              TransactionsWords.of(context).format(
                'transactions.reversal.writeoff_affected',
                {'value': _formatFrenchMoney(widget.writeoff.amount)},
              ),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            Text(
              TransactionsWords.of(context).format(
                'transactions.reversal.already',
                {'value': _formatFrenchMoney(widget.writeoff.reversedAmount)},
              ),
            ),
            Text(
              TransactionsWords.of(context).format(
                'transactions.reversal.still_possible',
                {'value': _formatFrenchMoney(widget.writeoff.reversibleAmount)},
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              key: const Key('writeoff-reversal-amount-field'),
              controller: _amount,
              enabled: !_submitting,
              onChanged: (_) => setState(() => _error = null),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: TransactionsWords.of(
                  context,
                ).text('transactions.reversal.amount_required'),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              key: const Key('writeoff-reversal-reason-field'),
              controller: _reason,
              enabled: !_submitting,
              decoration: InputDecoration(
                labelText: TransactionsWords.of(
                  context,
                ).text('transactions.reason_required'),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              key: const Key('writeoff-reversal-notes-field'),
              controller: _notes,
              enabled: !_submitting,
              decoration: InputDecoration(
                labelText: TransactionsWords.of(
                  context,
                ).text('transactions.notes'),
              ),
              maxLines: 2,
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
    actions: [
      TextButton(
        onPressed: _submitting ? null : () => Navigator.of(context).pop(),
        child: Text(TransactionsWords.of(context).text('transactions.cancel')),
      ),
      FilledButton(
        key: const Key('writeoff-reversal-submit-button'),
        onPressed: _submitting ? null : _submit,
        child: Text(
          TransactionsWords.of(context).text(
            _submitting ? 'transactions.validating' : 'transactions.validate',
          ),
        ),
      ),
    ],
  );
}

class _WriteoffDialog extends ConsumerStatefulWidget {
  const _WriteoffDialog({
    required this.kind,
    required this.obligationId,
    required this.description,
    required this.counterparty,
    required this.remaining,
  });

  final _WriteoffKind kind;
  final String obligationId;
  final String description;
  final String? counterparty;
  final Money remaining;

  @override
  ConsumerState<_WriteoffDialog> createState() => _WriteoffDialogState();
}

class _WriteoffDialogState extends ConsumerState<_WriteoffDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _reason = TextEditingController();
  final _notes = TextEditingController();
  final _idempotencyKey = _newIdempotencyKey();
  String? _error;
  var _submitting = false;

  bool get _isRecovery => widget.kind == _WriteoffKind.recovery;
  int get _amountCents => _madToCents(_amount.text) ?? 0;

  @override
  void initState() {
    super.initState();
    _amount.text = widget.remaining.dirhams.toStringAsFixed(2);
  }

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || !_formKey.currentState!.validate()) return;
    final amount = Money.fromMinorUnits(_amountCents);
    if (amount.minorUnits <= 0 ||
        amount.minorUnits > widget.remaining.minorUnits) {
      setState(
        () => _error = TransactionsWords.of(
          context,
        ).text('transactions.writeoff_limit_error'),
      );
      return;
    }
    if (_reason.text.trim().isEmpty) {
      setState(
        () => _error = TransactionsWords.of(
          context,
        ).text('transactions.reason_missing'),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          TransactionsWords.of(context).text('transactions.confirm_writeoff'),
        ),
        content: Text(
          TransactionsWords.of(
            context,
          ).format('transactions.writeoff_confirmation', {
            'description': widget.description,
            'amount': _formatFrenchMoney(amount),
            'remaining': _formatFrenchMoney(
              Money.fromMinorUnits(
                widget.remaining.minorUnits - amount.minorUnits,
              ),
            ),
          }),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              TransactionsWords.of(context).text('transactions.cancel'),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              TransactionsWords.of(
                context,
              ).text('transactions.confirm_writeoff'),
            ),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final repository = await ref.read(
        financialEventRepositoryProvider.future,
      );
      switch (widget.kind) {
        case _WriteoffKind.debt:
          await repository.writeOffDebt(
            obligationId: widget.obligationId,
            occurredAt: DateTime.now(),
            amount: amount,
            remaining: widget.remaining,
            reason: _reason.text,
            notes: _notes.text,
            idempotencyKey: _idempotencyKey,
          );
        case _WriteoffKind.income:
          await repository.writeOffIncomeReceivable(
            obligationId: widget.obligationId,
            occurredAt: DateTime.now(),
            amount: amount,
            remaining: widget.remaining,
            reason: _reason.text,
            notes: _notes.text,
            idempotencyKey: _idempotencyKey,
          );
        case _WriteoffKind.recovery:
          await repository.writeOffRecovery(
            obligationId: widget.obligationId,
            occurredAt: DateTime.now(),
            amount: amount,
            remaining: widget.remaining,
            reason: _reason.text,
            notes: _notes.text,
            idempotencyKey: _idempotencyKey,
          );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (exception) {
      if (mounted) {
        setState(() => _error = _financialErrorMessage(context, exception));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      _isRecovery
          ? TransactionsWords.of(
              context,
            ).text('transactions.writeoff_recovery_title')
          : TransactionsWords.of(
              context,
            ).format('transactions.writeoff_title', {
              'kind': TransactionsWords.of(context).text(
                widget.kind == _WriteoffKind.debt
                    ? 'transactions.debt_singular'
                    : 'transactions.receivable_singular',
              ),
            }),
    ),
    content: SizedBox(
      width: 500,
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.description,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (widget.counterparty != null)
                Text(
                  TransactionsWords.of(context).format(
                    _isRecovery || widget.kind != _WriteoffKind.debt
                        ? 'transactions.detail.debtor'
                        : 'transactions.creditor_value',
                    {'value': widget.counterparty!},
                  ),
                ),
              Text(
                TransactionsWords.of(context).format('transactions.remaining', {
                  'value': _formatFrenchMoney(widget.remaining),
                }),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: TransactionsWords.of(
                    context,
                  ).text('transactions.writeoff_amount_required'),
                ),
                validator: (value) => (_madToCents(value ?? '') ?? 0) <= 0
                    ? TransactionsWords.of(
                        context,
                      ).text('transactions.amount_invalid')
                    : null,
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _reason,
                decoration: InputDecoration(
                  labelText: TransactionsWords.of(
                    context,
                  ).text('transactions.reason_required'),
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? TransactionsWords.of(
                        context,
                      ).text('transactions.reason_missing')
                    : null,
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _notes,
                decoration: InputDecoration(
                  labelText: TransactionsWords.of(
                    context,
                  ).text('transactions.notes'),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                _isRecovery
                    ? TransactionsWords.of(
                        context,
                      ).text('transactions.writeoff_recovery_warning')
                    : widget.kind == _WriteoffKind.debt
                    ? TransactionsWords.of(
                        context,
                      ).text('transactions.writeoff_debt_warning')
                    : TransactionsWords.of(
                        context,
                      ).text('transactions.writeoff_receivable_warning'),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Text(
                    _error!,
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
    actions: [
      TextButton(
        onPressed: _submitting ? null : () => Navigator.pop(context),
        child: Text(TransactionsWords.of(context).text('transactions.cancel')),
      ),
      FilledButton(
        onPressed: _submitting ? null : _submit,
        child: Text(
          _submitting
              ? TransactionsWords.of(context).text('transactions.validating')
              : TransactionsWords.of(context).text('transactions.write_off'),
        ),
      ),
    ],
  );
}

class _ReceivableSettlementDialog extends ConsumerStatefulWidget {
  const _ReceivableSettlementDialog({
    required this.receivable,
    required this.accounts,
    required this.envelopes,
  });

  final RemoteReceivableBalance receivable;
  final List<FinancialAccount> accounts;
  final List<RemoteEnvelopeBalance> envelopes;

  @override
  ConsumerState<_ReceivableSettlementDialog> createState() =>
      _ReceivableSettlementDialogState();
}

class _ReceivableSettlementDialogState
    extends ConsumerState<_ReceivableSettlementDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _notes = TextEditingController();
  final _splitRows = <_AllocationRow>[];
  final _idempotencyKey = _newIdempotencyKey();
  String? _accountId;
  String? _error;
  var _submitting = false;

  @override
  void initState() {
    super.initState();
    _amount.text = widget.receivable.remainingAmount.dirhams.toStringAsFixed(2);
  }

  @override
  void dispose() {
    _amount.dispose();
    _notes.dispose();
    for (final row in _splitRows) {
      row.dispose();
    }
    super.dispose();
  }

  bool get _isIncome => widget.receivable.kind == 'income';
  RemoteEnvelopeBalance? get _recoverySourceEnvelope {
    final sourceId = widget.receivable.recoverySourceEnvelopeId;
    if (sourceId == null) return null;
    for (final envelope in widget.envelopes) {
      if (envelope.id == sourceId) return envelope;
    }
    return null;
  }

  String? get _recoverySourceEnvelopeName => _recoverySourceEnvelope?.name;
  int get _amountCents => _madToCents(_amount.text) ?? 0;
  int get _splitCents => _splitRows.fold(
    0,
    (sum, row) => sum + (_madToCents(row.amount.text) ?? 0),
  );
  int get _remainingCents => _amountCents - _splitCents;
  bool get _allocationsAreValid {
    if (!_isIncome) return true;
    final seen = <String>{};
    for (final row in _splitRows) {
      if (row.envelopeId == null ||
          (_madToCents(row.amount.text) ?? 0) <= 0 ||
          !seen.add(row.envelopeId!)) {
        return false;
      }
    }
    return _splitCents <= _amountCents;
  }

  List<FinancialEventAllocation> _allocations() => _splitRows
      .map(
        (row) => FinancialEventAllocation(
          envelopeId: row.envelopeId!,
          amount: Money.fromMinorUnits(
            _madToCents(row.amount.text) ?? 0,
          ).dirhams,
        ),
      )
      .toList(growable: false);

  void _addSplitRow() => setState(() => _splitRows.add(_AllocationRow()));

  void _removeSplitRow(_AllocationRow row) {
    setState(() {
      _splitRows.remove(row);
      row.dispose();
    });
  }

  Future<void> _submit() async {
    if (_submitting || !_formKey.currentState!.validate()) return;
    final cents = _amountCents;
    if (cents <= 0 || cents > widget.receivable.remainingAmount.minorUnits) {
      setState(
        () => _error = TransactionsWords.of(
          context,
        ).text('transactions.collection_limit_error'),
      );
      return;
    }
    if (_accountId == null) {
      setState(
        () => _error = TransactionsWords.of(
          context,
        ).text('transactions.choose_credit_account'),
      );
      return;
    }
    if (!_allocationsAreValid) {
      setState(
        () => _error = _splitCents > cents
            ? TransactionsWords.of(
                context,
              ).text('transactions.collection_allocation_error')
            : TransactionsWords.of(
                context,
              ).text('transactions.unique_allocation_error'),
      );
      return;
    }
    final allocations = _isIncome
        ? _allocations()
        : const <FinancialEventAllocation>[];
    final account = widget.accounts.firstWhere((item) => item.id == _accountId);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _ReceivableSettlementConfirmationDialog(
        amount: Money.fromMinorUnits(cents),
        accountName: account.name,
        allocations: allocations,
        envelopes: widget.envelopes,
        recoveryEnvelopeName: _isIncome ? null : _recoverySourceEnvelopeName,
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final repository = await ref.read(
        financialEventRepositoryProvider.future,
      );
      final details = 'Encaissement : ${widget.receivable.description}';
      if (widget.receivable.kind == 'recovery') {
        await repository.settleRecoveryReceivable(
          obligationId: widget.receivable.id,
          occurredAt: DateTime.now(),
          description: details,
          amount: Money.fromMinorUnits(cents),
          remaining: widget.receivable.remainingAmount,
          destinationAccountId: _accountId!,
          notes: _notes.text,
          idempotencyKey: _idempotencyKey,
        );
      } else {
        await repository.settleIncomeReceivable(
          obligationId: widget.receivable.id,
          occurredAt: DateTime.now(),
          description: details,
          amount: Money.fromMinorUnits(cents),
          remaining: widget.receivable.remainingAmount,
          destinationAccountId: _accountId!,
          allocations: allocations,
          notes: _notes.text,
          idempotencyKey: _idempotencyKey,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (exception) {
      if (mounted) {
        setState(() => _error = _financialErrorMessage(context, exception));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    InputDecoration fieldDecoration(String label) => InputDecoration(
      labelText: label,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
    );
    return AlertDialog(
      title: Text(
        TransactionsWords.of(context).text('transactions.collect_receivable'),
      ),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.receivable.description,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  TransactionsWords.of(
                    context,
                  ).format('transactions.remaining_to_collect', {
                    'value': _formatFrenchMoney(
                      widget.receivable.remainingAmount,
                    ),
                  }),
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _amount,
                  onChanged: (_) => setState(() {}),
                  decoration: fieldDecoration(
                    TransactionsWords.of(
                      context,
                    ).text('transactions.collected_amount_required'),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: (value) => (_madToCents(value ?? '') ?? 0) <= 0
                      ? TransactionsWords.of(
                          context,
                        ).text('transactions.amount_invalid')
                      : null,
                ),
                const SizedBox(height: AppSpacing.sm),
                _AccountSelector(
                  label: TransactionsWords.of(
                    context,
                  ).text('transactions.credit_account_required'),
                  decoration: fieldDecoration(
                    TransactionsWords.of(
                      context,
                    ).text('transactions.credit_account_required'),
                  ),
                  accounts: widget.accounts,
                  value: _accountId,
                  onChanged: _submitting
                      ? null
                      : (value) => setState(() => _accountId = value),
                ),
                if (!_isIncome && _recoverySourceEnvelopeName != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    TransactionsWords.of(
                      context,
                    ).text('transactions.refund_expense'),
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    TransactionsWords.of(context).format(
                      'transactions.restored_envelope',
                      {'value': _recoverySourceEnvelopeName!},
                    ),
                  ),
                  Text(
                    TransactionsWords.of(
                      context,
                    ).format('transactions.restored_amount', {
                      'value': _formatFrenchMoney(
                        Money.fromMinorUnits(_amountCents),
                      ),
                    }),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    TransactionsWords.of(
                      context,
                    ).text('transactions.refund_envelope_hint'),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                if (_isIncome) ...[
                  const SizedBox(height: AppSpacing.md),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      TransactionsWords.of(
                        context,
                      ).text('transactions.collection_allocation'),
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  ..._splitRows.asMap().entries.map(
                    (entry) => _SplitAllocationInput(
                      key: Key('receivable-allocation-row-${entry.key}'),
                      row: entry.value,
                      envelopes: widget.envelopes,
                      amountFieldKey: Key(
                        'receivable-envelope-amount-${entry.key}',
                      ),
                      excludedEnvelopeIds: _splitRows
                          .where((row) => row != entry.value)
                          .map((row) => row.envelopeId)
                          .whereType<String>()
                          .toSet(),
                      onChanged: () => setState(() {}),
                      onRemove: _submitting
                          ? null
                          : () => _removeSplitRow(entry.value),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const Key('add-receivable-envelope-row'),
                      onPressed: _submitting ? null : _addSplitRow,
                      icon: const Icon(Icons.add),
                      label: Text(
                        TransactionsWords.of(
                          context,
                        ).text('transactions.add_envelope'),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      TransactionsWords.of(
                        context,
                      ).format('transactions.collection_summary', {
                        'collected': _formatFrenchMoney(
                          Money.fromMinorUnits(_amountCents),
                        ),
                        'allocated': _formatFrenchMoney(
                          Money.fromMinorUnits(_splitCents),
                        ),
                        'remaining': _formatFrenchMoney(
                          Money.fromMinorUnits(_remainingCents),
                        ),
                      }),
                    ),
                  ),
                  if (_remainingCents > 0)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        TransactionsWords.of(
                          context,
                        ).format('transactions.auto_allocate_remaining', {
                          'value': _formatFrenchMoney(
                            Money.fromMinorUnits(_remainingCents),
                          ),
                        }),
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  if (_splitCents > _amountCents)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        TransactionsWords.of(
                          context,
                        ).text('transactions.collection_allocation_error'),
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ),
                ],
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: _notes,
                  decoration: fieldDecoration(
                    TransactionsWords.of(context).text('transactions.notes'),
                  ),
                  maxLines: 2,
                ),
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    _error!,
                    style: TextStyle(color: theme.colorScheme.error),
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
          child: Text(
            TransactionsWords.of(context).text('transactions.cancel'),
          ),
        ),
        FilledButton(
          onPressed:
              _submitting ||
                  _amountCents <= 0 ||
                  _accountId == null ||
                  !_allocationsAreValid
              ? null
              : _submit,
          child: Text(
            _submitting
                ? TransactionsWords.of(context).text('transactions.validating')
                : TransactionsWords.of(context).text('transactions.collect'),
          ),
        ),
      ],
    );
  }
}

class _ReceivableSettlementConfirmationDialog extends StatelessWidget {
  const _ReceivableSettlementConfirmationDialog({
    required this.amount,
    required this.accountName,
    required this.allocations,
    required this.envelopes,
    this.recoveryEnvelopeName,
  });

  final Money amount;
  final String accountName;
  final List<FinancialEventAllocation> allocations;
  final List<RemoteEnvelopeBalance> envelopes;
  final String? recoveryEnvelopeName;

  @override
  Widget build(BuildContext context) {
    final allocatedCents = allocations.fold<int>(
      0,
      (sum, allocation) =>
          sum + Money.fromDirhams(allocation.amount).minorUnits,
    );
    final remainder = Money.fromMinorUnits(amount.minorUnits - allocatedCents);
    String envelopeName(String id) => envelopes
        .firstWhere(
          (envelope) => envelope.id == id,
          orElse: () => throw StateError('Enveloppe de confirmation absente.'),
        )
        .name;
    return AlertDialog(
      title: Text(
        TransactionsWords.of(context).format('transactions.collect_amount', {
          'value': _formatFrenchMoney(amount),
        }),
      ),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              TransactionsWords.of(context).text(
                recoveryEnvelopeName == null
                    ? 'transactions.account_label'
                    : 'transactions.credited_account_label',
              ),
            ),
            Text(accountName, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: AppSpacing.md),
            if (recoveryEnvelopeName != null) ...[
              Text(
                TransactionsWords.of(
                  context,
                ).text('transactions.restored_envelope_label'),
              ),
              Text(
                recoveryEnvelopeName!,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              Text(
                TransactionsWords.of(context).format(
                  'transactions.restored_amount',
                  {'value': _formatFrenchMoney(amount)},
                ),
              ),
            ] else ...[
              Text(
                TransactionsWords.of(context).text('transactions.allocation'),
              ),
              for (final allocation in allocations)
                Text(
                  // i18n-dynamic-only
                  '→ ${envelopeName(allocation.envelopeId)} : '
                  '${_formatFrenchMoney(Money.fromDirhams(allocation.amount))}',
                ),
              if (remainder.minorUnits > 0)
                Text(
                  TransactionsWords.of(context).format(
                    'transactions.to_allocate',
                    {'value': _formatFrenchMoney(remainder)},
                  ),
                ),
            ],
            const SizedBox(height: AppSpacing.md),
            Text(
              TransactionsWords.of(context).text('transactions.no_new_income'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(
            TransactionsWords.of(context).text('transactions.cancel'),
          ),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(
            TransactionsWords.of(context).text('transactions.collect'),
          ),
        ),
      ],
    );
  }
}

String _recoverySourceLabel(
  BuildContext context,
  RecoveryExpenseSource source,
) {
  final envelope = source.envelopeName == null
      ? ''
      : ' • ${source.envelopeName}';
  final account = source.accountName == null ? '' : ' • ${source.accountName}';
  return TransactionsWords.of(
    context,
  ).format('transactions.recovery.source_summary', {
    'description': source.description,
    'date': _formatDate(source.occurredAt),
    'source': _formatFrenchMoney(source.sourceAmount),
    'committed': _formatFrenchMoney(source.committedAmount),
    'maximum': _formatFrenchMoney(source.maximumAmount),
    'account': account,
    'envelope': envelope,
  });
}

String _formatFrenchMoney(Money amount) {
  final cents = amount.minorUnits.abs();
  final whole = (cents ~/ 100).toString().replaceAllMapped(
    RegExp(r'(?<=\d)(?=(\d{3})+$)'),
    (_) => ' ',
  );
  return '${amount.minorUnits < 0 ? '-' : ''}$whole,${(cents % 100).toString().padLeft(2, '0')} MAD';
}

class _DebtSettlementDialog extends ConsumerStatefulWidget {
  const _DebtSettlementDialog({required this.debt, required this.accounts});
  final RemoteDebtBalance debt;
  final List<FinancialAccount> accounts;
  @override
  ConsumerState<_DebtSettlementDialog> createState() =>
      _DebtSettlementDialogState();
}

class _DebtSettlementDialogState extends ConsumerState<_DebtSettlementDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _description = TextEditingController();
  final _notes = TextEditingController();
  final _idempotencyKey = _newIdempotencyKey();
  String? _accountId;
  var _submitting = false;
  var _descriptionInitialized = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_descriptionInitialized) return;
    _description.text = TransactionsWords.of(context).format(
      'transactions.debt_payment_description',
      {'value': widget.debt.description},
    );
    _descriptionInitialized = true;
  }

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || !_formKey.currentState!.validate()) return;
    final cents = _madToCents(_amount.text) ?? 0;
    if (cents <= 0 || cents > widget.debt.remainingAmount.minorUnits) {
      setState(
        () => _error = TransactionsWords.of(
          context,
        ).text('transactions.debt_payment_limit_error'),
      );
      return;
    }
    if (_accountId == null) {
      setState(
        () => _error = TransactionsWords.of(
          context,
        ).text('transactions.choose_payment_account'),
      );
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final repository = await ref.read(
        financialEventRepositoryProvider.future,
      );
      await repository.settleDebt(
        obligationId: widget.debt.id,
        occurredAt: DateTime.now(),
        description: _description.text.trim(),
        amount: Money.fromMinorUnits(cents),
        remaining: widget.debt.remainingAmount,
        sourceAccountId: _accountId!,
        notes: _notes.text.trim(),
        idempotencyKey: _idempotencyKey,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() => _error = _financialErrorMessage(context, error));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    InputDecoration fieldDecoration(String label) => InputDecoration(
      labelText: label,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
    );
    final remaining = _formatDebtAmount(widget.debt.remainingAmount.minorUnits);

    return AlertDialog(
      title: Text(
        TransactionsWords.of(context).text('transactions.settle_debt'),
      ),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.debt.description,
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        TransactionsWords.of(
                          context,
                        ).format('transactions.creditor_value', {
                          'value':
                              widget.debt.creditorName ??
                              TransactionsWords.of(
                                context,
                              ).text('transactions.creditor_unknown'),
                        }),
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        TransactionsWords.of(context).format(
                          'transactions.remaining_to_settle',
                          {'value': '$remaining MAD'},
                        ),
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _amount,
                  decoration: fieldDecoration(
                    TransactionsWords.of(
                      context,
                    ).text('transactions.settle_amount_required'),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: (value) => (_madToCents(value ?? '') ?? 0) <= 0
                      ? TransactionsWords.of(
                          context,
                        ).text('transactions.amount_invalid')
                      : null,
                ),
                const SizedBox(height: AppSpacing.sm),
                _AccountSelector(
                  label: TransactionsWords.of(
                    context,
                  ).text('transactions.payment_account_required'),
                  decoration: fieldDecoration(
                    TransactionsWords.of(
                      context,
                    ).text('transactions.payment_account_required'),
                  ),
                  accounts: widget.accounts
                      .where((item) => !item.isArchived && !item.isSystem)
                      .toList(growable: false),
                  value: _accountId,
                  onChanged: _submitting
                      ? null
                      : (value) => setState(() => _accountId = value),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: _description,
                  decoration: fieldDecoration(
                    TransactionsWords.of(
                      context,
                    ).text('transactions.label_required'),
                  ),
                  validator: (value) => value?.trim().isEmpty ?? true
                      ? TransactionsWords.of(
                          context,
                        ).text('transactions.label_empty')
                      : null,
                ),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: _notes,
                  decoration: fieldDecoration(
                    TransactionsWords.of(context).text('transactions.notes'),
                  ),
                  maxLines: 2,
                ),
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    _error!,
                    style: TextStyle(color: theme.colorScheme.error),
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
          child: Text(
            TransactionsWords.of(context).text('transactions.cancel'),
          ),
        ),
        FilledButton(
          key: const Key('settle-debt-button'),
          onPressed: _submitting ? null : _submit,
          child: Text(
            _submitting
                ? TransactionsWords.of(context).text('transactions.validating')
                : TransactionsWords.of(context).text('transactions.settle'),
          ),
        ),
      ],
    );
  }

  String _formatDebtAmount(int cents) {
    final amount = cents.abs();
    final integral = (amount ~/ 100).toString().replaceAllMapped(
      RegExp(r'(?<=\d)(?=(\d{3})+$)'),
      (_) => ' ',
    );
    final decimal = (amount % 100).toString().padLeft(2, '0');
    return '${cents < 0 ? '-' : ''}$integral,$decimal';
  }
}

String _financialErrorMessage(BuildContext context, Object error) {
  final value = error.toString().toLowerCase();
  if (value.contains('write-off reversal') ||
      value.contains('writeoff reversal') ||
      value.contains('still reversible')) {
    return TransactionsWords.of(
      context,
    ).text('transactions.error.writeoff_not_reversible');
  }
  if (value.contains('write-off source') ||
      value.contains('source adjustment')) {
    return TransactionsWords.of(
      context,
    ).text('transactions.error.writeoff_unavailable');
  }
  if (value.contains('remaining') || value.contains('dépasse')) {
    return TransactionsWords.of(
      context,
    ).text('transactions.error.exceeds_remaining');
  }
  if (value.contains('network') || value.contains('socket')) {
    return TransactionsWords.of(context).text('transactions.error.network');
  }
  if (value.contains('account') || value.contains('compte')) {
    return TransactionsWords.of(context).text('transactions.error.account');
  }
  if (value.contains('envelope') || value.contains('enveloppe')) {
    return TransactionsWords.of(context).text('transactions.error.envelope');
  }
  return TransactionsWords.of(context).text('transactions.error.save');
}

String _newIdempotencyKey() {
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
