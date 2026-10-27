import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    ('Bienvenue', 'Choisissez uniquement les modules utiles aujourd’hui.'),
    (
      'Votre foyer',
      'Créez ou rejoignez le foyer avec les primitives Auth existantes.',
    ),
    ('Membres', 'Ajoutez un, deux ou plusieurs membres selon votre situation.'),
    (
      'Finances',
      'Comptes, enveloppes et budget peuvent être configurés maintenant ou plus tard.',
    ),
    (
      'Organisation',
      'Activez tâches, courses, calendrier et rappels à votre rythme.',
    ),
    (
      'Confidentialité',
      'Vérifiez qui peut voir chaque donnée sensible ou financière.',
    ),
    (
      'Terminé',
      'Vous pourrez reprendre ou ajuster chaque module depuis les paramètres.',
    ),
  ];
  OnboardingProgress? _progress;

  @override
  Widget build(BuildContext context) {
    final loaded = ref.watch(onboardingProgressProvider);
    final progress = _progress ?? loaded.valueOrNull;
    if (progress == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final index = progress.step.clamp(0, _steps.length - 1);
    final step = _steps[index];
    return Scaffold(
      appBar: AppBar(title: const Text('Configuration guidée')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: ListView(
              padding: AppSpacing.page,
              children: [
                Semantics(
                  label: 'Étape ${index + 1} sur ${_steps.length}',
                  child: LinearProgressIndicator(
                    value: (index + 1) / _steps.length,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  step.$1,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(step.$2),
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
                    index == _steps.length - 1 ? 'Terminer' : 'Continuer',
                  ),
                ),
                TextButton(
                  key: const Key('onboarding-skip'),
                  onPressed: () => _move(progress, index + 1, skipped: true),
                  child: const Text('Passer pour le moment'),
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
            title: Text(module.label),
            subtitle: Text(
              _label(
                progress.modules[module.id] ?? ModuleSetupState.notStarted,
              ),
            ),
            trailing: Wrap(
              children: [
                TextButton(
                  onPressed: () =>
                      onChanged(progress, module.id, ModuleSetupState.skipped),
                  child: const Text('Plus tard'),
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
                  child: const Text('Configurer'),
                ),
              ],
            ),
          ),
        ),
    ],
  );

  String _label(ModuleSetupState state) => switch (state) {
    ModuleSetupState.notStarted => 'Pas commencé',
    ModuleSetupState.inProgress => 'En cours',
    ModuleSetupState.configured => 'Configuré',
    ModuleSetupState.skipped => 'Passé pour le moment',
  };
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
