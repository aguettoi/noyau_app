import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../../core/theme/app_design_system.dart';
import '../../finance/application/providers/remote_debts_provider.dart';
import '../../finance/presentation/transactions_page.dart';
import '../application/providers/wealth_provider.dart';
import '../domain/wealth_models.dart';
import 'home_auto_panels.dart';

class WealthPage extends ConsumerWidget {
  const WealthPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('Patrimoine & financements')),
    body: ref
        .watch(wealthDataProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) =>
              Center(child: Text('Chargement impossible : $error')),
          data: (data) => DefaultTabController(
            length: 5,
            child: Column(
              children: [
                const TabBar(
                  tabs: [
                    Tab(text: 'Patrimoine'),
                    Tab(text: 'Investissements'),
                    Tab(text: 'Financements'),
                    Tab(text: 'Logement'),
                    Tab(text: 'Véhicules'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _WealthOverview(data, ref),
                      _Investments(data, ref),
                      _Financings(data),
                      HomePanel(wealth: data),
                      VehiclePanel(wealth: data),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => _showCreateMenu(context, ref),
      icon: const Icon(Icons.add),
      label: const Text('Ajouter'),
    ),
  );

  Future<void> _showCreateMenu(BuildContext context, WidgetRef ref) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Actif patrimonial'),
              leading: const Icon(Icons.home_work_outlined),
              onTap: () => Navigator.pop(context, 'asset'),
            ),
            ListTile(
              title: const Text('Investissement'),
              leading: const Icon(Icons.trending_up),
              onTap: () => Navigator.pop(context, 'investment'),
            ),
            ListTile(
              title: const Text('Financement lié à une dette'),
              leading: const Icon(Icons.request_quote_outlined),
              onTap: () => Navigator.pop(context, 'financing'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted || choice == null) return;
    if (choice == 'asset') {
      await _createAsset(context, ref);
    }
    if (!context.mounted) return;
    if (choice == 'investment') {
      await _createInvestment(context, ref);
    }
    if (!context.mounted) return;
    if (choice == 'financing') {
      await _createFinancing(context, ref);
    }
  }

  Future<void> _createAsset(BuildContext context, WidgetRef ref) async {
    final label = TextEditingController();
    final value = TextEditingController();
    var type = 'other';
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Nouvel actif'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: label,
                decoration: const InputDecoration(labelText: 'Libellé'),
              ),
              DropdownButtonFormField<String>(
                initialValue: type,
                items: const [
                  DropdownMenuItem(
                    value: 'real_estate',
                    child: Text('Immobilier'),
                  ),
                  DropdownMenuItem(value: 'vehicle', child: Text('Véhicule')),
                  DropdownMenuItem(value: 'other', child: Text('Autre')),
                ],
                onChanged: (v) => setState(() => type = v!),
                decoration: const InputDecoration(labelText: 'Type'),
              ),
              TextField(
                controller: value,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Valeur d’acquisition (MAD)',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Créer'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || label.text.trim().isEmpty) return;
    await ref.read(wealthActionsProvider).createAsset({
      'label': label.text.trim(),
      'asset_type': type,
      'ownership_type': 'household',
      'acquisition_value': double.tryParse(value.text.replaceAll(',', '.')),
      'acquisition_date': DateTime.now().toIso8601String().split('T').first,
    });
  }

  Future<void> _createInvestment(BuildContext context, WidgetRef ref) async {
    final label = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Nouvel investissement'),
        content: TextField(
          controller: label,
          decoration: const InputDecoration(labelText: 'Libellé'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Créer'),
          ),
        ],
      ),
    );
    if (ok != true || label.text.trim().isEmpty) return;
    await ref.read(wealthActionsProvider).createInvestment({
      'label': label.text.trim(),
      'product_type': 'other',
    });
  }

  Future<void> _createFinancing(BuildContext context, WidgetRef ref) async {
    final debts = await ref.read(remoteDebtBalancesProvider.future);
    if (!context.mounted) return;
    if (debts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Créez d’abord la dette canonique correspondante.'),
        ),
      );
      return;
    }
    final label = TextEditingController();
    final principal = TextEditingController();
    final duration = TextEditingController(text: '12');
    var debtId = debts.first.id;
    var structure = 'fixed_cost';
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Nouveau financement'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: label,
                  decoration: const InputDecoration(labelText: 'Libellé'),
                ),
                DropdownButtonFormField<String>(
                  initialValue: debtId,
                  items: debts
                      .map(
                        (d) => DropdownMenuItem(
                          value: d.id,
                          child: Text(d.description),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => debtId = v!),
                  decoration: const InputDecoration(
                    labelText: 'Dette canonique',
                  ),
                ),
                DropdownButtonFormField<String>(
                  initialValue: structure,
                  items: const [
                    DropdownMenuItem(
                      value: 'interest_loan',
                      child: Text('Prêt à intérêt'),
                    ),
                    DropdownMenuItem(
                      value: 'murabaha',
                      child: Text('Murabaha / participatif'),
                    ),
                    DropdownMenuItem(
                      value: 'fixed_cost',
                      child: Text('Coût fixe'),
                    ),
                    DropdownMenuItem(value: 'other', child: Text('Autre')),
                  ],
                  onChanged: (v) => setState(() => structure = v!),
                  decoration: const InputDecoration(labelText: 'Structure'),
                ),
                TextField(
                  controller: principal,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Capital initial',
                  ),
                ),
                TextField(
                  controller: duration,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Durée (mois)'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Créer'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || label.text.trim().isEmpty) return;
    await ref.read(wealthActionsProvider).createFinancing({
      'label': label.text.trim(),
      'structure_type': structure,
      'obligation_id': debtId,
      'principal_initial':
          double.tryParse(principal.text.replaceAll(',', '.')) ??
          debts.first.initialAmount.dirhams,
      'start_date': DateTime.now().toIso8601String().split('T').first,
      'duration_months': int.tryParse(duration.text) ?? 12,
      'periodicity_months': 1,
      'annual_rate': structure == 'interest_loan' ? 0.0 : null,
    });
  }
}

