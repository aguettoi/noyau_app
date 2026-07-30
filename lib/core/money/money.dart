/// Exact monetary value stored in Moroccan centimes.
class Money implements Comparable<Money> {
  const Money.fromMinorUnits(this.minorUnits);

  factory Money.fromDirhams(num dirhams) =>
      Money.fromMinorUnits((dirhams * 100).round());

  final int minorUnits;

  double get dirhams => minorUnits / 100;

  Money operator +(Money other) =>
      Money.fromMinorUnits(minorUnits + other.minorUnits);

  Money operator -(Money other) =>
      Money.fromMinorUnits(minorUnits - other.minorUnits);

  @override
  int compareTo(Money other) => minorUnits.compareTo(other.minorUnits);

  @override
  bool operator ==(Object other) =>
      other is Money && other.minorUnits == minorUnits;

  @override
  int get hashCode => minorUnits.hashCode;
}
