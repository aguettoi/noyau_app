import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../../core/theme/app_design_system.dart';
import '../../envelopes/application/providers/remote_envelopes_provider.dart';
import '../application/providers/remote_account_balances_provider.dart';
import '../application/providers/remote_accounts_provider.dart';
import '../application/providers/remote_transactions_provider.dart';
import '../application/providers/financial_event_provider.dart';
import '../application/providers/remote_debts_provider.dart';
import '../application/financial_event_contract.dart';
import '../domain/financial_account.dart';
import '../domain/transaction_draft.dart';
import '../domain/transaction_history_item.dart';

class TransactionsPage extends ConsumerStatefulWidget {
  const TransactionsPage({super.key});

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
  ) async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => _CreateTransactionDialog(
        accounts: accounts
            .where((account) => !account.isArchived && !account.isSystem)
            .toList(growable: false),
        envelopes: envelopes,
        onCreate: _create,
        onCreateDebt: _createDebt,
      ),
    );
    if (created == true && mounted) {
      ref.invalidate(remoteTransactionsProvider);
      ref.invalidate(remoteAccountBalancesProvider);
      ref.invalidate(remoteAccountsProvider);
      ref.invalidate(remoteEnvelopeBalancesProvider);
      ref.invalidate(remoteEnvelopeHistoryProvider);
      ref.invalidate(remoteEnvelopeMovementsProvider);
      ref.invalidate(remoteDebtBalancesProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Transaction validée dans le Grand Livre.'),
        ),
      );
    }
  }

  Future<void> _create(FinancialTransactionDraft draft) async {
    if (_creating) {
      return;
    }
    setState(() => _creating = true);
    try {
      if (draft.type == LedgerTransactionType.expense) {
        final repository = await ref.read(
          financialEventRepositoryProvider.future,
        );
        await repository.createCashExpense(
          occurredAt: draft.occurredAt,
          description: draft.description,
          amount: draft.amount,
          sourceAccountId: draft.sourceAccountId!,
          allocations: draft.envelopeAllocations
              .map(
                (allocation) => FinancialEventAllocation(
                  envelopeId: allocation.envelopeId,
                  amount: allocation.amount.dirhams,
                ),
              )
              .toList(growable: false),
          idempotencyKey: _expenseIdempotencyKey,
        );
        _expenseIdempotencyKey = _newIdempotencyKey();
      } else if (draft.type == LedgerTransactionType.income) {
        final repository = await ref.read(
          financialEventRepositoryProvider.future,
        );
        await repository.createCashIncome(
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
      } else if (draft.type == LedgerTransactionType.transfer) {
        final repository = await ref.read(
          financialEventRepositoryProvider.future,
        );
        await repository.createAccountTransfer(
          occurredAt: draft.occurredAt,
          description: draft.description,
          amount: draft.amount,
          sourceAccountId: draft.sourceAccountId!,
          destinationAccountId: draft.destinationAccountId!,
          idempotencyKey: _accountTransferIdempotencyKey,
          notes: draft.notes,
        );
        _accountTransferIdempotencyKey = _newIdempotencyKey();
      } else {
        await ref.read(createRemoteTransactionProvider)(draft);
      }
    } finally {
      if (mounted) {
        setState(() => _creating = false);
      }
    }
  }

  Future<void> _createDebt(_DebtExpenseSubmission submission) async {
    if (_creating) return;
    setState(() => _creating = true);
    try {
      final repository = await ref.read(
        financialEventRepositoryProvider.future,
      );
      await repository.createDebtExpense(
        occurredAt: submission.occurredAt,
        description: submission.description,
        amount: submission.amount,
        allocations: submission.allocations,
        creditorName: submission.creditorName,
        notes: submission.notes,
        idempotencyKey: _expenseIdempotencyKey,
      );
      _expenseIdempotencyKey = _newIdempotencyKey();
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final transactions = ref.watch(remoteTransactionsProvider);
    final accounts = ref.watch(remoteAccountsProvider);
    final envelopes = ref.watch(remoteEnvelopeBalancesProvider);
    final canOpen = accounts.hasValue && envelopes.hasValue && !_creating;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transactions'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => const DebtsPage())),
            child: const Text('Dettes'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ReceivablesPage()),
            ),
            child: const Text('Créances'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('add-transaction-button'),
        onPressed: canOpen
            ? () => _openCreateDialog(
                accounts.requireValue,
                envelopes.requireValue,
              )
            : null,
        icon: _creating
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add),
        label: const Text('Ajouter'),
      ),
      body: transactions.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: AppSpacing.page,
            child: Text('Impossible de lire le Grand Livre : $error'),
          ),
        ),
        data: (items) => _TransactionList(items: items),
      ),
    );
  }
}

class _TransactionList extends StatelessWidget {
  const _TransactionList({required this.items});

  final List<TransactionHistoryItem> items;

