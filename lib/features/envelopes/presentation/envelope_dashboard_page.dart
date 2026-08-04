import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_design_system.dart';
import '../../finance/application/workbook_import.dart';
import '../application/envelope_imported_data.dart';

class EnvelopeDashboardPage extends ConsumerWidget {
  const EnvelopeDashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final import = ref.watch(workbookImportProvider);
    final hasValidatedSources =
        import.isConfirmed &&
        import.selectedImporterIds.contains('envelopes') &&
        import.selectedImporterIds.contains('journal');
    final data = hasValidatedSources && import.analysis != null
        ? const EnvelopeImportedDataReader().read(import.analysis!)
        : null;

    return SafeArea(
      child: ListView(
        padding: AppSpacing.page,
        children: [
          Text('Enveloppes', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: AppSpacing.xs),
          const Text(
            'Soldes calcules a partir du Journal importe. Aucun montant n est saisi ici.',
          ),
          const SizedBox(height: AppSpacing.md),
          if (data == null)
            const Card(
              child: ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('Données Enveloppes non encore confirmées'),
                subtitle: Text(
                  'Dans Import, choisissez et confirmez les onglets Enveloppes et Journal. Les vrais soldes apparaîtront ici.',
                ),
              ),
            )
          else ...[
            Card(
              child: ListTile(
                leading: const Icon(Icons.account_balance_wallet_outlined),
                title: const Text('Total des enveloppes'),
                subtitle: Text('${_money(data.totalFunds)} MAD'),
                trailing: Text('${data.importedMovements} mouvements'),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            ...data.balances.map(
              (envelope) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Card(
                  child: ListTile(
                    title: Text(envelope.name),
                    trailing: Text('${_money(envelope.balance)} MAD'),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _money(dynamic amount) =>
      amount.dirhams.toStringAsFixed(2).replaceAll(RegExp(r'\.00$'), '');
}
