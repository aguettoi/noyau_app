import 'workbook_import.dart';

/// Provenance status of an obligation mentioned by a source workbook.
///
/// A value from a scenario is not evidence of an outstanding obligation. The
/// status stays local to the preparation screen and has no materialisation
/// effect by itself.
enum CutoverObligationClassification {
  confirmable,
  ambiguous,
  nonImportableAutomatically,
}

extension CutoverObligationClassificationLabel
    on CutoverObligationClassification {
  String get label => switch (this) {
    CutoverObligationClassification.confirmable => 'Confirmable',
    CutoverObligationClassification.ambiguous =>
      'Ambiguë — confirmation utilisateur obligatoire',
    CutoverObligationClassification.nonImportableAutomatically =>
      'Non importable automatiquement',
  };
}

/// Local-only review state for a real cutover source.
///
/// It deliberately contains no database identifier and no execution method:
/// candidates remain candidates until a future, explicit Cutover B1 plan is
/// built from confirmed values.
class CutoverPreparation {
  const CutoverPreparation({
    required this.sourceFingerprint,
    required this.accounts,
    required this.envelopes,
    required this.incomes,
    required this.obligations,
    this.effectiveDate,
  });

  final String sourceFingerprint;
  final DateTime? effectiveDate;
  final List<CutoverPreparationAccount> accounts;
  final List<CutoverPreparationEnvelope> envelopes;
  final List<CutoverPreparationIncome> incomes;
  final List<CutoverPreparationObligation> obligations;

  int get confirmedCount =>
      accounts.where((item) => item.isConfirmed).length +
      envelopes.where((item) => item.isConfirmed).length +
      incomes.where((item) => item.isActive && item.isConfirmed).length +
      obligations.where((item) => item.exists && item.isConfirmed).length;

  int get remainingConfirmations =>
      accounts.where((item) => !item.isConfirmed).length +
      envelopes.where((item) => !item.isConfirmed).length +
      incomes.where((item) => item.isActive && !item.isConfirmed).length +
      obligations.where((item) => item.exists && !item.isConfirmed).length;

  bool get canPrepareFuturePlan =>
      effectiveDate != null && remainingConfirmations == 0;

  num get candidateAccountsTotal =>
      accounts.fold(0, (total, item) => total + (item.candidateAmount ?? 0));
  num get confirmedAccountsTotal =>
      accounts.fold(0, (total, item) => total + (item.confirmedAmount ?? 0));
  num get candidateEnvelopesTotal =>
      envelopes.fold(0, (total, item) => total + (item.candidateAmount ?? 0));
  num get confirmedEnvelopesTotal =>
      envelopes.fold(0, (total, item) => total + (item.confirmedAmount ?? 0));

  num get accountsDifference => confirmedAccountsTotal - candidateAccountsTotal;
  num get envelopesDifference =>
      confirmedEnvelopesTotal - candidateEnvelopesTotal;

  CutoverPreparation copyWith({
    DateTime? effectiveDate,
    bool clearEffectiveDate = false,
    List<CutoverPreparationAccount>? accounts,
    List<CutoverPreparationEnvelope>? envelopes,
    List<CutoverPreparationIncome>? incomes,
    List<CutoverPreparationObligation>? obligations,
  }) => CutoverPreparation(
    sourceFingerprint: sourceFingerprint,
    effectiveDate: clearEffectiveDate
        ? null
        : effectiveDate ?? this.effectiveDate,
    accounts: accounts ?? this.accounts,
    envelopes: envelopes ?? this.envelopes,
    incomes: incomes ?? this.incomes,
    obligations: obligations ?? this.obligations,
  );

  CutoverPreparation updateAccount(CutoverPreparationAccount value) => copyWith(
    accounts: accounts
        .map((item) => item.id == value.id ? value : item)
        .toList(growable: false),
  );

  CutoverPreparation updateEnvelope(CutoverPreparationEnvelope value) =>
      copyWith(
        envelopes: envelopes
            .map((item) => item.id == value.id ? value : item)
            .toList(growable: false),
      );

  CutoverPreparation updateIncome(CutoverPreparationIncome value) => copyWith(
    incomes: incomes
        .map((item) => item.id == value.id ? value : item)
        .toList(growable: false),
  );

  CutoverPreparation updateObligation(CutoverPreparationObligation value) =>
      copyWith(
        obligations: obligations
            .map((item) => item.id == value.id ? value : item)
            .toList(growable: false),
      );
}

abstract class CutoverPreparationItem {
  const CutoverPreparationItem({
    required this.id,
    required this.name,
    required this.candidateSource,
    required this.candidateAmount,
    required this.confirmedAmount,
    required this.isConfirmed,
  });

  final String id;
  final String name;
  final String candidateSource;
  final num? candidateAmount;
  final num? confirmedAmount;
  final bool isConfirmed;
}

class CutoverPreparationAccount extends CutoverPreparationItem {
  const CutoverPreparationAccount({
    required super.id,
    required super.name,
    required super.candidateSource,
    required super.candidateAmount,
    required super.confirmedAmount,
    required super.isConfirmed,
    required this.holder,
    required this.kind,
  });

