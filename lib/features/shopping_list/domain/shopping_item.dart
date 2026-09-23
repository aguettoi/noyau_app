import '../../../core/money/money.dart';

enum ShoppingItemStatus { planned, purchased, cancelled, archived }

extension ShoppingItemStatusLabel on ShoppingItemStatus {
  String get databaseValue => name;

  String get label => switch (this) {
    ShoppingItemStatus.planned => 'Prévu',
    ShoppingItemStatus.purchased => 'Acheté',
    ShoppingItemStatus.cancelled => 'Annulé',
    ShoppingItemStatus.archived => 'Archivé',
  };

  static ShoppingItemStatus fromDatabase(Object? value) => switch (value) {
    'purchased' => ShoppingItemStatus.purchased,
    'cancelled' => ShoppingItemStatus.cancelled,
    'archived' => ShoppingItemStatus.archived,
    _ => ShoppingItemStatus.planned,
  };
}

class ShoppingItem {
  const ShoppingItem({
    required this.id,
    required this.householdId,
    required this.label,
    required this.status,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.estimatedAmount,
    this.notes,
    this.desiredDate,
    this.envelopeId,
    this.budgetGoalId,
    this.finalPriority,
    this.finalPrioritySetBy,
    this.finalPrioritySetAt,
    this.updatedBy,
    this.cancelledBy,
    this.cancelledAt,
    this.cancellationReason,
    this.archivedBy,
    this.archivedAt,
  });

  final String id;
  final String householdId;
  final String label;
  final Money? estimatedAmount;
  final String? notes;
  final DateTime? desiredDate;
  final ShoppingItemStatus status;
  final String? envelopeId;
  final String? budgetGoalId;
  final int? finalPriority;
  final String? finalPrioritySetBy;
  final DateTime? finalPrioritySetAt;
  final String createdBy;
  final DateTime createdAt;
  final String? updatedBy;
  final DateTime updatedAt;
  final String? cancelledBy;
  final DateTime? cancelledAt;
  final String? cancellationReason;
  final String? archivedBy;
  final DateTime? archivedAt;
}

class ShoppingMemberPriority {
  const ShoppingMemberPriority({
    required this.itemId,
    required this.memberUserId,
    required this.priority,
    required this.memberName,
  });

  final String itemId;
  final String memberUserId;
  final int priority;
  final String memberName;
}

class ShoppingItemHistoryEntry {
  const ShoppingItemHistoryEntry({
    required this.id,
    required this.action,
    required this.actorId,
    required this.actorName,
    required this.createdAt,
    this.reason,
  });

  final String id;
  final String action;
  final String actorId;
  final String actorName;
  final DateTime createdAt;
  final String? reason;
}

class ShoppingItemDraft {
  const ShoppingItemDraft({
    required this.label,
    this.estimatedAmount,
    this.notes,
    this.desiredDate,
    this.envelopeId,
    this.budgetGoalId,
    this.finalPriority,
  });

  final String label;
  final Money? estimatedAmount;
  final String? notes;
  final DateTime? desiredDate;
  final String? envelopeId;
  final String? budgetGoalId;
  final int? finalPriority;

  String? validate() {
    if (label.trim().isEmpty || label.trim().length > 160) {
      return 'Le libellé doit contenir entre 1 et 160 caractères.';
    }
    if (estimatedAmount != null && estimatedAmount!.minorUnits <= 0) {
      return 'Le montant estimé doit être strictement positif.';
    }
    if ((notes?.trim().length ?? 0) > 2000) {
      return 'Les notes ne peuvent pas dépasser 2 000 caractères.';
    }
    if (finalPriority != null && (finalPriority! < 0 || finalPriority! > 3)) {
      return 'La priorité finale doit être comprise entre 0 et 3.';
    }
    return null;
  }
}

class ShoppingItemView {
  const ShoppingItemView({
    required this.item,
    required this.memberPriorities,
    this.envelopeName,
    this.envelopeBalance,
    this.goalName,
    this.goalProgress,
  });

  final ShoppingItem item;
  final List<ShoppingMemberPriority> memberPriorities;
  final String? envelopeName;
  final Money? envelopeBalance;
  final String? goalName;
  final double? goalProgress;

  Money? get estimatedGap {
    if (item.estimatedAmount == null || envelopeBalance == null) return null;
    return Money.fromMinorUnits(
      (item.estimatedAmount!.minorUnits - envelopeBalance!.minorUnits).clamp(
        0,
        item.estimatedAmount!.minorUnits,
      ),
    );
  }
}
