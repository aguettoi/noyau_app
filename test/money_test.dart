import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/core/money/money.dart';

void main() {
  test('conserve les montants sans erreur d’arrondi flottant', () {
    final total = Money.fromDirhams(0.1) + Money.fromDirhams(0.2);

    expect(total, Money.fromDirhams(0.3));
    expect(total.minorUnits, 30);
  });
}
