import '../../../core/money/money.dart';
import 'account_ownership.dart';

enum FinancialAccountType { bank, cash, savings, debt }

class FinancialAccount {
  FinancialAccount({
    required this.id,
    required this.name,
    required this.type,
    required this.openingBalance,
    this.canReadBalance = true,
    this.visibility = 'visible',
    this.holder,
    this.ownershipType = AccountOwnershipType.household,
    this.holders = const [],
    this.isSystem = false,
    this.archivedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  final String id;
  final String name;
  final FinancialAccountType type;

  /// Null only when the server does not authorize this viewer to read it.
  final Money? openingBalance;
  final bool canReadBalance;
  final String visibility;
  final String? holder;
  final AccountOwnershipType ownershipType;
  final List<AccountHolder> holders;
  final bool isSystem;
  final DateTime? archivedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isArchived => archivedAt != null;

  FinancialAccount copyWith({
    String? name,
    FinancialAccountType? type,
    String? holder,
    AccountOwnershipType? ownershipType,
    List<AccountHolder>? holders,
    bool? isSystem,
    DateTime? archivedAt,
    bool clearArchivedAt = false,
  }) => FinancialAccount(
    id: id,
    name: name ?? this.name,
    type: type ?? this.type,
    openingBalance: openingBalance,
    canReadBalance: canReadBalance,
    visibility: visibility,
    holder: holder ?? this.holder,
    ownershipType: ownershipType ?? this.ownershipType,
    holders: holders ?? this.holders,
    isSystem: isSystem ?? this.isSystem,
    archivedAt: clearArchivedAt ? null : (archivedAt ?? this.archivedAt),
    createdAt: createdAt,
    updatedAt: DateTime.now(),
  );
}
