import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_design_system.dart';
import '../application/cutover_preparation.dart';
import '../application/cutover_opening_import.dart';
import '../application/workbook_import.dart';
import 'cutover_preparation_card.dart';

class ImportPreviewPage extends ConsumerStatefulWidget {
  const ImportPreviewPage({super.key});

  @override
  ConsumerState<ImportPreviewPage> createState() => _ImportPreviewPageState();
}

class _ImportPreviewPageState extends ConsumerState<ImportPreviewPage> {
  late final TextEditingController _googleSheetController;
  CutoverOpeningPlan? _cutoverPlan;
  Map<String, dynamic>? _cutoverResult;
  String? _cutoverError;
  String? _selectedCutoverHouseholdId;
  var _executingCutover = false;
  var _preparingCutover = false;
  var _preparationHasLocalChanges = false;
  var _allowPop = false;

  @override
  void initState() {
    super.initState();
    _googleSheetController = TextEditingController();
  }

  @override
  void dispose() {
    _googleSheetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(workbookImportProvider);
    final controller = ref.read(workbookImportProvider.notifier);
    final cutoverHouseholds = ref.watch(cutoverEligibleHouseholdsProvider);
    final analysis = state.analysis;
    final selectedPreviews =
        analysis?.previewsFor(state.selectedImporterIds) ?? const [];
    final isRealCutoverSource =
        analysis != null &&
        const CutoverPreparationBuilder().isRealCutoverSource(analysis);
    final blockingSelected = selectedPreviews
        .where((preview) => !preview.canBeConfirmed)
        .toList(growable: false);
    final currentStep = analysis == null
        ? 0
        : state.selectedImporterIds.isEmpty
        ? 1
        : blockingSelected.isNotEmpty
        ? 2
        : 3;

    return PopScope<Object?>(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop && await _confirmLeave(controller) && mounted) {
          setState(() => _allowPop = true);
          Navigator.of(this.context).pop();
        }
      },
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.xl,
          ),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    isRealCutoverSource
                        ? 'Préparation du cutover réel'
                        : 'Importer mon fichier Excel',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                TextButton.icon(
                  key: const Key('exit-import-assistant-button'),
                  onPressed: () => _exitAssistant(controller),
                  icon: const Icon(Icons.close_outlined),
                  label: const Text('Quitter'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            _NoticeCard(
              icon: Icons.info_outline,
              color: const Color(0xFFEEF1F4),
              message: isRealCutoverSource
                  ? 'Source reconnue pour la préparation du cutover réel. Cette revue locale ne sélectionne ni n’archive aucun onglet.'
                  : 'Parcourez le fichier, contrôlez les données et confirmez uniquement ce que vous souhaitez préparer.',
            ),
            const SizedBox(height: AppSpacing.md),
            if (!isRealCutoverSource) _ProgressCard(currentStep: currentStep),
            if (state.loadingProgress case final progress?) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(value: progress.clamp(0, 1).toDouble()),
              const SizedBox(height: 6),
              Text(state.loadingMessage ?? 'Preparation de l import...'),
            ],
            const SizedBox(height: 20),
            _ActionCard(
              icon: Icons.upload_file_rounded,
              title: '1. Choisir votre fichier',
              body:
                  'Selectionnez votre fichier Excel. Il est lu avant tout import.',
              action: FilledButton.icon(
                onPressed: state.isPicking ? null : controller.chooseWorkbook,
                icon: const Icon(Icons.folder_open_outlined),
                label: Text(
                  state.isPicking
                      ? 'Lecture du fichier en cours...'
                      : 'Choisir mon fichier Excel',
                ),
              ),
            ),
            const SizedBox(height: 12),
            _ActionCard(
              icon: Icons.link_rounded,
              title: 'Ou importer depuis Google Sheets',
              body:
                  'Collez le lien de votre Google Sheet. Le document doit etre partage avec ce lien ou accessible a votre compte Google.',
              action: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _googleSheetController,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: 'Lien Google Sheets',
                      hintText: 'https://docs.google.com/spreadsheets/d/...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: state.isLoadingGoogleSheet
                        ? null
                        : () => controller.loadGoogleSheet(
                            _googleSheetController.text,
                          ),
                    icon: const Icon(Icons.cloud_download_outlined),
                    label: Text(
                      state.isLoadingGoogleSheet
                          ? (state.loadingMessage ??
                                'Lecture du Google Sheet en cours...')
                          : 'Lire ce Google Sheet',
                    ),
                  ),
                ],
              ),
            ),
            if (state.error case final error?) ...[
              const SizedBox(height: 12),
              _NoticeCard(
                icon: Icons.error_outline,
                color: Theme.of(context).colorScheme.errorContainer,
                message: error,
              ),
            ],
            if (analysis case final analysis?) ...[
              const SizedBox(height: 16),
              if (isRealCutoverSource) ...[
                CutoverPreparationCard(
                  key: ValueKey(
                    'cutover-preparation-${analysis.sourceFingerprint}',
                  ),
                  analysis: analysis,
                  onDirtyChanged: (value) =>
                      _preparationHasLocalChanges = value,
                ),
                const SizedBox(height: 16),
              ],
              _ActionCard(
                icon: Icons.checklist_rounded,
                title: isRealCutoverSource
                    ? 'Archivage optionnel des onglets'
                    : '2. Choisir ce que vous voulez importer',
                body: isRealCutoverSource
                    ? 'Ce mécanisme historique est distinct du cutover réel. Journal, scénarios et simulations ne sont pas nécessaires pour préparer les positions d’ouverture.'
                    : '${analysis.fileName} est pret. Cochez uniquement les onglets que vous souhaitez conserver.',
                action: isRealCutoverSource
                    ? const Text(
                        'Aucun onglet n’est requis pour cette préparation. Ouvrez cette section uniquement si vous souhaitez utiliser l’archivage séparé.',
                      )
                    : Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${state.selectedImporterIds.length} onglet(s) choisi(s) sur ${analysis.sheetPreviews.length}',
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: controller.selectAllSheets,
                            icon: const Icon(Icons.select_all_rounded),
                            label: const Text('Selectionner tout'),
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: 8),
              if (isRealCutoverSource)
                _OptionalArchiveSheets(
                  child: _buildSheetPreviews(
                    analysis: analysis,
                    state: state,
                    controller: controller,
                  ),
                )
              else
                _buildSheetPreviews(
                  analysis: analysis,
                  state: state,
                  controller: controller,
                ),
              if (!isRealCutoverSource ||
                  state.selectedImporterIds.isNotEmpty) ...[
                const SizedBox(height: 16),
                _ActionCard(
                  icon: Icons.health_and_safety_outlined,
                  title: isRealCutoverSource
                      ? 'Vérifier l’archivage sélectionné'
                      : '3. Verifier puis confirmer',
                  body: blockingSelected.isEmpty
                      ? isRealCutoverSource
                            ? 'Cette confirmation concerne uniquement l’archivage d’onglets, jamais le cutover réel.'
                            : 'Les onglets choisis sont prets. Vous gardez le controle jusqu a la confirmation.'
                      : '${blockingSelected.length} onglet(s) choisi(s) demandent votre attention.',
                  action: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      OutlinedButton.icon(
                        onPressed: blockingSelected.isEmpty
                            ? null
                            : () => _showProblemsDialog(
                                context: context,
                                previews: blockingSelected,
                                onSelectOnlyValid:
                                    controller.selectOnlyValidSheets,
                              ),
                        icon: const Icon(Icons.help_outline_rounded),
                        label: Text(
                          'M aider a resoudre les problemes (${blockingSelected.length})',
                        ),
                      ),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed:
                            analysis.canConfirmSelection(
                                  state.selectedImporterIds,
                                ) &&
                                !state.isConfirmed
                            ? controller.confirmAnalysis
                            : null,
                        icon: const Icon(Icons.verified_outlined),
                        label: Text(
                          state.isConfirmed
                              ? 'Onglets confirmes'
                              : 'Confirmer mes choix',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (state.isConfirmed) ...[
                const SizedBox(height: 12),
                _NoticeCard(
                  icon: Icons.check_circle_outline,
                  color: Theme.of(context).colorScheme.primaryContainer,
                  message:
                      'Vos choix sont confirmes. L archivage sera realise apres l activation du foyer Supabase.',
                ),
                const SizedBox(height: 12),
                _buildCutoverSection(
                  analysis: analysis,
                  selectedImporterIds: state.selectedImporterIds,
                  cutoverHouseholds: cutoverHouseholds,
                ),
              ],
              if (!isRealCutoverSource ||
                  state.lastImportSessionId != null) ...[
                const SizedBox(height: 16),
                _ActionCard(
                  icon: Icons.undo_rounded,
                  title: isRealCutoverSource
                      ? 'Annuler le dernier archivage'
                      : 'Besoin de revenir en arriere ?',
                  body:
                      'Le dernier import termine pourra etre annule sans effacer son historique.',
                  action: OutlinedButton.icon(
                    onPressed: state.lastImportSessionId == null
                        ? null
                        : () => _showUndoDialog(context, controller),
                    icon: const Icon(Icons.undo_outlined),
                    label: Text(
                      isRealCutoverSource
                          ? 'Annuler le dernier archivage'
                          : 'Annuler le dernier import',
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('back-to-file-step-button'),
                onPressed: () => _returnToFileStep(controller),
                icon: const Icon(Icons.arrow_back_outlined),
                label: const Text('Retour au choix du fichier'),
              ),
            ],
            const SizedBox(height: 20),
            TextButton.icon(
              key: const Key('quit-import-assistant-bottom-button'),
              onPressed: () => _exitAssistant(controller),
              icon: const Icon(Icons.close_outlined),
              label: const Text('Quitter l’assistant'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSheetPreviews({
    required WorkbookImportAnalysis analysis,
    required WorkbookImportState state,
    required WorkbookImportController controller,
  }) => Column(
    children: [
      ...analysis.sheetPreviews.map(
        (preview) => _SheetPreviewCard(
          preview: preview,
          selected: state.selectedImporterIds.contains(preview.importerId),
          onSelected: (selected) =>
              controller.toggleSheet(preview.importerId, selected),
        ),
      ),
      if (analysis.unhandledSheetNames.isNotEmpty)
        _NoticeCard(
          icon: Icons.warning_amber_rounded,
          color: Theme.of(context).colorScheme.tertiaryContainer,
          message:
              'Ces onglets ne sont pas encore reconnus : ${analysis.unhandledSheetNames.join(', ')}',
        ),
    ],
  );

  Future<bool> _confirmLeave(WorkbookImportController controller) async {
    final hasLocalWork =
        _preparationHasLocalChanges ||
        ref.read(workbookImportProvider).analysis != null;
    if (!hasLocalWork) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.info_outline),
        title: const Text('Quitter l’assistant ?'),
        content: const Text(
          'La prévisualisation et les confirmations locales seront abandonnées. Aucune écriture financière n’a été créée.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Rester'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Quitter sans enregistrer'),
          ),
        ],
      ),
    );
    if (discard == true) {
      controller.abandonPreparation();
      _preparationHasLocalChanges = false;
      return true;
    }
    return false;
  }

  Future<void> _exitAssistant(WorkbookImportController controller) async {
    if (await _confirmLeave(controller) && mounted) {
      setState(() => _allowPop = true);
      Navigator.of(context).pop();
    }
  }

  Future<void> _returnToFileStep(WorkbookImportController controller) async {
    if (await _confirmLeave(controller) && mounted) {
      controller.abandonPreparation();
      setState(() {
        _cutoverPlan = null;
        _cutoverResult = null;
        _cutoverError = null;
        _selectedCutoverHouseholdId = null;
        _preparationHasLocalChanges = false;
      });
    }
  }

  Widget _buildCutoverSection({
    required WorkbookImportAnalysis analysis,
    required Set<String> selectedImporterIds,
    required AsyncValue<List<CutoverEligibleHousehold>> cutoverHouseholds,
  }) {
    final hasOpeningSheet = selectedImporterIds.contains(
      'cutover-opening-positions',
    );
    final plan = _cutoverPlan;
    final households = cutoverHouseholds.valueOrNull ?? const [];
    final selectedHousehold = households
        .where((household) => household.id == _selectedCutoverHouseholdId)
        .firstOrNull;
    return _ActionCard(
      icon: Icons.account_balance_outlined,
      title: '4. Plan de positions d’ouverture B1',
      body: hasOpeningSheet
          ? 'Le plan cible est explicite, auditable et exécute seulement les RPC canoniques Cutover A.'
          : 'Sélectionnez l’onglet « Positions ouverture » pour préparer le cutover B1.',
      action: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (cutoverHouseholds.hasError)
            const Text('Impossible de charger les households éligibles.'),
          if (cutoverHouseholds.isLoading) const LinearProgressIndicator(),
          if (!cutoverHouseholds.isLoading && !cutoverHouseholds.hasError)
            DropdownButtonFormField<String>(
              key: const Key('cutover-household-selector'),
              initialValue: _selectedCutoverHouseholdId,
              decoration: const InputDecoration(
                labelText: 'Household cible',
                border: OutlineInputBorder(),
              ),
              items: households
                  .where((household) => household.isOperational)
                  .map(
                    (household) => DropdownMenuItem(
                      value: household.id,
                      child: Text(
                        '${household.name} — ${household.classificationLabel}',
                      ),
                    ),
                  )
                  .toList(growable: false),
              onChanged: plan?.confirmedAt != null
                  ? null
                  : (householdId) => setState(() {
                      _selectedCutoverHouseholdId = householdId;
                      _cutoverPlan = null;
                      _cutoverResult = null;
                      _cutoverError = null;
                    }),
            ),
          if (selectedHousehold != null) ...[
            const SizedBox(height: 8),
            Text('Classification : ${selectedHousehold.classificationLabel}'),
            Text(
              !selectedHousehold.isOperational
                  ? 'ENVIRONNEMENT TECHNIQUE'
                  : 'ENVIRONNEMENT OPÉRATIONNEL',
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ],
          Text('Fingerprint source : ${analysis.sourceFingerprint}'),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('cutover-plan-button'),
            onPressed:
                !hasOpeningSheet ||
                    selectedHousehold == null ||
                    _preparingCutover
                ? null
                : () => _prepareCutover(analysis, selectedHousehold),
            icon: const Icon(Icons.preview_outlined),
            label: Text(
              _preparingCutover ? 'Recherche du run...' : 'Préparer le plan B1',
            ),
          ),
          if (plan != null) ...[
            const SizedBox(height: 10),
            Text(
              'Date effective : ${CutoverOpeningPlan.formatDate(plan.effectiveDate)}',
            ),
            if (selectedHousehold != null) ...[
              Text('Household cible : ${selectedHousehold.name}'),
              Text('Classification : ${selectedHousehold.classificationLabel}'),
            ],
            Text(
              'Comptes : ${plan.accounts.length} • Enveloppes : ${plan.envelopes.length}',
            ),
            ...plan.accounts.map(
              (item) => Text('${item.name} • ${item.openingAmount} MAD'),
            ),
            ...plan.envelopes.map(
              (item) => Text(
                '${item.name}${item.isToAllocate ? ' (À répartir)' : ''} • ${item.openingAmount} MAD',
              ),
            ),
            if (plan.blockingErrors.isNotEmpty) ...[
              const SizedBox(height: 6),
              ...plan.blockingErrors.map((error) => Text(error)),
            ],
            if (plan.confirmedAt == null)
              FilledButton.icon(
                key: const Key('cutover-confirm-button'),
                onPressed: plan.canConfirm
                    ? () => setState(
                        () => _cutoverPlan = plan.confirm(DateTime.now()),
                      )
                    : null,
                icon: const Icon(Icons.verified_outlined),
                label: const Text('Confirmer ce plan'),
              )
            else ...[
              const SizedBox(height: 8),
              FilledButton.icon(
                key: const Key('cutover-execute-button'),
                onPressed: _executingCutover
                    ? null
                    : () => _executeCutover(analysis, plan),
                icon: _executingCutover
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow_rounded),
                label: Text(
                  _executingCutover
                      ? 'Exécution...'
                      : 'Exécuter et réconcilier',
                ),
              ),
            ],
          ],
          if (_cutoverError case final error?) ...[
            const SizedBox(height: 8),
            Text(error),
          ],
          if (_cutoverResult case final result?) ...[
            const SizedBox(height: 8),
            Text(
              result['status'] == 'RECONCILED'
                  ? 'RECONCILED — écart zéro.'
                  : 'NOT_RECONCILED',
            ),
            Text(
              'Événements : ${result['financial_events']} • transactions GL : ${result['gl_transactions']} • mouvements enveloppes : ${result['envelope_movements']}',
            ),
            ...((result['accounts'] as List<dynamic>? ?? const []).map((item) {
              final value = Map<String, dynamic>.from(item as Map);
              return Text(
                '${value['name']} : attendu ${value['expected']} / réel ${value['actual']} / écart ${value['difference']}',
              );
            })),
            ...((result['envelopes'] as List<dynamic>? ?? const []).map((item) {
              final value = Map<String, dynamic>.from(item as Map);
              return Text(
                '${value['name']} : attendu ${value['expected']} / réel ${value['actual']} / écart ${value['difference']}',
              );
            })),
          ],
        ],
      ),
    );
  }

  Future<void> _executeCutover(
    WorkbookImportAnalysis analysis,
    CutoverOpeningPlan plan,
  ) async {
    // The source is re-read here; Google Sheets is downloaded again. Preview
    // bytes are never accepted as execution proof.
    final sourceCheck = await ref
        .read(workbookImportProvider.notifier)
        .verifyConfirmedSource(plan.sourceFingerprint);
    if (!sourceCheck.isMatch) {
      setState(() => _cutoverError = sourceCheck.error);
      return;
    }
    setState(() {
      _executingCutover = true;
      _cutoverError = null;
    });
    try {
      final result = await ref
          .read(cutoverOpeningImportRepositoryProvider)
          .execute(plan);
      if (!mounted) return;
      setState(() => _cutoverResult = result);
    } catch (error) {
      if (!mounted) return;
      setState(() => _cutoverError = 'Exécution B1 refusée : $error');
    } finally {
      if (mounted) setState(() => _executingCutover = false);
    }
  }

  Future<void> _prepareCutover(
    WorkbookImportAnalysis analysis,
    CutoverEligibleHousehold household,
  ) async {
    setState(() {
      _preparingCutover = true;
      _cutoverError = null;
      _cutoverResult = null;
    });
    try {
      final effectiveDate = DateTime.now();
      final existing = await ref
          .read(cutoverOpeningImportRepositoryProvider)
          .findExisting(
            householdId: household.id,
            sourceFingerprint: analysis.sourceFingerprint,
            effectiveDate: effectiveDate,
          );
      if (!mounted) return;
      setState(() {
        if (existing != null) {
          _cutoverPlan = CutoverOpeningPlan.fromJson(
            Map<String, dynamic>.from(existing['plan'] as Map),
          );
          _cutoverResult = Map<String, dynamic>.from(existing['result'] as Map);
        } else {
          _cutoverPlan = CutoverOpeningPlanBuilder().build(
            analysis: analysis,
            householdId: household.id,
            effectiveDate: effectiveDate,
          );
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _cutoverError = 'Impossible de retrouver le run B1 : $error',
      );
    } finally {
      if (mounted) setState(() => _preparingCutover = false);
    }
  }

  Future<void> _showProblemsDialog({
    required BuildContext context,
    required List<SheetImportPreview> previews,
    required VoidCallback onSelectOnlyValid,
  }) => showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(Icons.help_outline_rounded),
      title: const Text('Comment resoudre ces problemes ?'),
      content: SizedBox(
        width: 580,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Deux choix simples : corriger le fichier Excel puis le relire, ou retirer temporairement les onglets concernes.',
              ),
              const SizedBox(height: 16),
              ...previews.map((preview) => _ProblemsForSheet(preview: preview)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Je vais corriger le fichier'),
        ),
        FilledButton(
          onPressed: () {
            onSelectOnlyValid();
            Navigator.of(dialogContext).pop();
          },
          child: const Text('Importer seulement les onglets valides'),
        ),
      ],
    ),
  );

  Future<void> _showUndoDialog(
    BuildContext context,
    WorkbookImportController controller,
  ) => showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(Icons.undo_rounded),
      title: const Text('Annuler le dernier import'),
      content: const Text(
        'Les donnees source seront archivees et l historique restera disponible. Un motif sera demande lorsque le foyer Supabase sera actif.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Conserver'),
        ),
        FilledButton(
          onPressed: () {
            controller.clearLastImport();
            Navigator.of(dialogContext).pop();
          },
          child: const Text('Annuler l import'),
        ),
      ],
    ),
  );
}

