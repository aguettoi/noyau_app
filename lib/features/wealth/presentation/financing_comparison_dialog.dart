import 'package:flutter/material.dart';

import '../../../core/money/money.dart';
import '../../financial_availability/domain/financial_availability.dart';
import '../domain/financing_simulation.dart';
import '../domain/wealth_models.dart';

class FinancingComparisonDialog extends StatefulWidget {
  const FinancingComparisonDialog({required this.availability, super.key});

  final FinancialAvailabilitySnapshot availability;

  @override
  State<FinancingComparisonDialog> createState() =>
      _FinancingComparisonDialogState();
}

class _OfferControllers {
  _OfferControllers(String label)
    : label = TextEditingController(text: label),
      financed = TextEditingController(),
      downPayment = TextEditingController(text: '0'),
      duration = TextEditingController(text: '240'),
      rate = TextEditingController(),
      fixedCost = TextEditingController(text: '0'),
      benefits = TextEditingController(text: '0');

  final TextEditingController label;
  final TextEditingController financed;
  final TextEditingController downPayment;
  final TextEditingController duration;
  final TextEditingController rate;
  final TextEditingController fixedCost;
  final TextEditingController benefits;
  FinancingStructure structure = FinancingStructure.murabaha;

  void dispose() {
    label.dispose();
    financed.dispose();
    downPayment.dispose();
    duration.dispose();
    rate.dispose();
    fixedCost.dispose();
    benefits.dispose();
  }
}

class _FinancingComparisonDialogState extends State<FinancingComparisonDialog> {
  final _offers = [_OfferControllers('Offre A'), _OfferControllers('Offre B')];
  FinancingComparison? _comparison;
  String? _error;
  late DateTime _startDate = DateTime.now();

  @override
  void dispose() {
    for (final offer in _offers) {
      offer.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
    child: SizedBox(
      width: 980,
      height: MediaQuery.sizeOf(context).height * .92,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('Comparer des simulations de financement'),
          actions: [
            IconButton(
              tooltip: 'Fermer',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Card(
              child: ListTile(
                leading: Icon(Icons.science_outlined),
                title: Text('Simulation uniquement'),
                subtitle: Text(
                  'Aucune dette, obligation, écriture GL ou FinancialEvent n’est créé. Les hypothèses restent distinctes de la situation réelle.',
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.event_outlined),
              title: const Text('Date de départ de la simulation'),
              subtitle: Text(_date(_startDate)),
              trailing: const Icon(Icons.edit_calendar_outlined),
              onTap: _selectStartDate,
            ),
            LayoutBuilder(
              builder: (context, constraints) => constraints.maxWidth >= 720
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _offerForm(_offers[0], 0)),
                        const SizedBox(width: 12),
                        Expanded(child: _offerForm(_offers[1], 1)),
                      ],
                    )
                  : Column(
                      children: [
                        _offerForm(_offers[0], 0),
                        const SizedBox(height: 12),
                        _offerForm(_offers[1], 1),
                      ],
                    ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('compare-financing-offers'),
              onPressed: _compare,
              icon: const Icon(Icons.compare_arrows),
              label: const Text('Comparer les deux offres'),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (_comparison case final comparison?) ...[
              const SizedBox(height: 16),
              _results(comparison),
            ],
          ],
        ),
      ),
    ),
  );

