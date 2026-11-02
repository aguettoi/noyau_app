enum AssistantUseCase {
  budget,
  monthlySummary,
  anomalies,
  priorities,
  organization,
  shopping,
  wealth,
  productHelp,
}

enum AssistantStatementKind { fact, rule, suggestion, uncertainty }

enum AssistantActionState {
  proposed,
  confirmed,
  rejected,
  expired,
  executed,
  failed,
}

enum AssistantRisk { low, moderate, high }

class AuthorizedAssistantContext {
  const AuthorizedAssistantContext({
    required this.userId,
    required this.householdId,
    required this.useCase,
    required this.generatedAt,
    this.visibleFacts = const {},
    this.flags = const {},
    this.sourceCategories = const {},
  });

  final String userId;
  final String householdId;
  final AssistantUseCase useCase;
  final DateTime generatedAt;
  final Map<String, num> visibleFacts;
  final Map<String, bool> flags;
  final Set<String> sourceCategories;

  /// Deliberately excludes raw rows, account identifiers, member names,
  /// free-text notes, cycle data and hidden balances.
  bool get containsRawPrivateData => false;
}

class AssistantStatement {
  const AssistantStatement(
    this.kind,
    this.messageKey, {
    this.arguments = const {},
  });
  final AssistantStatementKind kind;
  final String messageKey;
  final Map<String, Object> arguments;
}

class AssistantProposal {
  const AssistantProposal({
    required this.id,
    required this.type,
    required this.objectiveKey,
    required this.justificationKey,
    required this.risk,
    required this.createdAt,
    required this.expiresAt,
    this.parameters = const {},
    this.sourceCategories = const {},
    this.state = AssistantActionState.proposed,
  });

  final String id;
  final String type;
  final String objectiveKey;
  final String justificationKey;
  final AssistantRisk risk;
  final DateTime createdAt;
  final DateTime expiresAt;
  final Map<String, Object?> parameters;
  final Set<String> sourceCategories;
  final AssistantActionState state;

  AssistantProposal copyWith({AssistantActionState? state}) =>
      AssistantProposal(
        id: id,
        type: type,
        objectiveKey: objectiveKey,
        justificationKey: justificationKey,
        risk: risk,
        createdAt: createdAt,
        expiresAt: expiresAt,
        parameters: parameters,
        sourceCategories: sourceCategories,
        state: state ?? this.state,
      );
}

class AssistantResponse {
  const AssistantResponse({
    required this.statements,
    this.proposals = const [],
  });
  final List<AssistantStatement> statements;
  final List<AssistantProposal> proposals;
}

abstract interface class AssistantContextBuilder {
  Future<AuthorizedAssistantContext> build(AssistantUseCase useCase);
}

abstract interface class AssistantProvider {
  String get mode;
  Future<AssistantResponse> answer(AuthorizedAssistantContext context);
}

abstract interface class AssistantActionExecutor {
  Future<void> revalidate(AssistantProposal proposal);
  Future<void> execute(AssistantProposal proposal);
}

class AssistantAuditEvent {
  const AssistantAuditEvent({
    required this.userId,
    required this.householdId,
    required this.useCase,
    required this.timestamp,
    required this.mode,
    required this.sourceCategories,
    this.proposalType,
    this.actionState,
  });
  final String userId;
  final String householdId;
  final AssistantUseCase useCase;
  final DateTime timestamp;
  final String mode;
  final Set<String> sourceCategories;
  final String? proposalType;
  final AssistantActionState? actionState;
}