class _ProblemsForSheet extends StatelessWidget {
  const _ProblemsForSheet({required this.preview});

  final SheetImportPreview preview;

  @override
  Widget build(BuildContext context) {
    final problems = preview.problems;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            preview.sourceSheetName,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 6),
          if (problems.isEmpty)
            Text(
              preview.issues
                  .where(
                    (issue) => issue.severity == ImportIssueSeverity.blocking,
                  )
                  .map((issue) => '• ${issue.message}')
                  .join('\n'),
            )
          else
            ...problems.map(
              (problem) => Card(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Padding(
                  padding: AppSpacing.card,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ligne ${problem.rowNumber} - ${problem.field}',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(problem.explanation),
                      const SizedBox(height: 6),
                      Text('Pour corriger : ${problem.correctionHint}'),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.currentStep});

  final int currentStep;

  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.secondaryContainer,
    child: Padding(
      padding: AppSpacing.card,
      child: Row(
        children: [
          _ProgressStep(
            number: '1',
            label: 'Fichier',
            active: currentStep >= 0,
          ),
          const Expanded(child: Divider()),
          _ProgressStep(number: '2', label: 'Choix', active: currentStep >= 1),
          const Expanded(child: Divider()),
          _ProgressStep(
            number: '3',
            label: 'Verification',
            active: currentStep >= 2,
          ),
          const Expanded(child: Divider()),
          _ProgressStep(
            number: '4',
            label: 'Confirmation',
            active: currentStep >= 3,
          ),
        ],
      ),
    ),
  );
}

