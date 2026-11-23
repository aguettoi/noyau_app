import 'dart:async';

import '../domain/conversation_contract.dart';

class AssistantConversationOrchestrator {
  const AssistantConversationOrchestrator({
    required this.provider,
    required this.capabilities,
    this.timeout = const Duration(seconds: 65),
    this.maxCapabilitiesPerTurn = 6,
  });

  final ConversationalAIProvider provider;
  final AssistantCapabilityExecutor capabilities;
  final Duration timeout;
  final int maxCapabilitiesPerTurn;

  Future<AssistantConversationAnswer> answer(
    AssistantConversationRequest request,
  ) async {
    if (request.question.trim().isEmpty || request.question.length > 4000) {
      throw ArgumentError.value(request.question, 'question');
    }
    final watch = Stopwatch()..start();
    late final AssistantConversationPlan plan;
    try {
      plan = await provider
          .plan(
            request: request,
            availableCapabilities: capabilities.descriptors,
          )
          .timeout(timeout);
    } on TimeoutException {
      return _providerFailure(
        request: request,
        watch: watch,
        phase: AssistantFailurePhase.planning,
        category: AssistantProviderErrorCategory.timeout,
        status: AssistantConversationStatus.timeout,
      );
    } on AssistantProviderException catch (error) {
      return _providerFailure(
        request: request,
        watch: watch,
        phase: error.phase,
        category: error.category,
      );
    } on FormatException {
      return _providerFailure(
        request: request,
        watch: watch,
        phase: AssistantFailurePhase.planning,
        category: AssistantProviderErrorCategory.invalidJson,
      );
    } catch (_) {
      return _providerFailure(
        request: request,
        watch: watch,
        phase: AssistantFailurePhase.planning,
        category: AssistantProviderErrorCategory.unknown,
      );
    }
    try {
      final allowedIds = capabilities.descriptors
          .map((item) => item.id)
          .toSet();
      final selected = plan.capabilityIds
          .intersection(allowedIds)
          .take(maxCapabilitiesPerTurn)
          .toSet();
      final scopeResolved = _scopeResolved(
        plan: plan,
        selectedIds: selected,
        question: request.question,
        descriptors: capabilities.descriptors,
      );
      if (plan.needsClarification || !scopeResolved) {
        final question = plan.clarificationQuestion?.trim();
        return AssistantConversationAnswer(
          text: question?.isNotEmpty == true
              ? question!
              : _clarificationAnswer(request.uiLocale),
          language: plan.language,
          status: AssistantConversationStatus.ready,
          provider: provider.providerId,
          model: 'semantic-planner',
          capabilityIds: const {},
          sourceCategories: const {},
          operationLevel: AssistantOperationLevel.read,
          duration: watch.elapsed,
        );
      }
      late final List<AuthorizedCapabilityResult> authorizedResults;
      try {
        authorizedResults = await capabilities
            .execute(selected)
            .timeout(timeout);
      } on TimeoutException {
        return _providerFailure(
          request: request,
          watch: watch,
          phase: AssistantFailurePhase.capabilityRetrieval,
          category: AssistantProviderErrorCategory.timeout,
          status: AssistantConversationStatus.failed,
        );
      } catch (_) {
        return _providerFailure(
          request: request,
          watch: watch,
          phase: AssistantFailurePhase.capabilityRetrieval,
          category: AssistantProviderErrorCategory.unknown,
          status: AssistantConversationStatus.failed,
        );
      }
      if (authorizedResults.isNotEmpty &&
          authorizedResults.every(
            (result) => result.unavailableReason != null,
          )) {
        return AssistantConversationAnswer(
          text: _unavailableAnswer(request.uiLocale),
          language: request.uiLocale,
          status: AssistantConversationStatus.ready,
          provider: 'deterministic-governance',
          model: 'none',
          capabilityIds: selected,
          sourceCategories: {
            for (final result in authorizedResults) ...result.sourceCategories,
          },
          operationLevel: plan.operationLevel,
          duration: watch.elapsed,
        );
      }
      final boundedPlan = AssistantConversationPlan(
        language: plan.language,
        capabilityIds: selected,
        operationLevel: plan.operationLevel,
      );
      return await provider
          .respond(
            request: request,
            plan: boundedPlan,
            authorizedResults: authorizedResults,
          )
          .timeout(timeout);
    } on TimeoutException {
      return _providerFailure(
        request: request,
        watch: watch,
        phase: AssistantFailurePhase.synthesis,
        category: AssistantProviderErrorCategory.timeout,
        status: AssistantConversationStatus.timeout,
      );
    } on AssistantProviderException catch (error) {
      return _providerFailure(
        request: request,
        watch: watch,
        phase: error.phase,
        category: error.category,
      );
    } on FormatException {
      return _providerFailure(
        request: request,
        watch: watch,
        phase: AssistantFailurePhase.synthesis,
        category: AssistantProviderErrorCategory.unsafeOutput,
      );
    } catch (_) {
      return _providerFailure(
        request: request,
        watch: watch,
        phase: AssistantFailurePhase.synthesis,
        category: AssistantProviderErrorCategory.unknown,
      );
    }
  }