  final String holder;
  final String kind;

  CutoverPreparationAccount copyWith({
    num? confirmedAmount,
    bool clearConfirmedAmount = false,
    bool? isConfirmed,
  }) => CutoverPreparationAccount(
    id: id,
    name: name,
    candidateSource: candidateSource,
    candidateAmount: candidateAmount,
    confirmedAmount: clearConfirmedAmount
        ? null
        : confirmedAmount ?? this.confirmedAmount,
    isConfirmed: isConfirmed ?? this.isConfirmed,
    holder: holder,
    kind: kind,
  );
}

class CutoverPreparationEnvelope extends CutoverPreparationItem {
  const CutoverPreparationEnvelope({
    required super.id,
    required super.name,
    required super.candidateSource,
    required super.candidateAmount,
    required super.confirmedAmount,
    required super.isConfirmed,
    required this.isToAllocate,
  });

  final bool isToAllocate;

  CutoverPreparationEnvelope copyWith({
    num? confirmedAmount,
    bool clearConfirmedAmount = false,
    bool? isConfirmed,
  }) => CutoverPreparationEnvelope(
    id: id,
    name: name,
    candidateSource: candidateSource,
    candidateAmount: candidateAmount,
    confirmedAmount: clearConfirmedAmount
        ? null
        : confirmedAmount ?? this.confirmedAmount,
    isConfirmed: isConfirmed ?? this.isConfirmed,
    isToAllocate: isToAllocate,
  );
}

class CutoverPreparationIncome extends CutoverPreparationItem {
  const CutoverPreparationIncome({
    required super.id,
    required super.name,
    required super.candidateSource,
    required super.candidateAmount,
    required super.confirmedAmount,
    required super.isConfirmed,
    required this.member,
    required this.destinationAccount,
    required this.isActive,
    required this.isConfiguration,
  });

  final String member;
  final String destinationAccount;
  final bool isActive;
  final bool isConfiguration;

  CutoverPreparationIncome copyWith({
    num? confirmedAmount,
    bool clearConfirmedAmount = false,
    bool? isConfirmed,
    String? member,
    String? destinationAccount,
    bool? isActive,
  }) => CutoverPreparationIncome(
    id: id,
    name: name,
    candidateSource: candidateSource,
    candidateAmount: candidateAmount,
    confirmedAmount: clearConfirmedAmount
        ? null
        : confirmedAmount ?? this.confirmedAmount,
    isConfirmed: isConfirmed ?? this.isConfirmed,
    member: member ?? this.member,
    destinationAccount: destinationAccount ?? this.destinationAccount,
    isActive: isActive ?? this.isActive,
    isConfiguration: isConfiguration,
  );
}

class CutoverPreparationObligation {
  const CutoverPreparationObligation({
    required this.id,
    required this.name,
    required this.candidateSource,
    required this.candidateAmount,
    required this.classification,
    required this.exists,
    required this.creditor,
    required this.initialAmount,
    required this.remainingAmount,
    required this.monthlyAmount,
    required this.nextDueDate,
    required this.isConfirmed,
  });

  final String id;
  final String name;
  final String candidateSource;
  final num? candidateAmount;
  final CutoverObligationClassification classification;
  final bool exists;
  final String creditor;
  final num? initialAmount;
  final num? remainingAmount;
  final num? monthlyAmount;
  final DateTime? nextDueDate;
  final bool isConfirmed;

  CutoverPreparationObligation copyWith({
    bool? exists,
    String? creditor,
    num? initialAmount,
    num? remainingAmount,
    num? monthlyAmount,
    DateTime? nextDueDate,
    bool? isConfirmed,
  }) => CutoverPreparationObligation(
    id: id,
    name: name,
    candidateSource: candidateSource,
    candidateAmount: candidateAmount,
    classification: classification,
    exists: exists ?? this.exists,
    creditor: creditor ?? this.creditor,
    initialAmount: initialAmount ?? this.initialAmount,
    remainingAmount: remainingAmount ?? this.remainingAmount,
    monthlyAmount: monthlyAmount ?? this.monthlyAmount,
    nextDueDate: nextDueDate ?? this.nextDueDate,
    isConfirmed: isConfirmed ?? this.isConfirmed,
  );
}

class CutoverPreparationBuilder {
  const CutoverPreparationBuilder();

  static const _accounts = [
    (
      'awb-ibrahim',
      'AWB Ibrahim',
      'Ibrahim',
      'Banque',
      'SCENARIOS!F18:F20 — compte de simulation à confirmer',
    ),
    (
      'cih-ibrahim',
      'CIH Ibrahim',
      'Ibrahim',
      'Banque',
      'Test Nv salaires!G30 — budget de simulation à confirmer',
    ),
    (
      'islamique-ibrahim',
      'Banque Islamique Ibrahim',
      'Ibrahim',
      'Banque',
      'Test Nv salaires!H30 — budget de simulation à confirmer',
    ),
    (
      'banque-nora',
      'Banque Nora',
      'Nora',
      'Banque',
      'Test Nv salaires!F30 — budget de simulation à confirmer',
    ),
    (
      'espece-maison',
      'Espèce maison',
      'Foyer',
      'Espèces',
      'Test Nv salaires!K60 — libellé historique à confirmer',
    ),
  ];

