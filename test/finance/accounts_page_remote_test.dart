import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/features/finance/application/providers/active_household_provider.dart';
import 'package:noyau_app/features/finance/application/providers/remote_accounts_provider.dart';
import 'package:noyau_app/features/finance/application/providers/remote_household_members_provider.dart';
import 'package:noyau_app/features/finance/domain/account_ownership.dart';
import 'package:noyau_app/features/finance/domain/household_member.dart';
import 'package:noyau_app/features/finance/infrastructure/accounts_supabase_repository.dart';
import 'package:noyau_app/features/finance/presentation/accounts_page.dart';

void main() {
  const householdId = 'household-1';

  Future<void> pumpPage(
    WidgetTester tester,
    _Gateway gateway, {
    List<HouseholdMember> members = const [],
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeHouseholdProvider.overrideWith(
            (ref) async => const ActiveHouseholdState(
              status: ActiveHouseholdStatus.singleHousehold,
              householdId: householdId,
              householdIds: [householdId],
            ),
          ),
          supabaseAccountsGatewayProvider.overrideWithValue(gateway),
          householdMembersGatewayProvider.overrideWithValue(
            _MembersGateway(members),
          ),
        ],
        child: const MaterialApp(home: AccountsPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openCreateDialog(WidgetTester tester) async {
    final add = find.byType(FloatingActionButton);
    expect(add, findsOneWidget);
    await tester.tap(add);
    await tester.pumpAndSettle();
    expect(find.text('Ajouter un compte'), findsOneWidget);
  }

  Future<void> selectType(WidgetTester tester, String label) async {
    final type = find.byKey(const Key('account-type-field'));
    expect(type, findsOneWidget);
    await tester.tap(type);
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  testWidgets('ecran Comptes affiche exclusivement les comptes distants', (
    tester,
  ) async {
    await pumpPage(tester, _Gateway(initialNames: ['Compte distant']));

    expect(find.text('Compte distant'), findsOneWidget);
    final add = tester.widget<FloatingActionButton>(
      find.byType(FloatingActionButton),
    );
    expect(add.onPressed, isNotNull);
  });

  testWidgets('creation reussie cree a distance et rafraichit la liste', (
    tester,
  ) async {
    final gateway = _Gateway();
    await pumpPage(tester, gateway);
    await openCreateDialog(tester);

    await tester.enterText(
      find.byKey(const Key('account-name-field')),
      'Compte principal',
    );
    await selectType(tester, 'Banque');
    await tester.enterText(
      find.byKey(const Key('account-opening-balance-field')),
      '1000,50',
    );
    await tester.tap(find.byKey(const Key('create-remote-account-button')));
    await tester.pumpAndSettle();

    expect(gateway.createCalls, 1);
    expect(gateway.createdValues.single['name'], 'Compte principal');
    expect(gateway.createdValues.single['kind'], 'bank');
    expect(gateway.createdValues.single['opening_balance'], '1000.50');
    expect(gateway.createdOwnershipType, AccountOwnershipType.household);
    expect(gateway.createdHolderUserIds, isEmpty);
    expect(gateway.fetchCalls, greaterThanOrEqualTo(2));
    expect(find.text('Compte principal'), findsOneWidget);
    expect(find.text('Compte créé avec succès.'), findsOneWidget);
  });

  testWidgets(
    'la liste affiche les titulaires lies sans utiliser ownership_type',
    (tester) async {
      const members = [
        HouseholdMember(id: 'ibrahim-id', displayName: 'Ibrahim'),
        HouseholdMember(id: 'nora-id', displayName: 'Nora'),
      ];
      final rows = [
        _Gateway._row(
          0,
          'Compte individuel',
          ownershipType: AccountOwnershipType.individual,
          holderUserIds: const ['ibrahim-id'],
        ),
        _Gateway._row(
          1,
          'Compte partage',
          ownershipType: AccountOwnershipType.shared,
          holderUserIds: const ['ibrahim-id', 'nora-id'],
        ),
        _Gateway._row(
          2,
          'Compte foyer',
          ownershipType: AccountOwnershipType.household,
          holderUserIds: const ['ibrahim-id', 'nora-id'],
        ),
      ];
      await pumpPage(tester, _Gateway(initialRows: rows), members: members);

      expect(find.text('Banque • Ibrahim • Actif'), findsOneWidget);
      expect(find.text('Banque • Ibrahim & Nora • Actif'), findsNWidgets(2));
      expect(find.text('Commun'), findsNothing);
    },
  );

  testWidgets('un compte foyer associe les membres du foyer selectionnes', (
    tester,
  ) async {
    const members = [
      HouseholdMember(id: 'ibrahim-id', displayName: 'Ibrahim'),
      HouseholdMember(id: 'nora-id', displayName: 'Nora'),
    ];
    final gateway = _Gateway();
    await pumpPage(tester, gateway, members: members);
    await openCreateDialog(tester);

    await tester.enterText(
      find.byKey(const Key('account-name-field')),
      'Compte foyer',
    );
    await selectType(tester, 'Banque');
    await tester.tap(find.byKey(const Key('create-remote-account-button')));
    await tester.pumpAndSettle();

    expect(gateway.createdOwnershipType, AccountOwnershipType.household);
    expect(gateway.createdHolderUserIds, ['ibrahim-id', 'nora-id']);
    expect(find.text('Banque • Ibrahim & Nora • Actif'), findsOneWidget);
  });

  testWidgets('nom obligatoire et nom deja existant sont refuses', (
    tester,
  ) async {
    await pumpPage(tester, _Gateway(initialNames: ['Compte existant']));
    await openCreateDialog(tester);

    await tester.tap(find.byKey(const Key('create-remote-account-button')));
    await tester.pumpAndSettle();
    expect(find.text('Le nom est obligatoire.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('account-name-field')),
      '  COMPTE EXISTANT  ',
    );
    await selectType(tester, 'Banque');
    await tester.tap(find.byKey(const Key('create-remote-account-button')));
    await tester.pumpAndSettle();
    expect(
      find.text('Un compte portant ce nom existe déjà dans le foyer.'),
      findsOneWidget,
    );
  });

  testWidgets('type obligatoire et solde MAD invalide sont refuses', (
    tester,
  ) async {
    await pumpPage(tester, _Gateway());
    await openCreateDialog(tester);
    await tester.enterText(
      find.byKey(const Key('account-name-field')),
      'Compte a valider',
    );

    await tester.tap(find.byKey(const Key('create-remote-account-button')));
    await tester.pumpAndSettle();
    expect(find.text('Choisissez un type de compte.'), findsOneWidget);

    await selectType(tester, 'Banque');
    await tester.enterText(
      find.byKey(const Key('account-opening-balance-field')),
      '12,345',
    );
    await tester.tap(find.byKey(const Key('create-remote-account-button')));
    await tester.pumpAndSettle();
    expect(find.text('Saisissez un montant MAD valide.'), findsOneWidget);
  });

  testWidgets('compte individuel sans titulaire est refuse', (tester) async {
    final gateway = _Gateway();
    await pumpPage(tester, gateway);
    await openCreateDialog(tester);
    await tester.enterText(
      find.byKey(const Key('account-name-field')),
      'Compte titulaire',
    );
    await selectType(tester, 'Banque');
    await tester.tap(find.byKey(const Key('account-ownership-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Compte individuel').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('create-remote-account-button')));
    await tester.pumpAndSettle();

    expect(find.text('Sélectionnez exactement un titulaire.'), findsOneWidget);
    expect(gateway.createCalls, 0);
  });

  testWidgets('compte individuel et partagé transmettent les titulaires', (
    tester,
  ) async {
    const members = [
      HouseholdMember(id: 'ibrahim-id', displayName: 'Ibrahim'),
      HouseholdMember(id: 'nora-id', displayName: 'Nora'),
    ];
    final individualGateway = _Gateway();
    await pumpPage(tester, individualGateway, members: members);
    await openCreateDialog(tester);
    await tester.enterText(
      find.byKey(const Key('account-name-field')),
      'Compte Ibrahim',
    );
    await selectType(tester, 'Banque');
    await tester.tap(find.byKey(const Key('account-ownership-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Compte individuel').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('account-holder-ibrahim-id')));
    await tester.tap(find.byKey(const Key('create-remote-account-button')));
    await tester.pumpAndSettle();
    expect(
      individualGateway.createdOwnershipType,
      AccountOwnershipType.individual,
    );
    expect(individualGateway.createdHolderUserIds, ['ibrahim-id']);
    expect(
      individualGateway.persistedOwnershipType,
      AccountOwnershipType.individual,
    );
    expect(individualGateway.persistedHolderUserIds, ['ibrahim-id']);

    final sharedGateway = _Gateway();
    await pumpPage(tester, sharedGateway, members: members);
    await openCreateDialog(tester);
    await tester.enterText(
      find.byKey(const Key('account-name-field')),
      'Compte Partage',
    );
    await selectType(tester, 'Banque');
    await tester.tap(find.byKey(const Key('account-ownership-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Compte partagé').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('account-holder-ibrahim-id')));
    await tester.tap(find.byKey(const Key('account-holder-nora-id')));
    await tester.tap(find.byKey(const Key('create-remote-account-button')));
    await tester.pumpAndSettle();
    expect(sharedGateway.createdOwnershipType, AccountOwnershipType.shared);
    expect(sharedGateway.createdHolderUserIds, ['ibrahim-id', 'nora-id']);
    expect(sharedGateway.persistedOwnershipType, AccountOwnershipType.shared);
    expect(sharedGateway.persistedHolderUserIds, ['ibrahim-id', 'nora-id']);
  });

  testWidgets('le formulaire affiche les noms des titulaires sans UUID', (
    tester,
  ) async {
    const members = [
      HouseholdMember(id: 'ibrahim-id', displayName: 'Ibrahim'),
      HouseholdMember(id: 'nora-id', displayName: 'Nora'),
    ];
    await pumpPage(tester, _Gateway(), members: members);
    await openCreateDialog(tester);
    await tester.tap(find.byKey(const Key('account-ownership-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Compte individuel').last);
    await tester.pumpAndSettle();

    expect(find.text('Ibrahim'), findsOneWidget);
    expect(find.text('Nora'), findsOneWidget);
    expect(find.text('ibrahim-id'), findsNothing);
    expect(find.text('nora-id'), findsNothing);
  });

  testWidgets('compte partagé avec un seul titulaire est refusé', (
    tester,
  ) async {
    const members = [
      HouseholdMember(id: 'ibrahim-id', displayName: 'Ibrahim'),
      HouseholdMember(id: 'nora-id', displayName: 'Nora'),
    ];
    final gateway = _Gateway();
    await pumpPage(tester, gateway, members: members);
    await openCreateDialog(tester);
    await tester.enterText(
      find.byKey(const Key('account-name-field')),
      'Compte partage',
    );
    await selectType(tester, 'Banque');
    await tester.tap(find.byKey(const Key('account-ownership-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Compte partagé').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('account-holder-ibrahim-id')));
    await tester.tap(find.byKey(const Key('create-remote-account-button')));
    await tester.pumpAndSettle();

    expect(find.text('Sélectionnez au moins deux titulaires.'), findsOneWidget);
    expect(gateway.createCalls, 0);
  });

  testWidgets('types francais sont convertis vers les types distants', (
    tester,
  ) async {
    const expectedKinds = {
      'Banque': 'bank',
      'Espèces': 'cash',
      'Épargne': 'savings',
      'Emprunt': 'loan',
    };

    for (final entry in expectedKinds.entries) {
      final gateway = _Gateway();
      await pumpPage(tester, gateway);
      await openCreateDialog(tester);
      await tester.enterText(
        find.byKey(const Key('account-name-field')),
        'Compte ${entry.value}',
      );
      await selectType(tester, entry.key);
      await tester.tap(find.byKey(const Key('create-remote-account-button')));
      await tester.pumpAndSettle();

      expect(gateway.createdValues.single['kind'], entry.value);
    }
  });

  testWidgets('double clic est bloque pendant la creation distante', (
    tester,
  ) async {
    final completer = Completer<void>();
    final gateway = _Gateway(createCompleter: completer);
    await pumpPage(tester, gateway);
    await openCreateDialog(tester);
    await tester.enterText(
      find.byKey(const Key('account-name-field')),
      'Compte attente',
    );
    await selectType(tester, 'Banque');

    final create = find.byKey(const Key('create-remote-account-button'));
    await tester.tap(create);
    await tester.pump();
    expect(gateway.createCalls, 1);
    expect(tester.widget<FilledButton>(create).onPressed, isNull);

    completer.complete();
    await tester.pumpAndSettle();
    expect(gateway.createCalls, 1);
  });

  testWidgets('erreur distante reste lisible et ne cree aucun compte local', (
    tester,
  ) async {
    final gateway = _Gateway(createError: Exception('reseau indisponible'));
    await pumpPage(tester, gateway);
    await openCreateDialog(tester);
    await tester.enterText(
      find.byKey(const Key('account-name-field')),
      'Compte erreur',
    );
    await selectType(tester, 'Banque');
    await tester.tap(find.byKey(const Key('create-remote-account-button')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Création impossible :'), findsOneWidget);
    expect(gateway.createdValues, isEmpty);
    expect(find.text('Ajouter un compte'), findsOneWidget);
  });

  testWidgets('sans foyer actif le bouton Ajouter reste indisponible', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeHouseholdProvider.overrideWith(
            (ref) async => const ActiveHouseholdState(
              status: ActiveHouseholdStatus.noAuthenticatedUser,
            ),
          ),
          supabaseAccountsGatewayProvider.overrideWithValue(_Gateway()),
        ],
        child: const MaterialApp(home: AccountsPage()),
      ),
    );
    await tester.pumpAndSettle();

    final add = tester.widget<FloatingActionButton>(
      find.byType(FloatingActionButton),
    );
    expect(add.onPressed, isNull);
    expect(find.textContaining('Aucun foyer actif'), findsOneWidget);
  });
}

class _Gateway implements AccountsSupabaseGateway {
  _Gateway({
    List<String> initialNames = const [],
    List<Map<String, Object?>> initialRows = const [],
    this.createCompleter,
    this.createError,
  }) : _rows = [
         ...initialNames.asMap().entries.map(
           (entry) => _row(entry.key, entry.value),
         ),
         ...initialRows.map(Map<String, Object?>.from),
       ];

  final List<Map<String, Object?>> _rows;
  final Completer<void>? createCompleter;
  final Exception? createError;
  final List<Map<String, Object?>> createdValues = [];
  AccountOwnershipType? createdOwnershipType;
  List<String>? createdHolderUserIds;
  AccountOwnershipType? persistedOwnershipType;
  List<String>? persistedHolderUserIds;
  var fetchCalls = 0;
  var createCalls = 0;

  @override
  Future<List<Map<String, Object?>>> fetchAccounts(String householdId) async {
    fetchCalls++;
    return List<Map<String, Object?>>.from(_rows);
  }

  @override
  Future<void> createAccount({
    required String householdId,
    required Map<String, Object?> values,
    required AccountOwnershipType ownershipType,
    required List<String> holderUserIds,
  }) async {
    createCalls++;
    createdOwnershipType = ownershipType;
    createdHolderUserIds = List<String>.from(holderUserIds);
    if (createError != null) {
      throw createError!;
    }
    if (createCompleter != null) {
      await createCompleter!.future;
    }
    final copy = Map<String, Object?>.from(values);
    createdValues.add(copy);
    persistedOwnershipType = ownershipType;
    persistedHolderUserIds = List<String>.from(holderUserIds);
    _rows.add(
      _row(
        _rows.length,
        copy['name']! as String,
        values: copy,
        ownershipType: ownershipType,
        holderUserIds: holderUserIds,
      ),
    );
  }

  static Map<String, Object?> _row(
    int index,
    String name, {
    Map<String, Object?>? values,
    AccountOwnershipType ownershipType = AccountOwnershipType.household,
    List<String> holderUserIds = const [],
  }) => {
    'id': 'account-$index',
    'household_id': 'household-1',
    'name': name,
    'kind': values?['kind'] ?? 'bank',
    'ownership_type': ownershipType.name,
    'account_holders': holderUserIds
        .map(
          (userId) => {
            'user_id': userId,
            'household_members': {'user_id': userId},
          },
        )
        .toList(growable: false),
    'opening_balance': values?['opening_balance'] ?? '0.00',
    'archived_at': values?['archived_at'],
    'created_at': '2026-08-04T10:00:00Z',
    'updated_at': '2026-08-04T10:00:00Z',
  };
}

class _MembersGateway implements HouseholdMembersGateway {
  const _MembersGateway(this.members);

  final List<HouseholdMember> members;

  @override
  Future<List<HouseholdMember>> fetchMembers(String householdId) async =>
      members;
}
