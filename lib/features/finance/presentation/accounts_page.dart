import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/money/money.dart';
import '../application/accounts_controller.dart';
import '../domain/financial_account.dart';

class AccountsPage extends ConsumerWidget {
  const AccountsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('Comptes')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => _form(context, ref),
      icon: const Icon(Icons.add),
      label: const Text('Ajouter'),
    ),
    body: ref
        .watch(accountsProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) =>
              Center(child: Text('Impossible de lire les comptes : $e')),
          data: (items) => ListView(
            padding: const EdgeInsets.all(16),
            children: items
                .map(
                  (a) => Card(
                    child: ListTile(
                      title: Text(a.name),
                      subtitle: Text(
                        '${a.type.name} • ${a.holder ?? 'Foyer'} • ${a.isArchived ? 'Archivé' : 'Actif'}',
                      ),
                      trailing: Text(
                        '${a.openingBalance.dirhams.toStringAsFixed(2)} MAD',
                      ),
                      onTap: () => _actions(context, ref, a),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
  );
  Future<void> _actions(BuildContext c, WidgetRef r, FinancialAccount a) =>
      showDialog<void>(
        context: c,
        builder: (d) => AlertDialog(
          title: Text(a.name),
          content: Text(
            a.isArchived
                ? 'Compte archivé : il reste dans l’historique.'
                : 'Compte actif.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(d);
                _form(c, r, a);
              },
              child: const Text('Modifier'),
            ),
            FilledButton(
              onPressed: () async {
                await r
                    .read(accountsProvider.notifier)
                    .save(
                      a.copyWith(
                        archivedAt: a.isArchived ? null : DateTime.now(),
                        clearArchivedAt: a.isArchived,
                      ),
                    );
                if (d.mounted) Navigator.pop(d);
              },
              child: Text(a.isArchived ? 'Réactiver' : 'Archiver'),
            ),
          ],
        ),
      );
  Future<void> _form(BuildContext c, WidgetRef r, [FinancialAccount? a]) async {
    final key = GlobalKey<FormState>();
    final name = TextEditingController(text: a?.name ?? '');
    final holder = TextEditingController(text: a?.holder ?? '');
    FinancialAccountType? type = a?.type;
    await showDialog<void>(
      context: c,
      builder: (d) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(a == null ? 'Créer un compte' : 'Modifier le compte'),
          content: Form(
            key: key,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Nom'),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Le nom est obligatoire.'
                      : null,
                ),
                DropdownButtonFormField(
                  initialValue: type,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: FinancialAccountType.values
                      .map(
                        (v) => DropdownMenuItem(value: v, child: Text(v.name)),
                      )
                      .toList(),
                  onChanged: (v) => set(() => type = v),
                  validator: (v) => v == null ? 'Choisissez un type.' : null,
                ),
                TextFormField(
                  controller: holder,
                  decoration: const InputDecoration(
                    labelText: 'Titulaire (facultatif)',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(d),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () async {
                if (!key.currentState!.validate()) return;
                await r
                    .read(accountsProvider.notifier)
                    .save(
                      a == null
                          ? FinancialAccount(
                              id: 'account-${DateTime.now().microsecondsSinceEpoch}',
                              name: name.text.trim(),
                              type: type!,
                              holder: holder.text.trim().isEmpty
                                  ? null
                                  : holder.text.trim(),
                              openingBalance: const Money.fromMinorUnits(0),
                            )
                          : a.copyWith(
                              name: name.text.trim(),
                              type: type!,
                              holder: holder.text.trim().isEmpty
                                  ? null
                                  : holder.text.trim(),
                            ),
                    );
                if (d.mounted) Navigator.pop(d);
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }
}
