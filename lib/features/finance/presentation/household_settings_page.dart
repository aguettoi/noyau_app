import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_design_system.dart';
import '../application/providers/active_household_provider.dart';
import '../application/providers/household_settings_provider.dart';
import '../application/providers/remote_household_members_provider.dart';

class HouseholdSettingsPage extends ConsumerStatefulWidget {
  const HouseholdSettingsPage({super.key});
  @override
  ConsumerState<HouseholdSettingsPage> createState() =>
      _HouseholdSettingsPageState();
}

class _HouseholdSettingsPageState extends ConsumerState<HouseholdSettingsPage> {
  final _profile = TextEditingController();
  final _household = TextEditingController();
  var _mode = 'authorized_member';
  var _busy = false;
  String? _message;

  @override
  void dispose() {
    _profile.dispose();
    _household.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final state = await ref.read(activeHouseholdProvider.future);
    final id = state.householdId;
    if (id == null ||
        _profile.text.trim().isEmpty ||
        _household.text.trim().isEmpty) {
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final gateway = ref.read(householdSettingsGatewayProvider);
      await gateway.updateProfile(_profile.text.trim());
      await gateway.update(
        householdId: id,
        name: _household.text.trim(),
        budgetValidationMode: _mode,
      );
      ref.invalidate(currentProfileProvider);
      ref.invalidate(householdSettingsProvider);
      ref.invalidate(activeHouseholdProvider);
      if (mounted) setState(() => _message = 'Paramètres enregistrés.');
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = 'Enregistrement impossible. Vérifiez vos droits.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(currentProfileProvider);
    final settings = ref.watch(householdSettingsProvider);
    final members = ref.watch(remoteHouseholdMembersProvider);
    profile.whenData((value) {
      if (_profile.text.isEmpty) {
        _profile.text = value['display_name'] ?? '';
      }
    });
    settings.whenData((value) {
      if (_household.text.isEmpty) {
        _household.text = value.name;
        _mode = value.budgetValidationMode;
      }
    });
    return Scaffold(
      appBar: AppBar(title: const Text('Profil et paramètres du foyer')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: AppSpacing.page,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Mon profil',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    key: const Key('profile-display-name-field'),
                    controller: _profile,
                    decoration: const InputDecoration(
                      labelText: 'Prénom / nom affiché',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text('E-mail : ${profile.valueOrNull?['email'] ?? '—'}'),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'Paramètres du foyer',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    key: const Key('household-name-settings-field'),
                    controller: _household,
                    decoration: const InputDecoration(
                      labelText: 'Nom du foyer',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  DropdownButtonFormField<String>(
                    key: const Key('budget-validation-mode-field'),
                    initialValue: _mode,
                    decoration: const InputDecoration(
                      labelText: 'Validation du budget',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'authorized_member',
                        child: Text('Un membre autorisé peut appliquer'),
                      ),
                      DropdownMenuItem(
                        value: 'joint_required',
                        child: Text('Validation conjointe requise'),
                      ),
                    ],
                    onChanged: (value) =>
                        setState(() => _mode = value ?? _mode),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  FilledButton(
                    key: const Key('save-household-settings-button'),
                    onPressed: _busy ? null : _save,
                    child: const Text('Enregistrer'),
                  ),
                  if (_message != null)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.sm),
                      child: Text(_message!),
                    ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'Membres',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  members.when(
                    loading: () => const LinearProgressIndicator(),
                    error: (_, _) => const Text('Membres indisponibles.'),
                    data: (items) => Column(
                      children: [
                        for (final member in items)
                          ListTile(
                            key: Key('settings-member-${member.id}'),
                            leading: const Icon(Icons.person_outline),
                            title: Text(member.displayName),
                            subtitle: Text(
                              member.role == 'owner'
                                  ? 'Propriétaire'
                                  : 'Membre',
                            ),
                            trailing: PopupMenuButton<String>(
                              tooltip: 'Actions membre',
                              onSelected: (action) async {
                                final state = await ref.read(
                                  activeHouseholdProvider.future,
                                );
                                final id = state.householdId;
                                if (id == null) return;
                                final gateway = ref.read(
                                  householdSettingsGatewayProvider,
                                );
                                if (action == 'owner' || action == 'member') {
                                  await gateway.changeRole(
                                    householdId: id,
                                    userId: member.id,
                                    role: action,
                                  );
                                } else if (action == 'remove') {
                                  await gateway.removeMember(
                                    householdId: id,
                                    userId: member.id,
                                  );
                                }
                                ref.invalidate(remoteHouseholdMembersProvider);
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'owner',
                                  child: Text('Rendre propriétaire'),
                                ),
                                PopupMenuItem(
                                  value: 'member',
                                  child: Text('Rendre membre'),
                                ),
                                PopupMenuItem(
                                  value: 'remove',
                                  child: Text('Retirer du foyer'),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  OutlinedButton(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => const _InvitationsDialog(),
                    ),
                    child: const Text('Voir les invitations'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InvitationsDialog extends ConsumerStatefulWidget {
  const _InvitationsDialog();
  @override
  ConsumerState<_InvitationsDialog> createState() => _InvitationsDialogState();
}

class _InvitationsDialogState extends ConsumerState<_InvitationsDialog> {
  Future<List<HouseholdInvitationAdmin>> _load() async {
    final state = await ref.read(activeHouseholdProvider.future);
    final id = state.householdId;
    if (id == null) throw StateError('Aucun foyer actif.');
    return ref.read(householdSettingsGatewayProvider).listInvitations(id);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Invitations'),
    content: SizedBox(
      width: 520,
      child: FutureBuilder<List<HouseholdInvitationAdmin>>(
        future: _load(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Text('Invitations indisponibles.');
          }
          final items = snapshot.data ?? const <HouseholdInvitationAdmin>[];
          if (items.isEmpty) {
            return const Text('Aucune invitation enregistrée.');
          }
          return SingleChildScrollView(
            child: Column(
              children: [
                for (final item in items)
                  ListTile(
                    key: Key('household-invitation-${item.id}'),
                    title: Text(item.email),
                    subtitle: Text('${item.status} · ${item.role}'),
                    trailing: item.status == 'pending'
                        ? IconButton(
                            tooltip: 'Révoquer',
                            icon: const Icon(Icons.cancel_outlined),
                            onPressed: () async {
                              await ref
                                  .read(householdSettingsGatewayProvider)
                                  .revokeInvitation(item.id);
                              if (mounted) setState(() {});
                            },
                          )
                        : null,
                  ),
              ],
            ),
          );
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Fermer'),
      ),
    ],
  );
}
