import 'package:flutter/foundation.dart';

/// Canonical, non-sensitive URLs exposed by FINANCIEL PILOTE.
abstract final class AppRoutes {
  static const home = '/';
  static const money = '/money';
  static const transactions = '/money/transactions';
  static const accounts = '/money/accounts';
  static const envelopes = '/money/envelopes';
  static const budget = '/money/budget';
  static const debts = '/money/debts';
  static const forecasts = '/money/forecasts';
  static const wealth = '/money/wealth';
  static const household = '/household';
  static const calendar = '/household/calendar';
  static const tasks = '/household/tasks';
  static const groceries = '/household/groceries';
  static const projects = '/projects';
  static const goals = '/projects/goals';
  static const priorities = '/projects/prios';
  static const simulations = '/projects/simulations';
  static const more = '/more';
  static const reports = '/more/reports';
  static const imports = '/more/imports';
  static const settings = '/more/settings';
  static const help = '/more/help';
  static const login = '/auth/login';
  static const signup = '/auth/signup';
  static const forgotPassword = '/auth/forgot-password';
  static const resetPassword = '/auth/reset-password';
  static const invitation = '/auth/invitation';
  static const callback = '/auth/callback';

  static const publicPaths = <String>{
    login,
    signup,
    forgotPassword,
    resetPassword,
    invitation,
    callback,
  };

  static const protectedPaths = <String>{
    home,
    money,
    transactions,
    accounts,
    envelopes,
    budget,
    debts,
    forecasts,
    wealth,
    household,
    calendar,
    tasks,
    groceries,
    projects,
    goals,
    priorities,
    simulations,
    more,
    reports,
    imports,
    settings,
    help,
  };

  static bool isKnown(String path) =>
      publicPaths.contains(path) || protectedPaths.contains(path);

  static String? authRedirect({required Uri location, required bool signedIn}) {
    final path = location.path;
    if (!isKnown(path)) return home;
    if (!signedIn && protectedPaths.contains(path) && path != home) {
      return loginFor(location.toString());
    }
    if (signedIn && publicPaths.contains(path) && path != resetPassword) {
      return safeReturnPath(location.queryParameters['returnTo']);
    }
    return null;
  }

  static bool isSafeReturnPath(String? value) {
    if (value == null || value.isEmpty || !value.startsWith('/')) return false;
    final uri = Uri.tryParse(value);
    return uri != null &&
        !uri.hasScheme &&
        uri.host.isEmpty &&
        protectedPaths.contains(uri.path) &&
        uri.queryParameters.keys.every((key) => key == 'tab');
  }

  static String loginFor(String returnPath) => Uri(
    path: login,
    queryParameters: returnPath == home ? null : {'returnTo': returnPath},
  ).toString();

  static String safeReturnPath(String? value) =>
      isSafeReturnPath(value) ? value! : home;

  static bool containsSensitiveParameters(Uri uri) {
    const forbidden = {
      'access_token',
      'refresh_token',
      'token',
      'password',
      'email',
      'code',
    };
    return uri.queryParameters.keys.any(
          (key) => forbidden.contains(key.toLowerCase()),
        ) ||
        uri.fragment.toLowerCase().contains('access_token=') ||
        uri.fragment.toLowerCase().contains('refresh_token=');
  }

  static String webAuthRedirect({
    required Uri currentBase,
    required String path,
    String configuredOrigin = '',
  }) {
    assert(publicPaths.contains(path));
    final origin = configuredOrigin.trim().isEmpty
        ? currentBase.origin
        : configuredOrigin.trim();
    final parsed = Uri.tryParse(origin);
    if (parsed == null ||
        !parsed.hasScheme ||
        (parsed.scheme != 'http' && parsed.scheme != 'https') ||
        parsed.host.isEmpty ||
        parsed.path != '' ||
        parsed.query.isNotEmpty ||
        parsed.fragment.isNotEmpty) {
      throw ArgumentError.value(configuredOrigin, 'configuredOrigin');
    }
    final loopback =
        parsed.host == 'localhost' ||
        parsed.host == '127.0.0.1' ||
        parsed.host == '::1';
    if (kReleaseMode && parsed.scheme != 'https' && !loopback) {
      throw StateError('A production Web Auth origin must use HTTPS.');
    }
    return parsed.replace(path: path).toString();
  }
}
