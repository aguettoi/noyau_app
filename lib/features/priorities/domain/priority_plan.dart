import '../../../core/money/money.dart';

enum PriorityPlanStatus { planned, active, paused, archived }

extension PriorityPlanStatusLabel on PriorityPlanStatus {
  String get databaseValue => name;

  String get label => switch (this) {
    PriorityPlanStatus.planned => 'Prévu',
    PriorityPlanStatus.active => 'Actif',
    PriorityPlanStatus.paused => 'En pause',
    PriorityPlanStatus.archived => 'Archivé',
  };

  bool get isEditable => this != PriorityPlanStatus.archived;

  static PriorityPlanStatus fromDatabase(Object? value) => switch (value) {
    'active' => PriorityPlanStatus.active,
    'paused' => PriorityPlanStatus.paused,
    'archived' => PriorityPlanStatus.archived,
    _ => PriorityPlanStatus.planned,
  };
}

enum PrioritySourceType { shoppingItem, budgetGoal }

extension PrioritySourceTypeLabel on PrioritySourceType {
  String get label => switch (this) {
    PrioritySourceType.shoppingItem => 'Achat',
    PrioritySourceType.budgetGoal => 'Objectif',
  };
}

class PriorityPlan {
  const PriorityPlan({
    required this.id,
    required this.householdId,
    required this.name,
    required this.status,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.monthlyCapacity,
    this.notes,
    this.updatedBy,
  });

  final String id;
  final String householdId;
  final String name;
  final PriorityPlanStatus status;
  final Money? monthlyCapacity;
  final String? notes;
  final String createdBy;
  final DateTime createdAt;
  final String? updatedBy;
  final DateTime updatedAt;
}

class PriorityPlanItem {
  const PriorityPlanItem({
    required this.id,
    required this.planId,
    required this.householdId,
    required this.rank,
    required this.sourceType,
    required this.sourceId,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.updatedBy,
  });

  final String id;
  final String planId;
  final String householdId;
  final int rank;
  final PrioritySourceType sourceType;
  final String sourceId;
  final String createdBy;
  final DateTime createdAt;
  final String? updatedBy;
  final DateTime updatedAt;
}

class PrioritySourceSnapshot {
  const PrioritySourceSnapshot({
    required this.type,
    required this.id,
    required this.label,
    required this.status,
    required this.estimatedNeed,
    this.date,
    this.progress,
    this.goalId,
  });

  final PrioritySourceType type;
  final String id;
  final String label;
  final String status;
  final Money? estimatedNeed;
  final DateTime? date;
  final double? progress;

  /// A shopping item linked to a goal represents that same project.
  final String? goalId;
}

class PriorityPlanItemView {
  const PriorityPlanItemView({required this.item, required this.source});

  final PriorityPlanItem item;
  final PrioritySourceSnapshot source;
}

class PriorityPlanView {
  const PriorityPlanView({required this.plan, required this.items});

  final PriorityPlan plan;
  final List<PriorityPlanItemView> items;
}

class PriorityPlanDraft {
  const PriorityPlanDraft({
    required this.name,
    this.monthlyCapacity,
    this.notes,
  });

  final String name;
  final Money? monthlyCapacity;
  final String? notes;

  String? validate() {
    if (name.trim().isEmpty || name.trim().length > 120) {
      return 'Le nom du plan doit contenir entre 1 et 120 caractères.';
    }
    if (monthlyCapacity != null && monthlyCapacity!.minorUnits <= 0) {
      return 'La capacité mensuelle doit être strictement positive.';
    }
    if ((notes?.trim().length ?? 0) > 2000) {
      return 'Les notes ne peuvent pas dépasser 2 000 caractères.';
    }
    return null;
  }
}

class PriorityProjectionEntry {
  const PriorityProjectionEntry({
    required this.item,
    required this.estimatedNeed,
    required this.estimatedMonths,
    required this.estimatedCompletionDate,
  });

  final PriorityPlanItemView item;
  final Money? estimatedNeed;
  final int? estimatedMonths;
  final DateTime? estimatedCompletionDate;
}
