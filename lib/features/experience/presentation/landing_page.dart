import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/localization/app_locale.dart';
import '../../../core/localization/app_language_picker.dart';
import '../../../core/theme/app_design_system.dart';
import '../../finance/presentation/supabase_auth_page.dart';
import 'help_center_page.dart';

enum DistributionStatus { available, comingSoon }

class DistributionLink {
  const DistributionLink({required this.status, this.url});
  final DistributionStatus status;
  final String? url;
  bool get canOpen =>
      status == DistributionStatus.available && url != null && url!.isNotEmpty;
}

class PublicDistributionConfig {
  const PublicDistributionConfig();
  DistributionLink get windows {
    const url = String.fromEnvironment('WINDOWS_DOWNLOAD_URL');
    return DistributionLink(
      status: url.isEmpty
          ? DistributionStatus.comingSoon
          : DistributionStatus.available,
      url: url,
    );
  }

  DistributionLink get android {
    const url = String.fromEnvironment('ANDROID_DOWNLOAD_URL');
    return DistributionLink(
      status: url.isEmpty
          ? DistributionStatus.comingSoon
          : DistributionStatus.available,
      url: url,
    );
  }
}

class LandingPage extends ConsumerWidget {
  const LandingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(appLocaleProvider);
    final words = AppWords(language);
    const distribution = PublicDistributionConfig();
    return Scaffold(
      appBar: AppBar(
        title: Text(words.text('title')),
        actions: [
          const AppLanguagePicker(
            key: Key('public-language-picker'),
            compact: true,
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: AppSpacing.page,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: Column(
                children: [
                  const SizedBox(height: AppSpacing.xl),
                  Semantics(
                    header: true,
                    child: Text(
                      words.text('title'),
                      style: Theme.of(context).textTheme.displaySmall,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    words.text('tagline'),
                    style: Theme.of(context).textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    alignment: WrapAlignment.center,
                    children: [
                      FilledButton.icon(
                        key: const Key('landing-login'),
                        onPressed: () => _openAuth(context),
                        icon: const Icon(Icons.login),
                        label: Text(words.text('login')),
                      ),
                      OutlinedButton(
                        key: const Key('landing-signup'),
                        onPressed: () =>
                            _openAuth(context, createAccount: true),
                        child: Text(words.text('signup')),
                      ),
                      OutlinedButton.icon(
                        key: const Key('landing-invitation'),
                        onPressed: () =>
                            _openAuth(context, invitationIntent: true),
                        icon: const Icon(Icons.mail_outline),
                        label: Text(words.text('invitation')),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  _ModuleGrid(words: words),
                  const SizedBox(height: AppSpacing.xl),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    alignment: WrapAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const HelpCenterPage(),
                          ),
                        ),
                        icon: const Icon(Icons.help_outline),
                        label: Text(words.text('help')),
                      ),
                      _DistributionButton(
                        words: words,
                        platformKey: 'landing.platform.windows',
                        link: distribution.windows,
                      ),
                      _DistributionButton(
                        words: words,
                        platformKey: 'landing.platform.android',
                        link: distribution.android,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openAuth(
    BuildContext context, {
    bool createAccount = false,
    bool invitationIntent = false,
  }) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => SupabaseAuthPage(
        createAccount: createAccount,
        invitationIntent: invitationIntent,
      ),
    ),
  );
}

class _ModuleGrid extends StatelessWidget {
  const _ModuleGrid({required this.words});

  final AppWords words;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: AppSpacing.md,
    runSpacing: AppSpacing.md,
    children: [
      _ModuleCard(
        Icons.account_balance_wallet_outlined,
        words.text('landing.module.finance.title'),
        words.text('landing.module.finance.description'),
      ),
      _ModuleCard(
        Icons.home_outlined,
        words.text('landing.module.household.title'),
        words.text('landing.module.household.description'),
      ),
      _ModuleCard(
        Icons.flag_outlined,
        words.text('landing.module.projects.title'),
        words.text('landing.module.projects.description'),
      ),
      _ModuleCard(
        Icons.shield_outlined,
        words.text('landing.module.privacy.title'),
        words.text('landing.module.privacy.description'),
      ),
    ],
  );
}

class _ModuleCard extends StatelessWidget {
  const _ModuleCard(this.icon, this.title, this.description);
  final IconData icon;
  final String title;
  final String description;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 220,
    child: Card(
      child: Padding(
        padding: AppSpacing.dialog,
        child: Column(
          children: [
            Icon(icon),
            const SizedBox(height: 8),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            Text(description, textAlign: TextAlign.center),
          ],
        ),
      ),
    ),
  );
}

class _DistributionButton extends StatelessWidget {
  const _DistributionButton({
    required this.words,
    required this.platformKey,
    required this.link,
  });
  final AppWords words;
  final String platformKey;
  final DistributionLink link;
  @override
  Widget build(BuildContext context) {
    final platform = words.text(platformKey);
    return OutlinedButton.icon(
      onPressed: link.canOpen ? () => launchUrl(Uri.parse(link.url!)) : null,
      icon: const Icon(Icons.download_outlined),
      label: Text(
        link.canOpen
            ? platform
            : words.format('landing.coming_soon', {'platform': platform}),
      ),
    );
  }
}