  AssistantConversationAnswer _providerFailure({
    required AssistantConversationRequest request,
    required Stopwatch watch,
    required AssistantFailurePhase phase,
    required AssistantProviderErrorCategory category,
    AssistantConversationStatus status =
        AssistantConversationStatus.providerUnavailable,
  }) => AssistantConversationAnswer(
    text: '',
    language: request.uiLocale,
    status: status,
    provider: provider.providerId,
    model: 'unavailable',
    capabilityIds: const {},
    sourceCategories: const {},
    operationLevel: AssistantOperationLevel.read,
    duration: watch.elapsed,
    fallbackUsed: true,
    failurePhase: phase,
    failureCategory: category,
  );
}

bool _scopeResolved({
  required AssistantConversationPlan plan,
  required Set<String> selectedIds,
  required String question,
  required List<AssistantCapabilityDescriptor> descriptors,
}) {
  if (selectedIds.isEmpty) {
    return plan.scopeBasis != AssistantScopeBasis.clarificationRequired;
  }
  switch (plan.scopeBasis) {
    case AssistantScopeBasis.explicitContext:
      final evidence = plan.scopeEvidence?.trim() ?? '';
      return evidence.isNotEmpty &&
          question.toLowerCase().contains(evidence.toLowerCase());
    case AssistantScopeBasis.canonicalGlobalAggregate:
      final byId = {for (final item in descriptors) item.id: item};
      return selectedIds.every(
        (id) => byId[id]?.allowsImplicitGlobalResolution == true,
      );
    case AssistantScopeBasis.clarificationRequired:
      return false;
    case AssistantScopeBasis.unspecified:
      final byId = {for (final item in descriptors) item.id: item};
      return selectedIds.every((id) => byId[id]?.semanticScope.isEmpty == true);
  }
}

String _clarificationAnswer(String locale) => switch (locale) {
  'en' =>
    'Which financial scope do you mean: a global overview or a more specific budget, category, or purpose?',
  'ar' =>
    'ما هو النطاق المالي المقصود: نظرة عامة أم ميزانية أو فئة أو غرض محدد؟',
  'ary' || 'ar-MA' =>
    'شنو هو النطاق المالي اللي كتعني: نظرة عامة ولا بودجي ولا فئة ولا غرض محدد؟',
  _ =>
    'De quel périmètre financier parlez-vous : une vue globale ou un budget, une catégorie ou un objectif précis ?',
};

String _unavailableAnswer(String locale) => switch (locale) {
  'en' =>
    'The available data does not provide a reliable amount for this question.',
  'ar' => 'المعطيات المتاحة لا تسمح بتحديد مبلغ موثوق لهذا السؤال.',
  'ary' || 'ar-MA' =>
    'المعطيات اللي متوفرة ما كافياش باش نعطيو مبلغ موثوق على هاد السؤال.',
  _ =>
    'Les données disponibles ne permettent pas de donner un montant fiable pour cette question.',
};
