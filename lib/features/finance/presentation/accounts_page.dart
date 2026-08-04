import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_design_system.dart';
import '../application/providers/remote_accounts_provider.dart';

/// Shows only accounts persisted in the active Supabase household.
class AccountsPage extends ConsumerWidget {
  const AccountsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('Comptes')),
    floatingActionButton: const FloatingActionButton.extended(
      onPressed: null,
      icon: Icon(Icons.add),
      label: Text('Ajouter'),
    ),
    body: ref
        .watch(remoteAccountsProvider)
        .when(
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
              const Text(
                'La création manuelle distante sera disponible prochainement.',
              ),
              const SizedBox(height: AppSpacing.md),
              if (items.isEmpty)
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.account_balance_outlined),
                    title: Text('Aucun compte distant'),
                    subtitle: Text(
                      'Importez vos comptes initiaux pour les afficher ici.',
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
                        '${account.type.name} • ${account.holder ?? 'Foyer'} • '
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
