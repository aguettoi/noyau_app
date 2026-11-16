import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/core/localization/accounts_locale.dart';
import 'package:noyau_app/core/localization/app_locale.dart';

void main() {
  String source(String path) => File(path).readAsStringSync();

  test('account privacy exposes exactly the three canonical modes', () {
    final page = source('lib/features/finance/presentation/accounts_page.dart');
    expect(page, contains("'visible'"));
    expect(page, contains("'balance_hidden'"));
    expect(page, contains("'private'"));
    expect(page, isNot(contains('limited_sharing')));
    expect(page, isNot(contains('partage limité')));
  });

  test('client mutations use only the audited canonical RPCs', () {
    final provider = source(
      'lib/features/finance/application/providers/account_privacy_provider.dart',
    );
    expect(provider, contains("'request_account_privacy_change'"));
    expect(provider, contains("'decide_account_privacy_change'"));
    expect(provider, contains("'cancel_account_privacy_change'"));
    expect(provider, isNot(contains(".from('account_privacy_settings')")));
    expect(provider, isNot(contains(".insert(")));
    expect(provider, isNot(contains(".update(")));
    expect(provider, isNot(contains(".delete(")));
  });

  test('privacy dialog starts from the refreshed effective mode', () {
    final page = source('lib/features/finance/presentation/accounts_page.dart');
    expect(page, contains('_request(account.visibility)'));
    expect(
      page,
      isNot(
        contains(
          '_accountPrivacyDialog(\n      context,\n      widget.account.visibility',
        ),
      ),
    );
  });

  test(
    'account detail derives mode and balance from live secure projections',
    () {
      final page = source(
        'lib/features/finance/presentation/accounts_page.dart',
      );
      final detail = page.substring(
        page.indexOf('class _AccountDetailPage'),
        page.indexOf('class _AccountReconciliationCard'),
      );
      expect(page, contains('_AccountDetailPage(accountId: account.id)'));
      expect(detail, contains('ref.watch(remoteAccountsProvider)'));
      expect(detail, contains('ref.watch(remoteAccountBalancesProvider)'));
      expect(detail, contains('accountsAsync.isRefreshing'));
      expect(detail, contains('balancesAsync.isRefreshing'));
      expect(detail, isNot(contains('final Money? balance;')));
      expect(
        page,
        isNot(
          contains('_AccountDetailPage(account: account, balance: balance)'),
        ),
      );
    },
  );

  test('privacy UI strings are complete in all four languages', () {
    const keys = <String>{
      'accounts.privacy.title',
      'accounts.privacy.current',
      'accounts.privacy.mode.visible',
      'accounts.privacy.mode.balance_hidden',
      'accounts.privacy.mode.private',
      'accounts.privacy.description.visible',
      'accounts.privacy.description.balance_hidden',
      'accounts.privacy.description.private',
      'accounts.privacy.manage',
      'accounts.privacy.pending',
      'accounts.privacy.approve',
      'accounts.privacy.reject',
      'accounts.privacy.cancel_request',
      'accounts.privacy.submit',
      'accounts.privacy.success_requested',
      'accounts.privacy.error',
    };
    for (final language in AppLanguage.values) {
      final catalogue = AccountsWords.keysFor(language);
      expect(catalogue, containsAll(keys), reason: language.name);
      for (final key in keys) {
        expect(
          AccountsWords.hasOwnTranslation(language, key),
          isTrue,
          reason: '${language.name}: $key',
        );
      }
    }
  });

  test(
    'Realtime invalidates both privacy workflow and account projections',
    () {
      final realtime = source(
        'lib/features/portability/application/household_realtime_provider.dart',
      );
      expect(realtime, contains("'account_privacy_settings'"));
      expect(realtime, contains("'account_privacy_requests'"));
      expect(realtime, contains('accountPrivacyRequestsProvider'));
      expect(realtime, contains('remoteAccountsProvider'));
      final requestCase = realtime.substring(
        realtime.indexOf("case 'account_privacy_requests':"),
        realtime.indexOf("case 'envelopes':"),
      );
      expect(requestCase, contains('remoteAccountsProvider'));
      expect(requestCase, contains('remoteAccountBalancesProvider'));
    },
  );
}
