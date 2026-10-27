import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('A1 migrated surfaces reject new visible hardcoded strings', () {
    const files = [
      'lib/app/noyau_app.dart',
      'lib/core/localization/app_language_picker.dart',
      'lib/features/experience/presentation/guided_onboarding_page.dart',
      'lib/features/experience/presentation/landing_page.dart',
      'lib/features/experience/presentation/quick_actions_dialog.dart',
      'lib/features/finance/presentation/household_onboarding_page.dart',
      'lib/features/finance/presentation/supabase_auth_page.dart',
    ];
    final visibleLiteralPatterns = <RegExp>[
      RegExp(r'''\bText\s*\(\s*['"]''', multiLine: true),
      RegExp(
        r'''\b(?:label|tooltip|hintText|helperText|semanticLabel|message)\s*:\s*['"]''',
        multiLine: true,
      ),
    ];
    final violations = <String>[];
    for (final path in files) {
      final source = File(path).readAsStringSync();
      for (final pattern in visibleLiteralPatterns) {
        for (final match in pattern.allMatches(source)) {
          final line =
              '\n'.allMatches(source.substring(0, match.start)).length + 1;
          violations.add('$path:$line ${match.group(0)}');
        }
      }
    }
    expect(
      violations,
      isEmpty,
      reason: 'Use AppWords for visible strings:\n${violations.join('\n')}',
    );
  });
}
