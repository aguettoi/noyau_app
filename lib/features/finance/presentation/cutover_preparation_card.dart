import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_design_system.dart';
import '../application/cutover_preparation.dart';
import '../application/workbook_import.dart';

class CutoverPreparationCard extends StatefulWidget {
  const CutoverPreparationCard({
    required this.analysis,
    required this.onDirtyChanged,
    super.key,
  });

  final WorkbookImportAnalysis analysis;
  final ValueChanged<bool> onDirtyChanged;

  @override
  State<CutoverPreparationCard> createState() => _CutoverPreparationCardState();
}

class _CutoverPreparationCardState extends State<CutoverPreparationCard> {
  CutoverPreparation? _preparation;
  var _dirty = false;

  @override
  void dispose() {
    if (_dirty) widget.onDirtyChanged(false);
    super.dispose();
  }

  void _change(CutoverPreparation value) {
    setState(() => _preparation = value);
    if (!_dirty) {
      _dirty = true;
      widget.onDirtyChanged(true);
    }
  }

  void _start() {
    setState(
      () => _preparation = const CutoverPreparationBuilder().build(
        widget.analysis,
      ),
    );
    if (!_dirty) {
      _dirty = true;
      widget.onDirtyChanged(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preparation = _preparation;
    if (preparation == null) {
      return _ActionCard(
        icon: Icons.fact_check_outlined,
        title: 'Préparer le cutover réel',
        body:
            'Contrôlez les valeurs candidates du classeur avant toute écriture. Cette préparation reste locale à cet appareil.',
        action: OutlinedButton.icon(
          key: const Key('start-real-cutover-preparation'),
          onPressed: _start,
          icon: const Icon(Icons.manage_search_outlined),
          label: const Text('Examiner les données candidates'),
        ),
      );
    }

    return _ActionCard(
      icon: Icons.fact_check_outlined,
      title: 'Préparation du cutover réel',
      body:
          'Source → candidat → confirmé → écart. Aucune écriture financière ne sera créée à cette étape.',
      action: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SourceSummary(
            preparation: preparation,
            onDateSelected: (date) =>
                _change(preparation.copyWith(effectiveDate: date)),
          ),
          const SizedBox(height: AppSpacing.sm),
          _AccountReview(
            preparation: preparation,
            onChanged: (value) => _change(preparation.updateAccount(value)),
          ),
          const SizedBox(height: AppSpacing.sm),
          _EnvelopeReview(
            preparation: preparation,
            onChanged: (value) => _change(preparation.updateEnvelope(value)),
          ),
          const SizedBox(height: AppSpacing.sm),
          _IncomeReview(
            preparation: preparation,
            onChanged: (value) => _change(preparation.updateIncome(value)),
          ),
          const SizedBox(height: AppSpacing.sm),
          _ObligationReview(
            preparation: preparation,
            onChanged: (value) => _change(preparation.updateObligation(value)),
          ),
          const SizedBox(height: AppSpacing.sm),
          _PreparationSummary(preparation: preparation),
          const SizedBox(height: AppSpacing.sm),
          FilledButton.icon(
            key: const Key('future-cutover-plan-button'),
            onPressed: preparation.canPrepareFuturePlan
                ? () => _showReadyDialog(context)
                : null,
            icon: const Icon(Icons.lock_outline),
            label: const Text('Préparer la revue finale'),
          ),
          if (!preparation.canPrepareFuturePlan)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Date effective et confirmations requises : ${preparation.remainingConfirmations}.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showReadyDialog(BuildContext context) => showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(Icons.verified_outlined),
      title: const Text('Préparation locale prête'),
      content: const Text(
        'Les valeurs sont confirmées localement. Aucun plan B1 ni aucune écriture n’est créé ici ; la revue finale devra rester explicite.',
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Continuer la revue'),
        ),
      ],
    ),
  );
}

class _SourceSummary extends StatelessWidget {
  const _SourceSummary({
    required this.preparation,
    required this.onDateSelected,
  });

  final CutoverPreparation preparation;
  final ValueChanged<DateTime> onDateSelected;

  @override
  Widget build(BuildContext context) => _SectionCard(
    title: 'Date et source',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Fingerprint : ${preparation.sourceFingerprint}'),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                preparation.effectiveDate == null
                    ? 'Date effective : à confirmer'
                    : 'Date effective : ${_date(preparation.effectiveDate!)}',
              ),
            ),
            OutlinedButton.icon(
              key: const Key('cutover-effective-date-button'),
              onPressed: () async {
                final value = await showDatePicker(
                  context: context,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                  initialDate: preparation.effectiveDate ?? DateTime.now(),
                );
                if (value != null) onDateSelected(value);
              },
              icon: const Icon(Icons.calendar_today_outlined),
              label: const Text('Choisir la date'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Les dates visibles dans le classeur sont des informations de source : elles ne sont jamais retenues automatiquement.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
  );
}

class _AccountReview extends StatelessWidget {
  const _AccountReview({required this.preparation, required this.onChanged});
  final CutoverPreparation preparation;
  final ValueChanged<CutoverPreparationAccount> onChanged;

