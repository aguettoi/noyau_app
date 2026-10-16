import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/core/money/money.dart';
import 'package:noyau_app/features/monthly_close/domain/monthly_close.dart';

void main() {
  test('manual opening positions are explicit inventory arbitrations', () {
    const position = EnvelopeAccountPosition(
      accountId: 'account',
      envelopeId: 'envelope',
      amount: Money.fromMinorUnits(100),
    );
    expect(position.provenance, PositionProvenance.openingInventoryArbitration);
  });
  test('health distinguishes hard blockers and overridable warnings', () {
    final snapshot = MonthlyCloseSnapshot(
      month: DateTime(2026, 10),
      status: MonthlyCloseStatus.open,
      issues: const [
        CloseIssue(
          code: 'r',
          label: 'Rapprochements',
          count: 1,
          severity: CloseIssueSeverity.blocker,
          destination: 'Comptes',
        ),
        CloseIssue(
          code: 'j',
          label: 'Justificatifs',
          count: 2,
          severity: CloseIssueSeverity.warning,
          destination: 'Historique',
        ),
        CloseIssue(
          code: 'c',
          label: 'Espèces',
          count: 0,
          severity: CloseIssueSeverity.blocker,
          destination: 'Comptes',
        ),
      ],
    );
    expect(snapshot.blockers, 1);
    expect(snapshot.warnings, 2);
    expect(snapshot.ready, isFalse);
    expect(snapshot.healthPercent, 86);
  });

  test('multi-account proposal nets transfers without financial write', () {
    final result = proposeSettlements([
      EnvelopeAccountTarget(
        memberId: 'a',
        accountId: 'account-a',
        envelopeId: 'food',
        current: Money.fromMinorUnits(15000),
        target: Money.fromMinorUnits(10000),
      ),
      EnvelopeAccountTarget(
        memberId: 'b',
        accountId: 'account-b',
        envelopeId: 'food',
        current: Money.fromMinorUnits(2000),
        target: Money.fromMinorUnits(7000),
      ),
    ]);
    expect(result, hasLength(1));
    expect(result.single.fromAccountId, 'account-a');
    expect(result.single.toAccountId, 'account-b');
    expect(result.single.amount.minorUnits, 5000);
  });

  test('one, two and N members remain data-driven', () {
    for (final members in [1, 2, 4]) {
      final targets = List.generate(
        members,
        (i) => EnvelopeAccountTarget(
          memberId: 'm$i',
          accountId: 'a$i',
          envelopeId: 'e$i',
          current: const Money.fromMinorUnits(1000),
          target: const Money.fromMinorUnits(1000),
        ),
      );
      expect(proposeSettlements(targets), isEmpty);
    }
  });

  test('solver preserves envelope identity and intra-month remainder', () {
    final moves = proposeEnvelopeAccountMoves([
      EnvelopeAccountTarget(
        memberId: 'a',
        accountId: 'a',
        envelopeId: 'food',
        current: Money.fromDirhams(80),
        target: Money.fromDirhams(30),
      ),
      EnvelopeAccountTarget(
        memberId: 'b',
        accountId: 'b',
        envelopeId: 'food',
        current: Money.fromDirhams(20),
        target: Money.fromDirhams(70),
      ),
      EnvelopeAccountTarget(
        memberId: 'a',
        accountId: 'a',
        envelopeId: 'cash',
        current: Money.fromDirhams(10),
        target: Money.fromDirhams(10),
      ),
    ]);
    expect(moves, hasLength(1));
    expect(moves.single.envelopeId, 'food');
    expect(moves.single.fromAccountId, 'a');
    expect(moves.single.toAccountId, 'b');
    expect(moves.single.amount, Money.fromDirhams(50));
  });

  test('global netting offsets opposite envelopes and keeps explanations', () {
    final simulation = simulateGlobalTransfers([
      EnvelopeAccountTarget(
        memberId: 'one',
        accountId: 'a',
        envelopeId: 'first',
        current: Money.fromDirhams(500),
        target: Money.fromDirhams(0),
      ),
      EnvelopeAccountTarget(
        memberId: 'two',
        accountId: 'b',
        envelopeId: 'first',
        current: Money.fromDirhams(0),
        target: Money.fromDirhams(500),
      ),
      EnvelopeAccountTarget(
        memberId: 'two',
        accountId: 'b',
        envelopeId: 'second',
        current: Money.fromDirhams(400),
        target: Money.fromDirhams(0),
      ),
      EnvelopeAccountTarget(
        memberId: 'one',
        accountId: 'a',
        envelopeId: 'second',
        current: Money.fromDirhams(0),
        target: Money.fromDirhams(400),
      ),
    ]);
    expect(simulation.analyticalMoves, hasLength(2));
    expect(simulation.physicalTransfers, hasLength(1));
    expect(simulation.physicalTransfers.single.fromAccountId, 'a');
    expect(simulation.physicalTransfers.single.toAccountId, 'b');
    expect(simulation.physicalTransfers.single.amount, Money.fromDirhams(100));
    expect(simulation.physicalTransfers.single.justifications, hasLength(2));
    expect(simulation.grossAmount, Money.fromDirhams(900));
    expect(simulation.netAmount, Money.fromDirhams(100));
  });

  test('equal opposite flows require no physical transfer', () {
    final simulation = simulateGlobalTransfers([
      for (final row in const [
        ('a', 'x', 50000, 0),
        ('b', 'x', 0, 50000),
        ('b', 'y', 50000, 0),
        ('a', 'y', 0, 50000),
      ])
        EnvelopeAccountTarget(
          memberId: null,
          accountId: row.$1,
          envelopeId: row.$2,
          current: Money.fromMinorUnits(row.$3),
          target: Money.fromMinorUnits(row.$4),
        ),
    ]);
    expect(simulation.analyticalMoves, hasLength(2));
    expect(simulation.physicalTransfers, isEmpty);
    expect(simulation.netAmount, const Money.fromMinorUnits(0));
  });

  test('three-account cycle is globally reduced deterministically', () {
    final simulation = simulateGlobalTransfers([
      for (final row in const [
        ('a', 'one', 50000, 0),
        ('b', 'one', 0, 50000),
        ('b', 'two', 30000, 0),
        ('c', 'two', 0, 30000),
        ('c', 'three', 20000, 0),
        ('a', 'three', 0, 20000),
      ])
        EnvelopeAccountTarget(
          memberId: null,
          accountId: row.$1,
          envelopeId: row.$2,
          current: Money.fromMinorUnits(row.$3),
          target: Money.fromMinorUnits(row.$4),
        ),
    ]);
    expect(simulation.physicalTransfers, hasLength(2));
    expect(simulation.physicalTransfers[0].fromAccountId, 'a');
    expect(simulation.physicalTransfers[0].toAccountId, 'b');
    expect(simulation.physicalTransfers[0].amount, Money.fromDirhams(200));
    expect(simulation.physicalTransfers[1].fromAccountId, 'a');
    expect(simulation.physicalTransfers[1].toAccountId, 'c');
    expect(simulation.physicalTransfers[1].amount, Money.fromDirhams(100));
    expect(
      simulation.physicalTransfers.every(
        (transfer) => transfer.justifications.length == 3,
      ),
      isTrue,
    );
  });

  test('incomplete historical matrix is represented, never invented', () {
    const matrix = EnvelopeAccountMatrix(
      positions: [],
      reliable: false,
      accountGap: Money.fromMinorUnits(100),
      envelopeGap: Money.fromMinorUnits(100),
      fingerprint: 'x',
    );
    expect(matrix.positions, isEmpty);
    expect(matrix.reliable, isFalse);
  });

  test('source proof is preserved and a final unique cell is deduced', () {
    final result = deduceUniqueInitialPositions(
      accountBalances: {
        'cash': Money.fromDirhams(50),
        'bank': Money.fromDirhams(100),
      },
      envelopeBalances: {
        'food': Money.fromDirhams(50),
        'savings': Money.fromDirhams(100),
      },
      known: const [
        EnvelopeAccountPosition(
          accountId: 'cash',
          envelopeId: 'food',
          amount: Money.fromMinorUnits(5000),
          provenance: PositionProvenance.sourceProof,
          provenanceReference: 'source',
        ),
      ],
    );
    expect(result, hasLength(2));
    final inferred = result.singleWhere((item) => item.accountId == 'bank');
    expect(inferred.envelopeId, 'savings');
    expect(inferred.amount, Money.fromDirhams(100));
    expect(inferred.provenance, PositionProvenance.balancingDeduction);
  });

  test('multiple valid residual allocations are never invented', () {
    final result = deduceUniqueInitialPositions(
      accountBalances: {
        'a': Money.fromDirhams(100),
        'b': Money.fromDirhams(100),
      },
      envelopeBalances: {
        'e1': Money.fromDirhams(100),
        'e2': Money.fromDirhams(100),
      },
      known: const [],
    );
    expect(result, isEmpty);
  });

  test('partial and multi-account source proof remain explicit', () {
    final result = deduceUniqueInitialPositions(
      accountBalances: {'a': Money.fromDirhams(70), 'b': Money.fromDirhams(30)},
      envelopeBalances: {'shared': Money.fromDirhams(100)},
      known: const [
        EnvelopeAccountPosition(
          accountId: 'a',
          envelopeId: 'shared',
          amount: Money.fromMinorUnits(7000),
          provenance: PositionProvenance.sourceProof,
          provenanceReference: 'part A',
        ),
        EnvelopeAccountPosition(
          accountId: 'b',
          envelopeId: 'shared',
          amount: Money.fromMinorUnits(3000),
          provenance: PositionProvenance.sourceProof,
          provenanceReference: 'part B',
        ),
      ],
    );
    expect(result, hasLength(2));
    expect(
      result.every((item) => item.provenance == PositionProvenance.sourceProof),
      isTrue,
    );
  });

  test('zero-balance envelopes do not require a position', () {
    final result = deduceUniqueInitialPositions(
      accountBalances: const {},
      envelopeBalances: {'zero': const Money.fromMinorUnits(0)},
      known: const [],
    );
    expect(result, isEmpty);
  });

  test(
    'inventory assistant protects a confirmed position and fills only residual',
    () {
      final proposal = proposeInventoryVentilation(
        accountBalances: {
          'cih': Money.fromDirhams(59330),
          'arreda': Money.fromDirhams(4150),
        },
        envelopeBalances: {'home': Money.fromDirhams(63480)},
        fixedPositions: const [
          EnvelopeAccountPosition(
            accountId: 'cih',
            envelopeId: 'home',
            amount: Money.fromMinorUnits(5933000),
            provenance: PositionProvenance.humanConfirmation,
          ),
        ],
        rules: const [
          InventoryVentilationRule(
            envelopeId: 'home',
            admissibleAccountIds: ['arreda'],
            preferredAccountIds: ['arreda'],
            reason: 'Compte structurel habituel',
          ),
        ],
      );
      expect(proposal.balanced, isTrue);
      expect(proposal.candidates, hasLength(1));
      expect(proposal.candidates.single.position.accountId, 'arreda');
      expect(proposal.candidates.single.position.amount.dirhams, 4150);
      expect(
        proposal.candidates.single.position.provenance,
        PositionProvenance.openingInventoryArbitration,
      );
    },
  );

  test(
    'inventory assistant labels a deterministic multiple solution as arbitration',
    () {
      final proposal = proposeInventoryVentilation(
        accountBalances: {
          'a': Money.fromDirhams(60),
          'b': Money.fromDirhams(40),
        },
        envelopeBalances: {
          'x': Money.fromDirhams(50),
          'y': Money.fromDirhams(50),
        },
        fixedPositions: const [],
        rules: const [
          InventoryVentilationRule(
            envelopeId: 'x',
            admissibleAccountIds: ['a', 'b'],
            preferredAccountIds: ['a'],
            reason: 'Répartition multi-comptes',
          ),
          InventoryVentilationRule(
            envelopeId: 'y',
            admissibleAccountIds: ['a', 'b'],
            preferredAccountIds: ['b'],
            reason: 'Répartition multi-comptes',
          ),
        ],
      );
      expect(proposal.balanced, isTrue);
      expect(proposal.isUnique, isFalse);
      expect(
        proposal.candidates.every(
          (candidate) =>
              candidate.position.provenance ==
              PositionProvenance.openingInventoryArbitration,
        ),
        isTrue,
      );
    },
  );

  test(
    'inventory assistant reports a partial proposal when a rule is missing',
    () {
      final proposal = proposeInventoryVentilation(
        accountBalances: {'a': Money.fromDirhams(100)},
        envelopeBalances: {'unknown': Money.fromDirhams(100)},
        fixedPositions: const [],
        rules: const [],
      );
      expect(proposal.balanced, isFalse);
      expect(proposal.candidates, isEmpty);
      expect(proposal.remainingEnvelopeAmount.dirhams, 100);
      expect(proposal.unresolvedResiduals, hasLength(1));
      expect(proposal.unresolvedResiduals.single.envelopeId, 'unknown');
      expect(
        proposal.unresolvedResiduals.single.reason,
        contains('Aucune règle structurelle'),
      );
    },
  );

  test('inventory assistant explains constrained residual capacities', () {
    final proposal = proposeInventoryVentilation(
      accountBalances: {'a': Money.fromDirhams(40)},
      envelopeBalances: {'shared': Money.fromDirhams(100)},
      fixedPositions: const [],
      rules: const [
        InventoryVentilationRule(
          envelopeId: 'shared',
          admissibleAccountIds: ['a'],
          reason: 'Compte structurel habituel',
        ),
      ],
    );
    expect(proposal.remainingEnvelopeAmount.dirhams, 60);
    expect(proposal.unresolvedResiduals, hasLength(1));
    final residual = proposal.unresolvedResiduals.single;
    expect(residual.admissibleAccountIds, ['a']);
    expect(residual.remainingAccountCapacities['a']!.minorUnits, 0);
    expect(residual.reason, contains('plus de capacité résiduelle'));
    expect(residual.expectedAction, isNotEmpty);
  });

  test('inventory assistant supports one, two and N admissible accounts', () {
    final proposal = proposeInventoryVentilation(
      accountBalances: {
        'a': Money.fromDirhams(10),
        'b': Money.fromDirhams(20),
        'c': Money.fromDirhams(30),
      },
      envelopeBalances: {'shared': Money.fromDirhams(60)},
      fixedPositions: const [],
      rules: const [
        InventoryVentilationRule(
          envelopeId: 'shared',
          admissibleAccountIds: ['a', 'b', 'c'],
          reason: 'Répartition multi-membres',
        ),
      ],
    );
    expect(proposal.balanced, isTrue);
    expect(
      proposal.candidates.fold<int>(
        0,
        (sum, candidate) => sum + candidate.position.amount.minorUnits,
      ),
      6000,
    );
  });

  test(
    'R2.12.1 keeps the confirmed home position and explains the exact pilot residual',
    () {
      const habitsId = 'f61a5376-46b2-4c81-9147-79d74b2800fc';
      const outingsId = '0348541e-715a-43a4-a009-95dd1225f743';
      const holidaysId = '8eeeb4e0-829a-4e7f-af4f-73997d50d438';
      final proposal = proposeInventoryVentilation(
        accountBalances: {
          'AWB Ibrahim': Money.fromDirhams(2590.31),
          'Banque Nora': Money.fromDirhams(23353.92),
          'CIH Ibrahim': Money.fromDirhams(59330),
          'Espèces maison': Money.fromDirhams(5169.50),
          'Islamique / Arreda Ibrahim': Money.fromDirhams(33585.77),
        },
        envelopeBalances: {
          'Besoin perso': Money.fromDirhams(520.48),
          'Eau elec abonnement': Money.fromDirhams(483.84),
          'Ecole Niece': Money.fromDirhams(523.38),
          'Epargne': Money.fromDirhams(18548.56),
          holidaysId: Money.fromDirhams(950.90),
          habitsId: Money.fromDirhams(1635.57),
          'Mouton': Money.fromDirhams(1600),
          'Navette': Money.fromDirhams(2753.50),
          'Nourriture': Money.fromDirhams(2416),
          'Parrents': Money.fromDirhams(6000),
          'Reste epargne (primes Ibrahim et Nora)': Money.fromDirhams(16446.47),
          outingsId: Money.fromDirhams(1000),
          'Syndic': Money.fromDirhams(566.67),
          'Traite maison': Money.fromDirhams(63480),
          'Traite voiture': Money.fromDirhams(5000),
          'TSC': Money.fromDirhams(750),
          'Voyages': Money.fromDirhams(728.33),
          'Wifi': Money.fromDirhams(625.80),
        },
        fixedPositions: const [
          EnvelopeAccountPosition(
            accountId: 'CIH Ibrahim',
            envelopeId: 'Traite maison',
            amount: Money.fromMinorUnits(5933000),
            provenance: PositionProvenance.humanConfirmation,
            provenanceReference: 'Confirmation métier',
          ),
          EnvelopeAccountPosition(
            accountId: 'Espèces maison',
            envelopeId: 'Nourriture',
            amount: Money.fromMinorUnits(241600),
            provenance: PositionProvenance.sourceProof,
          ),
          EnvelopeAccountPosition(
            accountId: 'Espèces maison',
            envelopeId: 'Navette',
            amount: Money.fromMinorUnits(275350),
            provenance: PositionProvenance.sourceProof,
          ),
          EnvelopeAccountPosition(
            accountId: 'Banque Nora',
            envelopeId: 'Traite voiture',
            amount: Money.fromMinorUnits(500000),
            provenance: PositionProvenance.sourceProof,
          ),
          EnvelopeAccountPosition(
            accountId: 'Banque Nora',
            envelopeId: 'Wifi',
            amount: Money.fromMinorUnits(62580),
            provenance: PositionProvenance.sourceProof,
          ),
          EnvelopeAccountPosition(
            accountId: 'Banque Nora',
            envelopeId: 'Besoin perso',
            amount: Money.fromMinorUnits(52048),
            provenance: PositionProvenance.sourceProof,
          ),
          EnvelopeAccountPosition(
            accountId: 'Banque Nora',
            envelopeId: habitsId,
            amount: Money.fromMinorUnits(76117),
            provenance: PositionProvenance.sourceProof,
          ),
          EnvelopeAccountPosition(
            accountId: 'Banque Nora',
            envelopeId: 'Reste epargne (primes Ibrahim et Nora)',
            amount: Money.fromMinorUnits(1644647),
            provenance: PositionProvenance.sourceProof,
          ),
          EnvelopeAccountPosition(
            accountId: 'Islamique / Arreda Ibrahim',
            envelopeId: 'Epargne',
            amount: Money.fromMinorUnits(1854856),
            provenance: PositionProvenance.humanConfirmation,
          ),
        ],
        rules: const [
          InventoryVentilationRule(
            envelopeId: 'Traite maison',
            admissibleAccountIds: ['Islamique / Arreda Ibrahim'],
            reason: 'Compte structurel habituel',
          ),
          InventoryVentilationRule(
            envelopeId: 'Eau elec abonnement',
            admissibleAccountIds: ['Islamique / Arreda Ibrahim'],
            reason: 'Compte structurel habituel',
          ),
          InventoryVentilationRule(
            envelopeId: 'Ecole Niece',
            admissibleAccountIds: ['Islamique / Arreda Ibrahim'],
            reason: 'Compte structurel habituel',
          ),
          InventoryVentilationRule(
            envelopeId: 'Mouton',
            admissibleAccountIds: ['Islamique / Arreda Ibrahim'],
            reason: 'Compte structurel habituel',
          ),
          InventoryVentilationRule(
            envelopeId: 'Parrents',
            admissibleAccountIds: ['Islamique / Arreda Ibrahim'],
            reason: 'Compte structurel habituel',
          ),
          InventoryVentilationRule(
            envelopeId: 'Syndic',
            admissibleAccountIds: ['Islamique / Arreda Ibrahim'],
            reason: 'Compte structurel habituel',
          ),
          InventoryVentilationRule(
            envelopeId: 'TSC',
            admissibleAccountIds: ['Islamique / Arreda Ibrahim'],
            reason: 'Compte structurel habituel',
          ),
          InventoryVentilationRule(
            envelopeId: 'Voyages',
            admissibleAccountIds: ['Islamique / Arreda Ibrahim'],
            reason: 'Compte structurel habituel',
          ),
          InventoryVentilationRule(
            envelopeId: outingsId,
            admissibleAccountIds: ['AWB Ibrahim'],
            reason: 'Compte structurel habituel',
          ),
          InventoryVentilationRule(
            envelopeId: holidaysId,
            admissibleAccountIds: ['AWB Ibrahim'],
            reason: 'Compte structurel habituel',
          ),
          InventoryVentilationRule(
            envelopeId: habitsId,
            admissibleAccountIds: ['AWB Ibrahim', 'Banque Nora'],
            reason: 'Répartition multi-comptes',
          ),
        ],
      );

      expect(proposal.initialResidual.dirhams, 17627.52);
      expect(proposal.remainingEnvelopeAmount.dirhams, 234.99);
      expect(proposal.unresolvedResiduals, hasLength(1));
      final residual = proposal.unresolvedResiduals.single;
      expect(residual.envelopeId, habitsId);
      expect(residual.amount.dirhams, 234.99);
      expect(residual.admissibleAccountIds, ['AWB Ibrahim', 'Banque Nora']);
      expect(
        residual.remainingAccountCapacities.values.every(
          (amount) => amount.minorUnits == 0,
        ),
        isTrue,
      );
      expect(
        proposal.candidates.any(
          (candidate) =>
              candidate.position.envelopeId == 'Traite maison' &&
              candidate.position.accountId == 'Islamique / Arreda Ibrahim' &&
              candidate.position.amount.dirhams == 4150,
        ),
        isTrue,
      );
      expect(
        proposal.candidates.any(
          (candidate) =>
              candidate.position.envelopeId == 'Voyages' &&
              candidate.position.accountId == 'Islamique / Arreda Ibrahim' &&
              candidate.position.amount.dirhams == 728.33,
        ),
        isTrue,
      );
      expect(
        proposal.candidates.any(
          (candidate) => candidate.position.accountId == 'CIH Ibrahim',
        ),
        isFalse,
      );
    },
  );
}
