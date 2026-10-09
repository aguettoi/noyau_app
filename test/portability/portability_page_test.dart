import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:noyau_app/features/portability/application/portability_provider.dart';
import 'package:noyau_app/features/portability/domain/portability_models.dart';
import 'package:noyau_app/features/portability/presentation/portability_page.dart';

class _Search implements GlobalSearchGateway {
  @override
  Future<List<GlobalSearchResult>> search(
    String query, {
    int page = 0,
    int size = 50,
  }) async => page == 0
      ? const [
          GlobalSearchResult(
            type: SearchResultType.task,
            id: 'task',
            title: 'Assurance voiture',
            subtitle: 'Tâche',
          ),
        ]
      : const [];
}

void main() {
  testWidgets('global search debounces, displays results and paginates', (
    tester,
  ) async {
    await initializeDateFormatting('fr');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          globalSearchGatewayProvider.overrideWithValue(_Search()),
          importHistoryProvider.overrideWith((ref) async => const []),
        ],
        child: const MaterialApp(home: PortabilityPage()),
      ),
    );
    expect(find.text('Saisissez au moins 2 caractères.'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('global-search-field')),
      'assurance',
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('Assurance voiture'), findsOneWidget);
    await tester.tap(find.text('Afficher plus'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('import history exposes its recorded actor', (tester) async {
    await initializeDateFormatting('fr');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          globalSearchGatewayProvider.overrideWithValue(_Search()),
          importHistoryProvider.overrideWith(
            (ref) async => [
              ImportHistoryEntry(
                id: 'run',
                fileName: 'source.xlsx',
                status: 'completed',
                createdAt: DateTime(2026, 10, 9),
                detectedRecords: 12,
                actorId: 'user-technique',
              ),
            ],
          ),
        ],
        child: const MaterialApp(home: PortabilityPage()),
      ),
    );
    await tester.tap(find.text('Imports'));
    await tester.pumpAndSettle();
    expect(find.textContaining('acteur user-technique'), findsOneWidget);
  });
}
