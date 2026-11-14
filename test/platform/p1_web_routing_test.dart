import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:noyau_app/app/app_routes.dart';
import 'package:noyau_app/core/platform/platform_link_contract.dart';

void main() {
  group('P1-B canonical Web routes', () {
    test('router consumes the browser initial location', () {
      final source = File('lib/app/noyau_app.dart').readAsStringSync();
      expect(source, contains('MaterialApp.router('));
      expect(
        source,
        contains('initialLocation: _initialLocationFor(widget.initialLink)'),
      );
      expect(
        source,
        contains(
          'overridePlatformDefaultLocation: !kIsWeb && widget.initialLink != null',
        ),
      );
      expect(
        source,
        contains('GoRouter.optionURLReflectsImperativeAPIs = true'),
      );
      expect(source, contains('_openCanonicalRoute(AppRoutes.transactions)'));
      expect(source, contains('_openCanonicalRoute(AppRoutes.imports)'));
      expect(source, contains('if (current != route) context.push(route)'));
    });

    test('canonical routes build only their active surface', () {
      final source = File('lib/app/noyau_app.dart').readAsStringSync();
      for (final route in <String>[
        'AppRoutes.home',
        'AppRoutes.accounts',
        'AppRoutes.money',
        'AppRoutes.envelopes',
        'AppRoutes.goals',
        'AppRoutes.priorities',
        'AppRoutes.imports',
        'AppRoutes.household',
        'AppRoutes.projects',
        'AppRoutes.more',
      ]) {
        expect(source, contains('$route =>'));
      }
      expect(
        source,
        contains('final routedPage = _pageForPath(widget.destinationPath);'),
      );
    });

    test(
      'Web and desktop focus changes do not trigger a global data reload',
      () {
        final source = File('lib/app/noyau_app.dart').readAsStringSync();
        expect(source, contains('final refreshAfterResume ='));
        expect(source, contains('!kIsWeb &&'));
        expect(
          source,
          contains('defaultTargetPlatform == TargetPlatform.android'),
        );
        expect(source, contains('defaultTargetPlatform == TargetPlatform.iOS'));
        expect(
          source,
          contains(
            'if (refreshAfterResume && state == AppLifecycleState.resumed)',
          ),
        );
      },
    );

    testWidgets(
      'money hub-and-spoke history restores every real UI visit exactly',
      (tester) async {
        final previousReflection = GoRouter.optionURLReflectsImperativeAPIs;
        GoRouter.optionURLReflectsImperativeAPIs = true;
        addTearDown(() {
          GoRouter.optionURLReflectsImperativeAPIs = previousReflection;
        });
        const visits = <String>[
          AppRoutes.money,
          AppRoutes.accounts,
          AppRoutes.money,
          AppRoutes.envelopes,
          AppRoutes.money,
          AppRoutes.budget,
        ];
        final router = GoRouter(
          initialLocation: visits.first,
          overridePlatformDefaultLocation: true,
          routes: [
            for (final path in <String>{
              AppRoutes.money,
              AppRoutes.accounts,
              AppRoutes.envelopes,
              AppRoutes.budget,
            })
              GoRoute(path: path, builder: (_, state) => Text(state.uri.path)),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(MaterialApp.router(routerConfig: router));

        String visiblePath() => router.routeInformationParser
            .restoreRouteInformation(
              router.routerDelegate.currentConfiguration,
            )!
            .uri
            .path;

        final configurations = [router.routerDelegate.currentConfiguration];
        for (final path in visits.skip(1)) {
          router.push<void>(path);
          await tester.pump();
          expect(visiblePath(), path);
          configurations.add(router.routerDelegate.currentConfiguration);
        }
        for (final expected in visits.reversed.skip(1)) {
          router.pop();
          await tester.pumpAndSettle();
          expect(visiblePath(), expected);
        }
        for (var index = 1; index < configurations.length; index += 1) {
          router.restore(configurations[index]);
          await tester.pumpAndSettle();
          expect(visiblePath(), visits[index]);
        }
      },
    );

    testWidgets('universe history remains coherent in both directions', (
      tester,
    ) async {
      final previousReflection = GoRouter.optionURLReflectsImperativeAPIs;
      GoRouter.optionURLReflectsImperativeAPIs = true;
      addTearDown(() {
        GoRouter.optionURLReflectsImperativeAPIs = previousReflection;
      });
      const visits = <String>[
        AppRoutes.home,
        AppRoutes.money,
        AppRoutes.household,
        AppRoutes.projects,
        AppRoutes.more,
      ];
      final router = GoRouter(
        initialLocation: visits.first,
        overridePlatformDefaultLocation: true,
        routes: [
          for (final path in visits)
            GoRoute(path: path, builder: (_, state) => Text(state.uri.path)),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));

      String visiblePath() => router.routeInformationParser
          .restoreRouteInformation(router.routerDelegate.currentConfiguration)!
          .uri
          .path;

      final configurations = [router.routerDelegate.currentConfiguration];
      for (final path in visits.skip(1)) {
        router.push<void>(path);
        await tester.pump();
        expect(visiblePath(), path);
        configurations.add(router.routerDelegate.currentConfiguration);
      }
      for (final expected in visits.reversed.skip(1)) {
        router.pop();
        await tester.pumpAndSettle();
        expect(visiblePath(), expected);
      }
      for (var index = 1; index < configurations.length; index += 1) {
        router.restore(configurations[index]);
        await tester.pumpAndSettle();
        expect(visiblePath(), visits[index]);
      }
    });

    test('Dashboard, Ctrl+K and Universal Add use user-history routes', () {
      final source = File('lib/app/noyau_app.dart').readAsStringSync();
      expect(
        source,
        contains('run: () => _openCanonicalRoute(AppRoutes.accounts)'),
      );
      expect(
        source,
        contains(
          "'expense',\n          Icons.remove_circle_outline,\n"
          '          () => _openCanonicalRoute(AppRoutes.transactions)',
        ),
      );
      expect(
        source,
        contains('onOpenBudget: () => _openCanonicalRoute(AppRoutes.budget)'),
      );
      expect(source, contains('_router.go(AppRoutes.resetPassword)'));
      expect(source, contains('context.go(AppRoutes.household)'));
    });

    test('every public and protected route is explicit and unique', () {
      final all = {...AppRoutes.publicPaths, ...AppRoutes.protectedPaths};
      expect(
        all.length,
        AppRoutes.publicPaths.length + AppRoutes.protectedPaths.length,
      );
      expect(
        all,
        containsAll(<String>{
          '/',
          '/money/transactions',
          '/household/calendar',
          '/projects/prios',
          '/more/imports',
          '/auth/login',
          '/auth/reset-password',
        }),
      );
    });

    test('unauthenticated return paths are local, allow-listed and safe', () {
      expect(AppRoutes.safeReturnPath('/money/accounts'), '/money/accounts');
      expect(AppRoutes.safeReturnPath('https://evil.test/money'), '/');
      expect(AppRoutes.safeReturnPath('//evil.test'), '/');
      expect(AppRoutes.safeReturnPath('/unknown'), '/');
      expect(AppRoutes.safeReturnPath('/money?token=secret'), '/');
      expect(
        AppRoutes.loginFor('/money/accounts'),
        '/auth/login?returnTo=%2Fmoney%2Faccounts',
      );
    });

    test(
      'Auth redirect preserves intent and resumes only allow-listed paths',
      () {
        expect(
          AppRoutes.authRedirect(
            location: Uri.parse('/money/accounts'),
            signedIn: false,
          ),
          '/auth/login?returnTo=%2Fmoney%2Faccounts',
        );
        expect(
          AppRoutes.authRedirect(
            location: Uri.parse('/auth/login?returnTo=%2Fmoney%2Faccounts'),
            signedIn: true,
          ),
          '/money/accounts',
        );
        expect(
          AppRoutes.authRedirect(
            location: Uri.parse('/auth/reset-password'),
            signedIn: true,
          ),
          isNull,
        );
        expect(
          AppRoutes.authRedirect(
            location: Uri.parse('/unknown'),
            signedIn: true,
          ),
          '/',
        );
      },
    );

    test('canonical product URLs never contain sensitive parameters', () {
      for (final path in {
        ...AppRoutes.publicPaths,
        ...AppRoutes.protectedPaths,
      }) {
        expect(AppRoutes.containsSensitiveParameters(Uri.parse(path)), isFalse);
      }
      expect(
        AppRoutes.containsSensitiveParameters(
          Uri.parse('/auth/callback#access_token=secret'),
        ),
        isTrue,
      );
    });

    test('Web Auth redirect uses the current origin and dedicated route', () {
      expect(
        AppRoutes.webAuthRedirect(
          currentBase: Uri.parse('http://localhost:4173/money'),
          path: AppRoutes.resetPassword,
        ),
        'http://localhost:4173/auth/reset-password',
      );
      expect(
        () => AppRoutes.webAuthRedirect(
          currentBase: Uri.parse('http://localhost:4173'),
          path: AppRoutes.callback,
          configuredOrigin: 'https://app.example.test/extra',
        ),
        throwsArgumentError,
      );
    });

    test('strict Web origin parsing preserves native deep links', () {
      const allowed = {'http://localhost:4173'};
      expect(
        PlatformLinkContract.parse(
          Uri.parse('http://localhost:4173/auth/reset-password'),
          allowedWebOrigins: allowed,
        )?.kind,
        PlatformLinkKind.passwordReset,
      );
      expect(
        PlatformLinkContract.parse(
          Uri.parse('http://127.0.0.1:4173/auth/reset-password'),
          allowedWebOrigins: allowed,
        ),
        isNull,
      );
      expect(
        PlatformLinkContract.parse(
          Uri.parse('com.financielpilote.app://password-reset'),
        )?.kind,
        PlatformLinkKind.passwordReset,
      );
    });
  });
}
