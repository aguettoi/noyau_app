import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/finance_residual_locale.dart';
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
    final words = FinanceResidualWords.of(context);
    final email = _emailController.text.trim();
    final household = await ref.read(activeHouseholdProvider.future);
    final householdId = household.householdId;
    if (_busy || householdId == null || !email.contains('@')) {
      setState(() => _message = words.text('members.invalid_email'));
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
          _message = words.text('members.invited');
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _message = words.text('members.invite_failed'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final words = FinanceResidualWords.of(context);
    final members = ref.watch(remoteHouseholdMembersProvider);
    return AlertDialog(
      title: Text(words.text('members.title')),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              members.when(
                loading: () => const LinearProgressIndicator(),
                error: (_, _) => Text(words.text('members.unavailable')),
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
                words.text('members.invite_person'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                key: const Key('household-invite-email-field'),
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: words.text('members.email'),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              FilledButton.icon(
                key: const Key('household-invite-button'),
                onPressed: _busy ? null : _invite,
                icon: const Icon(Icons.person_add_alt_1),
                label: Text(words.text('members.send_invitation')),
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
          child: Text(words.text('members.close')),
        ),
      ],
    );
  }
}
