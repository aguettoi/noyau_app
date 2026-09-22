import '../../../core/money/money.dart';

enum SavingsGoalType {
  car,
  travel,
  majorPurchase,
  homeDownPayment,
  emergencyFund,
  custom;

  String get databaseValue => switch (this) {
    SavingsGoalType.car => 'car',
    SavingsGoalType.travel => 'travel',
    SavingsGoalType.majorPurchase => 'major_purchase',
    SavingsGoalType.homeDownPayment => 'home_down_payment',
    SavingsGoalType.emergencyFund => 'emergency_fund',
    SavingsGoalType.custom => 'custom',
  };

  String get label => switch (this) {
    SavingsGoalType.car => 'Voiture',
    SavingsGoalType.travel => 'Voyage',
    SavingsGoalType.majorPurchase => 'Achat important',
    SavingsGoalType.homeDownPayment => 'Apport immobilier',
    SavingsGoalType.emergencyFund => 'Fonds d’urgence',
    SavingsGoalType.custom => 'Objectif libre',
  };

  static SavingsGoalType fromDatabase(Object? value) => switch (value) {
    'car' => SavingsGoalType.car,
    'travel' => SavingsGoalType.travel,
    'major_purchase' => SavingsGoalType.majorPurchase,
    'home_down_payment' => SavingsGoalType.homeDownPayment,
    'emergency_fund' => SavingsGoalType.emergencyFund,
    _ => SavingsGoalType.custom,
  };
}

enum SavingsGoalStatus { planned, active, paused, completed, cancelled }

extension SavingsGoalStatusLabel on SavingsGoalStatus {
  String get databaseValue => name;

  String get label => switch (this) {
    SavingsGoalStatus.planned => 'Prévu',
    SavingsGoalStatus.active => 'Actif',
    SavingsGoalStatus.paused => 'En pause',
    SavingsGoalStatus.completed => 'Clôturé',
    SavingsGoalStatus.cancelled => 'Annulé',
  };

  bool get isClosed =>
      this == SavingsGoalStatus.completed ||
      this == SavingsGoalStatus.cancelled;

  static SavingsGoalStatus fromDatabase(Object? value) => switch (value) {
    'active' => SavingsGoalStatus.active,
    'paused' => SavingsGoalStatus.paused,
    'completed' => SavingsGoalStatus.completed,
    'cancelled' => SavingsGoalStatus.cancelled,
    _ => SavingsGoalStatus.planned,
  };
}

class SavingsGoal {
  const SavingsGoal({
    required this.id,
    required this.householdId,
    required this.name,
    required this.type,
    required this.targetAmount,
    required this.priority,
    required this.status,
    required this.fundingEnvelopeId,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.targetDate,
    this.monthlyTarget,
    this.notes,
    this.updatedBy,
    this.closedAt,
    this.closedBy,
    this.closureReason,
  });

  final String id;
  final String householdId;
  final String name;
  final SavingsGoalType type;
  final Money targetAmount;
  final DateTime? targetDate;
  final int priority;
  final SavingsGoalStatus status;
  final String fundingEnvelopeId;
  final Money? monthlyTarget;
  final String? notes;
  final String createdBy;
  final DateTime createdAt;
  final String? updatedBy;
  final DateTime updatedAt;
  final DateTime? closedAt;
  final String? closedBy;
  final String? closureReason;
}

class SavingsGoalProgress {
  const SavingsGoalProgress({
    required this.goal,
    required this.envelopeName,
    required this.accumulated,
  });

  final SavingsGoal goal;
  final String envelopeName;
  final Money accumulated;

  Money get remaining => Money.fromMinorUnits(
    (goal.targetAmount.minorUnits - accumulated.minorUnits).clamp(
      0,
      goal.targetAmount.minorUnits,
    ),
  );

  double get progressRatio {
    if (goal.targetAmount.minorUnits == 0) return 0;
    return accumulated.minorUnits / goal.targetAmount.minorUnits;
  }

  double get progressForIndicator => progressRatio.clamp(0, 1);

  bool get isFinancialTargetReached =>
      accumulated.minorUnits >= goal.targetAmount.minorUnits;

  int? get estimatedMonths {
    final monthly = goal.monthlyTarget;
    if (monthly == null ||
        monthly.minorUnits <= 0 ||
        remaining.minorUnits <= 0) {
      return remaining.minorUnits <= 0 ? 0 : null;
    }
    return (remaining.minorUnits / monthly.minorUnits).ceil();
  }

  DateTime? estimatedCompletionDate(DateTime from) {
    final months = estimatedMonths;
    if (months == null) return null;
    final monthIndex = from.month - 1 + months;
    final year = from.year + monthIndex ~/ 12;
    final month = monthIndex % 12 + 1;
    final lastDay = DateTime(year, month + 1, 0).day;
    return DateTime(year, month, from.day > lastDay ? lastDay : from.day);
  }

  Money? requiredMonthlyPace(DateTime from) {
    final targetDate = goal.targetDate;
    if (targetDate == null || remaining.minorUnits <= 0) return null;
    final months =
        (targetDate.year - from.year) * 12 + targetDate.month - from.month;
    if (months <= 0) return null;
    return Money.fromMinorUnits((remaining.minorUnits / months).ceil());
  }
}

class SavingsGoalHistoryItem {
  const SavingsGoalHistoryItem({
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

class SavingsGoalDraft {
  const SavingsGoalDraft({
    required this.name,
    required this.type,
    required this.targetAmount,
    required this.priority,
    required this.fundingEnvelopeId,
    this.targetDate,
    this.monthlyTarget,
    this.notes,
  });

  final String name;
  final SavingsGoalType type;
  final Money targetAmount;
  final DateTime? targetDate;
  final int priority;
  final String fundingEnvelopeId;
  final Money? monthlyTarget;
  final String? notes;

  String? validate() {
    if (name.trim().isEmpty || name.trim().length > 120) {
      return 'Le nom doit contenir entre 1 et 120 caractères.';
    }
    if (targetAmount.minorUnits <= 0) {
      return 'La cible financière doit être strictement positive.';
    }
    if (fundingEnvelopeId.isEmpty) {
      return 'Choisissez une enveloppe dédiée.';
    }
    if (monthlyTarget != null && monthlyTarget!.minorUnits < 0) {
      return 'La cible mensuelle ne peut pas être négative.';
    }
    return null;
  }
}
