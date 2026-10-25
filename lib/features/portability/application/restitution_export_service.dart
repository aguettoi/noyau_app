import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/money/money.dart';
import '../../envelopes/application/providers/remote_envelopes_provider.dart';
import '../../finance/application/providers/remote_account_balances_provider.dart';
import '../../finance/application/providers/remote_accounts_provider.dart';
import '../../finance/application/providers/remote_debts_provider.dart';
import '../../finance/application/providers/remote_transactions_provider.dart';
import '../../finance/domain/financial_account.dart';
import '../../finance/domain/transaction_draft.dart';
import '../../finance/domain/transaction_history_item.dart';
import '../../reporting/domain/business_reporting.dart';
import '../../wealth/application/providers/home_auto_provider.dart';
import '../../wealth/application/providers/wealth_provider.dart';
import '../../wealth/domain/home_auto_models.dart';
import '../../wealth/domain/wealth_models.dart';
import '../domain/portability_models.dart';
import '../domain/restitution_models.dart';
import 'restitution_formatters.dart';

class RestitutionExportService {
  RestitutionExportService(this.ref);
  final Ref ref;

  String _stamp() =>
      DateFormat('yyyyMMdd_HHmmss').format(DateTime.now().toUtc());

  Future<RestitutionDataset> dataset(RestitutionPeriod period) async {
    final values = await Future.wait([
      ref.read(remoteEnvelopeBalancesProvider.future),
      ref.read(remoteAccountsProvider.future),
      ref.read(remoteAccountBalancesProvider.future),
      ref.read(remoteDebtBalancesProvider.future),
      ref.read(remoteReceivableBalancesProvider.future),
      ref.read(wealthDataProvider.future),
      ref
          .read(transactionsSupabaseRepositoryProvider)
          .all(
            filter: TransactionHistoryFilter(
              from: period.start,
              to: period.endExclusive.subtract(const Duration(microseconds: 1)),
              pageSize: 5000,
            ),
          ),
    ]);
    final envelopes = values[0] as List<RemoteEnvelopeBalance>;
    final accounts = values[1] as List<FinancialAccount>;
    final balances = values[2] as Map<String, Money>;
    final debts = values[3] as List<RemoteDebtBalance>;
    final receivables = values[4] as List<RemoteReceivableBalance>;
    final wealth = values[5] as WealthData;
    final transactions = values[6] as List<TransactionHistoryItem>;
    String nature(LedgerTransactionType type) => switch (type) {
      LedgerTransactionType.income ||
      LedgerTransactionType.incomeReceivable => 'Revenus réalisés',
      LedgerTransactionType.transfer ||
      LedgerTransactionType.accountTransfer ||
      LedgerTransactionType.envelopeTransfer => 'Transferts réalisés',
      _ => 'Dépenses réalisées',
    };
    final timeline = buildSignificantTimeline(
      period: ReportingPeriod(
        start: period.start,
        endExclusive: period.endExclusive,
      ),
      nativeEvents: transactions,
      importedFacts: const [],
      closeDecisions: const [],
      dues: wealth.consolidatedDues,
    );
    return RestitutionDataset(
      period: period,
      envelopes: [
        for (final e in envelopes.where((e) => !e.isArchived))
          EnvelopeExportRow(
            label: e.name,
            balance: e.balance,
            status: e.isSystem ? 'Système' : 'Active',
            scope: e.economicRule,
            provenance: 'Envelope Ledger canonique',
          ),
      ],
      journal: [
        for (final t in transactions.where(
          (t) => period.contains(t.occurredAt),
        ))
          JournalExportRow(
            date: t.occurredAt,
            kind: nature(t.type),
            label: t.description,
            amount: t.amount,
            status: ReportFactStatus.observed,
            provenance: 'FinancialEvent / Grand Ledger',
            actor: t.actorId,
          ),
      ],
      cashPositions: [
        for (final a in accounts.where(
          (a) =>
              !a.isArchived &&
              !a.isSystem &&
              a.canReadBalance &&
              (a.type == FinancialAccountType.bank ||
                  a.type == FinancialAccountType.cash ||
                  a.type == FinancialAccountType.savings),
        ))
          CashPositionExportRow(
            label: a.name,
            kind: a.type.name,
            balance: balances[a.id] ?? const Money.fromMinorUnits(0),
            scope: a.visibility,
            provenance: 'Grand Ledger autorisé',
          ),
      ],
      obligations: [
        for (final d in debts)
          ObligationExportRow(
            kind: 'Dette',
            label: d.description,
            counterparty: d.creditorName,
            initialAmount: d.initialAmount,
            settledAmount: d.settledAmount,
            remainingAmount: d.remainingAmount,
            dueAt: d.dueAt,
            status: d.displayStatus,
            provenance: 'Obligation canonique',
          ),
        for (final r in receivables)
          ObligationExportRow(
            kind: 'Créance',
            label: r.description,
            counterparty: r.counterpartyName,
            initialAmount: r.initialAmount,
            settledAmount: r.settledAmount,
            remainingAmount: r.remainingAmount,
            dueAt: r.dueAt,
            status: r.status,
            provenance: 'Créance canonique',
          ),
      ],
      timeline: timeline,
      assets: wealth.assets,
      financings: wealth.financings,
      netWorth: wealth.snapshot.netWorth,
      limitations: const [
        'Restitution limitée aux données autorisées côté serveur pour la session courante.',
        'Les montants masqués et les comptes privés non partagés sont exclus, sans total déductible.',
        'Les faits observés, importés, attendus et projetés restent explicitement distingués.',
      ],
    );
  }

