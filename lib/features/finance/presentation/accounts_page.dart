import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_design_system.dart';
import '../application/providers/remote_accounts_provider.dart';
import '../application/providers/remote_household_members_provider.dart';
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
          padding: AppSpacing.page,
          children: [
            if (items.isEmpty)
              const Card(
                child: ListTile(
                  leading: Icon(Icons.account_balance_outlined),
                  title: Text('Aucun compte distant'),
                  subtitle: Text(
                    'Ajoutez un compte ou importez vos comptes initiaux.',
                  ),
                ),
              ),
            ...items.map(
              (account) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Card(
                  child: ListTile(
                    title: Text(account.name),
                    subtitle: Text(
                      '${_accountTypeLabel(account.type)} • '
                      '${_holdersLabel(account, membersAsync.valueOrNull ?? const [])} • '
                      '${account.isArchived ? 'Archivé' : 'Actif'}',
                    ),
                    trailing: Text(
                      '${account.openingBalance.dirhams.toStringAsFixed(2)} MAD',
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
}

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