class _WealthOverview extends StatelessWidget {
  const _WealthOverview(this.data, this.ref);
  final WealthData data;
  final WidgetRef ref;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(AppSpacing.md),
    children: [
      Text('Valeur nette', style: Theme.of(context).textTheme.headlineSmall),
      Text(
        _money(data.snapshot.netWorth),
        style: Theme.of(context).textTheme.displaySmall,
      ),
      const SizedBox(height: AppSpacing.md),
      ResponsiveGrid(
        minItemWidth: 220,
        children: [
          _metric(
            'Liquidités',
            data.snapshot.liquidity,
            Icons.account_balance_wallet_outlined,
          ),
          _metric(
            'Investissements',
            data.snapshot.investments,
            Icons.trending_up,
          ),
          _metric(
            'Actifs suivis',
            data.snapshot.assets,
            Icons.home_work_outlined,
          ),
          _metric(
            'Passifs',
            data.snapshot.liabilities,
            Icons.request_quote_outlined,
          ),
        ],
      ),
      const SizedBox(height: AppSpacing.md),
      Text('Actifs valorisés', style: Theme.of(context).textTheme.titleLarge),
      if (data.assets.isEmpty)
        const ListTile(
          title: Text('Aucun actif suivi'),
          subtitle: Text(
            'Les comptes restent alimentés automatiquement par le Grand Ledger.',
          ),
        )
      else
        ...data.assets.map(
          (a) => ListTile(
            title: Text(a.label),
            subtitle: Text(
              '${a.type.name} · valeur au ${a.valuationDate?.toIso8601String().split('T').first ?? 'non datée'}',
            ),
            trailing: Text(_money(a.currentValue)),
            onTap: () => _newValuation(context, a),
          ),
        ),
    ],
  );
  Widget _metric(String title, Money value, IconData icon) => Card(
    child: ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(
        _money(value),
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
  );

  Future<void> _newValuation(BuildContext context, WealthAsset asset) async {
    final value = await _askAmount(
      context,
      'Nouvelle valorisation — ${asset.label}',
    );
    if (value == null) return;
    await ref
        .read(wealthActionsProvider)
        .valueAsset(asset.id, value, DateTime.now());
  }
}

