import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/features/finance/application/cutover_opening_import.dart';
import 'package:noyau_app/features/finance/domain/account_ownership.dart';
import 'package:noyau_app/features/finance/domain/household_member.dart';
import 'package:noyau_app/features/finance/presentation/import_preview_page.dart';

void main() {
  testWidgets(
    'la preview exige une titularité explicite et des membres dynamiques',
    (tester) async {
      const memberA = HouseholdMember(id: 'member-a', displayName: 'Membre A');
      const memberB = HouseholdMember(id: 'member-b', displayName: 'Membre B');
      var account = const CutoverOpeningAccount(
        sourceLabel: 'A2',
        name: 'Compte sans indice nominatif',
        kind: 'bank',
        openingAmount: 1200,
      );

      Widget app() => MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => CutoverAccountOwnershipCard(
              account: account,
              members: const [memberA, memberB],
              membersLoading: false,
              membersError: false,
              enabled: true,
              onChanged: (value) => setState(() => account = value),
            ),
          ),
        ),
      );

      await tester.pumpWidget(app());
      expect(find.text('À CONFIRMER'), findsWidgets);
      expect(find.text('Membre A'), findsNothing);
      expect(find.text('Membre B'), findsNothing);

      await tester.tap(
        find.byKey(
          const ValueKey('cutover-ownership-Compte sans indice nominatif'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Partagé').last);
      await tester.pumpAndSettle();

      expect(find.text('Membre A'), findsOneWidget);
      expect(find.text('Membre B'), findsOneWidget);
      await tester.tap(find.text('Membre A'));
      await tester.pump();
      await tester.tap(find.text('Membre B'));
      await tester.pump();

      expect(account.ownershipType, AccountOwnershipType.shared);
      expect(account.holderUserIds, ['member-a', 'member-b']);
      expect(account.hasValidOwnership, isTrue);
      expect(find.textContaining('Décision : CRÉER'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
