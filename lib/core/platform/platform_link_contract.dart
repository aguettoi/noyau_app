enum PlatformLinkKind { authCallback, passwordReset, invitation, destination }

class PlatformLinkIntent {
  const PlatformLinkIntent(this.kind, {this.value});

  final PlatformLinkKind kind;
  final String? value;
}

abstract final class PlatformLinkContract {
  static const scheme = 'com.financielpilote.app';
  static final authCallback = Uri.parse('$scheme://auth-callback');
  static final passwordReset = Uri.parse('$scheme://password-reset');

  static const _allowedDestinations = <String>{
    'home',
    'money',
    'household',
    'projects',
    'more',
    'imports',
  };

  static PlatformLinkIntent? parse(Uri uri) {
    if (uri.scheme != scheme) return null;
    switch (uri.host) {
      case 'auth-callback':
        return const PlatformLinkIntent(PlatformLinkKind.authCallback);
      case 'password-reset':
        return const PlatformLinkIntent(PlatformLinkKind.passwordReset);
      case 'invite':
        final code = uri.queryParameters['code']?.trim();
        if (code == null || code.isEmpty || code.length > 128) return null;
        return PlatformLinkIntent(PlatformLinkKind.invitation, value: code);
      case 'open':
        final destination = uri.queryParameters['destination']?.trim();
        if (!_allowedDestinations.contains(destination)) return null;
        return PlatformLinkIntent(
          PlatformLinkKind.destination,
          value: destination,
        );
      default:
        return null;
    }
  }

  static bool isAuthRedirect(Uri uri) =>
      uri.scheme == scheme &&
      (uri.host == 'auth-callback' || uri.host == 'password-reset');
}
