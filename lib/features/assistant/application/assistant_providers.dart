import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../dashboard/application/providers/remote_financial_dashboard_provider.dart';
import '../../experience/application/offline_connectivity.dart';
import '../../finance/application/providers/active_household_provider.dart';
import '../../finance/application/providers/supabase_client_provider.dart';
import '../../organization/application/organization_provider.dart';
import '../domain/assistant_contract.dart';
import '../domain/conversation_contract.dart';
import '../infrastructure/edge_conversational_ai_provider.dart';
import 'assistant_authorization_revision.dart';
import 'assistant_capabilities.dart';
import 'assistant_engine.dart';
import 'conversational_assistant.dart';

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
        if (useCase == AssistantUseCase.budget &&
            dashboard.budget.hasPreparedBudget)
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
        if (useCase == AssistantUseCase.budget)
          'budget_summary_available': dashboard.budget.hasPreparedBudget,
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

  Future<void> appendConversation({
    required String userId,
    required String householdId,
    required AssistantConversationAnswer answer,
    required DateTime timestamp,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final current = preferences.getStringList(_key) ?? const [];
    final encoded = jsonEncode({
      'event': 'conversation_turn',
      'user_id': userId,
      'household_id': householdId,
      'timestamp': timestamp.toUtc().toIso8601String(),
      'provider': answer.provider,
      'model': answer.model,
      'status': answer.status.name,
      'capability_ids': answer.capabilityIds.toList()..sort(),
      'source_categories': answer.sourceCategories.toList()..sort(),
      'operation_level': answer.operationLevel.name,
      'latency_ms': answer.duration.inMilliseconds,
      'prompt_tokens': answer.promptTokens,
      'completion_tokens': answer.completionTokens,
      'total_tokens': answer.totalTokens,
      'estimated_cost_minor': answer.estimatedCostMinor,
      'fallback': answer.fallbackUsed,
      'failure_phase': answer.failurePhase?.name,
      'failure_category': answer.failureCategory?.name,
    });
    await preferences.setStringList(_key, [...current.take(199), encoded]);
  }
}

final assistantContextBuilderProvider = Provider<AssistantContextBuilder>(
  (ref) => CanonicalAssistantContextBuilder(ref),
);
final assistantProvider = Provider<AssistantProvider>(
  (_) => const DeterministicAssistantProvider(),
);
final assistantAuditStoreProvider = Provider((_) => AssistantAuditStore());

final assistantGenerativeEnabledProvider = Provider<bool>(
  (_) => const bool.fromEnvironment(
    'ENABLE_GENERATIVE_ASSISTANT',
    defaultValue: false,
  ),
);

final conversationalAIProvider = Provider<ConversationalAIProvider>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return EdgeConversationalAIProvider(SupabaseAssistantFunctionGateway(client));
});

class AssistantConversationState {
  const AssistantConversationState({
    this.messages = const [],
    this.navigations = const [],
    this.proposals = const [],
    this.isSending = false,
    this.lastStatus,
  });

  final List<AssistantConversationMessage> messages;
  final List<AssistantNavigationLink> navigations;
  final List<AssistantProposal> proposals;
  final bool isSending;
  final AssistantConversationStatus? lastStatus;

  AssistantConversationState copyWith({
    List<AssistantConversationMessage>? messages,
    List<AssistantNavigationLink>? navigations,
    List<AssistantProposal>? proposals,
    bool? isSending,
    AssistantConversationStatus? lastStatus,
  }) => AssistantConversationState(
    messages: messages ?? this.messages,
    navigations: navigations ?? this.navigations,
    proposals: proposals ?? this.proposals,
    isSending: isSending ?? this.isSending,
    lastStatus: lastStatus ?? this.lastStatus,
  );
}

class AssistantConversationController
    extends StateNotifier<AssistantConversationState> {
  AssistantConversationController(this.ref)
    : super(const AssistantConversationState()) {
    ref.listen<int>(assistantAuthorizationRevisionProvider, (_, _) => clear());
  }

  final Ref ref;

  Future<void> send(String question, {required String uiLocale}) async {
    final trimmed = question.trim();
    if (trimmed.isEmpty || state.isSending) return;
    if (!ref.read(assistantGenerativeEnabledProvider)) return;
    if (ref.read(syncConnectionStateProvider) == SyncConnectionState.offline) {
      state = state.copyWith(lastStatus: AssistantConversationStatus.offline);
      return;
    }
    final household = await ref.read(activeHouseholdProvider.future);
    final userId = ref.read(currentUserIdProvider);
    final householdId = household.householdId;
    if (userId == null || householdId == null) {
      state = state.copyWith(lastStatus: AssistantConversationStatus.failed);
      return;
    }
    final now = DateTime.now().toUtc();
    final userMessage = AssistantConversationMessage(
      id: 'user-${now.microsecondsSinceEpoch}',
      role: 'user',
      content: trimmed,
      createdAt: now,
    );
    final previousUserTurns = state.messages
        .where((message) => message.role == 'user')
        .toList(growable: false);
    state = state.copyWith(
      messages: [...state.messages, userMessage],
      isSending: true,
    );
    try {
      final orchestrator = AssistantConversationOrchestrator(
        provider: ref.read(conversationalAIProvider),
        capabilities: ref.read(assistantCapabilityExecutorProvider),
      );
      final answer = await orchestrator.answer(
        AssistantConversationRequest(
          question: trimmed,
          userId: userId,
          householdId: householdId,
          uiLocale: uiLocale,
          history: previousUserTurns,
        ),
      );
      final nextMessages = [...state.messages];
      if (answer.text.trim().isNotEmpty) {
        nextMessages.add(
          AssistantConversationMessage(
            id: 'assistant-${DateTime.now().microsecondsSinceEpoch}',
            role: 'assistant',
            content: answer.text,
            createdAt: DateTime.now().toUtc(),
          ),
        );
      }
      state = state.copyWith(
        messages: nextMessages,
        navigations: answer.navigations,
        proposals: answer.proposals,
        isSending: false,
        lastStatus: answer.status,
      );
      await ref
          .read(assistantAuditStoreProvider)
          .appendConversation(
            userId: userId,
            householdId: householdId,
            answer: answer,
            timestamp: DateTime.now().toUtc(),
          );
    } catch (_) {
      state = state.copyWith(
        isSending: false,
        lastStatus: AssistantConversationStatus.providerUnavailable,
      );
    }
  }

  void clear() => state = const AssistantConversationState();

  void dismissProposal(String id) {
    state = state.copyWith(
      proposals: state.proposals.where((item) => item.id != id).toList(),
    );
  }
}

final assistantConversationProvider =
    StateNotifierProvider.autoDispose<
      AssistantConversationController,
      AssistantConversationState
    >((ref) => AssistantConversationController(ref));

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