class _Investments extends StatelessWidget {
  const _Investments(this.data, this.ref);
  final WealthData data;
  final WidgetRef ref;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(AppSpacing.md),
    children: [
      const Card(
        child: ListTile(
          leading: Icon(Icons.info_outline),
          title: Text('Réel et projeté restent séparés'),
          subtitle: Text(
            'Un versement, retrait ou gain réel doit être lié à un FinancialEvent canonique. Une simulation ne crée aucune écriture.',
          ),
        ),
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: () => _simulate(context),
          icon: const Icon(Icons.calculate_outlined),
          label: const Text('Simuler un investissement'),
        ),
      ),
      if (data.investments.isEmpty)
        const ListTile(title: Text('Aucun investissement suivi'))
      else
        ...data.investments.map(
          (i) => Card(
            child: ExpansionTile(
              title: Text(i.label),
              subtitle: Text(
                'Capital net ${_money(i.netCapital)} · gain net ${_money(i.netGain)}${i.backingAccountId == null ? '' : ' · valeur portée par le compte lié'}',
              ),
              trailing: Text(_money(i.currentValue)),
              children: [
                ListTile(
                  leading: const Icon(Icons.price_change_outlined),
                  title: const Text('Ajouter une valorisation'),
                  subtitle: const Text(
                    'Historique non financier et append-only.',
                  ),
                  onTap: () => _value(context, i),
                ),
                ListTile(
                  leading: const Icon(Icons.link),
                  title: const Text('Lier une opération réelle'),
                  subtitle: const Text(
                    'Le FinancialEvent doit déjà avoir été créé par le flux canonique.',
                  ),
                  onTap: () => _linkOperation(context, i),
                ),
              ],
            ),
          ),
        ),
    ],
  );
  Future<void> _simulate(BuildContext context) async {
    final result = projectInvestment(
      const InvestmentProjectionInput(
        initialCapital: Money.fromMinorUnits(100000),
        periodicContribution: Money.fromMinorUnits(10000),
        annualRate: .04,
        taxRate: .15,
        months: 12,
      ),
    );
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Projection illustrative'),
        content: Text(
          'Capital versé ${_money(result.capitalPaid)}\nGain brut ${_money(result.grossGain)}\nRetenue ${_money(result.tax)}\nValeur projetée ${_money(result.projectedValue)}\n\nProjection uniquement.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  Future<void> _value(
    BuildContext context,
    InvestmentPosition investment,
  ) async {
    final value = await _askAmount(
      context,
      'Valeur actuelle — ${investment.label}',
    );
    if (value == null) return;
    await ref
        .read(wealthActionsProvider)
        .valueInvestment(investment.id, value, DateTime.now());
  }

  Future<void> _linkOperation(
    BuildContext context,
    InvestmentPosition investment,
  ) async {
    if (data.eventCandidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Aucun FinancialEvent canonique disponible à rattacher.',
          ),
        ),
      );
      return;
    }
    var eventId = data.eventCandidates.first.id;
    var type = 'contribution';
    final amount = TextEditingController();
    final tax = TextEditingController(text: '0');
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Rattacher une opération canonique'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: eventId,
                  items: data.eventCandidates
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.id,
                          child: Text(
                            e.description,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => eventId = v!),
                  decoration: const InputDecoration(
                    labelText: 'FinancialEvent',
                  ),
                ),
                DropdownButtonFormField<String>(
                  initialValue: type,
                  items: const [
                    DropdownMenuItem(
                      value: 'contribution',
                      child: Text('Versement'),
                    ),
                    DropdownMenuItem(
                      value: 'withdrawal',
                      child: Text('Retrait'),
                    ),
                    DropdownMenuItem(
                      value: 'distribution',
                      child: Text('Distribution / gain reçu'),
                    ),
                    DropdownMenuItem(
                      value: 'tax_withholding',
                      child: Text('Retenue / taxe'),
                    ),
                  ],
                  onChanged: (v) => setState(() => type = v!),
                  decoration: const InputDecoration(labelText: 'Nature'),
                ),
                TextField(
                  controller: amount,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Montant brut (MAD)',
                  ),
                ),
                TextField(
                  controller: tax,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Retenue incluse (MAD)',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Rattacher'),
            ),
          ],
        ),
      ),
    );
    final gross = double.tryParse(amount.text.replaceAll(',', '.'));
    final withholding = double.tryParse(tax.text.replaceAll(',', '.')) ?? 0;
    if (accepted != true ||
        gross == null ||
        gross <= 0 ||
        withholding < 0 ||
        withholding > gross) {
      return;
    }
    await ref.read(wealthActionsProvider).linkOperation({
      'investment_id': investment.id,
      'operation_type': type,
      'gross_amount': gross,
      'tax_amount': withholding,
      'occurred_on': DateTime.now().toIso8601String().split('T').first,
      'financial_event_id': eventId,
      'idempotency_key': eventId,
    });
  }
}

