import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_design_system.dart';
import '../application/providers/active_household_provider.dart';
import '../application/providers/household_onboarding_provider.dart';
import '../application/providers/remote_household_members_provider.dart';

class HouseholdMembersDialog extends ConsumerStatefulWidget {
  const HouseholdMembersDialog({super.key});

  @override
  ConsumerState<HouseholdMembersDialog> createState() =>
      _HouseholdMembersDialogState();
}

class _HouseholdMembersDialogState
    extends ConsumerState<HouseholdMembersDialog> {
  final _emailController = TextEditingController();
  var _busy = false;
  String? _message;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _invite() async {
    final email = _emailController.text.trim();
    final household = await ref.read(activeHouseholdProvider.future);
    final householdId = household.householdId;
    if (_busy || householdId == null || !email.contains('@')) {
      setState(() => _message = 'Saisissez une adresse e-mail valide.');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await ref
          .read(householdOnboardingGatewayProvider)
          .inviteMember(householdId: householdId, email: email);
      if (mounted) {
        setState(() {
          _emailController.clear();
          _message =
              'Invitation enregistrée. La personne la verra après création et confirmation de son compte avec cette adresse.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'Invitation impossible. Seul le propriétaire du foyer peut inviter un membre.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final members = ref.watch(remoteHouseholdMembersProvider);
    return AlertDialog(
      title: const Text('Membres du foyer'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              members.when(
                loading: () => const LinearProgressIndicator(),
                error: (_, _) => const Text('Membres indisponibles.'),
                data: (items) => Column(
                  children: [
                    for (final member in items)
                      ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.person_outline),
                        ),
                        title: Text(member.displayName),
                      ),
                  ],
                ),
              ),
              const Divider(),
              Text(
                'Inviter une personne',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                key: const Key('household-invite-email-field'),
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Adresse e-mail'),
              ),
              const SizedBox(height: AppSpacing.sm),
              FilledButton.icon(
                key: const Key('household-invite-button'),
                onPressed: _busy ? null : _invite,
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('Envoyer l’invitation'),
              ),
              if (_message != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(_message!),
              ],
            ],
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
}
