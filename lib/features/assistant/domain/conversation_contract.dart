import 'assistant_contract.dart';

enum AssistantConversationStatus {
  ready,
  providerUnavailable,
  offline,
  timeout,
  failed,
}

enum AssistantOperationLevel { read, recommend, prepare, execute }

enum AssistantFailurePhase { planning, capabilityRetrieval, synthesis }

enum AssistantProviderErrorCategory {
  emptyContent,
  timeout,
  rateLimited,
  serverError,
  invalidJson,
  invalidEnvelope,
  partialResponse,
  modelUnavailable,
  network,
  unsafeOutput,
  unknown,
}

class AssistantProviderException implements Exception {
  const AssistantProviderException({
    required this.phase,
    required this.category,
  });

  final AssistantFailurePhase phase;
  final AssistantProviderErrorCategory category;
}

enum AssistantScopeBasis {
  unspecified,
  explicitContext,
  canonicalGlobalAggregate,
  clarificationRequired,
}

class AssistantConversationMessage {
  const AssistantConversationMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
  });

  final String id;
  final String role;
  final String content;
  final DateTime createdAt;

  Map<String, Object?> toJson() => {
    'id': id,
    'role': role,
    'content': content,
    'created_at': createdAt.toUtc().toIso8601String(),
  };
}

class AssistantCapabilityDescriptor {
  const AssistantCapabilityDescriptor({
    required this.id,
    required this.description,
    required this.operationLevel,
    this.semanticScope = '',
    this.allowsImplicitGlobalResolution = false,
  });

  final String id;
  final String description;
  final AssistantOperationLevel operationLevel;
  final String semanticScope;
  final bool allowsImplicitGlobalResolution;

  Map<String, Object?> toJson() => {
    'id': id,
    'description': description,
    'operation_level': operationLevel.name,
    'semantic_scope': semanticScope,
    'allows_implicit_global_resolution': allowsImplicitGlobalResolution,
  };
}

class AuthorizedCapabilityResult {
  const AuthorizedCapabilityResult({
    required this.capabilityId,
    required this.generatedAt,
    required this.facts,
    required this.sourceCategories,
    this.unavailableReason,
  });

  final String capabilityId;
  final DateTime generatedAt;
  final Map<String, Object?> facts;
  final Set<String> sourceCategories;
  final String? unavailableReason;

  Map<String, Object?> toJson() => {
    'capability_id': capabilityId,
    'generated_at': generatedAt.toUtc().toIso8601String(),
    'facts': facts,
    'source_categories': sourceCategories.toList()..sort(),
    if (unavailableReason != null) 'unavailable_reason': unavailableReason,
  };
}

class AssistantConversationPlan {
  const AssistantConversationPlan({
    required this.language,
    required this.capabilityIds,
    required this.operationLevel,
    this.needsClarification = false,
    this.clarificationQuestion,
    this.scopeBasis = AssistantScopeBasis.unspecified,
    this.scopeEvidence,
  });

  final String language;
  final Set<String> capabilityIds;
  final AssistantOperationLevel operationLevel;
  final bool needsClarification;
  final String? clarificationQuestion;
  final AssistantScopeBasis scopeBasis;
  final String? scopeEvidence;
}

class AssistantConversationRequest {
  const AssistantConversationRequest({
    required this.question,
    required this.userId,
    required this.householdId,
    required this.uiLocale,
    required this.history,
  });

  final String question;
  final String userId;
  final String householdId;
  final String uiLocale;

  /// Only user-authored turns are sent back to the provider. Previous model
  /// output can contain facts whose authorization has since been revoked.
  final List<AssistantConversationMessage> history;
}

class AssistantConversationAnswer {
  const AssistantConversationAnswer({
    required this.text,
    required this.language,
    required this.status,
    required this.provider,
    required this.model,
    required this.capabilityIds,
    required this.sourceCategories,
    required this.operationLevel,
    required this.duration,
    this.navigations = const [],
    this.proposals = const [],
    this.fallbackUsed = false,
    this.promptTokens,
    this.completionTokens,
    this.totalTokens,
    this.estimatedCostMinor,
    this.failurePhase,
    this.failureCategory,
  });

  final String text;
  final String language;
  final AssistantConversationStatus status;
  final String provider;
  final String model;
  final Set<String> capabilityIds;
  final Set<String> sourceCategories;
  final AssistantOperationLevel operationLevel;
  final Duration duration;
  final List<AssistantNavigationLink> navigations;
  final List<AssistantProposal> proposals;
  final bool fallbackUsed;
  final int? promptTokens;
  final int? completionTokens;
  final int? totalTokens;
  final int? estimatedCostMinor;
  final AssistantFailurePhase? failurePhase;
  final AssistantProviderErrorCategory? failureCategory;
}

class AssistantNavigationLink {
  const AssistantNavigationLink({required this.target, required this.labelKey});

  final String target;
  final String labelKey;
}

abstract interface class ConversationalAIProvider {
  String get providerId;

  Future<AssistantConversationPlan> plan({
    required AssistantConversationRequest request,
    required List<AssistantCapabilityDescriptor> availableCapabilities,
  });

  Future<AssistantConversationAnswer> respond({
    required AssistantConversationRequest request,
    required AssistantConversationPlan plan,
    required List<AuthorizedCapabilityResult> authorizedResults,
  });
}

abstract interface class AssistantCapabilityExecutor {
  List<AssistantCapabilityDescriptor> get descriptors;

  Future<List<AuthorizedCapabilityResult>> execute(Set<String> capabilityIds);
}
