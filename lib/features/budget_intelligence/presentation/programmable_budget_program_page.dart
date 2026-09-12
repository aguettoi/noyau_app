import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_design_system.dart';
import '../../envelopes/application/providers/remote_envelopes_provider.dart';
import '../../finance/application/providers/remote_household_members_provider.dart';
import '../../finance/domain/household_member.dart';
import '../application/providers/remote_budget_provider.dart';
import '../application/programmable_budget_engine.dart';
import '../domain/budget_intelligence.dart';
import '../infrastructure/budget_supabase_repository.dart';

/// Editor for the reusable program only.  Monthly overrides stay in the
/// preparation flow, so historical runs cannot be rewritten from this page.
class ProgrammableBudgetProgramPage extends ConsumerWidget {
  const ProgrammableBudgetProgramPage({super.key, required this.scenario});
  final BudgetScenario scenario;

  Future<void> _createFirstVersion(WidgetRef ref) async {
    final repository = await ref.read(budgetSupabaseRepositoryProvider.future);
    final id = await repository.saveScenarioVersion(
      BudgetScenarioVersion(
        id: '',
        scenarioId: scenario.id,
        version: 1,
        createdAt: DateTime.now(),
        notes: 'Version initiale',
      ),
    );
    if (id == null) return;
    await repository.saveScenario(
      BudgetScenario(
        id: scenario.id,
        householdId: scenario.householdId,
        name: scenario.name,
        description: scenario.description,
        active: scenario.active,
        priority: scenario.priority,
        validFrom: scenario.validFrom,
        validTo: scenario.validTo,
        notes: scenario.notes,
        isDefault: scenario.isDefault,
        currentVersionId: id,
      ),
    );
    ref.invalidate(budgetScenarioVersionsProvider(scenario.id));
    ref.invalidate(remoteBudgetScenariosProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final versions = ref.watch(budgetScenarioVersionsProvider(scenario.id));
    return Scaffold(
      appBar: AppBar(title: Text('Programme — ${scenario.name}')),
      body: versions.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(
          child: Text('Le modèle programmable 080006 doit être installé.'),
        ),
        data: (items) {
          final version = items.firstOrNull;
          if (version == null) {
            return Center(
              child: FilledButton.icon(
                key: const Key('create-first-program-version'),
                onPressed: () => _createFirstVersion(ref),
                icon: const Icon(Icons.add),
                label: const Text('Créer la version 1'),
              ),
            );
          }
          return _ProgramVersionEditor(scenario: scenario, version: version);
        },
      ),
    );
  }
}

class _ProgramVersionEditor extends ConsumerStatefulWidget {
  const _ProgramVersionEditor({required this.scenario, required this.version});
  final BudgetScenario scenario;
  final BudgetScenarioVersion version;

  @override
  ConsumerState<_ProgramVersionEditor> createState() =>
      _ProgramVersionEditorState();
}

class _ProgramVersionEditorState extends ConsumerState<_ProgramVersionEditor> {
  bool _isReordering = false;
  bool _reorderScheduled = false;
  String? _reorderingError;
  final ScrollController _stepsScrollController = ScrollController();

  BudgetScenario get scenario => widget.scenario;
  BudgetScenarioVersion get version => widget.version;

  bool get _isReorderLocked => _isReordering || _reorderScheduled;

