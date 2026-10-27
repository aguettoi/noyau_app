import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_locale.dart';
import '../../../core/theme/app_design_system.dart';
import '../application/providers/household_onboarding_provider.dart';
import '../application/providers/supabase_client_provider.dart';

class HouseholdOnboardingPage extends ConsumerStatefulWidget {
  const HouseholdOnboardingPage({super.key});

  @override
  ConsumerState<HouseholdOnboardingPage> createState() =>
      _HouseholdOnboardingPageState();
}

class _HouseholdOnboardingPageState
    extends ConsumerState<HouseholdOnboardingPage> {
  final _nameController = TextEditingController();
  var _busy = false;
  String? _error;
  String _w(String key) => AppWords.of(context).text(key);

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _createHousehold() async {
    final name = _nameController.text.trim();
    if (_busy || name.isEmpty) {
      setState(() => _error = _w('household.validation.name'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(householdOnboardingGatewayProvider).createHousehold(name);
      refreshHouseholdContext(ref);
    } catch (_) {
      if (mounted) {
        setState(() => _error = _w('household.error.create'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _accept(HouseholdInvitation invitation) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(householdOnboardingGatewayProvider)
          .acceptInvitation(invitation.id);
      refreshHouseholdContext(ref);
    } catch (_) {
      if (mounted) {
        setState(() => _error = _w('household.error.invitation'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final invitations = ref.watch(pendingHouseholdInvitationsProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(_w('household.welcome')),
        actions: [
          IconButton(
            tooltip: _w('nav.logout'),
            onPressed: _busy
                ? null
                : () => ref.read(supabaseAuthGatewayProvider).signOut(),
            icon: const Icon(Icons.logout_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: AppSpacing.page,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _w('household.configure'),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(_w('household.intro')),
                  const SizedBox(height: AppSpacing.lg),
                  Card(
                    child: Padding(
                      padding: AppSpacing.dialog,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            _w('household.create'),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          TextField(
                            key: const Key('household-name-field'),
                            controller: _nameController,
                            decoration: InputDecoration(
                              labelText: _w('household.name'),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          FilledButton(
                            key: const Key('create-household-button'),
                            onPressed: _busy ? null : _createHousehold,
                            child: Text(_w('household.create')),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Card(
                    child: Padding(
                      padding: AppSpacing.dialog,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            _w('household.join'),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          invitations.when(
                            loading: () => const Center(
                              child: CircularProgressIndicator(),
                            ),
                            error: (_, _) =>
                                Text(_w('household.error.load_invitations')),
                            data: (items) => items.isEmpty
                                ? Text(_w('household.empty_invitations'))
                                : Column(
                                    children: [
                                      for (final invitation in items)
                                        ListTile(
                                          key: Key(
                                            'pending-invitation-${invitation.id}',
                                          ),
                                          contentPadding: EdgeInsets.zero,
                                          title: Text(invitation.householdName),
                                          subtitle: Text(
                                            AppWords.of(
                                              context,
                                            ).format('household.invited_by', {
                                              'name': invitation.invitedByName,
                                            }),
                                          ),
                                          trailing: FilledButton.tonal(
                                            onPressed: _busy
                                                ? null
                                                : () => _accept(invitation),
                                            child: Text(
                                              _w('household.join_action'),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MultipleHouseholdsPage extends ConsumerWidget {
  const MultipleHouseholdsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final words = AppWords.of(context);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: AppSpacing.page,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.warning_amber_rounded, size: 44),
                const SizedBox(height: AppSpacing.md),
                Text(
                  words.text('household.multiple.title'),
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  words.text('household.multiple.description'),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.lg),
                FilledButton.icon(
                  onPressed: () =>
                      ref.read(supabaseAuthGatewayProvider).signOut(),
                  icon: const Icon(Icons.logout_outlined),
                  label: Text(words.text('nav.logout')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
