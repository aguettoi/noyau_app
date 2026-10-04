class HouseholdMember {
  const HouseholdMember({
    required this.id,
    required this.displayName,
    this.role = 'member',
  });

  final String id;
  final String displayName;
  final String role;
}
