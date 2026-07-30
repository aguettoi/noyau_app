import '../../../core/money/money.dart';

enum FinancialAccountType { bank, cash, savings, debt }

class FinancialAccount {
  FinancialAccount({
    required this.id,
    required this.name,
    required this.type,
    required this.openingBalance,
    this.holder,
    this.archivedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  final String id;
  final String name;
  final FinancialAccountType type;
  final Money openingBalance;
  final String? holder;
  final DateTime? archivedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isArchived => archivedAt != null;

  FinancialAccount copyWith({
    String? name,
    FinancialAccountType? type,
    String? holder,
    DateTime? archivedAt,
    bool clearArchivedAt = false,
  }) => FinancialAccount(
    id: id,
    name: name ?? this.name,
    type: type ?? this.type,
    openingBalance: openingBalance,
    holder: holder ?? this.holder,
    archivedAt: clearArchivedAt ? null : (archivedAt ?? this.archivedAt),
    createdAt: createdAt,
    updatedAt: DateTime.now(),
  );
}