  @override
  void dispose() {
    _stepsScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sources = ref.watch(budgetScenarioSourcesProvider(version.id));
    final steps = ref.watch(budgetScenarioStepsProvider(version.id));
    final envelopes = ref.watch(remoteEnvelopeBalancesProvider);
    final members = ref.watch(remoteHouseholdMembersProvider);
    return LayoutBuilder(
      builder: (context, constraints) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppLayout.contentMaxWidth,
          ),
          child: ListView(
            padding: AppLayout.pagePaddingFor(constraints.maxWidth),
            children: [
              Card(
                child: Padding(
                  padding: AppSpacing.card,
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: AppSpacing.lg,
                    runSpacing: AppSpacing.sm,
                    children: [
                      SizedBox(
                        width: 620,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Programme d’allocation',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: AppSpacing.xxs),
                            Text(
                              'Version ${version.version} • Modèle réutilisable',
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            const Text(
                              'Les sources et étapes restent modifiables ici ; les mois enregistrés restent immuables.',
                            ),
                            // This slot deliberately keeps a stable height. A
                            // ReorderableListView can finish a drag while its
                            // ancestor LayoutBuilder is laying out; inserting
                            // or removing header content at that instant
                            // mutates the element tree during layout.
                            const SizedBox(height: AppSpacing.sm),
                            SizedBox(
                              key: const Key('budget-step-reordering-slot'),
                              height: 44,
                              child: _isReordering
                                  ? const _ReorderFeedback(
                                      key: Key(
                                        'budget-step-reordering-feedback',
                                      ),
                                      label: 'Réorganisation en cours…',
                                    )
                                  : _reorderingError != null
                                  ? _ReorderFeedback(
                                      key: const Key(
                                        'budget-step-reordering-error',
                                      ),
                                      label: _reorderingError!,
                                      error: true,
                                    )
                                  : null,
                            ),
                          ],
                        ),
                      ),
                      FilledButton.icon(
                        key: const Key('test-programmable-budget'),
                        onPressed:
                            sources.valueOrNull == null ||
                                steps.valueOrNull == null
                            ? null
                            : () => _testScenario(
                                context,
                                sources.valueOrNull!,
                                steps.valueOrNull!,
                                members.valueOrNull ?? const [],
                                {
                                  for (final envelope
                                      in envelopes.valueOrNull ?? const [])
                                    envelope.id: envelope.name,
                                },
                              ),
                        icon: const Icon(Icons.play_arrow_outlined),
                        label: const Text('Tester le scénario'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Card(
                child: Padding(
                  padding: AppSpacing.card,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Sources',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const Spacer(),
                          TextButton.icon(
                            key: const Key('add-budget-source'),
                            onPressed: () =>
                                _editSource(context, ref, version.id),
                            icon: const Icon(Icons.add),
                            label: const Text('Ajouter'),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      sources.when(
                        loading: () => const LinearProgressIndicator(),
                        error: (_, _) => const Text('Sources indisponibles.'),
                        data: (items) {
                          final visibleSources = items
                              .where(
                                (source) =>
                                    source.type !=
                                    BudgetSourceType.commonCapacity,
                              )
                              .toList(growable: false);
                          return Column(
                            children: [
                              if (visibleSources.isEmpty)
                                const Text('Aucune source définie.'),
                              ...visibleSources.map(
                                (source) => Padding(
                                  padding: const EdgeInsets.only(
                                    bottom: AppSpacing.xs,
                                  ),
                                  child: Material(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.surface,
                                    borderRadius: AppRadius.input,
                                    child: ListTile(
                                      dense: true,
                                      visualDensity: VisualDensity.compact,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: AppSpacing.sm,
                                          ),
                                      title: Text(source.name),
                                      subtitle: Text(
                                        '${_sourceLabel(source.type)} • ${_mad(source.expectedCents)}${source.active ? '' : ' • Inactive'}',
                                      ),
                                      trailing: Wrap(
                                        children: [
                                          IconButton(
                                            key: Key(
                                              'toggle-budget-source-${source.id}',
                                            ),
                                            tooltip: source.active
                                                ? 'Désactiver'
                                                : 'Activer',
                                            icon: Icon(
                                              source.active
                                                  ? Icons.toggle_on_outlined
                                                  : Icons.toggle_off_outlined,
                                            ),
                                            onPressed: () =>
                                                _toggleSource(ref, source),
                                          ),
                                          IconButton(
                                            key: Key(
                                              'edit-budget-source-${source.id}',
                                            ),
                                            tooltip: 'Modifier',
                                            icon: const Icon(
                                              Icons.edit_outlined,
                                            ),
                                            onPressed: () => _editSource(
                                              context,
                                              ref,
                                              version.id,
                                              source: source,
                                            ),
                                          ),
                                          IconButton(
                                            key: Key(
                                              'delete-budget-source-${source.id}',
                                            ),
                                            tooltip: 'Supprimer',
                                            icon: const Icon(
                                              Icons.delete_outline,
                                            ),
                                            onPressed: () => _deleteSource(
                                              context,
                                              ref,
                                              source,
                                              steps.valueOrNull ?? const [],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Card(
                child: Padding(
                  padding: AppSpacing.card,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.xs,
                        children: [
                          Text(
                            'Étapes de répartition',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          TextButton.icon(
                            key: const Key('add-budget-step'),
                            onPressed: sources.valueOrNull?.isEmpty ?? true
                                ? null
                                : () => _editStepsInBatch(
                                    context,
                                    ref,
                                    version.id,
                                    sources.valueOrNull ?? const [],
                                    envelopes.valueOrNull ?? const [],
                                    members.valueOrNull ?? const [],
                                    steps.valueOrNull ?? const [],
                                  ),
                            icon: const Icon(Icons.add),
                            label: const Text('Configurer plusieurs lignes'),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      steps.when(
                        loading: () => const LinearProgressIndicator(),
                        error: (_, _) => const Text('Étapes indisponibles.'),
                        data: (items) {
                          final sourceNames = {
                            for (final source
                                in sources.valueOrNull ??
                                    const <BudgetSource>[])
                              source.id: source.name,
                          };
                          final envelopeNames = {
                            for (final envelope
                                in envelopes.valueOrNull ?? const [])
                              envelope.id: envelope.name,
                          };
                          if (items.isEmpty) {
                            return const Text('Aucune étape définie.');
                          }
                          // The re-orderable list owns a bounded scrollable
                          // viewport. Flutter's native auto-scroller can now
                          // scroll it when the drag proxy reaches an edge.
                          return SizedBox(
                            height: constraints.maxWidth >= 900 ? 440 : 360,
                            child: ReorderableListView.builder(
                              key: const Key('budget-program-step-list'),
                              scrollController: _stepsScrollController,
                              primary: false,
                              physics: const ClampingScrollPhysics(),
                              autoScrollerVelocityScalar: 14,
                              buildDefaultDragHandles: false,
                              itemCount: items.length,
                              onReorderItem: (oldIndex, newIndex) {
                                _queueReorder(items, oldIndex, newIndex);
                              },
                              itemBuilder: (context, index) {
                                final step = items[index];
                                final shared =
                                    step.contributionKey !=
                                    ContributionKeyStrategy.singleMember;
                                return Padding(
                                  key: ValueKey('budget-step-${step.id}'),
                                  padding: const EdgeInsets.only(
                                    bottom: AppSpacing.xs,
                                  ),
                                  child: Material(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.surface,
                                    borderRadius: AppRadius.input,
                                    child: ListTile(
                                      dense: true,
                                      visualDensity: VisualDensity.compact,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: AppSpacing.sm,
                                          ),
                                      title: Text(
                                        '${index + 1} • ${step.groupName}',
                                      ),
                                      subtitle: Text(
                                        '${shared ? 'Contributions du foyer' : sourceNames[step.sourceId] ?? 'Source'} → ${envelopeNames[step.envelopeId] ?? 'Enveloppe'} • ${_stepValueLabel(step)} • ${_keyLabel(step.contributionKey)} • ${_policyLabel(step.insufficientFundsPolicy)}${step.active ? '' : ' • Inactive'}',
                                      ),
                                      trailing: Wrap(
                                        children: [
                                          IconButton(
                                            key: Key(
                                              'move-budget-step-up-${step.id}',
                                            ),
                                            tooltip: 'Monter',
                                            icon: const Icon(
                                              Icons.arrow_upward,
                                            ),
                                            onPressed:
                                                _isReorderLocked || index == 0
                                                ? null
                                                : () => _moveStep(
                                                    context,
                                                    items,
                                                    index,
                                                    -1,
                                                  ),
                                          ),
                                          IconButton(
                                            key: Key(
                                              'move-budget-step-down-${step.id}',
                                            ),
                                            tooltip: 'Descendre',
                                            icon: const Icon(
                                              Icons.arrow_downward,
                                            ),
                                            onPressed:
                                                _isReorderLocked ||
                                                    index == items.length - 1
                                                ? null
                                                : () => _moveStep(
                                                    context,
                                                    items,
                                                    index,
                                                    1,
                                                  ),
                                          ),
                                          IconButton(
                                            key: Key(
                                              'toggle-budget-step-${step.id}',
                                            ),
                                            tooltip: step.active
                                                ? 'Désactiver'
                                                : 'Activer',
                                            icon: Icon(
                                              step.active
                                                  ? Icons.toggle_on_outlined
                                                  : Icons.toggle_off_outlined,
                                            ),
                                            onPressed: () =>
                                                _toggleStep(ref, step),
                                          ),
                                          IconButton(
                                            key: Key(
                                              'duplicate-budget-step-${step.id}',
                                            ),
                                            tooltip: 'Dupliquer',
                                            icon: const Icon(
                                              Icons.copy_outlined,
                                            ),
                                            onPressed: () => _duplicateStep(
                                              ref,
                                              items,
                                              step,
                                            ),
                                          ),
                                          IconButton(
                                            key: Key(
                                              'edit-budget-step-${step.id}',
                                            ),
                                            tooltip: 'Modifier',
                                            icon: const Icon(
                                              Icons.edit_outlined,
                                            ),
                                            onPressed: _isReorderLocked
                                                ? null
                                                : () => _editStep(
                                                    context,
                                                    ref,
                                                    version.id,
                                                    sources.valueOrNull ??
                                                        const [],
                                                    envelopes.valueOrNull ??
                                                        const [],
                                                    members.valueOrNull ??
                                                        const [],
                                                    orderedSteps: items,
                                                    step: step,
                                                  ),
                                          ),
                                          IconButton(
                                            key: Key(
                                              'delete-budget-step-${step.id}',
                                            ),
                                            tooltip: 'Supprimer',
                                            icon: const Icon(
                                              Icons.delete_outline,
                                            ),
                                            onPressed: () =>
                                                _deleteStep(context, ref, step),
                                          ),
                                          IgnorePointer(
                                            ignoring: _isReorderLocked,
                                            child: Tooltip(
                                              message:
                                                  'Glisser pour réorganiser',
                                              child: ReorderableDragStartListener(
                                                key: Key(
                                                  'drag-budget-step-${step.id}',
                                                ),
                                                index: index,
                                                child: const Padding(
                                                  padding: EdgeInsets.symmetric(
                                                    horizontal: AppSpacing.xs,
                                                  ),
                                                  child: Icon(
                                                    Icons.drag_indicator,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _moveStep(
    BuildContext context,
    List<BudgetAllocationStep> steps,
    int index,
    int delta,
  ) {
    final targetIndex = index + delta;
    if (index < 0 || targetIndex < 0 || targetIndex >= steps.length) return;
    _queueReorder(steps, index, targetIndex);
  }

  void _queueReorder(
    List<BudgetAllocationStep> steps,
    int fromIndex,
    int toIndex,
  ) {
    if (_isReordering || _reorderScheduled) return;
    // ReorderableListView may report its result while its layout is settling.
    // Leave both that frame and its current event-loop turn before changing
    // state, so neither the feedback nor provider invalidation can rebuild
    // the list from within LayoutBuilder.performLayout.
    _reorderScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await Future<void>.delayed(Duration.zero);
      if (!mounted) return;
      _reorderScheduled = false;
      await _reorderStep(steps, fromIndex, toIndex);
    });
  }

  Future<void> _reorderStep(
    List<BudgetAllocationStep> steps,
    int fromIndex,
    int toIndex,
  ) async {
    final reordered = moveStepToPosition(
      steps,
      fromIndex: fromIndex,
      toIndex: toIndex,
    );
    if (_isReordering) return;
    setState(() {
      _isReordering = true;
      _reorderingError = null;
    });
    try {
      final repository = await ref.read(
        budgetSupabaseRepositoryProvider.future,
      );
      await repository.reorderSteps(reordered);
      ref.invalidate(budgetScenarioStepsProvider(version.id));
      _showReorderMessage(const Text('Ordre enregistré'));
    } catch (_) {
      // Refresh from the actual persistence state; no optimistic local order
      // is retained after an incomplete remote write.
      ref.invalidate(budgetScenarioStepsProvider(version.id));
      if (mounted) {
        setState(() {
          _reorderingError =
              'Réorganisation impossible. Vérifiez votre connexion puis réessayez.';
        });
        _showReorderMessage(
          const Text(
            'Réorganisation impossible. Vérifiez votre connexion puis réessayez.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isReordering = false);
    }
  }

  void _showReorderMessage(Widget message) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: message, duration: const Duration(seconds: 3)),
      );
    });
  }

  Future<void> _testScenario(
    BuildContext context,
    List<BudgetSource> sources,
    List<BudgetAllocationStep> steps,
    List<HouseholdMember> members,
    Map<String, String> envelopeNames,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _ConstrainedBudgetSheet(
        child: ScenarioTestSheet(
          sources: sources,
          steps: steps,
          members: members,
          envelopeNames: envelopeNames,
        ),
      ),
      /*builder: (context) => SafeArea(
        child: ListView(
          padding: AppSpacing.page,
          children: [
            Text(
              'Résultat du test',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const Text(
              'Simulation temporaire : aucune donnée financière n’est écrite.',
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Ressources initiales : ${_mad(sources.where((source) => source.active).fold(0, (sum, source) => sum + source.expectedCents))}',
            ),
            Text('Reste : ${_mad(result.remainingCents)}'),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Programme étape par étape',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            ...result.allocations.map((allocation) {
              final step = steps.firstWhere(
                (value) => value.id == allocation.stepId,
              );
              return ListTile(
                title: Text('${step.order} • ${step.groupName}'),
                subtitle: Text(
                  '${_stepValueLabel(step)} • Alloué : ${_mad(allocation.allocatedCents)} • Reste : ${_mad(result.remainingCents)}',
                ),
              );
            }),
            if (unused.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              const Text('Avertissements'),
              ...unused.map(
                (source) => Text(
                  '• La source « ${source.name} » n’est utilisée par aucune étape.',
                ),
              ),
            ],
            if (result.warnings.isNotEmpty) ...[
              const Text('Avertissements'),
              ...result.warnings.map((warning) => Text('• $warning')),
            ],
            if (steps.where((step) => !step.active).isNotEmpty)
              const Text('Info : certaines étapes sont inactives.'),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Réinitialiser le test'),
            ),
          ],
        ),
      ),*/
    );
  }

  Future<void> _toggleSource(WidgetRef ref, BudgetSource source) async {
    final repository = await ref.read(budgetSupabaseRepositoryProvider.future);
    await repository.saveSource(
      BudgetSource(
        id: source.id,
        scenarioVersionId: source.scenarioVersionId,
        type: source.type,
        name: source.name,
        expectedCents: source.expectedCents,
        memberUserId: source.memberUserId,
        exceptionalTreatment: source.exceptionalTreatment,
        active: !source.active,
      ),
    );
    ref.invalidate(budgetScenarioSourcesProvider(version.id));
  }

  Future<void> _toggleStep(WidgetRef ref, BudgetAllocationStep step) async {
    final repository = await ref.read(budgetSupabaseRepositoryProvider.future);
    await repository.saveStep(_withActive(step, !step.active));
    ref.invalidate(budgetScenarioStepsProvider(version.id));
  }

  Future<void> _duplicateStep(
    WidgetRef ref,
    List<BudgetAllocationStep> steps,
    BudgetAllocationStep step,
  ) async {
    final repository = await ref.read(budgetSupabaseRepositoryProvider.future);
    await repository.duplicateStep(step: step, orderedSteps: steps);
    ref.invalidate(budgetScenarioStepsProvider(version.id));
  }

  Future<void> _deleteSource(
    BuildContext context,
    WidgetRef ref,
    BudgetSource source,
    List<BudgetAllocationStep> displayedSteps,
  ) async {
    final references = displayedSteps
        .where((step) => step.sourceId == source.id)
        .toList(growable: false);
    if (references.isNotEmpty) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Impossible de supprimer cette source.'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Elle est utilisée par :'),
              const SizedBox(height: AppSpacing.sm),
              ...references.map((step) => Text('• ${step.groupName}')),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fermer'),
            ),
          ],
        ),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer cette source ?'),
        content: const Text('Cette action ne modifie aucun mois enregistré.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final repository = await ref.read(
        budgetSupabaseRepositoryProvider.future,
      );
      await repository.deleteSource(source);
      ref.invalidate(budgetScenarioSourcesProvider(version.id));
      ref.invalidate(budgetScenarioStepsProvider(version.id));
    } on StateError catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message.toString())));
    }
  }

  Future<void> _deleteStep(
    BuildContext context,
    WidgetRef ref,
    BudgetAllocationStep step,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer cette étape du scénario ?'),
        content: const Text(
          'Les simulations et historiques déjà enregistrés ne seront pas modifiés.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!context.mounted) return;
    final repository = await ref.read(budgetSupabaseRepositoryProvider.future);
    await repository.deleteStep(step.id);
    final remaining = await repository.stepsForVersion(version.id);
    await repository.reorderSteps(remaining);
    ref.invalidate(budgetScenarioStepsProvider(version.id));
  }

  Future<void> _editSource(
    BuildContext context,
    WidgetRef ref,
    String versionId, {
    BudgetSource? source,
  }) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _SourceDialog(versionId: versionId, source: source),
    );
    if (saved == true) ref.invalidate(budgetScenarioSourcesProvider(versionId));
  }

  Future<void> _editStep(
    BuildContext context,
    WidgetRef ref,
    String versionId,
    List<BudgetSource> sources,
    List<dynamic> envelopes,
    List<dynamic> members, {
    required List<BudgetAllocationStep> orderedSteps,
    BudgetAllocationStep? step,
  }) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => BudgetAllocationStepDialog(
        versionId: versionId,
        scenarioId: scenario.id,
        sources: sources,
        envelopes: envelopes,
        members: members,
        orderedSteps: orderedSteps,
        step: step,
      ),
    );
    if (saved == true) {
      ref.invalidate(budgetScenarioSourcesProvider(versionId));
      ref.invalidate(budgetScenarioStepsProvider(versionId));
    }
  }

  Future<void> _editStepsInBatch(
    BuildContext context,
    WidgetRef ref,
    String versionId,
    List<BudgetSource> sources,
    List<dynamic> envelopes,
    List<dynamic> members,
    List<BudgetAllocationStep> existingSteps,
  ) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ConstrainedBudgetSheet(
        child: BudgetAllocationBatchEditor(
          versionId: versionId,
          scenarioId: scenario.id,
          sources: sources,
          envelopes: envelopes,
          members: members.whereType<HouseholdMember>().toList(growable: false),
          existingSteps: existingSteps,
          nextOrder: existingSteps.length + 1,
        ),
      ),
    );
    if (saved == true) {
      ref.invalidate(budgetScenarioSourcesProvider(versionId));
      ref.invalidate(budgetScenarioStepsProvider(versionId));
    }
  }
}

/// Efficient one-session editor for the common programme patterns.  Existing
/// rows can still be edited individually, but initial configuration no longer
/// requires one popup per envelope.
class _ConstrainedBudgetSheet extends StatelessWidget {
  const _ConstrainedBudgetSheet({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = AppLayout.isCompact(size.width);
    return SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppLayout.wideDialogMaxWidth,
          ),
          child: FractionallySizedBox(
            heightFactor: compact ? 1 : 0.88,
            child: child,
          ),
        ),
      ),
    );
  }
}

class _ReorderFeedback extends StatelessWidget {
  const _ReorderFeedback({super.key, required this.label, this.error = false});

  final String label;
  final bool error;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: error
          ? Theme.of(context).colorScheme.errorContainer
          : AppColors.surface,
      borderRadius: AppRadius.input,
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!error)
            const SizedBox(
              height: 16,
              width: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(
              Icons.error_outline,
              color: Theme.of(context).colorScheme.error,
            ),
          const SizedBox(width: AppSpacing.xs),
          Flexible(child: Text(label)),
        ],
      ),
    ),
  );
}

class BudgetAllocationBatchEditor extends ConsumerStatefulWidget {
  const BudgetAllocationBatchEditor({
    super.key,
    required this.versionId,
    required this.scenarioId,
    required this.sources,
    required this.envelopes,
    required this.members,
    required this.nextOrder,
    this.existingSteps = const [],
  });

  final String versionId;
  final String scenarioId;
  final List<BudgetSource> sources;
  final List<dynamic> envelopes;
  final List<HouseholdMember> members;
  final int nextOrder;
  final List<BudgetAllocationStep> existingSteps;

  @override
  ConsumerState<BudgetAllocationBatchEditor> createState() =>
      _BudgetAllocationBatchEditorState();
}

enum _BatchStepKind {
  personal,
  sharedCustom,
  sharedAutomatic,
  sharedFixedByMember,
  other,
}

const _customPercentageEpsilon = 0.000001;
const _batchApplicableMethods = <BudgetAllocationMethod>[
  BudgetAllocationMethod.fixed,
  BudgetAllocationMethod.percentage,
  BudgetAllocationMethod.residual,
];

double? _parsePercentage(String value) =>
    double.tryParse(value.trim().replaceAll(',', '.'));

String? _customPercentageValidation(Iterable<String> values) {
  final parsed = values.map(_parsePercentage).toList(growable: false);
  if (parsed.any((value) => value == null)) {
    return 'Saisissez un pourcentage pour chaque membre concerné.';
  }
  if (parsed.any((value) => value! < 0 || value > 100)) {
    return 'Chaque pourcentage doit être compris entre 0 % et 100 %.';
  }
  final total = parsed.fold<double>(0, (sum, value) => sum + value!);
  if ((total - 100).abs() >= _customPercentageEpsilon) {
    return 'La répartition doit totaliser exactement 100 %. '
        'Total actuel : ${total.toStringAsFixed(2)} %.';
  }
  return null;
}

class _BatchStepDraft {
  _BatchStepDraft({
    required this.kind,
    required this.sourceId,
    required this.envelopeId,
    required this.order,
    this.memberId,
  });

  final _BatchStepKind kind;
  String? sourceId;
  String? envelopeId;
  int order;
  final String? memberId;
  BudgetAllocationMethod method = BudgetAllocationMethod.fixed;
  BudgetInsufficientFundsPolicy policy = BudgetInsufficientFundsPolicy.strict;
  bool active = true;
  final amount = TextEditingController();
  final Map<String, TextEditingController> memberValues = {};

  void dispose() {
    amount.dispose();
    for (final controller in memberValues.values) {
      controller.dispose();
    }
  }
}

class _BudgetAllocationBatchEditorState
    extends ConsumerState<BudgetAllocationBatchEditor> {
  final _rows = <_BatchStepDraft>[];
  String? _error;
  bool _saving = false;

  List<BudgetSource> get _activeSources =>
      widget.sources.where((source) => source.active).toList(growable: false);

  BudgetSource? _defaultSource({String? memberId}) {
    final matching = _activeSources.where(
      (source) => memberId == null || source.memberUserId == memberId,
    );
    return matching.firstOrNull ?? _activeSources.firstOrNull;
  }

  void _add(_BatchStepKind kind, {HouseholdMember? member}) {
    final personal = kind == _BatchStepKind.personal;
    final source = personal ? _defaultSource(memberId: member?.id) : null;
    if ((personal && source == null) || widget.envelopes.isEmpty) {
      setState(() {
        _error = widget.envelopes.isEmpty
            ? 'Ajoutez d’abord une enveloppe active.'
            : 'Ajoutez d’abord une source active pour ce membre.';
      });
      return;
    }
    setState(() {
      _error = null;
      _rows.add(
        _BatchStepDraft(
          kind: kind,
          sourceId: source?.id,
          envelopeId: widget.envelopes.first.id as String?,
          order: widget.nextOrder + _rows.length * 10,
          memberId: member?.id,
        ),
      );
    });
  }

  Map<String, int> _capacityPreview() {
    final resources = <String, int>{
      for (final member in widget.members) member.id: 0,
    };
    for (final source in _activeSources) {
      final memberId = source.memberUserId;
      if (memberId != null && resources.containsKey(memberId)) {
        resources[memberId] = (resources[memberId] ?? 0) + source.expectedCents;
      }
    }
    for (final row in _rows.where(
      (row) => row.kind == _BatchStepKind.personal,
    )) {
      final memberId = row.memberId;
      final amount = _cents(row.amount.text) ?? 0;
      if (memberId != null && row.method == BudgetAllocationMethod.fixed) {
        resources[memberId] = (resources[memberId] ?? 0) - amount;
      }
    }
    return resources;
  }

  Map<String, Object?>? _validationFor(_BatchStepDraft row) {
    final amount = _cents(row.amount.text);
    final percentage = double.tryParse(
      row.amount.text.trim().replaceAll(',', '.'),
    );
    if ((row.kind == _BatchStepKind.personal && row.sourceId == null) ||
        row.envelopeId == null) {
      return null;
    }
    if (row.method == BudgetAllocationMethod.fixed &&
        (amount == null || amount <= 0)) {
      return null;
    }
    if (row.method == BudgetAllocationMethod.percentage &&
        (percentage == null || percentage < 0 || percentage > 100)) {
      return null;
    }
    if (row.kind == _BatchStepKind.sharedCustom &&
        _customPercentageError(row) != null) {
      return null;
    }
    if (row.kind == _BatchStepKind.sharedFixedByMember &&
        (amount == null || _memberFixedTotal(row) != amount)) {
      return null;
    }
    final key = switch (row.kind) {
      _BatchStepKind.personal => ContributionKeyStrategy.singleMember,
      _BatchStepKind.sharedCustom => ContributionKeyStrategy.customPercentage,
      _BatchStepKind.sharedAutomatic =>
        ContributionKeyStrategy.automaticRemainingCapacity,
      _BatchStepKind.sharedFixedByMember =>
        ContributionKeyStrategy.fixedByMember,
      _BatchStepKind.other => ContributionKeyStrategy.equal,
    };
    final definition = <String, Object?>{
      if (row.kind == _BatchStepKind.sharedCustom)
        for (final member in widget.members)
          member.id: double.tryParse(
            row.memberValues[member.id]?.text.trim().replaceAll(',', '.') ?? '',
          ),
      if (row.kind == _BatchStepKind.sharedFixedByMember)
        for (final member in widget.members)
          member.id: _cents(row.memberValues[member.id]?.text ?? ''),
      if (row.kind == _BatchStepKind.other)
        'members': widget.members.map((member) => member.id).toList(),
    };
    return {
      'amount': amount,
      'percentage': percentage,
      'key': key,
      'definition': definition,
    };
  }

  String? _customPercentageError(_BatchStepDraft row) =>
      _customPercentageValidation(
        widget.members.map((member) => row.memberValues[member.id]?.text ?? ''),
      );

  int _memberFixedTotal(_BatchStepDraft row) => widget.members.fold<int>(
    0,
    (total, member) =>
        total + (_cents(row.memberValues[member.id]?.text ?? '') ?? 0),
  );

  BudgetAllocationStep? _previewStep(_BatchStepDraft row) {
    final values = _validationFor(row);
    if (values == null) return null;
    return BudgetAllocationStep(
      id: 'batch-preview-${row.order}',
      scenarioVersionId: widget.versionId,
      order: row.order,
      groupName: _groupLabel(row),
      // Common steps are funded by the contribution key. Their relational
      // source anchor is not used by the interpreter for financing.
      sourceId: row.sourceId ?? 'batch-common-capacity-preview',
      envelopeId: row.envelopeId!,
      method: row.method,
      contributionKey: values['key']! as ContributionKeyStrategy,
      insufficientFundsPolicy: row.policy,
      amountCents: values['amount'] as int?,
      percentage: values['percentage'] as double?,
      memberUserId: row.memberId,
      keyDefinition: values['definition']! as Map<String, Object?>,
      active: row.active,
    );
  }

  ProgrammableBudgetStepResult? _previewResultFor(_BatchStepDraft row) {
    final previewSteps = [
      ...widget.existingSteps,
      for (final draft in _rows) ?_previewStep(draft),
    ];
    final stepId = 'batch-preview-${row.order}';
    return const ProgrammableBudgetEngine()
        .simulate(
          sources: widget.sources,
          steps: previewSteps,
          memberIds: widget.members.map((member) => member.id).toList(),
        )
        .stepResults
        .where((result) => result.step.id == stepId)
        .firstOrNull;
  }

  String? _strictFundsWarning(_BatchStepDraft row) {
    if (row.policy != BudgetInsufficientFundsPolicy.strict) return null;
    final preview = _previewResultFor(row);
    if (preview == null ||
        preview.status != ProgrammableBudgetStepStatus.blocked ||
        !preview.diagnostics.any(
          (diagnostic) => diagnostic.code == 'strict_insufficient_funds',
        )) {
      return null;
    }
    return 'Fonds insuffisants : cette étape demande '
        '${_mad(preview.requestedCents)} alors que '
        '${_mad(preview.availableBeforeCents)} sont disponibles à ce stade du scénario.';
  }

  String? _validateRows() {
    if (_rows.isEmpty) return 'Ajoutez au moins une ligne à enregistrer.';
    for (final row in _rows) {
      final values = _validationFor(row);
      if (values == null) {
        if (row.kind == _BatchStepKind.sharedCustom) {
          return _customPercentageError(row) ??
              'La clé personnalisée doit totaliser exactement 100 %.';
        }
        if (row.kind == _BatchStepKind.sharedFixedByMember) {
          return 'Les montants par membre doivent égaler le montant de la ligne.';
        }
        return 'Chaque ligne doit avoir une enveloppe et une valeur valide.';
      }
      if (row.kind == _BatchStepKind.personal) {
        final source = _activeSources
            .where((source) => source.id == row.sourceId)
            .firstOrNull;
        if (source?.memberUserId != row.memberId) {
          return 'Une charge personnelle doit utiliser la source de son membre.';
        }
      }
    }
    return null;
  }

  Future<void> _save() async {
    final validation = _validateRows();
    if (validation != null) {
      setState(() => _error = validation);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repository = await ref.read(
        budgetSupabaseRepositoryProvider.future,
      );
      final commonRows = _rows.where(
        (row) => row.kind != _BatchStepKind.personal,
      );
      final commonSourceId = commonRows.isEmpty
          ? null
          : await repository.ensureCommonCapacitySource(widget.versionId);
      for (final row in _rows) {
        final values = _validationFor(row)!;
        await repository.saveStep(
          BudgetAllocationStep(
            id: '',
            scenarioVersionId: widget.versionId,
            // Insert batch rows beyond the current range, then normalize the
            // whole sequence once. This avoids collisions with legacy orders.
            order: 1000000 + row.order,
            groupName: _groupLabel(row),
            sourceId: row.sourceId ?? commonSourceId!,
            envelopeId: row.envelopeId!,
            method: row.method,
            contributionKey: values['key'] as ContributionKeyStrategy,
            insufficientFundsPolicy: row.policy,
            amountCents: row.method == BudgetAllocationMethod.fixed
                ? values['amount'] as int?
                : null,
            percentage: row.method == BudgetAllocationMethod.percentage
                ? values['percentage'] as double?
                : null,
            memberUserId: row.memberId,
            keyDefinition: Map<String, Object?>.from(
              values['definition'] as Map<String, Object?>,
            ),
            active: row.active,
          ),
        );
      }
      final allSteps = await repository.stepsForVersion(widget.versionId);
      await repository.reorderSteps(allSteps);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      ref.invalidate(budgetScenarioStepsProvider(widget.versionId));
      if (mounted) {
        setState(() => _error = 'Enregistrement impossible : $error');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _groupLabel(_BatchStepDraft row) => switch (row.kind) {
    _BatchStepKind.personal => 'Charges personnelles',
    _BatchStepKind.sharedCustom => 'Charges communes — clé personnalisée',
    _BatchStepKind.sharedAutomatic => 'Charges communes — clé automatique',
    _BatchStepKind.sharedFixedByMember =>
      'Charges communes — montants par membre',
    _BatchStepKind.other => 'Autres allocations',
  };

  bool get _hasInvalidCustomPercentage => _rows.any(
    (row) =>
        row.kind == _BatchStepKind.sharedCustom &&
        _customPercentageError(row) != null,
  );

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final capacity = _capacityPreview();
    return SafeArea(
      child: Scaffold(
        appBar: AppBar(title: const Text('Configurer plusieurs enveloppes')),
        body: LayoutBuilder(
          builder: (context, constraints) => Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppLayout.formMaxWidth,
              ),
              child: ListView(
                padding: AppLayout.pagePaddingFor(constraints.maxWidth),
                children: [
                  const Text(
                    'Ajoutez plusieurs lignes puis enregistrez-les en une seule session. Les mois déjà préparés ne sont jamais modifiés.',
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Charges personnelles',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Text(
                    'Chaque charge est imputée directement à la source du membre concerné.',
                  ),
                  Wrap(
                    spacing: AppSpacing.xs,
                    children: widget.members
                        .map(
                          (member) => OutlinedButton.icon(
                            key: Key('add-personal-step-${member.id}'),
                            onPressed: () =>
                                _add(_BatchStepKind.personal, member: member),
                            icon: const Icon(Icons.add),
                            label: Text(member.displayName),
                          ),
                        )
                        .toList(growable: false),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Charges communes',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Wrap(
                    spacing: AppSpacing.xs,
                    children: [
                      OutlinedButton.icon(
                        key: const Key('add-shared-custom-step'),
                        onPressed: () => _add(_BatchStepKind.sharedCustom),
                        icon: const Icon(Icons.add),
                        label: const Text('Clé personnalisée'),
                      ),
                      OutlinedButton.icon(
                        key: const Key('add-shared-auto-step'),
                        onPressed: () => _add(_BatchStepKind.sharedAutomatic),
                        icon: const Icon(Icons.add),
                        label: const Text('Clé automatique'),
                      ),
                      OutlinedButton.icon(
                        key: const Key('add-shared-fixed-step'),
                        onPressed: () =>
                            _add(_BatchStepKind.sharedFixedByMember),
                        icon: const Icon(Icons.add),
                        label: const Text('Montants par membre'),
                      ),
                      OutlinedButton.icon(
                        key: const Key('add-other-batch-step'),
                        onPressed: () => _add(_BatchStepKind.other),
                        icon: const Icon(Icons.add),
                        label: const Text('Autre ligne'),
                      ),
                    ],
                  ),
                  if (_rows.isEmpty) const Text('Aucune ligne en attente.'),
                  ..._rows.asMap().entries.map(
                    (entry) => _BatchStepRow(
                      key: ValueKey('batch-step-${entry.key}'),
                      draft: entry.value,
                      sources: _activeSources,
                      envelopes: widget.envelopes,
                      members: widget.members,
                      capacity: capacity,
                      strictFundsWarning: _strictFundsWarning(entry.value),
                      onChanged: () => setState(() => _error = null),
                      onRemove: () => setState(() {
                        entry.value.dispose();
                        _rows.removeAt(entry.key);
                      }),
                    ),
                  ),
                  if (_error != null)
                    Text(
                      _error!,
                      key: const Key('batch-step-validation-error'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  const SizedBox(height: AppSpacing.md),
                  FilledButton.icon(
                    key: const Key('save-batch-steps'),
                    onPressed: _saving || _hasInvalidCustomPercentage
                        ? null
                        : _save,
                    icon: const Icon(Icons.save_outlined),
                    label: Text(
                      _saving ? 'Enregistrement…' : 'Enregistrer les lignes',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BatchStepRow extends StatelessWidget {
  const _BatchStepRow({
    super.key,
    required this.draft,
    required this.sources,
    required this.envelopes,
    required this.members,
    required this.capacity,
    required this.strictFundsWarning,
    required this.onChanged,
    required this.onRemove,
  });

  final _BatchStepDraft draft;
  final List<BudgetSource> sources;
  final List<dynamic> envelopes;
  final List<HouseholdMember> members;
  final Map<String, int> capacity;
  final String? strictFundsWarning;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  bool get _isPersonal => draft.kind == _BatchStepKind.personal;
  bool get _isCommon => !_isPersonal;
  bool get _isCustom => draft.kind == _BatchStepKind.sharedCustom;
  bool get _isAutomatic => draft.kind == _BatchStepKind.sharedAutomatic;
  bool get _isFixedByMember => draft.kind == _BatchStepKind.sharedFixedByMember;
  String? get _customPercentageError => _customPercentageValidation(
    members.map((member) => draft.memberValues[member.id]?.text ?? ''),
  );

  @override
  Widget build(BuildContext context) {
    final allowedSources = sources
        .where((source) => source.memberUserId == draft.memberId)
        .toList();
    final validSource =
        allowedSources.any((source) => source.id == draft.sourceId)
        ? draft.sourceId
        : allowedSources.firstOrNull?.id;
    if (_isPersonal && validSource != draft.sourceId) {
      draft.sourceId = validSource;
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _batchKindLabel(draft.kind, members, draft.memberId),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  tooltip: 'Retirer',
                  onPressed: onRemove,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            if (_isPersonal)
              DropdownButtonFormField<String>(
                initialValue: validSource,
                decoration: const InputDecoration(
                  labelText: 'Source personnelle',
                ),
                items: allowedSources
                    .map(
                      (source) => DropdownMenuItem(
                        value: source.id,
                        child: Text(source.name),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  draft.sourceId = value;
                  onChanged();
                },
              ),
            if (_isCommon)
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.groups_outlined),
                title: Text('Financement : contributions du foyer'),
                subtitle: Text(
                  'Aucun salaire individuel ne finance seul cette ligne.',
                ),
              ),
            LayoutBuilder(
              builder: (context, constraints) {
                final fieldWidth = constraints.maxWidth >= 900
                    ? (constraints.maxWidth - (AppSpacing.sm * 2)) / 3
                    : constraints.maxWidth;
                return Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    SizedBox(
                      width: fieldWidth,
                      child: DropdownButtonFormField<String>(
                        initialValue: draft.envelopeId,
                        decoration: const InputDecoration(
                          labelText: 'Enveloppe',
                        ),
                        items: envelopes
                            .map(
                              (envelope) => DropdownMenuItem(
                                value: envelope.id as String,
                                child: Text(envelope.name as String),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (value) {
                          draft.envelopeId = value;
                          onChanged();
                        },
                      ),
                    ),
                    SizedBox(
                      width: fieldWidth,
                      child: DropdownButtonFormField<BudgetAllocationMethod>(
                        initialValue: draft.method,
                        decoration: const InputDecoration(
                          labelText: 'Calcul du montant',
                        ),
                        items: _batchApplicableMethods
                            .map(
                              (method) => DropdownMenuItem(
                                value: method,
                                child: Text(_methodLabel(method)),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (value) {
                          if (value != null) {
                            draft.method = value;
                            onChanged();
                          }
                        },
                      ),
                    ),
                    if (draft.method != BudgetAllocationMethod.residual)
                      SizedBox(
                        width: fieldWidth,
                        child: TextField(
                          key: Key('batch-step-value-${draft.order}'),
                          controller: draft.amount,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText:
                                draft.method ==
                                    BudgetAllocationMethod.percentage
                                ? 'Pourcentage'
                                : 'Montant (MAD)',
                          ),
                          onChanged: (_) => onChanged(),
                        ),
                      ),
                  ],
                );
              },
            ),
            if (_isCustom) ...[
              const Text('Clé personnalisée — la somme doit être 100 %.'),
              LayoutBuilder(
                builder: (context, constraints) {
                  final fieldWidth = constraints.maxWidth >= 700
                      ? (constraints.maxWidth - AppSpacing.sm) / 2
                      : constraints.maxWidth;
                  return Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: members
                        .map((member) {
                          final controller = draft.memberValues.putIfAbsent(
                            member.id,
                            TextEditingController.new,
                          );
                          return SizedBox(
                            width: fieldWidth,
                            child: TextField(
                              key: Key(
                                'batch-custom-${draft.order}-${member.id}',
                              ),
                              controller: controller,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: '${member.displayName} (%)',
                              ),
                              onChanged: (_) => onChanged(),
                            ),
                          );
                        })
                        .toList(growable: false),
                  );
                },
              ),
              Text(
                'Total de la clé : ${_batchCustomTotal(draft, members).toStringAsFixed(2)} %',
              ),
              if (_customPercentageError != null)
                Text(
                  _customPercentageError!,
                  key: Key('batch-custom-error-${draft.order}'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
            if (_isFixedByMember) ...[
              const Text(
                'Montants par membre — leur somme doit égaler le montant de la ligne.',
              ),
              LayoutBuilder(
                builder: (context, constraints) {
                  final fieldWidth = constraints.maxWidth >= 700
                      ? (constraints.maxWidth - AppSpacing.sm) / 2
                      : constraints.maxWidth;
                  return Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: members
                        .map((member) {
                          final controller = draft.memberValues.putIfAbsent(
                            member.id,
                            TextEditingController.new,
                          );
                          return SizedBox(
                            width: fieldWidth,
                            child: TextField(
                              key: Key(
                                'batch-fixed-${draft.order}-${member.id}',
                              ),
                              controller: controller,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: '${member.displayName} (MAD)',
                              ),
                              onChanged: (_) => onChanged(),
                            ),
                          );
                        })
                        .toList(growable: false),
                  );
                },
              ),
              Text('Total : ${_mad(_batchFixedTotal(draft, members))}'),
            ],
            if (_isAutomatic) ...[
              const Text('Clé automatique selon la capacité contributive :'),
              ...members.map((member) {
                final positive = capacity[member.id] ?? 0;
                final total = capacity.values
                    .where((value) => value > 0)
                    .fold<int>(0, (sum, value) => sum + value);
                final share = total == 0 || positive <= 0
                    ? 0
                    : positive / total * 100;
                return Text(
                  '${member.displayName} : ${share.toStringAsFixed(1)} %',
                );
              }),
            ],
            DropdownButtonFormField<BudgetInsufficientFundsPolicy>(
              initialValue: draft.policy,
              decoration: const InputDecoration(
                labelText: 'Si les fonds sont insuffisants',
              ),
              items: BudgetInsufficientFundsPolicy.values
                  .map(
                    (policy) => DropdownMenuItem(
                      value: policy,
                      child: Text(_policyLabel(policy)),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) {
                if (value != null) {
                  draft.policy = value;
                  onChanged();
                }
              },
            ),
            if (strictFundsWarning != null)
              Text(
                strictFundsWarning!,
                key: Key('batch-strict-funds-warning-${draft.order}'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            SwitchListTile(
              title: const Text('Ligne active'),
              value: draft.active,
              onChanged: (value) {
                draft.active = value;
                onChanged();
              },
            ),
          ],
        ),
      ),
    );
  }
}

String _batchKindLabel(
  _BatchStepKind kind,
  List<HouseholdMember> members,
  String? memberId,
) => switch (kind) {
  _BatchStepKind.personal =>
    'Charge personnelle — ${members.where((member) => member.id == memberId).firstOrNull?.displayName ?? 'Membre'}',
  _BatchStepKind.sharedCustom => 'Charge commune — clé personnalisée',
  _BatchStepKind.sharedAutomatic => 'Charge commune — clé automatique',
  _BatchStepKind.sharedFixedByMember => 'Charge commune — montants par membre',
  _BatchStepKind.other => 'Autre allocation',
};

double _batchCustomTotal(
  _BatchStepDraft draft,
  List<HouseholdMember> members,
) => members.fold<double>(
  0,
  (total, member) =>
      total +
      (double.tryParse(
            draft.memberValues[member.id]?.text.trim().replaceAll(',', '.') ??
                '',
          ) ??
          0),
);

int _batchFixedTotal(_BatchStepDraft draft, List<HouseholdMember> members) =>
    members.fold<int>(
      0,
      (total, member) =>
          total + (_cents(draft.memberValues[member.id]?.text ?? '') ?? 0),
    );

class ScenarioTestSheet extends StatefulWidget {
  const ScenarioTestSheet({
    super.key,
    required this.sources,
    required this.steps,
    required this.members,
    this.envelopeNames = const {},
  });
  final List<BudgetSource> sources;
  final List<BudgetAllocationStep> steps;
  final List<HouseholdMember> members;
  final Map<String, String> envelopeNames;
  @override
  State<ScenarioTestSheet> createState() => _ScenarioTestSheetState();
}

class _ScenarioTestSheetState extends State<ScenarioTestSheet> {
  final Map<String, int> _overridesCents = {};
  int? _parseCents(String value) => _cents(value);
  @override
  Widget build(BuildContext context) {
    final effectiveSources = widget.sources
        .map(
          (source) => BudgetSource(
            id: source.id,
            scenarioVersionId: source.scenarioVersionId,
            type: source.type,
            name: source.name,
            expectedCents: _overridesCents[source.id] ?? source.expectedCents,
            memberUserId: source.memberUserId,
            exceptionalTreatment: source.exceptionalTreatment,
            active: source.active,
          ),
        )
        .toList(growable: false);
    final result = const ProgrammableBudgetEngine().simulate(
      sources: effectiveSources,
      steps: widget.steps,
      memberIds: widget.members
          .map((member) => member.id)
          .toList(growable: false),
    );
    final memberNames = <String, String>{
      for (final member in widget.members) member.id: member.displayName,
    };
    return SafeArea(
      child: ListView(
        padding: AppSpacing.page,
        children: [
          Card(
            child: Padding(
              padding: AppSpacing.card,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Revenus utilisés pour le test',
                    style: _simulationSectionStyle(context),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  const Text(
                    'Ces valeurs sont temporaires et ne modifient pas le scénario.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final fieldWidth = constraints.maxWidth >= 760
                          ? (constraints.maxWidth - AppSpacing.sm) / 2
                          : constraints.maxWidth;
                      return Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        children: widget.sources
                            .where(
                              (source) =>
                                  source.active &&
                                  source.type !=
                                      BudgetSourceType.commonCapacity,
                            )
                            .map((source) {
                              final member = widget.members
                                  .where(
                                    (item) => item.id == source.memberUserId,
                                  )
                                  .firstOrNull;
                              final value =
                                  (_overridesCents[source.id] ??
                                      source.expectedCents) /
                                  100;
                              return SizedBox(
                                width: fieldWidth,
                                child: TextFormField(
                                  key: ValueKey(
                                    'test-source-value-${source.id}-${_overridesCents[source.id] ?? source.expectedCents}',
                                  ),
                                  initialValue: value.toString(),
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(
                                    labelText:
                                        '${source.name}${member == null ? '' : ' • ${member.displayName}'}',
                                    helperText:
                                        'Valeur normale : ${_mad(source.expectedCents)}',
                                  ),
                                  onChanged: (input) {
                                    final cents = _parseCents(input);
                                    setState(() {
                                      if (cents == null) {
                                        _overridesCents.remove(source.id);
                                      } else {
                                        _overridesCents[source.id] = cents;
                                      }
                                    });
                                  },
                                ),
                              );
                            })
                            .toList(growable: false),
                      );
                    },
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: AppSpacing.sm,
                    children: [
                      Text(
                        'Reste : ${_mad(result.remainingCents)}',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      TextButton.icon(
                        key: const Key('reset-test-source-values'),
                        onPressed: () => setState(_overridesCents.clear),
                        icon: const Icon(Icons.restart_alt_outlined),
                        label: const Text('Réinitialiser les valeurs'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Card(
            child: Padding(
              padding: AppSpacing.card,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Capacité contributive',
                    style: _simulationSectionStyle(context),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  const Text(
                    'La clé est calculée après les charges personnelles.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: result.memberCapacities
                        .map((capacity) {
                          final name =
                              memberNames[capacity.memberUserId] ??
                              'Membre du foyer';
                          return _SimulationMetricCard(
                            title: name,
                            width: 250,
                            lines: [
                              'Ressources retenues : ${_mad(capacity.resourcesCents)}',
                              'Charges personnelles : ${_mad(capacity.directChargesCents)}',
                              'Capacité brute : ${_mad(capacity.rawCapacityCents)}',
                              'Capacité utilisée : ${_mad(capacity.contributionCapacityCents)}',
                              if (capacity.rawCapacityCents < 0)
                                'Déficit personnel : ${_mad(-capacity.rawCapacityCents)}',
                              'Clé automatique : ${(capacity.autoShare * 100).toStringAsFixed(2)} %',
                            ],
                          );
                        })
                        .toList(growable: false),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Capacité contributive totale du foyer : ${_mad(result.householdContributionCapacityCents)}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  if (!result.hasAutomaticContributionCapacity)
                    const Padding(
                      padding: EdgeInsets.only(top: AppSpacing.xs),
                      child: Text(
                        'Impossible de calculer une clé automatique : aucune capacité contributive positive.',
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Card(
            child: Padding(
              padding: AppSpacing.card,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Résultat étape par étape',
                    style: _simulationSectionStyle(context),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  const Text(
                    'Ouvrez une ligne pour consulter son calcul et sa répartition.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  SizedBox(
                    height: 340,
                    child: ListView.separated(
                      itemCount: result.stepResults.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: AppSpacing.xs),
                      itemBuilder: (context, index) {
                        final stepResult = result.stepResults[index];
                        final status = _stepStatusVisual(stepResult.status);
                        return Material(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: AppRadius.input,
                          child: ExpansionTile(
                            title: Text(
                              'Étape ${stepResult.step.order} — ${stepResult.step.groupName}',
                            ),
                            leading: _StatusBadge(
                              label: _stepStatusLabel(stepResult.status),
                              color: status.color,
                              icon: status.icon,
                            ),
                            subtitle: Text(
                              '${_mad(stepResult.allocatedCents)} alloués',
                              style: TextStyle(color: status.color),
                            ),
                            childrenPadding: const EdgeInsets.fromLTRB(
                              AppSpacing.md,
                              0,
                              AppSpacing.md,
                              AppSpacing.md,
                            ),
                            children: [
                              Text(
                                stepResult.step.contributionKey ==
                                        ContributionKeyStrategy.singleMember
                                    ? 'Source : ${widget.sources.where((source) => source.id == stepResult.step.sourceId).map((source) => source.name).firstOrNull ?? 'Source non configurée'}'
                                    : 'Financement : Contributions du foyer',
                              ),
                              Text(
                                'Destination : ${widget.envelopeNames[stepResult.step.envelopeId] ?? 'Destination non configurée'}',
                              ),
                              Text(
                                'Méthode : ${_methodLabel(stepResult.step.method)}',
                              ),
                              Text(
                                'Politique : ${_policyLabel(stepResult.step.insufficientFundsPolicy)}',
                              ),
                              if (stepResult.percentageBaseCents != null)
                                Text(
                                  'Base : ${_mad(stepResult.percentageBaseCents!)}',
                                ),
                              _SimulationAmountRow(
                                label: 'Demandé',
                                value: _mad(stepResult.requestedCents),
                              ),
                              _SimulationAmountRow(
                                label: 'Alloué',
                                value: _mad(stepResult.allocatedCents),
                                color:
                                    stepResult.status ==
                                        ProgrammableBudgetStepStatus.executed
                                    ? AppColors.success
                                    : null,
                              ),
                              _SimulationAmountRow(
                                label: 'Disponible avant',
                                value: _mad(stepResult.availableBeforeCents),
                                color: AppColors.primary,
                              ),
                              _SimulationAmountRow(
                                label: 'Reste après',
                                value: _mad(stepResult.remainingAfterCents),
                                color: stepResult.remainingAfterCents > 0
                                    ? AppColors.success
                                    : null,
                              ),
                              if (stepResult.reductionCoefficient != null &&
                                  stepResult.reductionCoefficient! < 1)
                                Text(
                                  'Coefficient de réduction : ${formatReductionCoefficient(stepResult.reductionCoefficient!)}',
                                ),
                              if (stepResult
                                  .memberContributions
                                  .isNotEmpty) ...[
                                const SizedBox(height: AppSpacing.sm),
                                const Text('Contributions par membre'),
                                ...stepResult.memberContributions.entries.map(
                                  (entry) => Text(
                                    '${memberNames[entry.key] ?? 'Membre du foyer'} : ${_mad(entry.value)}',
                                  ),
                                ),
                              ],
                              ...stepResult.diagnostics.map(
                                _DiagnosticLine.new,
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Card(
            child: Padding(
              padding: AppSpacing.card,
              child: Wrap(
                spacing: AppSpacing.lg,
                runSpacing: AppSpacing.md,
                crossAxisAlignment: WrapCrossAlignment.start,
                children: [
                  SizedBox(
                    width: 540,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Synthèse par membre',
                          style: _simulationSectionStyle(context),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.sm,
                          children: result.memberSummaries
                              .map(
                                (summary) => _SimulationMetricCard(
                                  title:
                                      memberNames[summary.memberUserId] ??
                                      'Membre du foyer',
                                  width: 245,
                                  lines: [
                                    'Ressources initiales : ${_mad(summary.initialResourcesCents)}',
                                    'Total affecté : ${_mad(summary.allocatedCents)}',
                                    'Reste disponible : ${_mad(summary.remainingCents)}',
                                  ],
                                ),
                              )
                              .toList(growable: false),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 320,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Synthèse finale du foyer',
                          style: _simulationSectionStyle(context),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        _SimulationAmountRow(
                          label: 'Ressources initiales',
                          value: _mad(result.initialResourcesCents),
                        ),
                        _SimulationAmountRow(
                          label: 'Total alloué',
                          value: _mad(result.allocatedCents),
                          color: AppColors.success,
                        ),
                        _SimulationAmountRow(
                          label: 'Reste final',
                          value: _mad(result.remainingCents),
                          color: result.remainingCents > 0
                              ? AppColors.success
                              : null,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Wrap(
                          spacing: AppSpacing.xs,
                          runSpacing: AppSpacing.xs,
                          children: [
                            _StatusBadge(
                              label:
                                  'Exécutées ${result.count(ProgrammableBudgetStepStatus.executed)}',
                              color: AppColors.success,
                              icon: Icons.check_circle_outline,
                            ),
                            _StatusBadge(
                              label:
                                  'Partielles ${result.count(ProgrammableBudgetStepStatus.partiallyExecuted)}',
                              color: AppColors.warning,
                              icon: Icons.timelapse_outlined,
                            ),
                            _StatusBadge(
                              label:
                                  'Ignorées ${result.count(ProgrammableBudgetStepStatus.skipped)}',
                              color: AppColors.textSecondary,
                              icon: Icons.remove_circle_outline,
                            ),
                            _StatusBadge(
                              label:
                                  'Bloquées ${result.count(ProgrammableBudgetStepStatus.blocked)}',
                              color: AppColors.danger,
                              icon: Icons.block_outlined,
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          'Informations ${result.diagnosticsCount(ProgrammableBudgetDiagnosticSeverity.info)} • Avertissements ${result.diagnosticsCount(ProgrammableBudgetDiagnosticSeverity.warning)} • Blocages ${result.diagnosticsCount(ProgrammableBudgetDiagnosticSeverity.blocker)}',
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        _StatusBadge(
                          label: result.isSimulable
                              ? 'Budget simulable : Oui'
                              : 'Budget simulable : Non',
                          color: result.isSimulable
                              ? AppColors.success
                              : AppColors.danger,
                          icon: result.isSimulable
                              ? Icons.verified_outlined
                              : Icons.error_outline,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SimulationMetricCard extends StatelessWidget {
  const _SimulationMetricCard({
    required this.title,
    required this.width,
    required this.lines,
  });

  final String title;
  final double width;
  final List<String> lines;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: AppRadius.input,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          ...lines.map(
            (line) => Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xxs),
              child: Text(line),
            ),
          ),
        ],
      ),
    ),
  );
}

TextStyle _simulationSectionStyle(BuildContext context) => Theme.of(context)
    .textTheme
    .titleMedium!
    .copyWith(color: AppColors.primary, fontWeight: FontWeight.w700);

class _StatusVisual {
  const _StatusVisual(this.color, this.icon);
  final Color color;
  final IconData icon;
}

_StatusVisual _stepStatusVisual(ProgrammableBudgetStepStatus status) =>
    switch (status) {
      ProgrammableBudgetStepStatus.executed => const _StatusVisual(
        AppColors.success,
        Icons.check_circle_outline,
      ),
      ProgrammableBudgetStepStatus.partiallyExecuted => const _StatusVisual(
        AppColors.warning,
        Icons.timelapse_outlined,
      ),
      ProgrammableBudgetStepStatus.skipped => const _StatusVisual(
        AppColors.textSecondary,
        Icons.remove_circle_outline,
      ),
      ProgrammableBudgetStepStatus.blocked => const _StatusVisual(
        AppColors.danger,
        Icons.block_outlined,
      ),
      ProgrammableBudgetStepStatus.inactive => const _StatusVisual(
        AppColors.textSecondary,
        Icons.pause_circle_outline,
      ),
    };

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({
    required this.label,
    required this.color,
    required this.icon,
  });
  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .12),
      borderRadius: AppRadius.small,
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: AppSpacing.xxs),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _SimulationAmountRow extends StatelessWidget {
  const _SimulationAmountRow({
    required this.label,
    required this.value,
    this.color,
  });
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.xxs),
    child: Row(
      children: [
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: color ?? AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _DiagnosticLine extends StatelessWidget {
  const _DiagnosticLine(this.diagnostic);
  final ProgrammableBudgetDiagnostic diagnostic;

  @override
  Widget build(BuildContext context) {
    final visual = switch (diagnostic.severity) {
      ProgrammableBudgetDiagnosticSeverity.info => const _StatusVisual(
        AppColors.primary,
        Icons.info_outline,
      ),
      ProgrammableBudgetDiagnosticSeverity.warning => const _StatusVisual(
        AppColors.warning,
        Icons.warning_amber_outlined,
      ),
      ProgrammableBudgetDiagnosticSeverity.blocker => const _StatusVisual(
        AppColors.danger,
        Icons.error_outline,
      ),
    };
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(visual.icon, size: 16, color: visual.color),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              diagnostic.message,
              style: TextStyle(color: visual.color),
            ),
          ),
        ],
      ),
    );
  }
}

/// Affichage transparent : une étape partielle ne doit jamais paraître être
/// réduite à 100 % simplement parce que le pourcentage a été arrondi.
String formatReductionCoefficient(double coefficient) {
  final percentage = coefficient * 100;
  final twoDecimals = percentage.toStringAsFixed(2);
  if (coefficient < 1 && twoDecimals == '100.00') {
    return '${percentage.toStringAsFixed(4)} %';
  }
  return '$twoDecimals %';
}

class _SourceDialog extends ConsumerStatefulWidget {
  const _SourceDialog({required this.versionId, this.source});
  final String versionId;
  final BudgetSource? source;
  @override
  ConsumerState<_SourceDialog> createState() => _SourceDialogState();
}

class _SourceDialogState extends ConsumerState<_SourceDialog> {
  late final TextEditingController _name;
  late final TextEditingController _amount;
  late BudgetSourceType _type;
  late bool _active;
  String? _memberId;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.source?.name ?? '');
    _amount = TextEditingController(
      text: ((widget.source?.expectedCents ?? 0) / 100).toString(),
    );
    _type = widget.source?.type ?? BudgetSourceType.memberRecurringIncome;
    _active = widget.source?.active ?? true;
    _memberId = widget.source?.memberUserId;
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final members = ref.watch(remoteHouseholdMembersProvider);
    final needsMember =
        _type == BudgetSourceType.memberRecurringIncome ||
        _type == BudgetSourceType.memberOtherRecurringIncome;
    return AlertDialog(
      title: Text(
        widget.source == null ? 'Ajouter une source' : 'Modifier la source',
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Nom *'),
            onChanged: (_) => setState(() {}),
          ),
          DropdownButtonFormField<BudgetSourceType>(
            initialValue: _type,
            items: BudgetSourceType.values
                .where((value) => value != BudgetSourceType.commonCapacity)
                .map(
                  (value) => DropdownMenuItem(
                    value: value,
                    child: Text(_sourceLabel(value)),
                  ),
                )
                .toList(growable: false),
            onChanged: (value) => setState(() => _type = value!),
            decoration: const InputDecoration(labelText: 'Type'),
          ),
          if (needsMember)
            members.when(
              loading: () => const LinearProgressIndicator(),
              error: (_, _) => const Text('Membres indisponibles.'),
              data: (items) => DropdownButtonFormField<String>(
                initialValue: _memberId,
                items: items
                    .map(
                      (member) => DropdownMenuItem(
                        value: member.id,
                        child: Text(member.displayName),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) => setState(() => _memberId = value),
                decoration: const InputDecoration(labelText: 'Membre *'),
              ),
            ),
          TextField(
            controller: _amount,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Montant prévu (MAD)'),
          ),
          SwitchListTile(
            title: const Text('Active'),
            value: _active,
            onChanged: (value) => setState(() => _active = value),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed:
              _name.text.trim().isEmpty || (needsMember && _memberId == null)
              ? null
              : _save,
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final cents = _cents(_amount.text);
    if (cents == null || cents < 0) return;
    final repository = await ref.read(budgetSupabaseRepositoryProvider.future);
    await repository.saveSource(
      BudgetSource(
        id: widget.source?.id ?? '',
        scenarioVersionId: widget.versionId,
        type: _type,
        name: _name.text.trim(),
        expectedCents: cents,
        memberUserId: _memberId,
        exceptionalTreatment: widget.source?.exceptionalTreatment,
        active: _active,
      ),
    );
    if (mounted) {
      Navigator.pop(context, true);
    }
  }
}

class BudgetAllocationStepDialog extends ConsumerStatefulWidget {
  const BudgetAllocationStepDialog({
    super.key,
    required this.versionId,
    required this.scenarioId,
    required this.sources,
    required this.envelopes,
    required this.members,
    this.orderedSteps = const [],
    this.step,
    this.onSaved,
  });
  final String versionId;
  final String scenarioId;
  final List<BudgetSource> sources;
  final List<dynamic> envelopes;
  final List<dynamic> members;
  final List<BudgetAllocationStep> orderedSteps;
  final BudgetAllocationStep? step;
  final ValueChanged<BudgetAllocationStep>? onSaved;
  @override
  ConsumerState<BudgetAllocationStepDialog> createState() => _StepDialogState();
}

class _StepDialogState extends ConsumerState<BudgetAllocationStepDialog> {
  late final TextEditingController _group;
  late final TextEditingController _amount;
  late final TextEditingController _order;
  String? _sourceId;
  String? _envelopeId;
  late BudgetAllocationMethod _method;
  late ContributionKeyStrategy _key;
  late BudgetInsufficientFundsPolicy _policy;
  late bool _active;
  final _memberValues = <String, TextEditingController>{};
  final _selectedMemberIds = <String>{};
  String? _validationError;
  bool _isSaving = false;
  @override
  void initState() {
    super.initState();
    final step = widget.step;
    _group = TextEditingController(text: step?.groupName ?? 'Sans groupe');
    _amount = TextEditingController(
      text: step?.amountCents == null
          ? ''
          : (step!.amountCents! / 100).toString(),
    );
    final currentIndex = step == null
        ? widget.orderedSteps.length
        : widget.orderedSteps.indexWhere((item) => item.id == step.id);
    final position = currentIndex < 0
        ? (step?.order ?? widget.orderedSteps.length + 1)
        : currentIndex + 1;
    _order = TextEditingController(text: position.toString());
    _sourceId = step?.sourceId ?? widget.sources.firstOrNull?.id;
    _envelopeId = step?.envelopeId ?? widget.envelopes.firstOrNull?.id;
    _method = step?.method ?? BudgetAllocationMethod.fixed;
    _key =
        step?.contributionKey ??
        ContributionKeyStrategy.automaticRemainingCapacity;
    _policy =
        step?.insufficientFundsPolicy ?? BudgetInsufficientFundsPolicy.strict;
    _active = step?.active ?? true;
    _selectedMemberIds.addAll(
      step?.keyDefinition.keys.where((id) => id != 'members') ?? const [],
    );
    final configuredMembers = step?.keyDefinition['members'];
    if (configuredMembers is List) {
      _selectedMemberIds.addAll(configuredMembers.whereType<String>());
    }
    final previousDefinition = step?.keyDefinition ?? const <String, Object?>{};
    for (final entry in previousDefinition.entries) {
      if (entry.key != 'members') {
        _memberValues[entry.key] = TextEditingController(
          text: entry.value.toString(),
        );
      }
    }
  }

  @override
  void dispose() {
    _group.dispose();
    _amount.dispose();
    _order.dispose();
    for (final controller in _memberValues.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final memberIncomes = ref.watch(
      budgetScenarioMemberIncomesProvider(widget.scenarioId),
    );
    return AlertDialog(
      title: Text(
        widget.step == null ? 'Ajouter une étape' : 'Modifier l’étape',
      ),
      content: Theme(
        data: Theme.of(context).copyWith(
          inputDecorationTheme: Theme.of(context).inputDecorationTheme.copyWith(
            isDense: false,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: 14,
            ),
          ),
        ),
        child: SizedBox(
          width: 720,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _StepDialogSectionLabel('Identification'),
                const SizedBox(height: AppSpacing.xs),
                LayoutBuilder(
                  builder: (context, constraints) => Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      SizedBox(
                        width: constraints.maxWidth >= 580
                            ? (constraints.maxWidth - AppSpacing.sm) / 3
                            : constraints.maxWidth,
                        child: TextField(
                          controller: _order,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Position',
                            helperText:
                                'De 1 à ${widget.orderedSteps.length + (widget.step == null ? 1 : 0)}',
                          ),
                        ),
                      ),
                      SizedBox(
                        width: constraints.maxWidth >= 580
                            ? (constraints.maxWidth - AppSpacing.sm) * 2 / 3
                            : constraints.maxWidth,
                        child: TextField(
                          controller: _group,
                          decoration: const InputDecoration(
                            labelText: 'Groupe',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const _StepDialogDivider(),
                const _StepDialogSectionLabel('Allocation'),
                const SizedBox(height: AppSpacing.xs),
                DropdownButtonFormField<String>(
                  initialValue: _sourceId,
                  items: widget.sources
                      .map(
                        (source) => DropdownMenuItem(
                          value: source.id,
                          child: Text(source.name),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _sourceId = value),
                  decoration: const InputDecoration(labelText: 'Source'),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _envelopeId,
                  items: widget.envelopes
                      .map(
                        (envelope) => DropdownMenuItem(
                          value: envelope.id as String,
                          child: Text(envelope.name as String),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _envelopeId = value),
                  decoration: const InputDecoration(labelText: 'Enveloppe'),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<BudgetAllocationMethod>(
                  key: const Key('budget-step-method'),
                  initialValue: _method,
                  items:
                      const [
                            BudgetAllocationMethod.fixed,
                            BudgetAllocationMethod.percentage,
                            BudgetAllocationMethod.residual,
                          ]
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(_methodLabel(value)),
                            ),
                          )
                          .toList(),
                  onChanged: (value) => setState(() => _method = value!),
                  decoration: const InputDecoration(labelText: 'Méthode'),
                ),
                const SizedBox(height: 10),
                if (_method != BudgetAllocationMethod.residual)
                  TextField(
                    key: const Key('budget-step-value'),
                    controller: _amount,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: _method == BudgetAllocationMethod.percentage
                          ? 'Pourcentage'
                          : 'Montant (MAD)',
                    ),
                  ),
                if (_method != BudgetAllocationMethod.residual)
                  const SizedBox(height: 10),
                DropdownButtonFormField<ContributionKeyStrategy>(
                  key: const Key('budget-step-contribution-key'),
                  isExpanded: true,
                  initialValue: _key,
                  items: ContributionKeyStrategy.values
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(_keyLabel(value)),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _key = value!),
                  decoration: const InputDecoration(
                    labelText: 'Clé de contribution',
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: AppRadius.input,
                  ),
                  child: Text(
                    _keyExplanation(_key),
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ),
                if (_key == ContributionKeyStrategy.equal)
                  _memberConfiguration(
                    label: 'Membres concernés',
                    showPreview: true,
                  ),
                if (_key == ContributionKeyStrategy.fixedByMember)
                  _memberConfiguration(
                    label: 'Montant par membre (MAD)',
                    amountMode: true,
                  ),
                if (_key == ContributionKeyStrategy.customPercentage)
                  _memberConfiguration(
                    label: 'Pourcentage par membre',
                    percentageMode: true,
                  ),
                if (_key == ContributionKeyStrategy.automaticRemainingCapacity)
                  memberIncomes.when(
                    loading: () => const LinearProgressIndicator(),
                    error: (_, _) => const Text('Capacités indisponibles.'),
                    data: (incomes) {
                      final capacities = {
                        for (final income in incomes)
                          income.memberUserId: income.eligibleIncomeCents,
                      };
                      final total = capacities.values
                          .where((value) => value > 0)
                          .fold<int>(0, (sum, value) => sum + value);
                      if (total == 0) {
                        return const Text(
                          'Blocage : aucune capacité positive disponible.',
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Clé = capacité positive / somme des capacités positives.',
                          ),
                          ...widget.members.map((member) {
                            final capacity = capacities[member.id] ?? 0;
                            final share = capacity <= 0
                                ? 0
                                : capacity / total * 100;
                            return Text(
                              '${member.displayName} : ${_mad(capacity)} • ${share.toStringAsFixed(1)} %',
                            );
                          }),
                        ],
                      );
                    },
                  ),
                const _StepDialogDivider(),
                const _StepDialogSectionLabel('Politique'),
                const SizedBox(height: AppSpacing.xs),
                DropdownButtonFormField<BudgetInsufficientFundsPolicy>(
                  initialValue: _policy,
                  items: BudgetInsufficientFundsPolicy.values
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(_policyLabel(value)),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _policy = value!),
                  decoration: const InputDecoration(
                    labelText: 'Si les fonds sont insuffisants',
                  ),
                ),
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: AppSpacing.xs),
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: AppRadius.input,
                  ),
                  child: Text(
                    _policyExplanation(_policy),
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ),
                if (_validationError != null)
                  Text(
                    _validationError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if (_isSaving) ...[
                  const SizedBox(height: AppSpacing.sm),
                  const _ReorderFeedback(
                    key: Key('budget-step-dialog-reordering-feedback'),
                    label: 'Réorganisation en cours…',
                  ),
                ],
                const _StepDialogDivider(),
                const _StepDialogSectionLabel('État'),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active'),
                  value: _active,
                  onChanged: (value) => setState(() => _active = value),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed:
              _isSaving ||
                  _sourceId == null ||
                  _envelopeId == null ||
                  _group.text.trim().isEmpty ||
                  (_key == ContributionKeyStrategy.customPercentage &&
                      _customPercentageError() != null)
              ? null
              : _save,
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }

  Widget _memberConfiguration({
    required String label,
    bool amountMode = false,
    bool percentageMode = false,
    bool showPreview = false,
  }) {
    final selected = widget.members
        .where((member) => _selectedMemberIds.contains(member.id))
        .toList(growable: false);
    final total = _cents(_amount.text) ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        ...widget.members.map((member) {
          final controller = _memberValues.putIfAbsent(
            member.id,
            () => TextEditingController(),
          );
          return Column(
            children: [
              CheckboxListTile(
                key: Key('budget-step-member-${member.id}'),
                value: _selectedMemberIds.contains(member.id),
                title: Text(member.displayName),
                onChanged: (selected) => setState(() {
                  if (selected ?? false) {
                    _selectedMemberIds.add(member.id);
                  } else {
                    _selectedMemberIds.remove(member.id);
                  }
                }),
              ),
              if ((amountMode || percentageMode) &&
                  _selectedMemberIds.contains(member.id))
                TextField(
                  key: Key('budget-step-member-value-${member.id}'),
                  controller: controller,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: percentageMode ? '%' : 'MAD',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
            ],
          );
        }),
        if (showPreview && selected.isNotEmpty)
          Text(
            'Montant total : ${_mad(total)} • ${selected.length} membres → ${_mad(total ~/ selected.length)} chacun',
          ),
        if (percentageMode) ...[
          Text(
            'Total de la clé : ${_customPercentageTotal().toStringAsFixed(2)} %',
          ),
          if (_customPercentageError() != null)
            Text(
              _customPercentageError()!,
              key: const Key('budget-step-custom-percentage-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ],
    );
  }

  double _customPercentageTotal() => _selectedMemberIds.fold<double>(
    0,
    (sum, id) =>
        sum +
        (double.tryParse(_memberValues[id]?.text.replaceAll(',', '.') ?? '') ??
            0),
  );

  String? _customPercentageError() => _customPercentageValidation(
    _selectedMemberIds.map((id) => _memberValues[id]?.text ?? ''),
  );

  int get _maximumPosition => widget.orderedSteps.isEmpty
      ? (widget.step == null
            ? 1
            : (widget.step!.order < 1 ? 1 : widget.step!.order))
      : widget.orderedSteps.length + (widget.step == null ? 1 : 0);

  Future<void> _save() async {
    final positionText = _order.text.trim();
    final requestedPosition = int.tryParse(positionText);
    final amount = _method == BudgetAllocationMethod.percentage
        ? null
        : _cents(_amount.text);
    final percentage = _method == BudgetAllocationMethod.percentage
        ? double.tryParse(_amount.text.replaceAll(',', '.'))
        : null;
    final keyDefinition = <String, Object?>{
      if (_key == ContributionKeyStrategy.equal)
        'members': _selectedMemberIds.toList(growable: false),
      if (_key == ContributionKeyStrategy.fixedByMember ||
          _key == ContributionKeyStrategy.customPercentage)
        for (final id in _selectedMemberIds)
          id: _key == ContributionKeyStrategy.fixedByMember
              ? _cents(_memberValues[id]?.text ?? '')
              : double.tryParse(
                  (_memberValues[id]?.text ?? '').replaceAll(',', '.'),
                ),
    };
    String? error;
    if (!RegExp(r'^[1-9]\d*$').hasMatch(positionText) ||
        requestedPosition == null ||
        requestedPosition > _maximumPosition) {
      error = 'Saisissez une position entière entre 1 et $_maximumPosition.';
    }
    if (error == null &&
            (_method == BudgetAllocationMethod.fixed &&
                (amount == null || amount <= 0)) ||
        (_method == BudgetAllocationMethod.percentage &&
            (percentage == null || percentage < 0 || percentage > 100))) {
      error = 'La valeur indiquée est invalide.';
    } else if (error == null &&
        _key == ContributionKeyStrategy.equal &&
        _selectedMemberIds.isEmpty) {
      error = 'Sélectionnez au moins un membre.';
    } else if (error == null &&
        _key == ContributionKeyStrategy.fixedByMember &&
        (_selectedMemberIds.isEmpty ||
            keyDefinition.values.whereType<int?>().any(
              (value) => value == null,
            ) ||
            (amount ?? 0) !=
                keyDefinition.values.whereType<int>().fold<int>(
                  0,
                  (sum, value) => sum + value,
                ))) {
      error = 'Les montants par membre doivent égaler le montant de l’étape.';
    } else if (error == null &&
        _key == ContributionKeyStrategy.customPercentage &&
        _customPercentageError() != null) {
      error = _customPercentageError();
    }
    if (error != null) {
      setState(() => _validationError = error);
      return;
    }
    final position = requestedPosition;
    if (position == null) return;
    final selectedSource = widget.sources
        .where((source) => source.id == _sourceId)
        .firstOrNull;
    final memberUserId = _key == ContributionKeyStrategy.singleMember
        ? selectedSource?.memberUserId
        : widget.step?.memberUserId;
    if (_key == ContributionKeyStrategy.singleMember && memberUserId == null) {
      setState(() {
        _validationError =
            'Une charge personnelle doit utiliser une source liée à un membre.';
      });
      return;
    }
    final updated = BudgetAllocationStep(
      id: widget.step?.id ?? '',
      scenarioVersionId: widget.versionId,
      // Updating a step must not briefly collide with another persisted row.
      // The requested visible position is applied atomically by reorderSteps.
      order: widget.step?.order ?? 1000000 + position,
      groupName: _group.text.trim(),
      sourceId: _sourceId!,
      envelopeId: _envelopeId!,
      method: _method,
      contributionKey: _key,
      insufficientFundsPolicy: _policy,
      amountCents: _method == BudgetAllocationMethod.residual ? null : amount,
      percentage: percentage,
      memberUserId: memberUserId,
      keyDefinition: keyDefinition.isEmpty
          ? widget.step?.keyDefinition ?? const {}
          : keyDefinition,
      fundingSourcePreference: widget.step?.fundingSourcePreference,
      active: _active,
    );
    try {
      setState(() => _isSaving = true);
      if (widget.onSaved != null) {
        widget.onSaved!(_withOrder(updated, position));
      } else {
        final repository = await ref.read(
          budgetSupabaseRepositoryProvider.future,
        );
        final savedId = await repository.saveStep(updated);
        if (savedId == null || savedId.isEmpty) {
          throw StateError('L’étape n’a pas pu être enregistrée.');
        }
        final saved = _withOrder(updated, position, id: savedId);
        final withoutSaved = widget.orderedSteps
            .where((item) => item.id != savedId)
            .toList(growable: true);
        final insertAt = position - 1;
        final currentIndex = widget.orderedSteps.indexWhere(
          (item) => item.id == savedId,
        );
        if (currentIndex != insertAt) {
          withoutSaved.insert(insertAt, saved);
          await repository.reorderSteps(withoutSaved);
        }
      }
      if (mounted) {
        if (widget.onSaved == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ordre enregistré'),
              duration: Duration(seconds: 3),
            ),
          );
        }
        Navigator.pop(context, widget.onSaved == null ? true : updated);
      }
    } catch (error) {
      ref.invalidate(budgetScenarioStepsProvider(widget.versionId));
      if (mounted) {
        setState(
          () => _validationError =
              'Réorganisation impossible. Vérifiez votre connexion puis réessayez.',
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}

class _StepDialogSectionLabel extends StatelessWidget {
  const _StepDialogSectionLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label.toUpperCase(),
    style: Theme.of(context).textTheme.labelLarge?.copyWith(
      color: AppColors.primary,
      letterSpacing: .7,
    ),
  );
}

class _StepDialogDivider extends StatelessWidget {
  const _StepDialogDivider();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
    child: Divider(height: 1),
  );
}

String _sourceLabel(BudgetSourceType value) => switch (value) {
  BudgetSourceType.memberRecurringIncome => 'Salaire récurrent',
  BudgetSourceType.memberOtherRecurringIncome => 'Autre revenu récurrent',
  BudgetSourceType.exceptionalIncome => 'Revenu exceptionnel',
  BudgetSourceType.commonCapacity => 'Capacité commune',
  BudgetSourceType.availableSavings => 'Épargne disponible',
  BudgetSourceType.other => 'Autre source',
};
String _methodLabel(BudgetAllocationMethod value) => switch (value) {
  BudgetAllocationMethod.fixed => 'Montant fixe',
  BudgetAllocationMethod.percentage => 'Pourcentage',
  BudgetAllocationMethod.residual => 'Reste',
  _ => 'Méthode',
};
String _stepValueLabel(BudgetAllocationStep step) => switch (step.method) {
  BudgetAllocationMethod.fixed =>
    'Montant fixe : ${_mad(step.amountCents ?? 0)}',
  BudgetAllocationMethod.percentage =>
    'Pourcentage : ${(step.percentage ?? 0).toStringAsFixed(1)} %',
  BudgetAllocationMethod.residual => 'Affecter le reste disponible',
  _ => _methodLabel(step.method),
};
String _keyLabel(ContributionKeyStrategy value) => switch (value) {
  ContributionKeyStrategy.automaticRemainingCapacity =>
    'Répartition automatique selon la capacité',
  ContributionKeyStrategy.customPercentage => 'Pourcentages personnalisés',
  ContributionKeyStrategy.fixedByMember => 'Montant fixe par membre',
  ContributionKeyStrategy.singleMember => 'Un membre',
  ContributionKeyStrategy.equal => 'Répartition égale',
};
String _keyExplanation(ContributionKeyStrategy value) => switch (value) {
  ContributionKeyStrategy.automaticRemainingCapacity =>
    'La capacité correspond aux revenus retenus moins les charges directes.',
  ContributionKeyStrategy.customPercentage =>
    'Les pourcentages doivent totaliser exactement 100 %.',
  ContributionKeyStrategy.fixedByMember =>
    'La somme des montants doit égaler le montant de l’étape.',
  ContributionKeyStrategy.singleMember => 'Un seul membre finance cette étape.',
  ContributionKeyStrategy.equal =>
    'Le montant est réparti à parts égales entre les membres sélectionnés.',
};
String _policyLabel(BudgetInsufficientFundsPolicy value) => switch (value) {
  BudgetInsufficientFundsPolicy.strict => 'Bloquer',
  BudgetInsufficientFundsPolicy.cap => 'Utiliser le disponible',
  BudgetInsufficientFundsPolicy.skip => 'Ignorer si insuffisant',
  BudgetInsufficientFundsPolicy.proportional => 'Réduire proportionnellement',
};
String _policyExplanation(BudgetInsufficientFundsPolicy value) =>
    switch (value) {
      BudgetInsufficientFundsPolicy.strict =>
        'Bloque la validation si les ressources ne couvrent pas le montant.',
      BudgetInsufficientFundsPolicy.cap =>
        'Utilise uniquement le montant encore disponible.',
      BudgetInsufficientFundsPolicy.skip =>
        'Ignore cette étape si les ressources sont insuffisantes.',
      BudgetInsufficientFundsPolicy.proportional =>
        'Réduit l’allocation en fonction des ressources disponibles.',
    };
String _stepStatusLabel(ProgrammableBudgetStepStatus value) => switch (value) {
  ProgrammableBudgetStepStatus.executed => 'Exécutée',
  ProgrammableBudgetStepStatus.partiallyExecuted => 'Exécutée partiellement',
  ProgrammableBudgetStepStatus.skipped => 'Ignorée',
  ProgrammableBudgetStepStatus.blocked => 'Bloquée',
  ProgrammableBudgetStepStatus.inactive => 'Inactive',
};
String _mad(int cents) => '${(cents / 100).toStringAsFixed(2)} MAD';
int? _cents(String input) {
  final value = double.tryParse(input.trim().replaceAll(',', '.'));
  return value == null ? null : (value * 100).round();
}

BudgetAllocationStep _withOrder(
  BudgetAllocationStep step,
  int order, {
  String? id,
}) => BudgetAllocationStep(
  id: id ?? step.id,
  scenarioVersionId: step.scenarioVersionId,
  order: order,
  groupName: step.groupName,
  sourceId: step.sourceId,
  envelopeId: step.envelopeId,
  method: step.method,
  contributionKey: step.contributionKey,
  insufficientFundsPolicy: step.insufficientFundsPolicy,
  amountCents: step.amountCents,
  percentage: step.percentage,
  memberUserId: step.memberUserId,
  keyDefinition: step.keyDefinition,
  fundingSourcePreference: step.fundingSourcePreference,
  active: step.active,
);

BudgetAllocationStep _withActive(BudgetAllocationStep step, bool active) =>
    BudgetAllocationStep(
      id: step.id,
      scenarioVersionId: step.scenarioVersionId,
      order: step.order,
      groupName: step.groupName,
      sourceId: step.sourceId,
      envelopeId: step.envelopeId,
      method: step.method,
      contributionKey: step.contributionKey,
      insufficientFundsPolicy: step.insufficientFundsPolicy,
      amountCents: step.amountCents,
      percentage: step.percentage,
      memberUserId: step.memberUserId,
      keyDefinition: step.keyDefinition,
      fundingSourcePreference: step.fundingSourcePreference,
      active: active,
    );

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
