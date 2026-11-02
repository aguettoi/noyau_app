import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../dashboard/application/providers/remote_financial_dashboard_provider.dart';
import '../../finance/application/providers/active_household_provider.dart';
import '../../finance/application/providers/supabase_client_provider.dart';
import '../../organization/application/organization_provider.dart';
import '../domain/assistant_contract.dart';
import 'assistant_engine.dart';

class CanonicalAssistantContextBuilder implements AssistantContextBuilder {
  const CanonicalAssistantContextBuilder(this.ref);
  final Ref ref;

  @override
  Future<AuthorizedAssistantContext> build(AssistantUseCase useCase) async {
    final household = await ref.read(activeHouseholdProvider.future);
    final userId = ref.read(currentUserIdProvider);
    if (userId == null || household.householdId == null) {
      throw StateError('assistant.context.unavailable');
    }
    final dashboard = await ref.read(financialDashboardProvider.future);
    final tasks = useCase == AssistantUseCase.organization
        ? await ref.read(householdTasksProvider.future)
        : const [];
    return AuthorizedAssistantContext(
      userId: userId,
      householdId: household.householdId!,
      useCase: useCase,
      generatedAt: DateTime.now().toUtc(),
      visibleFacts: {
        if (useCase == AssistantUseCase.budget)
          'budget_remaining_minor': dashboard.budget.remaining.minorUnits,
        if (useCase == AssistantUseCase.monthlySummary ||
            useCase == AssistantUseCase.anomalies)
          'alert_count': dashboard.alerts.length,
        if (useCase == AssistantUseCase.monthlySummary)
          'goal_count': dashboard.activeGoals.length,
        if (useCase == AssistantUseCase.organization)
          'open_task_count': tasks.where((task) => !task.completed).length,
      },
      flags: {
        'has_hidden_financial_data': dashboard.hasHiddenAccountBalances,
        'has_next_priority': dashboard.nextPriority != null,
        'authorized_availability_ok':
            dashboard.availability?.isComplete == true &&
            dashboard.availability!.warnings.isEmpty,
      },
      sourceCategories: switch (useCase) {
        AssistantUseCase.budget => const {'budget_summary'},
        AssistantUseCase.monthlySummary => const {'dashboard_summary'},
        AssistantUseCase.anomalies => const {'authorized_alerts'},
        AssistantUseCase.priorities => const {'priority_summary'},
        AssistantUseCase.organization => const {'household_task_counts'},
        AssistantUseCase.shopping => const {'bounded_availability'},
        AssistantUseCase.wealth => const {'wealth_explanation_contract'},
        AssistantUseCase.productHelp => const {'local_help_catalog'},
      },
    );
  }
}

class AssistantAuditStore {
  static const _key = 'l5.assistant.audit.v1';

  Future<void> append(AssistantAuditEvent event) async {
    final preferences = await SharedPreferences.getInstance();
    final current = preferences.getStringList(_key) ?? const [];
    final encoded = jsonEncode({
      'user_id': event.userId,
      'household_id': event.householdId,
      'use_case': event.useCase.name,
      'timestamp': event.timestamp.toUtc().toIso8601String(),
      'mode': event.mode,
      'source_categories': event.sourceCategories.toList()..sort(),
      'proposal_type': event.proposalType,
      'action_state': event.actionState?.name,
    });
    await preferences.setStringList(_key, [...current.take(199), encoded]);
  }

  Future<List<String>> readMinimizedEvents() async =>
      (await SharedPreferences.getInstance()).getStringList(_key) ?? const [];
}

final assistantContextBuilderProvider = Provider<AssistantContextBuilder>(
  (ref) => CanonicalAssistantContextBuilder(ref),
);
final assistantProvider = Provider<AssistantProvider>(
  (_) => const DeterministicAssistantProvider(),
);
final assistantAuditStoreProvider = Provider((_) => AssistantAuditStore());

final assistantResponseProvider =
    FutureProvider.family<AssistantResponse, AssistantUseCase>((
      ref,
      useCase,
    ) async {
      final context = await ref
          .read(assistantContextBuilderProvider)
          .build(useCase);
      final provider = ref.read(assistantProvider);
      final response = await provider.answer(context);
      await ref
          .read(assistantAuditStoreProvider)
          .append(
            AssistantAuditEvent(
              userId: context.userId,
              householdId: context.householdId,
              useCase: useCase,
              timestamp: DateTime.now().toUtc(),
              mode: provider.mode,
              sourceCategories: context.sourceCategories,
            ),
          );
      return response;
    });