class _ProgressStep extends StatelessWidget {
  const _ProgressStep({
    required this.number,
    required this.label,
    required this.active,
  });

  final String number;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      CircleAvatar(
        radius: 16,
        backgroundColor: active
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        foregroundColor: active
            ? Theme.of(context).colorScheme.onPrimary
            : Theme.of(context).colorScheme.onSurfaceVariant,
        child: Text(number),
      ),
      const SizedBox(height: 6),
      Text(label, style: Theme.of(context).textTheme.labelSmall),
    ],
  );
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.action,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget action;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: AppSpacing.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(body),
          const SizedBox(height: 14),
          action,
        ],
      ),
    ),
  );
}

class _OptionalArchiveSheets extends StatelessWidget {
  const _OptionalArchiveSheets({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: ExpansionTile(
      key: const Key('optional-archive-sheets-panel'),
      title: const Text('Parcourir les onglets à archiver'),
      subtitle: const Text(
        'Optionnel et distinct de la préparation du cutover réel.',
      ),
      childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      children: [child],
    ),
  );
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({
    required this.icon,
    required this.color,
    required this.message,
  });

  final IconData icon;
  final Color color;
  final String message;

  @override
  Widget build(BuildContext context) => Card(
    color: color,
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ],
      ),
    ),
  );
}

class _SheetPreviewCard extends StatelessWidget {
  const _SheetPreviewCard({
    required this.preview,
    required this.selected,
    required this.onSelected,
  });

  final SheetImportPreview preview;
  final bool selected;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) => Card(
    color: selected && !preview.canBeConfirmed
        ? Theme.of(context).colorScheme.errorContainer
        : null,
    child: CheckboxListTile(
      value: selected,
      onChanged: (value) => onSelected(value ?? false),
      controlAffinity: ListTileControlAffinity.leading,
      secondary: Icon(
        preview.canBeConfirmed
            ? Icons.check_circle_outline
            : Icons.error_outline,
      ),
      title: Text(preview.sourceSheetName),
      subtitle: Text(
        '${preview.detectedRecords} elements reconnus\n${preview.issues.map((issue) => issue.message).join('\n')}',
      ),
      isThreeLine: true,
    ),
  );
}
