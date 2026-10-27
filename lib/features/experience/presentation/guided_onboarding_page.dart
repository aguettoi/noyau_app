import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_locale.dart';
import '../../../core/theme/app_design_system.dart';
import '../application/experience_provider.dart';

class GuidedOnboardingPage extends ConsumerStatefulWidget {
  const GuidedOnboardingPage({super.key, this.modules = const []});

  final List<OnboardingModuleLink> modules;
  @override
  ConsumerState<GuidedOnboardingPage> createState() =>
      _GuidedOnboardingPageState();
}

class _GuidedOnboardingPageState extends ConsumerState<GuidedOnboardingPage> {
  static const _steps = [
    ('onboarding.welcome.title', 'onboarding.welcome.description'),
    ('onboarding.household.title', 'onboarding.household.description'),
    ('onboarding.members.title', 'onboarding.members.description'),
    ('onboarding.finance.title', 'onboarding.finance.description'),
    ('onboarding.organization.title', 'onboarding.organization.description'),
    ('onboarding.privacy.title', 'onboarding.privacy.description'),
    ('onboarding.done.title', 'onboarding.done.description'),
  ];
  OnboardingProgress? _progress;

  @override
  Widget build(BuildContext context) {
    final words = AppWords.of(context);
    final loaded = ref.watch(onboardingProgressProvider);
    final progress = _progress ?? loaded.valueOrNull;
    if (progress == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final index = progress.step.clamp(0, _steps.length - 1);
    final step = _steps[index];
    return Scaffold(
      appBar: AppBar(title: Text(words.text('onboarding.title'))),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: ListView(
              padding: AppSpacing.page,
              children: [
                Semantics(
                  label: words.format('onboarding.step', {
                    'current': index + 1,
                    'total': _steps.length,
                  }),
                  child: LinearProgressIndicator(
                    value: (index + 1) / _steps.length,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  words.text(step.$1),
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(words.text(step.$2)),
                const SizedBox(height: AppSpacing.lg),
                if (index >= 1 && index <= 5)
                  _ModuleChoices(
                    progress: progress,
                    modules: widget.modules,
                    onChanged: _updateModule,
                  ),
                const SizedBox(height: AppSpacing.xl),
                FilledButton(
                  key: const Key('onboarding-continue'),
                  onPressed: () => _move(progress, index + 1),
                  child: Text(
                    index == _steps.length - 1
                        ? words.text('common.finish')
                        : words.text('continue'),
                  ),
                ),
                TextButton(
                  key: const Key('onboarding-skip'),
                  onPressed: () => _move(progress, index + 1, skipped: true),
                  child: Text(words.text('skip')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _move(
    OnboardingProgress progress,
    int requested, {
    bool skipped = false,
  }) async {
    final completed = requested >= _steps.length;
    final next = progress.copyWith(
      step: completed ? _steps.length - 1 : requested,
      completed: completed,
    );
    await ref.read(experienceStoreProvider).saveProgress(next);
    ref.invalidate(onboardingProgressProvider);
    if (!mounted) return;
    if (completed) {
      Navigator.of(context).pop();
    } else {
      setState(() => _progress = next);
    }
  }

  Future<void> _updateModule(
    OnboardingProgress progress,
    String module,
    ModuleSetupState state,
  ) async {
    final next = progress.copyWith(
      modules: {...progress.modules, module: state},
    );
    await ref.read(experienceStoreProvider).saveProgress(next);
    setState(() => _progress = next);
  }
}

class _ModuleChoices extends StatelessWidget {
  const _ModuleChoices({
    required this.progress,
    required this.modules,
    required this.onChanged,
  });
  final OnboardingProgress progress;
  final List<OnboardingModuleLink> modules;
  final Future<void> Function(OnboardingProgress, String, ModuleSetupState)
  onChanged;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final module in modules)
        Card(
          child: ListTile(
            key: Key('onboarding-module-${module.id}'),
            leading: Icon(module.icon),
            title: Text(_moduleLabel(context, module.id)),
            subtitle: Text(
              _label(
                context,
                progress.modules[module.id] ?? ModuleSetupState.notStarted,
              ),
            ),
            trailing: Wrap(
              children: [
                TextButton(
                  onPressed: () =>
                      onChanged(progress, module.id, ModuleSetupState.skipped),
                  child: Text(AppWords.of(context).text('common.later')),
                ),
                FilledButton.tonal(
                  onPressed: () async {
                    await onChanged(
                      progress,
                      module.id,
                      ModuleSetupState.inProgress,
                    );
                    await module.open();
                    final configured = await module.isConfigured();
                    await onChanged(
                      progress,
                      module.id,
                      configured
                          ? ModuleSetupState.configured
                          : ModuleSetupState.inProgress,
                    );
                  },
                  child: Text(AppWords.of(context).text('common.configure')),
                ),
              ],
            ),
          ),
        ),
    ],
  );

  String _label(BuildContext context, ModuleSetupState state) =>
      switch (state) {
        ModuleSetupState.notStarted => AppWords.of(
          context,
        ).text('onboarding.not_started'),
        ModuleSetupState.inProgress => AppWords.of(
          context,
        ).text('onboarding.in_progress'),
        ModuleSetupState.configured => AppWords.of(
          context,
        ).text('onboarding.configured'),
        ModuleSetupState.skipped => AppWords.of(
          context,
        ).text('onboarding.skipped'),
      };

  String _moduleLabel(BuildContext context, String id) {
    final words = AppWords.of(context);
    final key = switch (id) {
      'household' => 'household.configure',
      'members' => 'nav.members',
      'accounts' => 'nav.accounts',
      'envelopes' => 'nav.envelopes',
      'objectives' => 'nav.goals',
      'organization' => 'onboarding.module.organization',
      'reminders' => 'onboarding.module.reminders',
      'privacy' => 'onboarding.module.privacy',
      _ => 'onboarding.module.other',
    };
    return words.text(key);
  }
}

class OnboardingModuleLink {
  const OnboardingModuleLink({
    required this.id,
    required this.label,
    required this.icon,
    required this.open,
    required this.isConfigured,
  });

  final String id;
  final String label;
  final IconData icon;
  final Future<void> Function() open;
  final Future<bool> Function() isConfigured;
}
