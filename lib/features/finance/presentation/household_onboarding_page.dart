import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _createHousehold() async {
    final name = _nameController.text.trim();
    if (_busy || name.isEmpty) {
      setState(() => _error = 'Donnez un nom à votre foyer.');
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
        setState(
          () => _error =
              'Création impossible. Confirmez votre e-mail puis réessayez.',
        );
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
        setState(
          () => _error =
              'Cette invitation n’est plus disponible ou ne correspond pas à ce compte.',
        );
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
        title: const Text('Bienvenue dans FINANCIEL PILOTE'),
        actions: [
          IconButton(
            tooltip: 'Se déconnecter',
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
                    'Configurer votre foyer',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  const Text(
                    'Créez votre foyer principal ou acceptez une invitation reçue. Aucune donnée financière n’est créée ici.',
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Card(
                    child: Padding(
                      padding: AppSpacing.dialog,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Créer mon foyer',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          TextField(
                            key: const Key('household-name-field'),
                            controller: _nameController,
                            decoration: const InputDecoration(
                              labelText: 'Nom du foyer',
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          FilledButton(
                            key: const Key('create-household-button'),
                            onPressed: _busy ? null : _createHousehold,
                            child: const Text('Créer mon foyer'),
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
                            'Rejoindre un foyer',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          invitations.when(
                            loading: () => const Center(
                              child: CircularProgressIndicator(),
                            ),
                            error: (_, _) => const Text(
                              'Impossible de vérifier les invitations pour le moment.',
                            ),
                            data: (items) => items.isEmpty
                                ? const Text(
                                    'Aucune invitation en attente pour cette adresse e-mail.',
                                  )
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
                                            'Invitation de ${invitation.invitedByName}',
                                          ),
                                          trailing: FilledButton.tonal(
                                            onPressed: _busy
                                                ? null
                                                : () => _accept(invitation),
                                            child: const Text('Rejoindre'),
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
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
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
                'Plusieurs foyers opérationnels sont accessibles',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                'FINANCIEL PILOTE ne choisira jamais un foyer arbitrairement. Déconnectez-vous et contactez l’assistance pour régulariser cet accès.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                onPressed: () =>
                    ref.read(supabaseAuthGatewayProvider).signOut(),
                icon: const Icon(Icons.logout_outlined),
                label: const Text('Se déconnecter'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