  @override
  Widget build(BuildContext context) => _SectionCard(
    title: 'Comptes candidats (${preparation.accounts.length})',
    child: Column(
      children: [
        const _CandidateTableHeader(),
        const SizedBox(height: 6),
        ...preparation.accounts.map(
          (account) => _AmountConfirmationRow(
            key: Key('cutover-account-${account.id}'),
            title: account.name,
            details: '${account.holder} • ${account.kind}',
            source: account.candidateSource,
            candidateAmount: account.candidateAmount,
            confirmedAmount: account.confirmedAmount,
            isConfirmed: account.isConfirmed,
            onAmountChanged: (value) => onChanged(
              account.copyWith(
                confirmedAmount: value,
                clearConfirmedAmount: value == null,
                isConfirmed: value == null ? false : account.isConfirmed,
              ),
            ),
            onConfirmedChanged: (value) => onChanged(
              account.copyWith(
                isConfirmed: value && account.confirmedAmount != null,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _EnvelopeReview extends StatelessWidget {
  const _EnvelopeReview({required this.preparation, required this.onChanged});
  final CutoverPreparation preparation;
  final ValueChanged<CutoverPreparationEnvelope> onChanged;

  @override
  Widget build(BuildContext context) => _SectionCard(
    title: 'Enveloppes candidates (${preparation.envelopes.length})',
    child: Column(
      children: [
        Text(
          'Les comptes et les enveloppes sont contrôlés séparément. Aucune différence ne sera compensée automatiquement.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        const _CandidateTableHeader(),
        const SizedBox(height: 6),
        ...preparation.envelopes.map(
          (envelope) => _AmountConfirmationRow(
            key: Key('cutover-envelope-${envelope.id}'),
            title: envelope.name,
            details: envelope.isToAllocate
                ? 'Enveloppe système — position indépendante'
                : 'Enveloppe ordinaire',
            source: envelope.candidateSource,
            candidateAmount: envelope.candidateAmount,
            confirmedAmount: envelope.confirmedAmount,
            isConfirmed: envelope.isConfirmed,
            onAmountChanged: (value) => onChanged(
              envelope.copyWith(
                confirmedAmount: value,
                clearConfirmedAmount: value == null,
                isConfirmed: value == null ? false : envelope.isConfirmed,
              ),
            ),
            onConfirmedChanged: (value) => onChanged(
              envelope.copyWith(
                isConfirmed: value && envelope.confirmedAmount != null,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _IncomeReview extends StatelessWidget {
  const _IncomeReview({required this.preparation, required this.onChanged});
  final CutoverPreparation preparation;
  final ValueChanged<CutoverPreparationIncome> onChanged;

  @override
  Widget build(BuildContext context) => _SectionCard(
    title: 'Revenus candidats',
    child: Column(
      children: preparation.incomes
          .map(
            (income) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: Text(income.name),
                    subtitle: Text(
                      '${income.isConfiguration ? 'Paramètre de budget, pas un encaissement' : 'Candidat'} : ${_money(income.candidateAmount)} • ${income.candidateSource}',
                    ),
                    value: income.isActive,
                    onChanged: (value) => onChanged(
                      income.copyWith(isActive: value, isConfirmed: false),
                    ),
                  ),
                  if (income.isActive) ...[
                    _TextInput(
                      label: 'Membre bénéficiaire',
                      value: income.member,
                      onChanged: (value) => onChanged(
                        income.copyWith(member: value, isConfirmed: false),
                      ),
                    ),
                    _TextInput(
                      label: 'Compte d’encaissement',
                      value: income.destinationAccount,
                      onChanged: (value) => onChanged(
                        income.copyWith(
                          destinationAccount: value,
                          isConfirmed: false,
                        ),
                      ),
                    ),
                    _AmountConfirmationRow(
                      title: 'Montant mensuel confirmé',
                      details:
                          'Aucun revenu n’est créé pendant la préparation.',
                      source: income.candidateSource,
                      candidateAmount: income.candidateAmount,
                      confirmedAmount: income.confirmedAmount,
                      isConfirmed: income.isConfirmed,
                      onAmountChanged: (value) => onChanged(
                        income.copyWith(
                          confirmedAmount: value,
                          clearConfirmedAmount: value == null,
                          isConfirmed: value == null
                              ? false
                              : income.isConfirmed,
                        ),
                      ),
                      onConfirmedChanged: (value) => onChanged(
                        income.copyWith(
                          isConfirmed:
                              value &&
                              income.confirmedAmount != null &&
                              income.member.trim().isNotEmpty &&
                              income.destinationAccount.trim().isNotEmpty,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          )
          .toList(growable: false),
    ),
  );
}

class _ObligationReview extends StatelessWidget {
  const _ObligationReview({required this.preparation, required this.onChanged});
  final CutoverPreparation preparation;
  final ValueChanged<CutoverPreparationObligation> onChanged;

  @override
  Widget build(BuildContext context) => _SectionCard(
    title: 'Obligations candidates',
    child: Column(
      children: preparation.obligations
          .map(
            (obligation) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: Text(obligation.name),
                    subtitle: Text(
                      '${obligation.classification.label}\nValeur candidate : ${_money(obligation.candidateAmount)} • ${obligation.candidateSource}',
                    ),
                    value: obligation.exists,
                    onChanged: (value) => onChanged(
                      obligation.copyWith(exists: value, isConfirmed: false),
                    ),
                  ),
                  if (obligation.exists) ...[
                    _TextInput(
                      label: 'Créancier',
                      value: obligation.creditor,
                      onChanged: (value) => onChanged(
                        obligation.copyWith(
                          creditor: value,
                          isConfirmed: false,
                        ),
                      ),
                    ),
                    _NumericInput(
                      label: 'Montant initial (MAD)',
                      value: obligation.initialAmount,
                      onChanged: (value) => onChanged(
                        obligation.copyWith(
                          initialAmount: value,
                          isConfirmed: false,
                        ),
                      ),
                    ),
                    _NumericInput(
                      label: 'Solde restant réel (MAD)',
                      value: obligation.remainingAmount,
                      onChanged: (value) => onChanged(
                        obligation.copyWith(
                          remainingAmount: value,
                          isConfirmed: false,
                        ),
                      ),
                    ),
                    _NumericInput(
                      label: 'Mensualité (MAD)',
                      value: obligation.monthlyAmount,
                      onChanged: (value) => onChanged(
                        obligation.copyWith(
                          monthlyAmount: value,
                          isConfirmed: false,
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            obligation.nextDueDate == null
                                ? 'Prochaine échéance : à confirmer'
                                : 'Prochaine échéance : ${_date(obligation.nextDueDate!)}',
                          ),
                        ),
                        TextButton(
                          onPressed: () async {
                            final date = await showDatePicker(
                              context: context,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2100),
                              initialDate:
                                  obligation.nextDueDate ?? DateTime.now(),
                            );
                            if (date != null) {
                              onChanged(
                                obligation.copyWith(
                                  nextDueDate: date,
                                  isConfirmed: false,
                                ),
                              );
                            }
                          },
                          child: const Text('Choisir'),
                        ),
                      ],
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Obligation confirmée'),
                      value: obligation.isConfirmed,
                      onChanged: (value) => onChanged(
                        obligation.copyWith(
                          isConfirmed:
                              value == true &&
                              obligation.creditor.trim().isNotEmpty &&
                              obligation.remainingAmount != null &&
                              obligation.nextDueDate != null,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          )
          .toList(growable: false),
    ),
  );
}

class _PreparationSummary extends StatelessWidget {
  const _PreparationSummary({required this.preparation});
  final CutoverPreparation preparation;

  @override
  Widget build(BuildContext context) => _SectionCard(
    title: 'Synthèse de contrôle',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _summaryLine(
          'Comptes',
          preparation.candidateAccountsTotal,
          preparation.confirmedAccountsTotal,
          preparation.accountsDifference,
        ),
        _summaryLine(
          'Enveloppes',
          preparation.candidateEnvelopesTotal,
          preparation.confirmedEnvelopesTotal,
          preparation.envelopesDifference,
        ),
        const SizedBox(height: 6),
        Text('Confirmés : ${preparation.confirmedCount}'),
        Text('À confirmer : ${preparation.remainingConfirmations}'),
        const SizedBox(height: 4),
        Text(
          'Les deux totaux sont indépendants : aucun écart ne génère de correction automatique.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
  );

  Widget _summaryLine(
    String label,
    num candidate,
    num confirmed,
    num delta,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(
      '$label — candidat ${_money(candidate)} • confirmé ${_money(confirmed)} • écart ${_money(delta)}',
    ),
  );
}

class _AmountConfirmationRow extends StatelessWidget {
  const _AmountConfirmationRow({
    required this.title,
    required this.details,
    required this.source,
    required this.candidateAmount,
    required this.confirmedAmount,
    required this.isConfirmed,
    required this.onAmountChanged,
    required this.onConfirmedChanged,
    super.key,
  });

  final String title;
  final String details;
  final String source;
  final num? candidateAmount;
  final num? confirmedAmount;
  final bool isConfirmed;
  final ValueChanged<num?> onAmountChanged;
  final ValueChanged<bool> onConfirmedChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 880;
        final item = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            Text(details, style: Theme.of(context).textTheme.bodySmall),
          ],
        );
        final sourceValue = Text(
          source,
          style: Theme.of(context).textTheme.bodySmall,
          maxLines: desktop ? 2 : null,
          overflow: desktop ? TextOverflow.ellipsis : TextOverflow.visible,
        );
        final candidate = Text(
          candidateAmount == null
              ? 'Calcul source à contrôler'
              : _money(candidateAmount),
          style: Theme.of(context).textTheme.bodySmall,
        );
        final amountField = TextFormField(
          key: ValueKey('$title-confirmed-value'),
          initialValue: confirmedAmount?.toString() ?? '',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Montant confirmé (MAD)',
            isDense: true,
            border: OutlineInputBorder(),
          ),
          onChanged: (value) => onAmountChanged(_parseAmount(value)),
        );
        final status = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Tooltip(
              message: confirmedAmount == null
                  ? 'Saisissez un montant avant confirmation.'
                  : 'Confirmer cette valeur.',
              child: Checkbox(
                value: isConfirmed,
                onChanged: confirmedAmount == null
                    ? null
                    : (value) => onConfirmedChanged(value ?? false),
              ),
            ),
            Flexible(
              child: Text(
                isConfirmed ? 'Confirmé' : 'À confirmer',
                style: TextStyle(
                  color: isConfirmed
                      ? const Color(0xFF4F6F52)
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        );
        return DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isConfirmed
                  ? const Color(0xFF4F6F52)
                  : Theme.of(context).dividerColor,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: desktop
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(width: 180, child: item),
                      const SizedBox(width: 12),
                      Expanded(flex: 3, child: sourceValue),
                      const SizedBox(width: 12),
                      SizedBox(width: 140, child: candidate),
                      const SizedBox(width: 12),
                      SizedBox(width: 220, child: amountField),
                      const SizedBox(width: 8),
                      SizedBox(width: 125, child: status),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      item,
                      const SizedBox(height: 4),
                      Text(
                        'Source : $source',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Text(
                        'Candidat : ${candidateAmount == null ? 'calcul source à contrôler' : _money(candidateAmount)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(child: amountField),
                          const SizedBox(width: 8),
                          status,
                        ],
                      ),
                    ],
                  ),
          ),
        );
      },
    ),
  );
}

class _CandidateTableHeader extends StatelessWidget {
  const _CandidateTableHeader();

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 880) return const SizedBox.shrink();
      final style = Theme.of(context).textTheme.labelSmall;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: [
            SizedBox(width: 180, child: Text('Élément', style: style)),
            const SizedBox(width: 12),
            const Expanded(flex: 3, child: Text('Source / candidat')),
            const SizedBox(width: 12),
            SizedBox(width: 140, child: Text('Valeur source', style: style)),
            const SizedBox(width: 12),
            SizedBox(
              width: 220,
              child: Text('Montant confirmé (MAD)', style: style),
            ),
            const SizedBox(width: 8),
            SizedBox(width: 125, child: Text('Statut', style: style)),
          ],
        ),
      );
    },
  );
}

class _TextInput extends StatelessWidget {
  const _TextInput({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: TextFormField(
      key: ValueKey('$label-$value'),
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
      onChanged: onChanged,
    ),
  );
}

class _NumericInput extends StatelessWidget {
  const _NumericInput({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final num? value;
  final ValueChanged<num?> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: TextFormField(
      key: ValueKey('$label-$value'),
      initialValue: value?.toString() ?? '',
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
      onChanged: (value) => onChanged(_parseAmount(value)),
    ),
  );
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    color: const Color(0xFFF7F8F5),
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          child,
        ],
      ),
    ),
  );
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.action,
  });
  final IconData icon;
  final String title;
  final String body;
  final Widget action;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: AppSpacing.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFF163A5F)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(body),
          const SizedBox(height: 12),
          action,
        ],
      ),
    ),
  );
}

num? _parseAmount(String value) {
  final parsed = num.tryParse(
    value.trim().replaceAll(' ', '').replaceAll(',', '.'),
  );
  return parsed != null && parsed >= 0 ? parsed : null;
}

String _money(num? value) => value == null
    ? 'Non déterminé'
    : NumberFormat.currency(
        locale: 'fr_FR',
        symbol: 'MAD',
        decimalDigits: 2,
      ).format(value);

String _date(DateTime value) => DateFormat('dd/MM/yyyy', 'fr_FR').format(value);
