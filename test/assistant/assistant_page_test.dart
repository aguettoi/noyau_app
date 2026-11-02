import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/core/localization/app_locale.dart';
import 'package:noyau_app/features/assistant/application/assistant_providers.dart';
import 'package:noyau_app/features/assistant/domain/assistant_contract.dart';
import 'package:noyau_app/features/assistant/presentation/assistant_locale.dart';
import 'package:noyau_app/features/assistant/presentation/assistant_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('assistant renders all languages with correct direction', (
    tester,
  ) async {
    final controller = AppLocaleController(
      environmentLocales: () => const [Locale('fr')],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appLocaleProvider.overrideWith((ref) => controller),
          assistantContextBuilderProvider.overrideWithValue(
            const _ContextBuilder(),
          ),
        ],
        child: const _Harness(),
      ),
    );
    for (final language in AppLanguage.values) {
      await controller.select(language);
      await tester.pumpAndSettle();
      final title = find.text(AssistantWords(language).text('assistant.title'));
      expect(title, findsOneWidget, reason: language.name);
      expect(
        Directionality.of(tester.element(title)),
        language == AppLanguage.arabic || language == AppLanguage.darija
            ? TextDirection.rtl
            : TextDirection.ltr,
      );
    }
  });
}

class _Harness extends ConsumerWidget {
  const _Harness();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(appLocaleProvider);
    return MaterialApp(
      locale: language.locale,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('fr'),
        Locale('en'),
        Locale('ar'),
        Locale('ar', 'MA'),
      ],
      home: const AssistantPage(),
    );
  }
}

class _ContextBuilder implements AssistantContextBuilder {
  const _ContextBuilder();
  @override
  Future<AuthorizedAssistantContext> build(AssistantUseCase useCase) async =>
      AuthorizedAssistantContext(
        userId: 'user-a',
        householdId: 'household-a',
        useCase: useCase,
        generatedAt: DateTime.utc(2026, 11, 2),
        visibleFacts: const {'budget_remaining_minor': 10},
        sourceCategories: const {'budget_summary'},
      );
}
