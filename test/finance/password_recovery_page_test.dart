import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/core/localization/app_locale.dart';
import 'package:noyau_app/features/finance/application/providers/supabase_client_provider.dart';
import 'package:noyau_app/features/finance/presentation/password_recovery_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'password recovery validates locally and rejects expired session',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appLocaleProvider.overrideWith(
              (ref) => AppLocaleController(
                environmentLocales: () => const [Locale('fr')],
              ),
            ),
            optionalSupabaseClientProvider.overrideWithValue(null),
          ],
          child: const MaterialApp(
            locale: Locale('fr'),
            supportedLocales: [Locale('fr'), Locale('en'), Locale('ar')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: PasswordRecoveryPage(),
          ),
        ),
      );

      await tester.enterText(
        find.byKey(const Key('recovery-password')),
        'valid-password',
      );
      await tester.enterText(
        find.byKey(const Key('recovery-password-confirmation')),
        'valid-password',
      );
      await tester.tap(find.byKey(const Key('recovery-submit')));
      await tester.pump();

      expect(
        find.text('Ce lien a expiré ou a déjà été utilisé.'),
        findsOneWidget,
      );
    },
  );
}