  Widget _offerForm(_OfferControllers offer, int index) => Card(
    key: Key('financing-offer-$index'),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          TextField(
            controller: offer.label,
            decoration: const InputDecoration(labelText: 'Nom de l’offre'),
          ),
          DropdownButtonFormField<FinancingStructure>(
            initialValue: offer.structure,
            items: const [
              DropdownMenuItem(
                value: FinancingStructure.murabaha,
                child: Text('Murabaha / participatif'),
              ),
              DropdownMenuItem(
                value: FinancingStructure.fixedCost,
                child: Text('Financement à coût fixe'),
              ),
              DropdownMenuItem(
                value: FinancingStructure.interestLoan,
                child: Text('Prêt à intérêt'),
              ),
              DropdownMenuItem(
                value: FinancingStructure.other,
                child: Text('Autre structure'),
              ),
            ],
            onChanged: (value) => setState(() => offer.structure = value!),
            decoration: const InputDecoration(labelText: 'Structure'),
          ),
          _number(
            offer.financed,
            'Montant financé (MAD)',
            key: Key('financed-amount-$index'),
          ),
          _number(offer.downPayment, 'Apport (MAD)'),
          _number(offer.duration, 'Durée (mois)'),
          _number(offer.rate, 'Taux annuel (%) — prêt à intérêt uniquement'),
          _number(offer.fixedCost, 'Coût / marge fixe (MAD)'),
          _number(offer.benefits, 'Aides/avantages projetés (MAD)'),
        ],
      ),
    ),
  );

  Widget _number(TextEditingController controller, String label, {Key? key}) =>
      TextField(
        key: key,
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label),
      );

  void _compare() {
    try {
      final inputs = _offers.indexed.map((entry) {
        final index = entry.$1;
        final offer = entry.$2;
        final financed = _amount(offer.financed, required: true);
        final downPayment = _amount(offer.downPayment);
        final duration = int.tryParse(offer.duration.text.trim());
        final ratePercent = _optionalDouble(offer.rate);
        final fixedCost = _amount(offer.fixedCost);
        final benefits = _amount(offer.benefits);
        if (duration == null || duration <= 0) {
          throw const FormatException('La durée doit être positive.');
        }
        return FinancingSimulationInput(
          id: 'offer-$index',
          label: offer.label.text.trim().isEmpty
              ? 'Offre ${index + 1}'
              : offer.label.text.trim(),
          structure: offer.structure,
          financedAmount: financed,
          downPayment: downPayment,
          startDate: _startDate,
          durationMonths: duration,
          annualRate: offer.structure == FinancingStructure.interestLoan
              ? (ratePercent ?? 0) / 100
              : null,
          fixedTotalCost: offer.structure == FinancingStructure.interestLoan
              ? null
              : fixedCost,
          projectedBenefits: benefits,
        );
      });
      setState(() {
        _comparison = compareFinancingOffers(
          inputs,
          authorizedLiquidity: widget.availability.realLiquidity,
          availabilityComplete: widget.availability.isComplete,
        );
        _error = null;
      });
    } on FormatException catch (error) {
      setState(() {
        _comparison = null;
        _error = error.message;
      });
    } on ArgumentError catch (error) {
      setState(() {
        _comparison = null;
        _error = error.message?.toString() ?? 'Hypothèses invalides.';
      });
    }
  }

  Future<void> _selectStartDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(1900),
      lastDate: DateTime(2200),
    );
    if (selected != null && mounted) {
      setState(() => _startDate = selected);
    }
  }

  Widget _results(FinancingComparison comparison) => Card(
    key: const Key('financing-comparison-results'),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Comparaison explicable',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          ...comparison.results.map(
            (result) => ListTile(
              title: Text(result.input.label),
              subtitle: Text(
                '${result.input.structure.name} · apport ${_money(result.input.downPayment)} · ${result.input.durationMonths} mois\n'
                'Échéance ${_money(result.periodicPayment)} · coût ${_money(result.totalCost)} · total payé ${_money(result.totalPaid)} · coût net projeté ${_money(result.netProjectedCost)}\n'
                'Fin projetée ${_date(result.endDate)} · capacité ${_capacity(result.capacityStatus)}',
              ),
            ),
          ),
          const Divider(),
          Text(
            'Coût projeté le plus faible : ${comparison.lowestProjectedCost?.input.label}. '
            'Échéance la plus faible : ${comparison.lowestPayment?.input.label}. '
            'Durée la plus courte : ${comparison.shortestDuration?.input.label}.',
          ),
          const SizedBox(height: 8),
          const Text(
            'Ces constats ne désignent pas automatiquement un “meilleur choix”. Liquidité, durée, objectifs et conditions contractuelles doivent être arbitrés par le foyer.',
          ),
          if (!widget.availability.isComplete)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Capacité non conclue : les données autorisées sont incomplètes. Aucun montant privé n’est déduit ni affiché.',
              ),
            ),
        ],
      ),
    ),
  );
}

Money _amount(TextEditingController controller, {bool required = false}) {
  final value = double.tryParse(controller.text.trim().replaceAll(',', '.'));
  if (value == null) {
    if (!required && controller.text.trim().isEmpty) {
      return const Money.fromMinorUnits(0);
    }
    throw const FormatException(
      'Tous les montants requis doivent être valides.',
    );
  }
  if (value < 0 || required && value == 0) {
    throw const FormatException('Les montants doivent être positifs.');
  }
  return Money.fromDirhams(value);
}

double? _optionalDouble(TextEditingController controller) {
  if (controller.text.trim().isEmpty) return null;
  final value = double.tryParse(controller.text.trim().replaceAll(',', '.'));
  if (value == null || value < 0) {
    throw const FormatException('Le taux doit être valide.');
  }
  return value;
}

String _money(Money value) => '${value.dirhams.toStringAsFixed(2)} MAD';
String _date(DateTime value) => value.toIso8601String().split('T').first;
String _capacity(FinancingCapacityStatus status) => switch (status) {
  FinancingCapacityStatus.sufficient => 'apport possible',
  FinancingCapacityStatus.insufficient => 'apport non couvert',
  FinancingCapacityStatus.unavailable => 'à confirmer',
};