  @override
  Widget build(BuildContext context) => ListView(
    padding: AppSpacing.page,
    children: [
      Text('Grand Livre', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: AppSpacing.xs),
      const Text('Historique validé et immuable des opérations financières.'),
      const SizedBox(height: AppSpacing.lg),
      if (items.isEmpty)
        const Card(
          child: ListTile(
            leading: Icon(Icons.receipt_long_outlined),
            title: Text('Aucune transaction'),
            subtitle: Text('Ajoutez votre première opération financière.'),
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
              subtitle: Text(_historySubtitle(item)),
              trailing: Text('${item.amount.dirhams.toStringAsFixed(2)} MAD'),
            ),
          ),
        ),
      ),
    ],
  );
}

class _CreateTransactionDialog extends StatefulWidget {
  const _CreateTransactionDialog({
    required this.accounts,
    required this.envelopes,
    required this.onCreate,
    required this.onCreateDebt,
  });

  final List<FinancialAccount> accounts;
  final List<RemoteEnvelopeBalance> envelopes;
  final Future<void> Function(FinancialTransactionDraft draft) onCreate;
  final Future<void> Function(_DebtExpenseSubmission submission) onCreateDebt;

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
  String? _destinationAccountId;
  String? _singleEnvelopeId;
  var _splitExpense = false;
  var _expenseIsDebt = false;
  var _submitting = false;
  String? _error;

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
      setState(() => _error = 'Saisissez un montant positif valide en MAD.');
      return;
    }
    if (_isExpense && _splitExpense && _remainingCents != 0) {
      setState(() => _error = 'Le total ventilé doit égaler le montant.');
      return;
    }
    if (_isIncome && _splitCents > _amountCents) {
      setState(
        () => _error = 'Le total affecté ne peut pas dépasser le revenu.',
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
        await widget.onCreateDebt(
          _DebtExpenseSubmission(
            occurredAt: DateTime.now(),
            description: _description.text.trim(),
            amount: Money.fromMinorUnits(_amountCents),
            allocations: allocations,
            creditorName: _creditor.text.trim(),
            notes: _notes.text.trim(),
          ),
        );
        if (mounted) Navigator.of(context).pop(true);
      } catch (error) {
        if (mounted) setState(() => _error = _financialErrorMessage(error));
      } finally {
        if (mounted) setState(() => _submitting = false);
      }
      return;
    }
    final draft = FinancialTransactionDraft(
      type: _type,
      occurredAt: DateTime.now(),
      description: _description.text.trim(),
      amount: Money.fromMinorUnits(_amountCents),
      sourceAccountId: _needsSource ? _sourceAccountId : null,
      destinationAccountId: _needsDestination ? _destinationAccountId : null,
      direction: _direction,
      envelopeAllocations: _allocations(),
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
      await widget.onCreate(draft);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = _financialErrorMessage(error));
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Ajouter une transaction'),
    content: SizedBox(
      width: 480,
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          key: const Key('create-transaction-form-scroll'),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<LedgerTransactionType>(
                key: const Key('transaction-type-field'),
                initialValue: _type,
                decoration: const InputDecoration(labelText: 'Type *'),
                items:
                    const [
                          LedgerTransactionType.expense,
                          LedgerTransactionType.income,
                          LedgerTransactionType.transfer,
                          LedgerTransactionType.adjustment,
                        ]
                        .map(
                          (type) => DropdownMenuItem(
                            value: type,
                            child: Text(_labelFor(type)),
                          ),
                        )
                        .toList(growable: false),
                onChanged: _submitting ? null : (type) => _changeType(type!),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                key: const Key('transaction-description-field'),
                controller: _description,
                decoration: const InputDecoration(labelText: 'Libellé *'),
                validator: (value) => (value?.trim().isEmpty ?? true)
                    ? 'Le libellé est obligatoire.'
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
                decoration: const InputDecoration(labelText: 'Montant (MAD) *'),
                validator: (value) => (_madToCents(value ?? '') ?? 0) <= 0
                    ? 'Saisissez un montant positif valide.'
                    : null,
              ),
              if (_needsSource) ...[
                const SizedBox(height: AppSpacing.sm),
                _AccountSelector(
                  key: const Key('transaction-source-account-field'),
                  label: _type == LedgerTransactionType.transfer
                      ? 'Compte source *'
                      : 'Compte concerné *',
                  accounts: widget.accounts,
                  value: _sourceAccountId,
                  onChanged: _submitting
                      ? null
                      : (id) => setState(() => _sourceAccountId = id),
                ),
              ],
              if (_needsDestination) ...[
                const SizedBox(height: AppSpacing.sm),
                _AccountSelector(
                  key: const Key('transaction-destination-account-field'),
                  label: _type == LedgerTransactionType.transfer
                      ? 'Compte destination *'
                      : 'Compte encaissé *',
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
                  decoration: const InputDecoration(labelText: 'Sens *'),
                  items: const [
                    DropdownMenuItem(
                      value: BalanceDirection.increase,
                      child: Text('Augmenter le solde'),
                    ),
                    DropdownMenuItem(
                      value: BalanceDirection.decrease,
                      child: Text('Diminuer le solde'),
                    ),
                  ],
                  onChanged: _submitting
                      ? null
                      : (value) => setState(() => _direction = value!),
                ),
              ],
              if (_isIncome) ...[
                const SizedBox(height: AppSpacing.md),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Répartition du revenu',
                    style: TextStyle(fontWeight: FontWeight.w600),
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
                    label: const Text('Ajouter une enveloppe'),
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Revenu : ${_formatCents(_amountCents)} MAD • '
                    'Affecté : ${_formatCents(_splitCents)} MAD • '
                    'Reste à répartir : ${_formatCents(_remainingCents)} MAD',
                  ),
                ),
                if (_remainingCents > 0)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${_formatCents(_remainingCents)} MAD seront automatiquement '
                      'affectés à « À répartir ».',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                if (_splitCents > _amountCents)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Le total affecté ne peut pas dépasser le revenu.',
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
                  initialValue: _expenseIsDebt,
                  decoration: const InputDecoration(labelText: 'Paiement *'),
                  items: const [
                    DropdownMenuItem(
                      value: false,
                      child: Text('Payée maintenant'),
                    ),
                    DropdownMenuItem(
                      value: true,
                      child: Text('À payer plus tard / Dette'),
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
                    decoration: const InputDecoration(labelText: 'Créancier'),
                  ),
                ],
                SwitchListTile(
                  key: const Key('transaction-split-switch'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Ventiler sur plusieurs enveloppes'),
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
                    label: 'Enveloppe *',
                    envelopes: widget.envelopes,
                    value: _singleEnvelopeId,
                    onChanged: _submitting
                        ? null
                        : (id) => setState(() => _singleEnvelopeId = id),
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
                      label: const Text('Ajouter une enveloppe'),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Total ventilé : ${_formatCents(_splitCents)} MAD • Reste à affecter : ${_formatCents(_remainingCents)} MAD',
                    ),
                  ),
                ],
              ],
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                key: const Key('transaction-notes-field'),
                controller: _notes,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Notes'),
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
        child: const Text('Annuler'),
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
        child: Text(_submitting ? 'Validation…' : 'Valider'),
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
      label: 'Enveloppe *',
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
      decoration: const InputDecoration(labelText: 'MAD *'),
    );
    final removeButton = IconButton(
      onPressed: onRemove,
      constraints: const BoxConstraints.tightFor(
        width: _removeButtonWidth,
        height: 46,
      ),
      padding: EdgeInsets.zero,
      icon: const Icon(Icons.remove_circle_outline),
      tooltip: 'Supprimer cette enveloppe',
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

String _labelFor(LedgerTransactionType type) => switch (type) {
  LedgerTransactionType.expense => 'Dépense',
  LedgerTransactionType.income => 'Revenu',
  LedgerTransactionType.transfer => 'Virement interne',
  LedgerTransactionType.adjustment => 'Ajustement',
  LedgerTransactionType.openingBalance => 'Solde d’ouverture',
  LedgerTransactionType.correction => 'Correction',
  LedgerTransactionType.debtExpense => 'Dépense à payer',
  LedgerTransactionType.incomeReceivable => 'Revenu à encaisser',
  LedgerTransactionType.recovery => 'Remboursement à recevoir',
  LedgerTransactionType.recoveryReceivable => 'Remboursement à recevoir',
  LedgerTransactionType.debtSettlement => 'Paiement d’une dette',
  LedgerTransactionType.receivableSettlement => 'Encaissement d’une créance',
  LedgerTransactionType.recoverySettlement => 'Remboursement encaissé',
  LedgerTransactionType.allocation => 'Alimentation d’enveloppe',
  LedgerTransactionType.accountTransfer => 'Virement entre comptes',
  LedgerTransactionType.envelopeTransfer => 'Transfert entre enveloppes',
  LedgerTransactionType.unknown => 'Opération',
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
String _formatDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

String _formatDateTime(DateTime date) =>
    '${_formatDate(date)} • ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
String _formatCents(int cents) => (cents / 100).toStringAsFixed(2);
String _historySubtitle(TransactionHistoryItem item) {
  final needsRegularization =
      (item.type == LedgerTransactionType.expense ||
          item.type == LedgerTransactionType.income) &&
      !item.hasEnvelopeMovement;
  return '${_labelFor(item.type)} • ${_formatDate(item.occurredAt)}${needsRegularization ? ' • À régulariser' : ''}';
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

class _TransactionDetailDialog extends StatelessWidget {
  const _TransactionDetailDialog({required this.item});
  final TransactionHistoryItem item;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Détail de l’opération'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(item.description, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        Text('Type : ${_labelFor(item.type)}'),
        Text('Date : ${_formatDate(item.occurredAt)}'),
        Text('Montant : ${item.amount.dirhams.toStringAsFixed(2)} MAD'),
        Text(
          item.hasEnvelopeMovement
              ? 'Ventilation d’enveloppe enregistrée.'
              : 'Historique sans mouvement d’enveloppe.',
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Fermer'),
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
      appBar: AppBar(title: const Text('Dettes')),
      body: debts.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(
          child: Text('Impossible de charger les dettes pour le moment.'),
        ),
        data: (items) => ListView(
          padding: AppSpacing.page,
          children: [
            Text('Dettes', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: AppSpacing.sm),
            if (items.isEmpty)
              const Card(child: ListTile(title: Text('Aucune dette ouverte'))),
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
                          Text(debt.creditorName ?? 'Créancier non renseigné'),
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
                            label: 'Initial',
                            amount: debt.initialAmount,
                          ),
                          _AmountIndicator(
                            label: 'Réglé',
                            amount: debt.settledAmount,
                          ),
                          _AmountIndicator(
                            label: 'Abandonné',
                            amount: debt.writtenOffAmount,
                          ),
                          _AmountIndicator(
                            label: 'Restant',
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
                          label: const Text('Historique'),
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
                                  child: const Text(
                                    'Abandonner',
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
                                  child: const Text('Régler', softWrap: false),
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
          const SnackBar(content: Text('Règlement de dette enregistré.')),
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
          const SnackBar(content: Text('Abandon de dette enregistré.')),
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
  const ReceivablesPage({super.key});

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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Créance enregistrée.')));
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
          const SnackBar(content: Text('Encaissement de créance enregistré.')),
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
      appBar: AppBar(title: const Text('Créances')),
      body: receivables.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(
          child: Text('Impossible de charger les créances pour le moment.'),
        ),
        data: (items) => ListView(
          padding: AppSpacing.page,
          children: [
            Text('Créances', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: AppSpacing.sm),
            if (items.isEmpty)
              const Card(child: ListTile(title: Text('Aucune créance'))),
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
                            '${item.displayKind} · ${item.counterpartyName ?? 'Contrepartie non renseignée'}',
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
                            label: 'Initial',
                            amount: item.initialAmount,
                          ),
                          _AmountIndicator(
                            label: 'Encaissé',
                            amount: item.settledAmount,
                          ),
                          _AmountIndicator(
                            label: 'Abandonné',
                            amount: item.writtenOffAmount,
                          ),
                          _AmountIndicator(
                            label: 'Restant',
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
                          label: const Text('Historique'),
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
                                  child: const Text(
                                    'Abandonner',
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
                                  child: const Text(
                                    'Encaisser',
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
        label: const Text('Nouvelle créance'),
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
          const SnackBar(content: Text('Abandon de créance enregistré.')),
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
  final settlementLabel = isReceivable ? 'encaissée' : 'réglée';

  if (remaining.minorUnits <= 0) {
    if (hasSettled && hasWrittenOff) return 'Clôturée — mixte';
    if (hasSettled) return 'Soldée';
    if (hasWrittenOff) return 'Abandonnée';
  }

  if (hasSettled && hasWrittenOff) {
    return 'Partiellement $settlementLabel et abandonnée';
  }
  if (hasWrittenOff) return 'Partiellement abandonnée';
  if (hasSettled) return 'Partiellement $settlementLabel';
  return 'Ouverte';
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final complete =
        label == 'Soldée' ||
        label == 'Abandonnée' ||
        label == 'Clôturée — mixte';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: complete
            ? colors.surfaceContainerHighest
            : colors.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall),
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
    title: const Text('Nouvelle créance'),
    content: SizedBox(
      width: 460,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            key: const Key('income-receivable-choice'),
            leading: const Icon(Icons.schedule_outlined),
            title: const Text('Revenu à encaisser'),
            subtitle: const Text(
              'Un revenu déjà acquis mais qui sera encaissé plus tard.',
            ),
            onTap: () =>
                Navigator.of(context).pop(_ReceivableCreationKind.income),
          ),
          const Divider(height: AppSpacing.md),
          ListTile(
            key: const Key('recovery-receivable-choice'),
            leading: const Icon(Icons.replay_outlined),
            title: const Text('Remboursement à récupérer'),
            subtitle: const Text(
              'Une dépense déjà payée qui doit vous être remboursée.',
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
        child: const Text('Annuler'),
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
          ? 'Échéance (optionnelle)'
          : 'Échéance : ${_formatDate(dueAt!)}',
    ),
  );

  Widget standardFields() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextFormField(
        key: const Key('receivable-description-field'),
        controller: description,
        decoration: fieldDecoration('Libellé *'),
        validator: (value) => value?.trim().isEmpty ?? true
            ? 'Le libellé est obligatoire.'
            : null,
      ),
      const SizedBox(height: AppSpacing.sm),
      TextFormField(
        key: const Key('receivable-amount-field'),
        controller: amount,
        decoration: fieldDecoration('Montant (MAD) *'),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: onAmountChanged,
        validator: (value) => (_madToCents(value ?? '') ?? 0) <= 0
            ? 'Saisissez un montant positif.'
            : null,
      ),
      const SizedBox(height: AppSpacing.sm),
      TextFormField(
        key: const Key('receivable-debtor-field'),
        controller: debtor,
        decoration: fieldDecoration('Débiteur *'),
        validator: (value) => value?.trim().isEmpty ?? true
            ? 'Le débiteur est obligatoire.'
            : null,
      ),
      const SizedBox(height: AppSpacing.sm),
      dueDateField(),
      const SizedBox(height: AppSpacing.sm),
      TextFormField(
        key: const Key('receivable-notes-field'),
        controller: notes,
        decoration: fieldDecoration('Notes'),
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
        title: 'Créer une créance',
        type: 'Revenu à encaisser',
        debtor: debtor.text.trim(),
        amount: Money.fromMinorUnits(cents),
        detail:
            'Aucun encaissement n’est effectué maintenant. Le revenu est reconnu et la créance sera encaissée ultérieurement.',
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
      if (mounted) setState(() => error = _financialErrorMessage(exception));
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Revenu à encaisser'),
    content: SizedBox(
      width: 500,
      child: SingleChildScrollView(
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Créez le revenu acquis sans créditer de compte maintenant.',
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
        child: const Text('Annuler'),
      ),
      FilledButton(
        key: const Key('create-income-receivable-button'),
        onPressed: submitting ? null : _submit,
        child: Text(submitting ? 'Création…' : 'Créer la créance'),
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
      setState(() => error = 'Choisissez une dépense source.');
      return;
    }
    if (cents == null ||
        cents <= 0 ||
        cents > source!.maximumAmount.minorUnits) {
      setState(
        () => error =
            'Le montant dépasse le maximum récupérable pour cette dépense.',
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _ReceivableConfirmationDialog(
        title: 'Créer un remboursement à récupérer',
        type: 'Remboursement à récupérer',
        debtor: debtor.text.trim(),
        amount: Money.fromMinorUnits(cents),
        sourceDescription: source!.description,
        detail:
            'Aucun revenu supplémentaire n’est reconnu et aucun compte n’est crédité maintenant.',
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
      if (mounted) setState(() => error = _financialErrorMessage(exception));
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sources = ref.watch(eligibleRecoverySourcesProvider);
    return AlertDialog(
      title: const Text('Remboursement à récupérer'),
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
                  error: (_, _) => const Text(
                    'Impossible de charger les dépenses éligibles.',
                  ),
                  data: (items) =>
                      DropdownButtonFormField<RecoveryExpenseSource>(
                        key: const Key('recovery-source-field'),
                        isExpanded: true,
                        initialValue: source,
                        decoration: fieldDecoration('Dépense à rembourser *'),
                        items: items
                            .map(
                              (item) => DropdownMenuItem(
                                value: item,
                                child: Text(_recoverySourceLabel(item)),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: submitting
                            ? null
                            : (value) => setState(() => source = value),
                        validator: (value) => value == null
                            ? 'Choisissez une dépense source.'
                            : null,
                      ),
                ),
                if (source != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Montant dépense source : ${_formatFrenchMoney(source!.sourceAmount)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    'Déjà engagé : ${_formatFrenchMoney(source!.committedAmount)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    'Maximum récupérable : ${_formatFrenchMoney(source!.maximumAmount)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                standardFields(),
                if (_amountExceedsMaximum)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: Text(
                      'Le montant dépasse le maximum récupérable pour cette dépense.',
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
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: const Key('create-recovery-receivable-button'),
          onPressed: submitting || _amountExceedsMaximum ? null : _submit,
          child: Text(submitting ? 'Création…' : 'Créer la créance'),
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
          Text('Type : $type'),
          if (sourceDescription != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text('Dépense source : $sourceDescription'),
          ],
          const SizedBox(height: AppSpacing.xs),
          Text('Débiteur : $debtor'),
          const SizedBox(height: AppSpacing.xs),
          Text('Montant : ${_formatFrenchMoney(amount)}'),
          const SizedBox(height: AppSpacing.md),
          Text(detail),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(false),
        child: const Text('Annuler'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(true),
        child: const Text('Créer la créance'),
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
      title: const Text('Historique'),
      content: SizedBox(
        width: 620,
        child: history.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => const Text('Impossible de charger l’historique.'),
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
                                ? 'Création de la dette'
                                : kind == _SettlementHistoryKind.recovery
                                ? 'Création du remboursement à récupérer'
                                : 'Création de la créance',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          Text(
                            'Effectué${kind == _SettlementHistoryKind.debt ? '' : 'e'} par : ${historyItems.creation!.actor.displayName}',
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                ],
                if (historyItems.settlements.isEmpty &&
                    historyItems.writeoffs.isEmpty)
                  const Text(
                    'Aucun règlement, encaissement ou abandon enregistré.',
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
                            '${kind == _SettlementHistoryKind.debt ? 'Règlement' : 'Encaissement'} : ${_formatFrenchMoney(item.grossAmount)}',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          if (item.accountName != null)
                            Text('Compte : ${item.accountName}'),
                          Text('Effectué par : ${item.actor.displayName}'),
                          if (item.envelopeMovements.isNotEmpty)
                            for (final movement in item.envelopeMovements)
                              Text(
                                '${movement.envelopeName} +${_formatFrenchMoney(movement.amount)}',
                              ),
                          Text(
                            'Déjà annulé : ${_formatFrenchMoney(item.reversedAmount)} • Net : ${_formatFrenchMoney(item.netAmount)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          if (kind == _SettlementHistoryKind.recovery &&
                              item.reversibleAmount.minorUnits > 0)
                            Text(
                              'La contrepassation peut rendre l’enveloppe source négative si ses fonds ont déjà été consommés.',
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
                                  child: const Text('Corriger'),
                                ),
                                FilledButton(
                                  onPressed: () => _openReversal(
                                    context,
                                    ref,
                                    item,
                                    isFull: true,
                                  ),
                                  child: const Text('Annuler'),
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
                              kind == _SettlementHistoryKind.debt
                                  ? 'Correction du règlement'
                                  : 'Correction de l’encaissement',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(_formatDateTime(reversal.recordedAt)),
                            Text(
                              'Montant annulé : ${_formatFrenchMoney(reversal.amount)}',
                            ),
                            Text(
                              'Effectuée par : ${reversal.actor.displayName}',
                            ),
                            for (final movement in reversal.envelopeMovements)
                              Text(
                                '${movement.envelopeName} -${_formatFrenchMoney(movement.amount)}',
                              ),
                            Text('Motif : ${reversal.reason}'),
                            if (reversal.notes != null &&
                                reversal.notes!.trim().isNotEmpty)
                              Text('Notes : ${reversal.notes}'),
                            Text(
                              'Net après correction : ${_formatFrenchMoney(reversal.netAmountAfter)}',
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
                            'Abandon',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          Text(
                            'Montant abandonné : ${_formatFrenchMoney(writeoff.amount)}',
                          ),
                          Text('Effectué par : ${writeoff.actor.displayName}'),
                          Text('Motif : ${writeoff.reason}'),
                          if (writeoff.notes != null &&
                              writeoff.notes!.trim().isNotEmpty)
                            Text('Notes : ${writeoff.notes}'),
                          if (writeoff.reversals.isNotEmpty)
                            Text(
                              'Déjà annulé : ${_formatFrenchMoney(writeoff.reversedAmount)} • Encore annulable : ${_formatFrenchMoney(writeoff.reversibleAmount)}',
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
                                child: const Text('Annuler l’abandon'),
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
                              'Annulation de l’abandon',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(_formatDateTime(reversal.recordedAt)),
                            Text(
                              'Montant annulé : ${_formatFrenchMoney(reversal.amount)}',
                            ),
                            Text(
                              'Effectuée par : ${reversal.actor.displayName}',
                            ),
                            Text('Motif : ${reversal.reason}'),
                            if (reversal.notes != null &&
                                reversal.notes!.trim().isNotEmpty)
                              Text('Notes : ${reversal.notes}'),
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
          child: const Text('Fermer'),
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
      setState(() => _error = 'Saisissez un montant réversible et un motif.');
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
          () => _error =
              'La ventilation d’enveloppes doit être exactement égale au montant annulé.',
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
      if (mounted) setState(() => _error = _financialErrorMessage(error));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.isFull ? 'Annuler le règlement' : 'Corriger le règlement',
    ),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Encore réversible : ${_formatFrenchMoney(widget.item.reversibleAmount)}',
            ),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              controller: _amount,
              enabled: !_submitting && !widget.isFull,
              decoration: const InputDecoration(
                labelText: 'Montant à annuler (MAD) *',
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              controller: _reason,
              enabled: !_submitting,
              decoration: const InputDecoration(labelText: 'Motif *'),
            ),
            if (widget.kind == _SettlementHistoryKind.income) ...[
              const SizedBox(height: AppSpacing.md),
              const Text('Ventilation exacte à contrepasser'),
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
                      helperText:
                          'Maximum : ${_formatFrenchMoney(widget.item.envelopeMovements[index].amount)}',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                ),
            ],
            if (widget.kind == _SettlementHistoryKind.recovery) ...[
              const SizedBox(height: AppSpacing.sm),
              const Text(
                'L’enveloppe source sera contrepassée du même montant.',
              ),
              const Text(
                'Son solde peut devenir négatif si les fonds ont déjà été consommés.',
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              controller: _notes,
              enabled: !_submitting,
              decoration: const InputDecoration(labelText: 'Notes'),
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
        child: const Text('Annuler'),
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
        () => _error =
            'Le montant doit être positif et ne pas dépasser le reliquat annulable.',
      );
      return;
    }
    if (_reason.text.trim().isEmpty) {
      setState(() => _error = 'Le motif est obligatoire.');
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
      if (mounted) setState(() => _error = _financialErrorMessage(error));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Annuler l’abandon'),
    content: SizedBox(
      width: 500,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Abandon concerné : ${_formatFrenchMoney(widget.writeoff.amount)}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            Text(
              'Déjà annulé : ${_formatFrenchMoney(widget.writeoff.reversedAmount)}',
            ),
            Text(
              'Encore annulable : ${_formatFrenchMoney(widget.writeoff.reversibleAmount)}',
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
              decoration: const InputDecoration(
                labelText: 'Montant à annuler (MAD) *',
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              key: const Key('writeoff-reversal-reason-field'),
              controller: _reason,
              enabled: !_submitting,
              decoration: const InputDecoration(labelText: 'Motif *'),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              key: const Key('writeoff-reversal-notes-field'),
              controller: _notes,
              enabled: !_submitting,
              decoration: const InputDecoration(labelText: 'Notes'),
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
        child: const Text('Annuler'),
      ),
      FilledButton(
        key: const Key('writeoff-reversal-submit-button'),
        onPressed: _submitting ? null : _submit,
        child: Text(_submitting ? 'Validation…' : 'Valider'),
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
        () => _error =
            'Le montant doit être positif et ne pas dépasser le restant.',
      );
      return;
    }
    if (_reason.text.trim().isEmpty) {
      setState(() => _error = 'Le motif est obligatoire.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirmer l’abandon'),
        content: Text(
          '${widget.description}\n\nMontant abandonné : ${_formatFrenchMoney(amount)}\n'
          'Restant après abandon : ${_formatFrenchMoney(Money.fromMinorUnits(widget.remaining.minorUnits - amount.minorUnits))}\n\n'
          'Aucun compte financier et aucune enveloppe ne seront mouvementés.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmer l’abandon'),
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
      if (mounted) setState(() => _error = _financialErrorMessage(exception));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      _isRecovery
          ? 'Abandonner un remboursement à récupérer'
          : 'Abandonner une ${widget.kind == _WriteoffKind.debt ? 'dette' : 'créance'}',
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
                  _isRecovery
                      ? 'Débiteur : ${widget.counterparty}'
                      : '${widget.kind == _WriteoffKind.debt ? 'Créancier' : 'Débiteur'} : ${widget.counterparty}',
                ),
              Text('Restant : ${_formatFrenchMoney(widget.remaining)}'),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Montant abandonné (MAD) *',
                ),
                validator: (value) => (_madToCents(value ?? '') ?? 0) <= 0
                    ? 'Saisissez un montant positif.'
                    : null,
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _reason,
                decoration: const InputDecoration(labelText: 'Motif *'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Le motif est obligatoire.'
                    : null,
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _notes,
                decoration: const InputDecoration(labelText: 'Notes'),
                maxLines: 2,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                _isRecovery
                    ? 'Vous renoncez définitivement à récupérer ce montant. Aucun compte financier ne sera crédité et l’enveloppe source ne sera pas restaurée. Cet abandon ne permettra pas de créer un nouveau remboursement sur cette même part de dépense.'
                    : widget.kind == _WriteoffKind.debt
                    ? 'Aucun paiement ne sera effectué. Aucun compte financier ni aucune enveloppe ne seront modifiés. Le montant abandonné réduira définitivement la dette restante.'
                    : 'Aucun encaissement ne sera effectué. Aucun compte financier ne sera crédité et aucune enveloppe ne sera alimentée. Le montant sera définitivement passé en perte sur créance.',
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
        child: const Text('Annuler'),
      ),
      FilledButton(
        onPressed: _submitting ? null : _submit,
        child: Text(_submitting ? 'Validation…' : 'Abandonner'),
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
        () => _error =
            'L’encaissement doit être positif et ne pas dépasser le restant.',
      );
      return;
    }
    if (_accountId == null) {
      setState(() => _error = 'Choisissez un compte à créditer.');
      return;
    }
    if (!_allocationsAreValid) {
      setState(
        () => _error = _splitCents > cents
            ? 'Le total affecté ne peut pas dépasser l’encaissement.'
            : 'Chaque enveloppe ajoutée doit avoir un montant positif unique.',
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
      if (mounted) setState(() => _error = _financialErrorMessage(exception));
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
      title: const Text('Encaisser une créance'),
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
                  'Restant à encaisser : ${_formatFrenchMoney(widget.receivable.remainingAmount)}',
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _amount,
                  onChanged: (_) => setState(() {}),
                  decoration: fieldDecoration('Montant encaissé (MAD) *'),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: (value) => (_madToCents(value ?? '') ?? 0) <= 0
                      ? 'Saisissez un montant positif.'
                      : null,
                ),
                const SizedBox(height: AppSpacing.sm),
                _AccountSelector(
                  label: 'Compte à créditer *',
                  decoration: fieldDecoration('Compte à créditer *'),
                  accounts: widget.accounts,
                  value: _accountId,
                  onChanged: _submitting
                      ? null
                      : (value) => setState(() => _accountId = value),
                ),
                if (!_isIncome && _recoverySourceEnvelopeName != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Remboursement de la dépense',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text('Enveloppe restaurée : $_recoverySourceEnvelopeName'),
                  Text(
                    'Montant restauré : ${_formatFrenchMoney(Money.fromMinorUnits(_amountCents))}',
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Le remboursement recréditera automatiquement cette enveloppe.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                if (_isIncome) ...[
                  const SizedBox(height: AppSpacing.md),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Répartition de l’encaissement',
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
                      label: const Text('Ajouter une enveloppe'),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Encaissement : ${_formatFrenchMoney(Money.fromMinorUnits(_amountCents))} • '
                      'Affecté : ${_formatFrenchMoney(Money.fromMinorUnits(_splitCents))} • '
                      'Reste à répartir : ${_formatFrenchMoney(Money.fromMinorUnits(_remainingCents))}',
                    ),
                  ),
                  if (_remainingCents > 0)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${_formatFrenchMoney(Money.fromMinorUnits(_remainingCents))} seront automatiquement affectés à « À répartir ».',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  if (_splitCents > _amountCents)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Le total affecté ne peut pas dépasser l’encaissement.',
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ),
                ],
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: _notes,
                  decoration: fieldDecoration('Notes'),
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
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed:
              _submitting ||
                  _amountCents <= 0 ||
                  _accountId == null ||
                  !_allocationsAreValid
              ? null
              : _submit,
          child: Text(_submitting ? 'Validation…' : 'Encaisser'),
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
      title: Text('Encaisser ${_formatFrenchMoney(amount)}'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              recoveryEnvelopeName == null ? 'Compte :' : 'Compte crédité :',
            ),
            Text(accountName, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: AppSpacing.md),
            if (recoveryEnvelopeName != null) ...[
              const Text('Enveloppe restaurée :'),
              Text(
                recoveryEnvelopeName!,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              Text('Montant restauré : ${_formatFrenchMoney(amount)}'),
            ] else ...[
              const Text('Répartition :'),
              for (final allocation in allocations)
                Text(
                  '→ ${envelopeName(allocation.envelopeId)} : '
                  '${_formatFrenchMoney(Money.fromDirhams(allocation.amount))}',
                ),
              if (remainder.minorUnits > 0)
                Text('→ À répartir : ${_formatFrenchMoney(remainder)}'),
            ],
            const SizedBox(height: AppSpacing.md),
            const Text('Aucun nouveau revenu ne sera créé.'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Encaisser'),
        ),
      ],
    );
  }
}

String _recoverySourceLabel(RecoveryExpenseSource source) {
  final envelope = source.envelopeName == null
      ? ''
      : ' • ${source.envelopeName}';
  final account = source.accountName == null ? '' : ' • ${source.accountName}';
  return '${source.description} • ${_formatDate(source.occurredAt)} • '
      'Dépense ${_formatFrenchMoney(source.sourceAmount)} • '
      'Déjà engagé ${_formatFrenchMoney(source.committedAmount)} • '
      'Maximum ${_formatFrenchMoney(source.maximumAmount)}$account$envelope';
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
  String? _error;

  @override
  void initState() {
    super.initState();
    _description.text = 'Règlement : ${widget.debt.description}';
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
        () => _error =
            'Le règlement doit être positif et ne pas dépasser le restant.',
      );
      return;
    }
    if (_accountId == null) {
      setState(() => _error = 'Choisissez un compte de paiement.');
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
      if (mounted) setState(() => _error = _financialErrorMessage(error));
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
      title: const Text('Régler une dette'),
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
                        'Créancier : ${widget.debt.creditorName ?? 'Créancier non renseigné'}',
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Restant à régler : $remaining MAD',
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
                  decoration: fieldDecoration('Montant à régler (MAD) *'),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: (value) => (_madToCents(value ?? '') ?? 0) <= 0
                      ? 'Saisissez un montant positif.'
                      : null,
                ),
                const SizedBox(height: AppSpacing.sm),
                _AccountSelector(
                  label: 'Compte de paiement *',
                  decoration: fieldDecoration('Compte de paiement *'),
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
                  decoration: fieldDecoration('Libellé *'),
                  validator: (value) => value?.trim().isEmpty ?? true
                      ? 'Le libellé est obligatoire.'
                      : null,
                ),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: _notes,
                  decoration: fieldDecoration('Notes'),
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
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: const Key('settle-debt-button'),
          onPressed: _submitting ? null : _submit,
          child: Text(_submitting ? 'Validation…' : 'Régler'),
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

String _financialErrorMessage(Object error) {
  final value = error.toString().toLowerCase();
  if (value.contains('write-off reversal') ||
      value.contains('writeoff reversal') ||
      value.contains('still reversible')) {
    return 'Cet abandon est déjà totalement annulé ou le montant dépasse le reliquat annulable.';
  }
  if (value.contains('write-off source') ||
      value.contains('source adjustment')) {
    return 'L’abandon sélectionné n’est plus disponible.';
  }
  if (value.contains('remaining') || value.contains('dépasse')) {
    return 'Le règlement dépasse le montant restant.';
  }
  if (value.contains('network') || value.contains('socket')) {
    return 'Connexion indisponible. Réessayez.';
  }
  if (value.contains('account') || value.contains('compte')) {
    return 'Le compte sélectionné n’est pas autorisé.';
  }
  if (value.contains('envelope') || value.contains('enveloppe')) {
    return 'L’enveloppe sélectionnée n’est pas valide.';
  }
  return 'Impossible d’enregistrer cette opération. Réessayez.';
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
