import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_design_system.dart';
import '../../../core/localization/app_language_picker.dart';
import '../../../core/localization/app_locale.dart';
import '../../../core/localization/finance_residual_locale.dart';
import '../application/providers/active_household_provider.dart';
import '../application/providers/household_settings_provider.dart';
import '../application/providers/remote_household_members_provider.dart';
import 'payment_methods_page.dart';

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
    final residual = FinanceResidualWords(ref.read(appLocaleProvider));
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
      if (mounted) {
        setState(() => _message = residual.text('settings.saved'));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _message = residual.text('settings.save_failed'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final words = AppWords(ref.watch(appLocaleProvider));
    final residual = FinanceResidualWords(ref.watch(appLocaleProvider));
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
      appBar: AppBar(title: Text(residual.text('settings.title'))),
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
                    words.text('language.settings.title'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const AppLanguagePicker(key: Key('settings-language-picker')),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    residual.text('settings.profile'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    key: const Key('profile-display-name-field'),
                    controller: _profile,
                    decoration: InputDecoration(
                      labelText: residual.text('settings.display_name'),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    residual.format('settings.email', {
                      'email': profile.valueOrNull?['email'] ?? '—',
                    }),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    residual.text('settings.household'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    key: const Key('household-name-settings-field'),
                    controller: _household,
                    decoration: InputDecoration(
                      labelText: residual.text('settings.household_name'),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  DropdownButtonFormField<String>(
                    key: const Key('budget-validation-mode-field'),
                    initialValue: _mode,
                    decoration: InputDecoration(
                      labelText: residual.text('settings.budget_validation'),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'authorized_member',
                        child: Text(residual.text('settings.authorized_apply')),
                      ),
                      DropdownMenuItem(
                        value: 'joint_required',
                        child: Text(residual.text('settings.joint_required')),
                      ),
                    ],
                    onChanged: (value) =>
                        setState(() => _mode = value ?? _mode),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  FilledButton(
                    key: const Key('save-household-settings-button'),
                    onPressed: _busy ? null : _save,
                    child: Text(residual.text('settings.save')),
                  ),
                  if (_message != null)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.sm),
                      child: Text(_message!),
                    ),
                  const SizedBox(height: AppSpacing.lg),
                  OutlinedButton.icon(
                    key: const Key('payment-methods-settings-button'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const PaymentMethodsPage(),
                      ),
                    ),
                    icon: const Icon(Icons.credit_card),
                    label: Text(residual.text('settings.payment_methods')),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    residual.text('settings.members'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  members.when(
                    loading: () => const LinearProgressIndicator(),
                    error: (_, _) => Text(residual.text('members.unavailable')),
                    data: (items) => Column(
                      children: [
                        for (final member in items)
                          ListTile(
                            key: Key('settings-member-${member.id}'),
                            leading: const Icon(Icons.person_outline),
                            title: Text(member.displayName),
                            subtitle: Text(
                              member.role == 'owner'
                                  ? residual.text('settings.owner')
                                  : residual.text('settings.member'),
                            ),
                            trailing: PopupMenuButton<String>(
                              tooltip: residual.text('settings.member_actions'),
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
                              itemBuilder: (_) => [
                                PopupMenuItem(
                                  value: 'owner',
                                  child: Text(
                                    residual.text('settings.make_owner'),
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'member',
                                  child: Text(
                                    residual.text('settings.make_member'),
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'remove',
                                  child: Text(
                                    residual.text('settings.remove_member'),
                                  ),
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
                    child: Text(residual.text('settings.view_invitations')),
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
  Widget build(BuildContext context) {
    final words = FinanceResidualWords.of(context);
    return AlertDialog(
      title: Text(words.text('settings.invitations')),
      content: SizedBox(
        width: 520,
        child: FutureBuilder<List<HouseholdInvitationAdmin>>(
          future: _load(),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Text(words.text('settings.invitations_unavailable'));
            }
            final items = snapshot.data ?? const <HouseholdInvitationAdmin>[];
            if (items.isEmpty) {
              return Text(words.text('settings.no_invitations'));
            }
            return SingleChildScrollView(
              child: Column(
                children: [
                  for (final item in items)
                    ListTile(
                      key: Key('household-invitation-${item.id}'),
                      title: Text(item.email),
                      subtitle: Text(
                        words.format('settings.invitation_summary', {
                          'status': words.text(
                            'settings.invitation_status.${item.status}',
                          ),
                          'role': words.text(
                            'settings.invitation_role.${item.role}',
                          ),
                        }),
                      ),
                      trailing: item.status == 'pending'
                          ? IconButton(
                              tooltip: words.text('settings.revoke'),
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
          child: Text(words.text('members.close')),
        ),
      ],
    );
  }
}