class _Financings extends StatelessWidget {
  const _Financings(this.data);
  final WealthData data;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(AppSpacing.md),
    children: [
      Card(
        child: ListTile(
          leading: const Icon(Icons.shield_outlined),
          title: const Text('Capacité financière canonique'),
          subtitle: Text(
            'Liquidité réelle disponible : ${_money(data.availability.realLiquidity)}. Toute décision “puis-je rembourser ?” réutilise FinancialAvailability.',
          ),
        ),
      ),
      if (data.financings.isEmpty)
        const ListTile(
          title: Text('Aucun financement configuré'),
          subtitle: Text(
            'Un financement réel doit être lié à une obligation existante.',
          ),
        )
      else
        ...data.financings.map(
          (f) => Card(
            child: ExpansionTile(
              title: Text(f.label),
              subtitle: Text(
                'Restant canonique ${_money(f.remainingLiability)} · ${f.structure.name}',
              ),
              children: [
                ...buildFinancingSchedule(f)
                    .take(12)
                    .map(
                      (line) => ListTile(
                        dense: true,
                        title: Text(
                          'Échéance ${line.number} · ${line.date.toIso8601String().split('T').first}',
                        ),
                        subtitle: Text(
                          'Capital ${_money(line.principal)} · coût/marge ${_money(line.cost)}',
                        ),
                        trailing: Text(_money(line.payment)),
                      ),
                    ),
                ListTile(
                  title: const Text('Remboursement anticipé'),
                  subtitle: const Text(
                    'Simulation uniquement : réduction de durée ou d’échéance, selon le contrat.',
                  ),
                  trailing: const Icon(Icons.calculate_outlined),
                  onTap: () => _early(context, f),
                ),
                ListTile(
                  title: const Text('Paiement réel'),
                  subtitle: const Text(
                    'À enregistrer via le règlement canonique de l’obligation — jamais depuis l’échéancier projeté.',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const TransactionsPage(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
    ],
  );
  Future<void> _early(BuildContext context, FinancingProfile f) async {
    if (f.remainingLiability.minorUnits <= 0) return;
    final amount = Money.fromMinorUnits(
      (f.remainingLiability.minorUnits / 10).round(),
    );
    final duration = projectEarlyRepayment(
      f,
      amount,
      EarlyRepaymentStrategy.reduceDuration,
    );
    final payment = projectEarlyRepayment(
      f,
      amount,
      EarlyRepaymentStrategy.reducePayment,
    );
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Simulation remboursement anticipé'),
        content: Text(
          'Montant simulé : ${_money(amount)}\n\nRéduire la durée : ${duration.remainingMonths} mois restants, économie estimée ${_money(duration.estimatedCostSaving)}.\n\nRéduire l’échéance : nouvelle échéance ${_money(payment.newPayment)}, économie estimée ${_money(payment.estimatedCostSaving)}.\n\nAucune écriture financière.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }
}

String _money(Money value) => '${value.dirhams.toStringAsFixed(2)} MAD';

Future<Money?> _askAmount(BuildContext context, String title) async {
  final controller = TextEditingController();
  final accepted = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: 'Montant (MAD)'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Enregistrer'),
        ),
      ],
    ),
  );
  final value = double.tryParse(controller.text.replaceAll(',', '.'));
  return accepted == true && value != null && value >= 0
      ? Money.fromDirhams(value)
      : null;
}
