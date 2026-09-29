import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/features/finance/application/cutover_opening_import.dart';
import 'package:noyau_app/features/finance/application/providers/active_household_provider.dart';
import 'package:noyau_app/features/finance/application/workbook_import.dart';
import 'package:noyau_app/features/finance/domain/account_ownership.dart';

void main() {
  const fingerprint =
      '0123456789012345678901234567890123456789012345678901234567890123';
  const holderA = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  const holderB = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

  test(
    'le plan B1 porte cible explicite, fingerprint et positions fictives',
    () {
      const analysis = WorkbookImportAnalysis(
        fileName: 'fictif.xlsx',
        sourceFingerprint: fingerprint,
        sheetPreviews: [],
        unhandledSheetNames: [],
        sourceSheets: [
          SourceSheetSnapshot(
            sourceSheetName: 'Positions ouverture',
            cells: [
              SourceCellSnapshot(coordinate: 'A1', value: 'Type'),
              SourceCellSnapshot(coordinate: 'B1', value: 'Nom'),
              SourceCellSnapshot(coordinate: 'C1', value: 'Kind'),
              SourceCellSnapshot(coordinate: 'D1', value: 'Montant'),
              SourceCellSnapshot(coordinate: 'E1', value: 'Ownership type'),
              SourceCellSnapshot(coordinate: 'F1', value: 'Holder user ids'),
              SourceCellSnapshot(coordinate: 'A2', value: 'Compte'),
              SourceCellSnapshot(coordinate: 'B2', value: 'Banque A'),
              SourceCellSnapshot(coordinate: 'C2', value: 'bank'),
              SourceCellSnapshot(coordinate: 'D2', value: '1000'),
              SourceCellSnapshot(coordinate: 'E2', value: 'individual'),
              SourceCellSnapshot(coordinate: 'F2', value: holderA),
              SourceCellSnapshot(coordinate: 'A3', value: 'Compte'),
              SourceCellSnapshot(coordinate: 'B3', value: 'Caisse'),
              SourceCellSnapshot(coordinate: 'C3', value: 'cash'),
              SourceCellSnapshot(coordinate: 'D3', value: '200'),
              SourceCellSnapshot(coordinate: 'E3', value: 'shared'),
              SourceCellSnapshot(coordinate: 'F3', value: '$holderA;$holderB'),
              SourceCellSnapshot(coordinate: 'A4', value: 'Enveloppe'),
              SourceCellSnapshot(coordinate: 'B4', value: 'Nourriture'),
              SourceCellSnapshot(coordinate: 'D4', value: '500'),
              SourceCellSnapshot(coordinate: 'A5', value: 'Enveloppe'),
              SourceCellSnapshot(coordinate: 'B5', value: 'Épargne'),
              SourceCellSnapshot(coordinate: 'D5', value: '250'),
              SourceCellSnapshot(coordinate: 'A6', value: 'Enveloppe'),
              SourceCellSnapshot(coordinate: 'B6', value: 'À répartir'),
              SourceCellSnapshot(coordinate: 'D6', value: '50'),
            ],
          ),
        ],
      );
      final plan = CutoverOpeningPlanBuilder().build(
        analysis: analysis,
        householdId: 'household',
        effectiveDate: DateTime(2026, 9, 14),
        cutoverId: '11111111-1111-4111-8111-111111111111',
      );
      expect(plan.canConfirm, isTrue, reason: plan.blockingErrors.join(' | '));
      expect(plan.householdId, 'household');
      expect(plan.sourceFingerprint, fingerprint);
      expect(plan.accounts, hasLength(2));
      expect(
        plan.accounts.first.ownershipType,
        AccountOwnershipType.individual,
      );
      expect(plan.accounts.last.ownershipType, AccountOwnershipType.shared);
      expect(plan.accounts.last.holderUserIds, [holderA, holderB]);
      expect(plan.envelopes, hasLength(3));
      expect(plan.envelopes.last.isToAllocate, isTrue);
      expect(plan.confirm(DateTime(2026)).confirmedAt, isNotNull);
    },
  );

  test(
    'les erreurs bloquantes empêchent confirmation et changement de source',
    () {
      const analysis = WorkbookImportAnalysis(
        fileName: 'empty.xlsx',
        sourceFingerprint: fingerprint,
        sheetPreviews: [],
        unhandledSheetNames: [],
        sourceSheets: [],
      );
      final plan = CutoverOpeningPlanBuilder().build(
        analysis: analysis,
        householdId: 'h',
        effectiveDate: DateTime(2026),
      );
      expect(plan.canConfirm, isFalse);
      expect(plan.blockingErrors, isNotEmpty);
    },
  );

  test('un plan complété peut être restauré pour reprendre le même run', () {
    final plan = CutoverOpeningPlan(
      cutoverId: '11111111-1111-4111-8111-111111111111',
      householdId: 'household',
      sourceFingerprint: fingerprint,
      effectiveDate: DateTime(2026, 9, 14),
      accounts: const [
        CutoverOpeningAccount(
          sourceLabel: 'A2',
          name: 'Banque A',
          kind: 'bank',
          openingAmount: 1000,
          ownershipType: AccountOwnershipType.individual,
          holderUserIds: [holderA],
        ),
      ],
      envelopes: const [
        CutoverOpeningEnvelope(
          sourceLabel: 'A3',
          name: 'Nourriture',
          openingAmount: 500,
          isToAllocate: false,
        ),
      ],
    ).confirm(DateTime(2026, 9, 14, 9, 42));

    final restored = CutoverOpeningPlan.fromJson(
      Map<String, dynamic>.from(plan.toJson()),
    );

    expect(restored.cutoverId, plan.cutoverId);
    expect(restored.sourceFingerprint, plan.sourceFingerprint);
    expect(restored.effectiveDate, plan.effectiveDate);
    expect(restored.confirmedAt, plan.confirmedAt);
    expect(restored.accounts.single.openingAmount, 1000);
    expect(
      restored.accounts.single.ownershipType,
      AccountOwnershipType.individual,
    );
    expect(restored.accounts.single.holderUserIds, [holderA]);
    expect(restored.envelopes.single.name, 'Nourriture');
  });

  test(
    'une cible technique explicite reste inscrite dans le plan confirmé',
    () {
      const target = CutoverEligibleHousehold(
        id: 'technical-household',
        name: 'CUTOVER-B1-E2E',
        classification: HouseholdClassification.technical,
      );
      final plan = CutoverOpeningPlanBuilder().build(
        analysis: const WorkbookImportAnalysis(
          fileName: 'fictif.xlsx',
          sourceFingerprint: fingerprint,
          sheetPreviews: [],
          unhandledSheetNames: [],
          sourceSheets: [],
        ),
        householdId: target.id,
        effectiveDate: DateTime(2026, 9, 14),
      );

      expect(target.isTechnical, isTrue);
      expect(target.classificationLabel, 'TECHNIQUE');
      expect(plan.householdId, target.id);
      expect(plan.confirm(DateTime(2026)).householdId, target.id);
    },
  );

  test('la titularité absente reste à confirmer sans déduction du nom', () {
    const account = CutoverOpeningAccount(
      sourceLabel: 'A2',
      name: 'Compte Ibrahim et Nora',
      kind: 'bank',
      openingAmount: 100,
    );

    expect(account.ownershipType, isNull);
    expect(account.holderUserIds, isEmpty);
    expect(account.hasValidOwnership, isFalse);
    expect(account.ownershipValidationError, 'Titularité à confirmer.');
  });

  test('les cardinalités individual shared et household sont explicites', () {
    const individual = CutoverOpeningAccount(
      sourceLabel: 'A2',
      name: 'Individuel',
      kind: 'bank',
      openingAmount: 100,
      ownershipType: AccountOwnershipType.individual,
      holderUserIds: [holderA],
    );
    const shared = CutoverOpeningAccount(
      sourceLabel: 'A3',
      name: 'Partagé',
      kind: 'bank',
      openingAmount: 100,
      ownershipType: AccountOwnershipType.shared,
      holderUserIds: [holderA, holderB],
    );
    const household = CutoverOpeningAccount(
      sourceLabel: 'A4',
      name: 'Foyer',
      kind: 'cash',
      openingAmount: 100,
      ownershipType: AccountOwnershipType.household,
    );

    expect(individual.hasValidOwnership, isTrue);
    expect(shared.hasValidOwnership, isTrue);
    expect(household.hasValidOwnership, isTrue);
    expect(
      household.copyWith(holderUserIds: const [holderA]).hasValidOwnership,
      isFalse,
    );
  });

  test('un titulaire hors household bloque la confirmation locale', () {
    final plan = CutoverOpeningPlan(
      cutoverId: '11111111-1111-4111-8111-111111111111',
      householdId: 'household',
      sourceFingerprint: fingerprint,
      effectiveDate: DateTime(2026, 9, 29),
      accounts: const [
        CutoverOpeningAccount(
          sourceLabel: 'A2',
          name: 'Compte individuel',
          kind: 'bank',
          openingAmount: 100,
          ownershipType: AccountOwnershipType.individual,
          holderUserIds: [holderA],
        ),
      ],
      envelopes: const [
        CutoverOpeningEnvelope(
          sourceLabel: 'A3',
          name: 'Nourriture',
          openingAmount: 50,
          isToAllocate: false,
        ),
      ],
    );

    expect(plan.canConfirm, isTrue);
    expect(plan.canConfirmForMemberIds({holderA}), isTrue);
    expect(plan.canConfirmForMemberIds({holderB}), isFalse);
    expect(plan.ownershipErrorsForMemberIds({holderB}), hasLength(1));
  });

  test('la résolution read-only transporte les identifiants de match', () {
    final plan =
        CutoverOpeningPlan(
          cutoverId: '11111111-1111-4111-8111-111111111111',
          householdId: 'household',
          sourceFingerprint: fingerprint,
          effectiveDate: DateTime(2026, 9, 29),
          accounts: const [
            CutoverOpeningAccount(
              sourceLabel: 'A2',
              name: 'Banque A',
              kind: 'bank',
              openingAmount: 100,
              ownershipType: AccountOwnershipType.individual,
              holderUserIds: [holderA],
            ),
          ],
          envelopes: const [
            CutoverOpeningEnvelope(
              sourceLabel: 'A3',
              name: 'À répartir',
              openingAmount: 50,
              isToAllocate: true,
            ),
          ],
        ).resolveReferences(
          existingAccounts: const [
            CutoverExistingAccount(
              id: 'account-a',
              name: 'Banque A',
              kind: 'bank',
              ownershipType: AccountOwnershipType.individual,
              holderUserIds: [holderA],
              archived: false,
            ),
          ],
          existingEnvelopes: const [
            CutoverExistingEnvelope(
              id: 'envelope-to-allocate',
              name: 'À répartir',
              isSystem: true,
              systemKey: 'to_allocate',
              archived: false,
            ),
          ],
        );

    expect(plan.accounts.single.conflictDecision, 'match');
    expect(plan.accounts.single.matchedAccountId, 'account-a');
    expect(plan.envelopes.single.conflictDecision, 'match');
    expect(plan.envelopes.single.matchedEnvelopeId, 'envelope-to-allocate');
    expect(plan.canConfirm, isTrue);
    expect(plan.toJson().toString(), contains('matched_account_id'));
    expect(plan.toJson().toString(), contains('matched_envelope_id'));
  });

  test('un match incompatible est bloquant et ne réécrit rien', () {
    final plan =
        CutoverOpeningPlan(
          cutoverId: '11111111-1111-4111-8111-111111111111',
          householdId: 'household',
          sourceFingerprint: fingerprint,
          effectiveDate: DateTime(2026, 9, 29),
          accounts: const [
            CutoverOpeningAccount(
              sourceLabel: 'A2',
              name: 'Banque A',
              kind: 'bank',
              openingAmount: 100,
              ownershipType: AccountOwnershipType.individual,
              holderUserIds: [holderA],
            ),
          ],
          envelopes: const [
            CutoverOpeningEnvelope(
              sourceLabel: 'A3',
              name: 'Nourriture',
              openingAmount: 50,
              isToAllocate: false,
            ),
          ],
        ).resolveReferences(
          existingAccounts: const [
            CutoverExistingAccount(
              id: 'account-a',
              name: 'Banque A',
              kind: 'bank',
              ownershipType: AccountOwnershipType.shared,
              holderUserIds: [holderA, holderB],
              archived: false,
            ),
          ],
          existingEnvelopes: const [],
        );

    expect(plan.accounts.single.conflictDecision, 'conflict');
    expect(plan.accounts.single.matchedAccountId, 'account-a');
    expect(plan.accounts.single.hasReferenceConflict, isTrue);
    expect(plan.canConfirm, isFalse);
  });

  test('plusieurs références de même nom rendent le match ambigu', () {
    final plan =
        CutoverOpeningPlan(
          cutoverId: '11111111-1111-4111-8111-111111111111',
          householdId: 'household',
          sourceFingerprint: fingerprint,
          effectiveDate: DateTime(2026, 9, 29),
          accounts: const [
            CutoverOpeningAccount(
              sourceLabel: 'A2',
              name: 'Banque A',
              kind: 'bank',
              openingAmount: 100,
              ownershipType: AccountOwnershipType.individual,
              holderUserIds: [holderA],
            ),
          ],
          envelopes: const [
            CutoverOpeningEnvelope(
              sourceLabel: 'A3',
              name: 'Nourriture',
              openingAmount: 50,
              isToAllocate: false,
            ),
          ],
        ).resolveReferences(
          existingAccounts: const [
            CutoverExistingAccount(
              id: 'account-a',
              name: 'Banque A',
              kind: 'bank',
              ownershipType: AccountOwnershipType.individual,
              holderUserIds: [holderA],
              archived: false,
            ),
            CutoverExistingAccount(
              id: 'account-b',
              name: 'BANQUE A',
              kind: 'bank',
              ownershipType: AccountOwnershipType.individual,
              holderUserIds: [holderA],
              archived: false,
            ),
          ],
          existingEnvelopes: const [],
        );

    expect(plan.accounts.single.conflictDecision, 'conflict');
    expect(plan.accounts.single.matchedAccountId, isNull);
    expect(plan.canConfirm, isFalse);
  });
}
