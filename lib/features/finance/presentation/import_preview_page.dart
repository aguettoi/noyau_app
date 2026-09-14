import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_design_system.dart';
import '../application/cutover_opening_import.dart';
import '../application/workbook_import.dart';

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
  var _executingCutover = false;

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
    final targetHousehold = ref.watch(cutoverOpeningTargetHouseholdProvider);
    final analysis = state.analysis;
    final selectedPreviews =
        analysis?.previewsFor(state.selectedImporterIds) ?? const [];
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

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.xl,
        ),
        children: [
          Text(
            'Importer mon fichier Excel',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: AppSpacing.xs),
          const Text(
            'Cet assistant vous guide pas a pas. Vous ne pouvez rien casser : chaque import reste traçable et peut etre annule.',
          ),
          const SizedBox(height: AppSpacing.md),
          _ProgressCard(currentStep: currentStep),
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
            _ActionCard(
              icon: Icons.checklist_rounded,
              title: '2. Choisir ce que vous voulez importer',
              body:
                  '${analysis.fileName} est pret. Cochez uniquement les onglets que vous souhaitez conserver.',
              action: Row(
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
            ...analysis.sheetPreviews.map(
              (preview) => _SheetPreviewCard(
                preview: preview,
                selected: state.selectedImporterIds.contains(
                  preview.importerId,
                ),
                onSelected: (selected) =>
                    controller.toggleSheet(preview.importerId, selected),
              ),
            ),
            if (analysis.unhandledSheetNames.isNotEmpty)
              _NoticeCard(
                icon: Icons.warning_amber_rounded,
                color: Theme.of(context).colorScheme.errorContainer,
                message:
                    'Ces onglets ne sont pas encore reconnus : ${analysis.unhandledSheetNames.join(', ')}',
              ),
            const SizedBox(height: 16),
            _ActionCard(
              icon: Icons.health_and_safety_outlined,
              title: '3. Verifier puis confirmer',
              body: blockingSelected.isEmpty
                  ? 'Les onglets choisis sont prets. Vous gardez le controle jusqu a la confirmation.'
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
                            onSelectOnlyValid: controller.selectOnlyValidSheets,
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
                targetHousehold: targetHousehold,
              ),
            ],
            const SizedBox(height: 16),
            _ActionCard(
              icon: Icons.undo_rounded,
              title: 'Besoin de revenir en arriere ?',
              body:
                  'Le dernier import termine pourra etre annule sans effacer son historique.',
              action: OutlinedButton.icon(
                onPressed: state.lastImportSessionId == null
                    ? null
                    : () => _showUndoDialog(context, controller),
                icon: const Icon(Icons.undo_outlined),
                label: const Text('Annuler le dernier import'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCutoverSection({
    required WorkbookImportAnalysis analysis,
    required Set<String> selectedImporterIds,
    required AsyncValue<String> targetHousehold,
  }) {
    final hasOpeningSheet = selectedImporterIds.contains(
      'cutover-opening-positions',
    );
    final plan = _cutoverPlan;
    return _ActionCard(
      icon: Icons.account_balance_outlined,
      title: '4. Plan de positions d’ouverture B1',
      body: hasOpeningSheet
          ? 'Le plan cible est explicite, auditable et exécute seulement les RPC canoniques Cutover A.'
          : 'Sélectionnez l’onglet « Positions ouverture » pour préparer le cutover B1.',
      action: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (targetHousehold.hasError)
            const Text('Un household opérationnel explicite est requis.'),
          if (targetHousehold.hasValue)
            Text('Household cible : ${targetHousehold.value}'),
          Text('Fingerprint source : ${analysis.sourceFingerprint}'),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('cutover-plan-button'),
            onPressed: !hasOpeningSheet || !targetHousehold.hasValue
                ? null
                : () => setState(() {
                    _cutoverError = null;
                    _cutoverResult = null;
                    _cutoverPlan = CutoverOpeningPlanBuilder().build(
                      analysis: analysis,
                      householdId: targetHousehold.value!,
                      effectiveDate: DateTime.now(),
                    );
                  }),
            icon: const Icon(Icons.preview_outlined),
            label: const Text('Préparer le plan B1'),
          ),
          if (plan != null) ...[
            const SizedBox(height: 10),
            Text(
              'Date effective : ${CutoverOpeningPlan.formatDate(plan.effectiveDate)}',
            ),
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
    // The preview fingerprint is rechecked before touching Supabase. A changed
    // source must be analysed and explicitly confirmed again.
    if (analysis.sourceFingerprint != plan.sourceFingerprint) {
      setState(
        () => _cutoverError =
            'La source a changé : relancez l’analyse et confirmez un nouveau plan.',
      );
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