  CutoverPreparation build(WorkbookImportAnalysis analysis) {
    final envelopeNames = _envelopeNames(analysis);
    return CutoverPreparation(
      sourceFingerprint: analysis.sourceFingerprint,
      accounts: _accounts
          .map(
            (definition) => CutoverPreparationAccount(
              id: definition.$1,
              name: definition.$2,
              holder: definition.$3,
              kind: definition.$4,
              candidateSource: definition.$5,
              candidateAmount: null,
              confirmedAmount: null,
              isConfirmed: false,
            ),
          )
          .toList(growable: false),
      envelopes: [
        ...envelopeNames.map(
          (name) => CutoverPreparationEnvelope(
            id: _id(name),
            name: name,
            candidateSource:
                'Enveloppes!B17:B41 — libellé source, solde à confirmer',
            candidateAmount: null,
            confirmedAmount: null,
            isConfirmed: false,
            isToAllocate: false,
          ),
        ),
        const CutoverPreparationEnvelope(
          id: 'a-repartir',
          name: 'À répartir',
          candidateSource: 'Position indépendante à renseigner',
          candidateAmount: null,
          confirmedAmount: null,
          isConfirmed: false,
          isToAllocate: true,
        ),
      ],
      incomes: const [
        CutoverPreparationIncome(
          id: 'income-ibrahim',
          name: 'Salaire Ibrahim',
          candidateSource:
              'SCENARIOS!L1:M2 / Test Nv salaires!B6 — paramètre de budget',
          candidateAmount: 12800,
          confirmedAmount: null,
          isConfirmed: false,
          member: 'Ibrahim',
          destinationAccount: '',
          isActive: false,
          isConfiguration: true,
        ),
        CutoverPreparationIncome(
          id: 'income-nora',
          name: 'Salaire Nora',
          candidateSource:
              'SCENARIOS!L1:M2 / Test Nv salaires!B10 — paramètre de budget',
          candidateAmount: 15000,
          confirmedAmount: null,
          isConfirmed: false,
          member: 'Nora',
          destinationAccount: '',
          isActive: false,
          isConfiguration: true,
        ),
      ],
      obligations: const [
        CutoverPreparationObligation(
          id: 'parent-nora',
          name: 'Dette Parent Nora',
          candidateSource:
              'Test Nv salaires!J24 / ANCIEN PROGRAMME!M26 — hypothèse de financement voiture',
          candidateAmount: 40000,
          classification: CutoverObligationClassification.ambiguous,
          exists: false,
          creditor: '',
          initialAmount: null,
          remainingAmount: null,
          monthlyAmount: null,
          nextDueDate: null,
          isConfirmed: false,
        ),
        CutoverPreparationObligation(
          id: 'car',
          name: 'Financement voiture',
          candidateSource:
              'Acquisit voiture!A4:B4 — montant de simulation, sans capital restant dû identifié',
          candidateAmount: null,
          classification:
              CutoverObligationClassification.nonImportableAutomatically,
          exists: false,
          creditor: '',
          initialAmount: null,
          remainingAmount: null,
          monthlyAmount: null,
          nextDueDate: null,
          isConfirmed: false,
        ),
      ],
    );
  }

  List<String> _envelopeNames(WorkbookImportAnalysis analysis) {
    final sheet = analysis.sourceSheets
        .where((item) => _normalise(item.sourceSheetName) == 'enveloppes')
        .firstOrNull;
    if (sheet == null) return const [];
    final byCoordinate = {
      for (final cell in sheet.cells) cell.coordinate: cell.value,
    };
    final names = <String>[];
    for (var row = 1; row <= 200; row++) {
      final value = byCoordinate['B$row']?.trim() ?? '';
      if (value.isEmpty || _normalise(value) == 'total') continue;
      if (_knownEnvelope(value) && !names.contains(value)) names.add(value);
    }
    return names;
  }

  bool _knownEnvelope(String value) => const {
    'traite maison',
    'traite normale',
    'tsc',
    'syndic',
    'eau elec abonnement',
    'mouton',
    'ecole niece',
    'parrents',
    'parrents nora',
    'traite voiture',
    'wifi',
    'besoin perso',
    'nourriture',
    'habits',
    'imprevus',
    'voyages',
    'sorties we',
    'fetes religieuses',
    'navette',
    'epargne',
    'reste epargne (primes ibrahim et nora)',
    'vidange',
    'entretien',
    'assurance',
    'vignette',
  }.contains(_normalise(value));

  String _id(String value) => _normalise(value).replaceAll(' ', '-');
  String _normalise(String value) => value
      .toLowerCase()
      .trim()
      .replaceAll('é', 'e')
      .replaceAll('è', 'e')
      .replaceAll('ê', 'e')
      .replaceAll('à', 'a')
      .replaceAll('â', 'a')
      .replaceAll('î', 'i')
      .replaceAll('ô', 'o')
      .replaceAll('ù', 'u')
      .replaceAll(RegExp(r'\s+'), ' ');
}
