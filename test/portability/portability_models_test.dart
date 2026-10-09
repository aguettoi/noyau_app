import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/features/portability/domain/portability_models.dart';

void main() {
  test('export filenames are portable and remove special characters', () {
    expect(
      safeExportName('Foyer Ibrahim / Nora : 2026'),
      'Foyer_Ibrahim_Nora_2026',
    );
    expect(safeExportName('.._export.xlsx'), '.._export.xlsx');
  });
}
