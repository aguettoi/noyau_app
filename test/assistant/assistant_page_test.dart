import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/core/localization/app_locale.dart';
import 'package:noyau_app/features/assistant/application/assistant_providers.dart';
import 'package:noyau_app/features/assistant/domain/assistant_contract.dart';
import 'package:noyau_app/features/assistant/domain/conversation_contract.dart';
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
          assistantGenerativeEnabledProvider.overrideWithValue(true),
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
    expect(
      find.byKey(const ValueKey('assistant-question-field')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('assistant-send')), findsOneWidget);
  });

  testWidgets(
    'READ navigation is direct and has no reject or confirm controls',
    (tester) async {
      var opened = 0;
      final controller = AppLocaleController(
        environmentLocales: () => const [Locale('fr')],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            assistantGenerativeEnabledProvider.overrideWithValue(true),
            appLocaleProvider.overrideWith((ref) => controller),
            assistantContextBuilderProvider.overrideWithValue(
              const _ContextBuilder(),
            ),
            assistantConversationProvider.overrideWith(
              (ref) => _SeededConversationController(ref),
            ),
          ],
          child: MaterialApp(home: AssistantPage(onOpenBudget: () => opened++)),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('assistant-navigation-budget')),
        findsOneWidget,
      );
      expect(find.text('Refuser'), findsNothing);
      expect(find.text('Confirmer'), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('assistant-navigation-budget')),
      );
      expect(opened, 1);
    },
  );

  testWidgets('governed action proposals retain reject and confirm controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          assistantGenerativeEnabledProvider.overrideWithValue(true),
          assistantContextBuilderProvider.overrideWithValue(
            const _ContextBuilder(),
          ),
          assistantConversationProvider.overrideWith(
            (ref) => _SeededProposalController(ref),
          ),
        ],
        child: const MaterialApp(home: AssistantPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(OutlinedButton), findsOneWidget);
    expect(find.byType(FilledButton), findsOneWidget);
  });

  testWidgets('commercial V1 exposes deterministic assistant only by default', (
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
        child: const MaterialApp(home: AssistantPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Assistant déterministe'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('assistant-question-field')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('assistant-send')), findsNothing);
    expect(find.byType(ChoiceChip), findsWidgets);
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

class _SeededConversationController extends AssistantConversationController {
  _SeededConversationController(super.ref) {
    state = AssistantConversationState(
      messages: [
        AssistantConversationMessage(
          id: 'assistant-1',
          role: 'assistant',
          content: 'Réponse en lecture.',
          createdAt: DateTime.utc(2026, 11, 21),
        ),
      ],
      navigations: const [
        AssistantNavigationLink(
          target: 'budget',
          labelKey: 'assistant.action.open_budget',
        ),
      ],
      lastStatus: AssistantConversationStatus.ready,
    );
  }
}

class _SeededProposalController extends AssistantConversationController {
  _SeededProposalController(super.ref) {
    final now = DateTime.now().toUtc();
    state = AssistantConversationState(
      messages: [
        AssistantConversationMessage(
          id: 'assistant-1',
          role: 'assistant',
          content: 'Action préparée.',
          createdAt: now,
        ),
      ],
      proposals: [
        AssistantProposal(
          id: 'proposal-1',
          type: 'governed_action',
          objectiveKey: 'assistant.action.open_budget',
          justificationKey: 'assistant.action.review_budget',
          risk: AssistantRisk.moderate,
          createdAt: now,
          expiresAt: now.add(const Duration(minutes: 5)),
        ),
      ],
      lastStatus: AssistantConversationStatus.ready,
    );
  }
}
