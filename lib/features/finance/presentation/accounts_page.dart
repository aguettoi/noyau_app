import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../../core/theme/app_design_system.dart';
import '../application/providers/remote_account_balances_provider.dart';
import '../application/providers/account_balance_observation_provider.dart';
import '../application/providers/remote_accounts_provider.dart';
import '../application/providers/remote_household_members_provider.dart';
import '../application/providers/remote_transactions_provider.dart';
import '../domain/account_ownership.dart';
import '../domain/household_member.dart';
import '../domain/financial_account.dart';
import '../infrastructure/accounts_supabase_repository.dart';

class AccountsPage extends ConsumerStatefulWidget {
  const AccountsPage({super.key});

  @override
  ConsumerState<AccountsPage> createState() => _AccountsPageState();
}

class _AccountsPageState extends ConsumerState<AccountsPage> {
  var _creating = false;

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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Compte créé avec succès.')));
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
      appBar: AppBar(title: const Text('Comptes')),
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
        label: const Text('Ajouter'),
      ),
      body: accountsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: AppSpacing.page,
            child: Text('Impossible de lire les comptes distants : $error'),
          ),
        ),
        data: (items) => ListView(
          children: [
            DesktopPageContainer(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _AccountsHero(
                    accountCount: items.length,
                    totalBalance: items.fold<Money>(
                      const Money.fromMinorUnits(0),
                      (total, account) =>
                          total +
                          (balancesAsync.valueOrNull?[account.id] ??
                              account.openingBalance),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  DesktopSection(
                    title: 'Vos comptes',
                    subtitle: items.isEmpty
                        ? 'Ajoutez un compte ou importez vos comptes initiaux.'
                        : '${items.length} compte${items.length > 1 ? 's' : ''} suivi${items.length > 1 ? 's' : ''}',
                    child: items.isEmpty
                        ? const CompactListRow(
                            title: 'Aucun compte distant',
                            subtitle:
                                'La liste apparaîtra ici après création ou import.',
                            leading: Icon(Icons.account_balance_outlined),
                          )
                        : LayoutBuilder(
                            builder: (context, constraints) {
                              final grid = constraints.maxWidth >= 900;
                              return grid
                                  ? ResponsiveGrid(
                                      minItemWidth: 390,
                                      children: items
                                          .map(
                                            (account) => _AccountRow(
                                              account: account,
                                              balance:
                                                  balancesAsync
                                                      .valueOrNull?[account
                                                      .id] ??
                                                  account.openingBalance,
                                              members:
                                                  membersAsync.valueOrNull ??
                                                  const [],
                                            ),
                                          )
                                          .toList(growable: false),
                                    )
                                  : Column(
                                      children: items
                                          .map(
                                            (account) => Padding(
                                              padding: const EdgeInsets.only(
                                                bottom: AppSpacing.xs,
                                              ),
                                              child: _AccountRow(
                                                account: account,
                                                balance:
                                                    balancesAsync
                                                        .valueOrNull?[account
                                                        .id] ??
                                                    account.openingBalance,
                                                members:
                                                    membersAsync.valueOrNull ??
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
        ),
      ),
    );
  }
}

class _AccountsHero extends StatelessWidget {
  const _AccountsHero({required this.accountCount, required this.totalBalance});
  final int accountCount;
  final Money totalBalance;

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
                'Vue des comptes',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                '$accountCount compte${accountCount > 1 ? 's' : ''} relié${accountCount > 1 ? 's' : ''} à votre foyer.',
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('Solde total', style: Theme.of(context).textTheme.bodySmall),
              Text(
                '${totalBalance.dirhams.toStringAsFixed(2)} MAD',
                style: Theme.of(context).textTheme.titleLarge,
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
  final Money balance;
  final List<HouseholdMember> members;

  @override
  Widget build(BuildContext context) => CompactListRow(
    leading: Icon(_accountIcon(account.type), color: AppColors.secondary),
    title: account.name,
    subtitle:
        '${_accountTypeLabel(account.type)} • ${_holdersLabel(account, members)} • ${account.isArchived ? 'Archivé' : 'Actif'}',
    trailing: Text(
      '${balance.dirhams.toStringAsFixed(2)} MAD',
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
  final Money balance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(accountTransactionHistoryProvider(account.id));
    final observation = ref.watch(
      latestAccountBalanceObservationProvider(account.id),
    );
    final canReconcile =
        account.type == FinancialAccountType.bank ||
        account.type == FinancialAccountType.cash;
    return Scaffold(
      appBar: AppBar(title: Text(account.name)),
      body: ListView(
        padding: AppSpacing.page,
        children: [
          Text(account.name, style: Theme.of(context).textTheme.headlineSmall),
          Text('Solde actuel : ${balance.dirhams.toStringAsFixed(2)} MAD'),
          if (canReconcile) ...[
            const SizedBox(height: AppSpacing.md),
            _AccountReconciliationCard(
              account: account,
              theoreticalBalance: balance,
              observation: observation,
              onRecord: () => _openObservationDialog(context, ref),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Text('Opérations', style: Theme.of(context).textTheme.titleMedium),
          ...history.when(
            loading: () => const [Center(child: CircularProgressIndicator())],
            error: (_, _) => const [
              Text('Impossible de charger l’historique du compte.'),
            ],
            data: (items) => items.isEmpty
                ? const [Text('Aucune opération pour ce compte.')]
                : items
                      .map(
                        (item) => ListTile(
                          title: Text(item.description),
                          subtitle: Text(_accountHistoryLabel(item.type)),
                          trailing: Text(
                            '${item.amount.dirhams.toStringAsFixed(2)} MAD',
                          ),
                        ),
                      )
                      .toList(growable: false),
          ),
        ],
      ),
    );
  }

  Future<void> _openObservationDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _RecordAccountBalanceDialog(
        account: account,
        theoreticalBalance: balance,
        onRecord:
            ({required observedAt, required actualBalance, required reason}) =>
                ref.read(recordAccountBalanceObservationProvider)(
                  accountId: account.id,
                  observedAt: observedAt,
                  actualBalance: actualBalance,
                  reason: reason,
                ),
      ),
    );
    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Constat de solde enregistré.')),
      );
    }
  }
}

class _AccountReconciliationCard extends StatelessWidget {
  const _AccountReconciliationCard({
    required this.account,
    required this.theoreticalBalance,
    required this.observation,
    required this.onRecord,
  });

  final FinancialAccount account;
  final Money theoreticalBalance;
  final AsyncValue<AccountBalanceObservation?> observation;
  final VoidCallback onRecord;

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
                  ? 'Inventaire de caisse'
                  : 'Rapprochement bancaire',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Text('Le dernier constat ne peut pas être chargé.'),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton(
                onPressed: onRecord,
                child: const Text('Constater un solde réel'),
              ),
            ),
          ],
        ),
        data: (latest) {
          final difference = latest == null
              ? null
              : latest.actualBalance - theoreticalBalance;
          final reconciled = difference?.minorUnits == 0;
          final title = account.type == FinancialAccountType.cash
              ? 'Inventaire de caisse'
              : 'Rapprochement bancaire';
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.xxs),
              Text('Solde théorique GL : ${_frenchMoney(theoreticalBalance)}'),
              if (latest == null)
                const Text('Aucun solde réel constaté pour le moment.')
              else ...[
                Text(
                  'Solde réel constaté : ${_frenchMoney(latest.actualBalance)}',
                ),
                Text('Écart : ${_frenchMoney(difference!)}'),
                Text(
                  reconciled == true
                      ? 'État : Rapproché'
                      : 'État : Écart à expliquer',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: reconciled == true
                        ? AppColors.secondary
                        : Theme.of(context).colorScheme.error,
                  ),
                ),
                Text('Relevé : ${_formatObservationDate(latest.observedAt)}'),
                Text('Effectué par : ${latest.actorName}'),
                Text('Commentaire : ${latest.reason}'),
              ],
              const SizedBox(height: AppSpacing.sm),
              const Text(
                'Le compte financier indique où se trouve l’argent ; une enveloppe indique à quoi il est destiné. Aucun écart ne modifie le Grand Livre ni les enveloppes.',
              ),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  key: const Key('record-account-balance-observation-button'),
                  onPressed: onRecord,
                  icon: const Icon(Icons.fact_check_outlined),
                  label: Text(
                    account.type == FinancialAccountType.cash
                        ? 'Compter les espèces'
                        : 'Constater un solde réel',
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

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

  @override
  void initState() {
    super.initState();
    _actualBalance = TextEditingController(
      text: widget.theoreticalBalance.dirhams.toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    _actualBalance.dispose();
    _reason.dispose();
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
      widget.account.type == FinancialAccountType.cash
          ? 'Compter les espèces'
          : 'Constater un solde bancaire',
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
                'Solde théorique GL : ${_frenchMoney(widget.theoreticalBalance)}',
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                key: const Key('actual-account-balance-field'),
                controller: _actualBalance,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                decoration: InputDecoration(
                  labelText: widget.account.type == FinancialAccountType.cash
                      ? 'Espèces comptées (MAD) *'
                      : 'Solde bancaire réel (MAD) *',
                ),
                validator: (value) => _madToCents(value?.trim() ?? '') == null
                    ? 'Saisissez un montant MAD valide.'
                    : null,
              ),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton.icon(
                onPressed: _submitting ? null : _pickDateTime,
                icon: const Icon(Icons.schedule_outlined),
                label: Text(
                  'Date et heure : ${_formatObservationDate(_observedAt)}',
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                key: const Key('account-balance-observation-reason-field'),
                controller: _reason,
                maxLength: 280,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Commentaire / justification *',
                ),
                validator: (value) {
                  final reason = value?.trim() ?? '';
                  if (reason.isEmpty) return 'Le commentaire est obligatoire.';
                  if (reason.length > 280) return '280 caractères maximum.';
                  return null;
                },
              ),
              const Text(
                'Ce constat ne crée aucune correction comptable. Toute régularisation est une action distincte.',
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
        key: const Key('record-account-balance-observation-submit-button'),
        onPressed: _submitting ? null : _submit,
        child: Text(_submitting ? 'Enregistrement…' : 'Enregistrer le constat'),
      ),
    ],
  );
}

String _frenchMoney(Money amount) =>
    '${amount.dirhams.toStringAsFixed(2).replaceAll('.', ',')} MAD';

String _formatObservationDate(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year} • ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

String _accountHistoryLabel(Object type) => switch (type.toString()) {
  'LedgerTransactionType.expense' => 'Dépense',
  'LedgerTransactionType.debtSettlement' => 'Paiement d’une dette',
  'LedgerTransactionType.accountTransfer' => 'Virement entre comptes',
  _ => 'Opération',
};

String _accountTypeLabel(FinancialAccountType type) => switch (type) {
  FinancialAccountType.bank => 'Banque',
  FinancialAccountType.cash => 'Espèces',
  FinancialAccountType.savings => 'Épargne',
  FinancialAccountType.debt => 'Emprunt',
};

String _holdersLabel(
  FinancialAccount account,
  List<HouseholdMember> householdMembers,
) {
  final namesByUserId = {
    for (final member in householdMembers) member.id: member.displayName,
  };
  final holderNames = account.holders
      .map(
        (holder) =>
            namesByUserId[holder.userId] ?? _fallbackHolderLabel(holder),
      )
      .toList(growable: false);
  return holderNames.isEmpty ? 'Aucun titulaire lié' : holderNames.join(' & ');
}

String _fallbackHolderLabel(AccountHolder holder) {
  final name = holder.displayName.trim();
  return name.isEmpty || name == 'Membre du foyer' ? 'Membre du foyer' : name;
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
  final _balanceController = TextEditingController(text: '0');
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
    _balanceController.dispose();
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
      setState(() => _error = 'Sélectionnez exactement un titulaire.');
      return;
    }
    if (_ownershipType == AccountOwnershipType.shared &&
        _holderUserIds.length < 2) {
      setState(() => _error = 'Sélectionnez au moins deux titulaires.');
      return;
    }
    final cents = _madToCents(_balanceController.text.trim());
    if (cents == null) {
      setState(() => _error = 'Saisissez un solde d’ouverture valide en MAD.');
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
          openingBalanceCents: cents,
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
        setState(() => _error = 'Création impossible : $error');
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Ajouter un compte'),
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
                decoration: const InputDecoration(labelText: 'Nom *'),
                validator: (value) {
                  final name = value?.trim() ?? '';
                  if (name.isEmpty) return 'Le nom est obligatoire.';
                  if (widget.existingAccounts.any(
                    (account) =>
                        account.name.trim().toLowerCase() == name.toLowerCase(),
                  )) {
                    return 'Un compte portant ce nom existe déjà dans le foyer.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<FinancialAccountType>(
                key: const Key('account-type-field'),
                decoration: const InputDecoration(labelText: 'Type *'),
                items: const [
                  DropdownMenuItem(
                    value: FinancialAccountType.bank,
                    child: Text('Banque'),
                  ),
                  DropdownMenuItem(
                    value: FinancialAccountType.cash,
                    child: Text('Espèces'),
                  ),
                  DropdownMenuItem(
                    value: FinancialAccountType.savings,
                    child: Text('Épargne'),
                  ),
                  DropdownMenuItem(
                    value: FinancialAccountType.debt,
                    child: Text('Emprunt'),
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
                decoration: const InputDecoration(labelText: 'Titularité *'),
                items: const [
                  DropdownMenuItem(
                    value: AccountOwnershipType.household,
                    child: Text('Compte commun'),
                  ),
                  DropdownMenuItem(
                    value: AccountOwnershipType.individual,
                    child: Text('Compte individuel'),
                  ),
                  DropdownMenuItem(
                    value: AccountOwnershipType.shared,
                    child: Text('Compte partagé'),
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
                const Text('Chargement des membres du foyer...')
              else if (widget.membersError)
                const Text('Impossible de charger les membres du foyer.')
              else if (widget.members.isEmpty)
                const Text('Aucun membre du foyer n’est disponible.')
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
                decoration: const InputDecoration(labelText: 'Statut'),
                items: const [
                  DropdownMenuItem(value: false, child: Text('Actif')),
                  DropdownMenuItem(value: true, child: Text('Archivé')),
                ],
                onChanged: _submitting
                    ? null
                    : (value) => setState(() => _archived = value!),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                key: const Key('account-opening-balance-field'),
                controller: _balanceController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Solde d’ouverture (MAD)',
                ),
                validator: (value) => _madToCents(value?.trim() ?? '') == null
                    ? 'Saisissez un montant MAD valide.'
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
        onPressed: _submitting ? null : () => Navigator.of(context).pop(),
        child: const Text('Annuler'),
      ),
      FilledButton(
        key: const Key('create-remote-account-button'),
        onPressed: _submitting ? null : _submit,
        child: _submitting ? const Text('Création…') : const Text('Créer'),
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
