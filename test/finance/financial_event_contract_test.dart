import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/features/finance/application/financial_event_contract.dart';

void main() {
  group('FinancialEventContract', () {
    test('valide une dépense cash ventilée de 200', () {
      expect(
        () => FinancialEventContract.validateEnvelopeSplit(
          totalAmount: 200,
          allocations: const [
            FinancialEventAllocation(envelopeId: 'courses', amount: 120),
            FinancialEventAllocation(envelopeId: 'transport', amount: 80),
          ],
        ),
        returnsNormally,
      );
    });

    test('refuse une ventilation incomplète, excessive ou dupliquée', () {
      expect(
        () => FinancialEventContract.validateEnvelopeSplit(
          totalAmount: 200,
          allocations: const [
            FinancialEventAllocation(envelopeId: 'courses', amount: 199),
          ],
        ),
        throwsStateError,
      );
      expect(
        () => FinancialEventContract.validateEnvelopeSplit(
          totalAmount: 200,
          allocations: const [
            FinancialEventAllocation(envelopeId: 'courses', amount: 100),
            FinancialEventAllocation(envelopeId: 'courses', amount: 100),
          ],
        ),
        throwsStateError,
      );
    });

    test(
      'autorise un revenu non réparti ou partiel et refuse le dépassement',
      () {
        expect(
          () => FinancialEventContract.validateIncomeEnvelopeAllocations(
            totalAmount: 1000,
            allocations: const [],
          ),
          returnsNormally,
        );
        expect(
          () => FinancialEventContract.validateIncomeEnvelopeAllocations(
            totalAmount: 1000,
            allocations: const [
              FinancialEventAllocation(envelopeId: 'courses', amount: 600),
            ],
          ),
          returnsNormally,
        );
        expect(
          () => FinancialEventContract.validateIncomeEnvelopeAllocations(
            totalAmount: 1000,
            allocations: const [
              FinancialEventAllocation(envelopeId: 'courses', amount: 600),
              FinancialEventAllocation(envelopeId: 'navette', amount: 401),
            ],
          ),
          throwsStateError,
        );
      },
    );

    test('gère les règlements partiels puis final sans seconde charge', () {
      expect(
        FinancialEventContract.remainingAfterSettlement(
          initialAmount: 500,
          settledAmount: 0,
          settlementAmount: 200,
        ),
        300,
      );
      expect(
        FinancialEventContract.remainingAfterSettlement(
          initialAmount: 500,
          settledAmount: 200,
          settlementAmount: 300,
        ),
        0,
      );
    });

    test('refuse un règlement supérieur au restant', () {
      expect(
        () => FinancialEventContract.remainingAfterSettlement(
          initialAmount: 500,
          settledAmount: 200,
          settlementAmount: 301,
        ),
        throwsStateError,
      );
    });

    test(
      'autorise un recovery uniquement avec une enveloppe source non remboursée',
      () {
        expect(
          () => FinancialEventContract.validateRecoveryRefund(
            sourceEnvelopeIsLinked: true,
            unreimbursedSourceConsumption: 200,
            settlementAmount: 200,
          ),
          returnsNormally,
        );
        expect(
          () => FinancialEventContract.validateRecoveryRefund(
            sourceEnvelopeIsLinked: true,
            unreimbursedSourceConsumption: 199,
            settlementAmount: 200,
          ),
          throwsStateError,
        );
      },
    );
  });
}
