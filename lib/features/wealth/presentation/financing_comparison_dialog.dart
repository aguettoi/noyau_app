import 'package:flutter/material.dart';

import '../../../core/money/money.dart';
import '../../../core/localization/finance_residual_locale.dart';
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
  final _offers = [_OfferControllers(''), _OfferControllers('')];
  var _labelsInitialized = false;
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
  Widget build(BuildContext context) {
    final words = FinanceResidualWords.of(context);
    final compact = MediaQuery.sizeOf(context).width < 600;
    if (!_labelsInitialized) {
      _offers[0].label.text = words.text('financing.offer_a');
      _offers[1].label.text = words.text('financing.offer_b');
      _labelsInitialized = true;
    }
    return Dialog(
      insetPadding: compact ? EdgeInsets.zero : const EdgeInsets.all(40),
      child: SizedBox(
        width: 980,
        height: compact
            ? MediaQuery.sizeOf(context).height
            : MediaQuery.sizeOf(context).height * .92,
        child: Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            title: Text(
              words.text('financing.title'),
              style: compact ? const TextStyle(fontSize: 16) : null,
            ),
            actions: [
              IconButton(
                tooltip: words.text('members.close'),
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: ListTile(
                  leading: Icon(Icons.science_outlined),
                  title: Text(words.text('financing.simulation_only')),
                  subtitle: Text(words.text('financing.simulation_notice')),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.event_outlined),
                title: Text(words.text('financing.start_date')),
                subtitle: Text(_date(context, _startDate)),
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
                label: Text(words.text('financing.compare')),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
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
  }

  Widget _offerForm(_OfferControllers offer, int index) => Card(
    key: Key('financing-offer-$index'),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          TextField(
            controller: offer.label,
            decoration: InputDecoration(
              labelText: FinanceResidualWords.of(
                context,
              ).text('financing.offer_name'),
            ),
          ),
          DropdownButtonFormField<FinancingStructure>(
            initialValue: offer.structure,
            items: [
              DropdownMenuItem(
                value: FinancingStructure.murabaha,
                child: Text(
                  FinanceResidualWords.of(context).text('financing.murabaha'),
                ),
              ),
              DropdownMenuItem(
                value: FinancingStructure.fixedCost,
                child: Text(
                  FinanceResidualWords.of(context).text('financing.fixed_cost'),
                ),
              ),
              DropdownMenuItem(
                value: FinancingStructure.interestLoan,
                child: Text(
                  FinanceResidualWords.of(
                    context,
                  ).text('financing.interest_loan'),
                ),
              ),
              DropdownMenuItem(
                value: FinancingStructure.other,
                child: Text(
                  FinanceResidualWords.of(context).text('financing.other'),
                ),
              ),
            ],
            onChanged: (value) => setState(() => offer.structure = value!),
            decoration: InputDecoration(
              labelText: FinanceResidualWords.of(
                context,
              ).text('financing.structure'),
            ),
          ),
          _number(
            offer.financed,
            FinanceResidualWords.of(context).text('financing.financed_amount'),
            key: Key('financed-amount-$index'),
          ),
          _number(
            offer.downPayment,
            FinanceResidualWords.of(context).text('financing.down_payment'),
          ),
          _number(
            offer.duration,
            FinanceResidualWords.of(context).text('financing.duration'),
          ),
          _number(
            offer.rate,
            FinanceResidualWords.of(context).text('financing.annual_rate'),
          ),
          _number(
            offer.fixedCost,
            FinanceResidualWords.of(context).text('financing.fixed_margin'),
          ),
          _number(
            offer.benefits,
            FinanceResidualWords.of(context).text('financing.benefits'),
          ),
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
    final words = FinanceResidualWords.of(context);
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
          throw const FormatException('duration');
        }
        return FinancingSimulationInput(
          id: 'offer-$index',
          label: offer.label.text.trim().isEmpty
              ? words.format('financing.offer_number', {'number': index + 1})
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
        _error = words.text('financing.error.${error.message}');
      });
    } on ArgumentError {
      setState(() {
        _comparison = null;
        _error = words.text('financing.error.invalid_assumptions');
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
            FinanceResidualWords.of(context).text('financing.explainable'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          ...comparison.results.map(
            (result) => ListTile(
              title: Text(result.input.label),
              subtitle: Text(
                FinanceResidualWords.of(context).format('financing.result', {
                  'structure': _structure(result.input.structure),
                  'downPayment': _money(result.input.downPayment),
                  'duration': result.input.durationMonths,
                  'payment': _money(result.periodicPayment),
                  'cost': _money(result.totalCost),
                  'paid': _money(result.totalPaid),
                  'netCost': _money(result.netProjectedCost),
                  'endDate': _date(context, result.endDate),
                  'capacity': _capacity(result.capacityStatus),
                }),
              ),
            ),
          ),
          const Divider(),
          Text(
            FinanceResidualWords.of(context).format('financing.summary', {
              'cost': comparison.lowestProjectedCost?.input.label ?? '—',
              'payment': comparison.lowestPayment?.input.label ?? '—',
              'duration': comparison.shortestDuration?.input.label ?? '—',
            }),
          ),
          const SizedBox(height: 8),
          Text(FinanceResidualWords.of(context).text('financing.disclaimer')),
          if (!widget.availability.isComplete)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                FinanceResidualWords.of(
                  context,
                ).text('financing.capacity_incomplete'),
              ),
            ),
        ],
      ),
    ),
  );

  String _structure(FinancingStructure value) => FinanceResidualWords.of(
    context,
  ).text('financing.structure.${value.name}');

  String _capacity(FinancingCapacityStatus status) => FinanceResidualWords.of(
    context,
  ).text('financing.capacity.${status.name}');
}

Money _amount(TextEditingController controller, {bool required = false}) {
  final value = double.tryParse(controller.text.trim().replaceAll(',', '.'));
  if (value == null) {
    if (!required && controller.text.trim().isEmpty) {
      return const Money.fromMinorUnits(0);
    }
    throw const FormatException('invalid_amounts');
  }
  if (value < 0 || required && value == 0) {
    throw const FormatException('positive_amounts');
  }
  return Money.fromDirhams(value);
}

double? _optionalDouble(TextEditingController controller) {
  if (controller.text.trim().isEmpty) return null;
  final value = double.tryParse(controller.text.trim().replaceAll(',', '.'));
  if (value == null || value < 0) {
    throw const FormatException('invalid_rate');
  }
  return value;
}

String _money(Money value) => '${value.dirhams.toStringAsFixed(2)} MAD';
String _date(BuildContext context, DateTime value) =>
    MaterialLocalizations.of(context).formatCompactDate(value);