  String _name(String kind, RestitutionPeriod period, String extension) =>
      'FINANCIEL_PILOTE_${kind}_${period.fileKey}_${_stamp()}.$extension';

  Future<PortableFile> structuredXlsx(RestitutionPeriod period) async =>
      PortableFile(
        _name('EXPORT_STRUCTURE', period, 'xlsx'),
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        encodeStructuredHouseholdXlsx(await dataset(period)),
      );

  Future<PortableFile> periodPdf(RestitutionPeriod period) async =>
      PortableFile(
        _name('RAPPORT', period, 'pdf'),
        'application/pdf',
        await encodePeriodReportPdf(await dataset(period)),
      );

  Future<PortableFile> periodPptx(
    RestitutionPeriod period,
  ) async => PortableFile(
    _name('PRESENTATION', period, 'pptx'),
    'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    encodePeriodPresentationPptx(await dataset(period)),
  );

  Future<PortableFile> amortizationXlsx(FinancingProfile financing) async =>
      PortableFile(
        'FINANCIEL_PILOTE_AMORTISSEMENT_${financing.id}_${_stamp()}.xlsx',
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        encodeAmortizationXlsx(
          AmortizationExportDataset(
            financing: financing,
            schedule: buildFinancingSchedule(financing),
          ),
        ),
      );

  Future<PortableFile> fiscalHousingXlsx(RestitutionPeriod period) async {
    final data = await ref.read(homeAutoDataProvider.future);
    final rows = data.benefits
        .where((b) => b.type == BenefitType.taxSaving)
        .where(
          (b) =>
              b.periodStart == null ||
              b.periodStart!.isBefore(period.endExclusive),
        )
        .where(
          (b) => b.periodEnd == null || !b.periodEnd!.isBefore(period.start),
        )
        .map(
          (b) => FiscalHousingExportRow(
            periodStart: b.periodStart,
            periodEnd: b.periodEnd,
            effectiveDate: b.effectiveDate,
            recognition: b.recognition == BenefitRecognition.projected
                ? 'Économie fiscale estimée (projection)'
                : 'Avantage fiscal constaté',
            amount: b.amount,
            rate: b.rate,
            eligibleBase: b.eligibleBase,
            ceiling: b.ceiling,
            source: b.financialEventId == null
                ? 'Simulation/configuration fiscale'
                : 'Flux canonique ${b.financialEventId}',
          ),
        )
        .toList(growable: false);
    return PortableFile(
      _name('FISCALITE_LOGEMENT', period, 'xlsx'),
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      encodeFiscalHousingXlsx(
        FiscalHousingExportDataset(
          period: period,
          rows: rows,
          limitations: const [
            'Document informatif : il ne constitue pas une déclaration fiscale officielle.',
            'Les estimations ne créent aucune écriture financière.',
          ],
        ),
      ),
    );
  }
}

final restitutionExportServiceProvider = Provider(RestitutionExportService.new);
