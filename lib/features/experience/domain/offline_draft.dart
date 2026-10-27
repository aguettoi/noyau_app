enum OfflineDraftState {
  localDraft,
  pending,
  syncing,
  synced,
  conflict,
  rejected,
  actionRequired,
}

/// A local draft is never a financial posting. Submission must be delegated to
/// the canonical server action identified by [actionKind].
class OfflineDraft {
  const OfflineDraft({
    required this.idempotencyKey,
    required this.actionKind,
    required this.updatedAt,
    required this.state,
    this.householdId,
    this.memberId,
    this.payload = const {},
  });

  final String idempotencyKey;
  final String actionKind;
  final DateTime updatedAt;
  final OfflineDraftState state;
  final String? householdId;
  final String? memberId;
  final Map<String, Object?> payload;

  bool get mayCreateFinancialData => false;

  OfflineDraft copyWith({OfflineDraftState? state}) => OfflineDraft(
    idempotencyKey: idempotencyKey,
    actionKind: actionKind,
    updatedAt: updatedAt,
    state: state ?? this.state,
    householdId: householdId,
    memberId: memberId,
    payload: payload,
  );

  Map<String, Object?> toJson() => {
    'idempotency_key': idempotencyKey,
    'action_kind': actionKind,
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'state': state.name,
    'household_id': householdId,
    'member_id': memberId,
    'payload': payload,
  };

  factory OfflineDraft.fromJson(Map<String, Object?> json) => OfflineDraft(
    idempotencyKey: json['idempotency_key']! as String,
    actionKind: json['action_kind']! as String,
    updatedAt: DateTime.parse(json['updated_at']! as String),
    state: OfflineDraftState.values.byName(json['state']! as String),
    householdId: json['household_id'] as String?,
    memberId: json['member_id'] as String?,
    payload: Map<String, Object?>.from(json['payload']! as Map),
  );
}

enum OfflineCapability { cachedRead, localDraft, serverRequired }

OfflineCapability classifyOfflineAction(String actionKind) {
  if (const {'task', 'grocery_item', 'onboarding_note'}.contains(actionKind)) {
    return OfflineCapability.localDraft;
  }
  if (const {'help', 'dashboard_snapshot', 'calendar'}.contains(actionKind)) {
    return OfflineCapability.cachedRead;
  }
  return OfflineCapability.serverRequired;
}
