import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_design_system.dart';
import '../../../core/localization/import_preview_locale.dart';
import '../application/cutover_preparation.dart';
import '../application/cutover_opening_import.dart';
import '../application/workbook_import.dart';
import '../domain/account_ownership.dart';
import '../domain/household_member.dart';
import 'cutover_preparation_card.dart';
import 'historical_analytics_preview_card.dart';
import 'import_wizard_components.dart';

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
    final w = ImportPreviewWords.of(context);
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
    final currentStep = _cutoverResult != null
        ? 4
        : _cutoverPlan?.confirmedAt != null
        ? 3
        : analysis != null
        ? state.isConfirmed
              ? 2
              : 1
        : 0;

    return PopScope<Object?>(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop && await _confirmLeave(controller) && mounted) {
          setState(() => _allowPop = true);
          Navigator.of(this.context).pop();
        }
      },
      child: ColoredBox(
        color: AppColors.background,
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120),
              child: ListView(
                padding: AppLayout.pagePaddingFor(
                  MediaQuery.sizeOf(context).width,
                ),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          w.text('title'),
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ),
                      TextButton.icon(
                        key: const Key('exit-import-assistant-button'),
                        onPressed: () => _exitAssistant(controller),
                        icon: const Icon(Icons.close_outlined),
                        label: Text(w.text('exit')),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  SecondaryInfoText(w.text('intro')),
                  const SizedBox(height: AppSpacing.md),
                  ImportWizardStepper(currentStep: currentStep),
                  const SizedBox(height: AppSpacing.md),
                  _NoticeCard(
                    icon: Icons.info_outline,
                    color: const Color(0xFFEEF1F4),
                    message: isRealCutoverSource
                        ? w.text('real_source_notice')
                        : w.text('source_notice'),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (state.loadingProgress case final progress?) ...[
                    const SizedBox(height: 12),
                    LinearProgressIndicator(
                      value: progress.clamp(0, 1).toDouble(),
                    ),
                    const SizedBox(height: 6),
                    Text(state.loadingMessage ?? w.text('preparing')),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  ResponsiveGrid(
                    minItemWidth: 390,
                    children: [
                      _ActionCard(
                        icon: Icons.upload_file_rounded,
                        title: w.text('excel'),
                        body: w.text('excel_body'),
                        action: FilledButton.icon(
                          onPressed: state.isPicking
                              ? null
                              : controller.chooseWorkbook,
                          icon: const Icon(Icons.folder_open_outlined),
                          label: Text(
                            state.isPicking
                                ? w.text('reading')
                                : w.text('choose_excel'),
                          ),
                        ),
                      ),
                      _ActionCard(
                        icon: Icons.link_rounded,
                        title: w.text('google'),
                        body: w.text('google_body'),
                        action: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextField(
                              controller: _googleSheetController,
                              keyboardType: TextInputType.url,
                              decoration: InputDecoration(
                                labelText: w.text('google_link'),
                                hintText: w.text('google_hint'),
                                border: const OutlineInputBorder(),
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
                                          w.text('google_reading'))
                                    : w.text('read_google'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
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
                    _SourceSummaryCard(
                      analysis: analysis,
                      realCutover: isRealCutoverSource,
                    ),
                    const SizedBox(height: AppSpacing.md),
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
                      HistoricalAnalyticsPreviewCard(
                        key: ValueKey(
                          'historical-analytics-${analysis.sourceFingerprint}',
                        ),
                        analysis: analysis,
                      ),
                      const SizedBox(height: 16),
                    ],
                    _ActionCard(
                      icon: Icons.checklist_rounded,
                      title: isRealCutoverSource
                          ? w.text('optional_archive')
                          : w.text('choose_import'),
                      body: isRealCutoverSource
                          ? w.text('archive_body')
                          : w.format('choose_body', {
                              'file': analysis.fileName,
                            }),
                      action: isRealCutoverSource
                          ? Text(w.text('archive_none'))
                          : Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    w.format('selected', {
                                      'selected':
                                          state.selectedImporterIds.length,
                                      'total': analysis.sheetPreviews.length,
                                    }),
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelLarge,
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: controller.selectAllSheets,
                                  icon: const Icon(Icons.select_all_rounded),
                                  label: Text(w.text('select_all')),
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
                            ? w.text('verify_archive')
                            : w.text('verify_confirm'),
                        body: blockingSelected.isEmpty
                            ? isRealCutoverSource
                                  ? w.text('archive_confirmation')
                                  : w.text('sheets_ready')
                            : w.format('sheets_attention', {
                                'count': blockingSelected.length,
                              }),
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
                                w.format('help_problems', {
                                  'count': blockingSelected.length,
                                }),
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
                                    ? w.text('sheets_confirmed')
                                    : w.text('confirm_choices'),
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
                        message: w.text('choices_confirmed'),
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
                            ? w.text('undo_archive')
                            : w.text('go_back'),
                        body: w.text('undo_notice'),
                        action: OutlinedButton.icon(
                          onPressed: state.lastImportSessionId == null
                              ? null
                              : () => _showUndoDialog(context, controller),
                          icon: const Icon(Icons.undo_outlined),
                          label: Text(
                            isRealCutoverSource
                                ? w.text('undo_archive')
                                : w.text('undo_import'),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      key: const Key('back-to-file-step-button'),
                      onPressed: () => _returnToFileStep(controller),
                      icon: const Icon(Icons.arrow_back_outlined),
                      label: Text(w.text('back_file')),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  TextButton.icon(
                    key: const Key('quit-import-assistant-bottom-button'),
                    onPressed: () => _exitAssistant(controller),
                    icon: const Icon(Icons.close_outlined),
                    label: Text(w.text('exit_assistant')),
                  ),
                ],
              ),
            ),
          ),
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
          message: ImportPreviewWords.of(context).format('unhandled', {
            'sheets': analysis.unhandledSheetNames.join(', '),
          }),
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
      builder: (dialogContext) {
        final w = ImportPreviewWords.of(dialogContext);
        return AlertDialog(
          icon: const Icon(Icons.info_outline),
          title: Text(w.text('leave_title')),
          content: Text(w.text('leave_body')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(w.text('stay')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(w.text('leave_without_save')),
            ),
          ],
        );
      },
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
    final w = ImportPreviewWords.of(context);
    final hasOpeningSheet = selectedImporterIds.contains(
      'cutover-opening-positions',
    );
    final plan = _cutoverPlan;
    final households = cutoverHouseholds.valueOrNull ?? const [];
    final selectedHousehold = households
        .where((household) => household.id == _selectedCutoverHouseholdId)
        .firstOrNull;
    final householdMembers = _selectedCutoverHouseholdId == null
        ? const AsyncValue<List<HouseholdMember>>.data([])
        : ref.watch(
            cutoverHouseholdMembersProvider(_selectedCutoverHouseholdId!),
          );
    final memberIds = householdMembers.valueOrNull
        ?.map((member) => member.id)
        .toSet();
    final outsideHolderErrors = plan == null || memberIds == null
        ? const <String>[]
        : plan.ownershipErrorsForMemberIds(memberIds);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ActionCard(
          icon: Icons.home_work_outlined,
          title: w.text('destination'),
          body: hasOpeningSheet
              ? w.text('destination_ready')
              : w.text('destination_sheet'),
          action: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (cutoverHouseholds.hasError) Text(w.text('households_error')),
              if (cutoverHouseholds.isLoading) const LinearProgressIndicator(),
              if (!cutoverHouseholds.isLoading && !cutoverHouseholds.hasError)
                DropdownButtonFormField<String>(
                  key: const Key('cutover-household-selector'),
                  initialValue: _selectedCutoverHouseholdId,
                  decoration: InputDecoration(
                    labelText: w.text('target_household'),
                    border: const OutlineInputBorder(),
                  ),
                  items: households
                      .map(
                        (household) => DropdownMenuItem(
                          value: household.id,
                          child: Text(
                            // i18n-dynamic-only
                            '${household.name} — ${household.isOperational ? w.text('operational') : w.text('technical')}',
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
                const SizedBox(height: AppSpacing.sm),
                Align(
                  alignment: Alignment.centerLeft,
                  child: ImportDecisionBadge(
                    key: Key(
                      selectedHousehold.isOperational
                          ? 'operational-household-badge'
                          : 'technical-household-badge',
                    ),
                    label: selectedHousehold.isOperational
                        ? w.text('operational')
                        : w.text('technical'),
                    tone: selectedHousehold.isOperational
                        ? ImportDecisionTone.operational
                        : ImportDecisionTone.technical,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              ExpansionTile(
                key: const Key('cutover-technical-details'),
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: AppSpacing.sm),
                title: Text(w.text('technical_details')),
                subtitle: Text(w.text('technical_subtitle')),
                children: [
                  SelectableText(
                    w.format('fingerprint', {
                      'value': analysis.sourceFingerprint,
                    }),
                  ),
                  if (selectedHousehold != null)
                    SelectableText(
                      w.format('household_id', {'value': selectedHousehold.id}),
                    ),
                ],
              ),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  key: const Key('cutover-plan-button'),
                  onPressed:
                      !hasOpeningSheet ||
                          selectedHousehold == null ||
                          _preparingCutover
                      ? null
                      : () => _prepareCutover(analysis, selectedHousehold),
                  icon: const Icon(Icons.preview_outlined),
                  label: Text(
                    _preparingCutover
                        ? w.text('searching_run')
                        : w.text('prepare_b1'),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (plan != null) ...[
          const SizedBox(height: AppSpacing.md),
          _PlanSummaryCard(plan: plan, household: selectedHousehold),
          const SizedBox(height: AppSpacing.md),
          DesktopSection(
            title: w.text('candidate_accounts'),
            subtitle: w.format('account_positions', {
              'count': plan.accounts.length,
            }),
            child: ResponsiveGrid(
              minItemWidth: 330,
              children: plan.accounts.indexed
                  .map(
                    (entry) => CutoverAccountOwnershipCard(
                      key: ValueKey('cutover-account-${entry.$2.name}'),
                      account: entry.$2,
                      members: householdMembers.valueOrNull ?? const [],
                      membersLoading: householdMembers.isLoading,
                      membersError: householdMembers.hasError,
                      enabled: plan.confirmedAt == null,
                      onChanged: (account) => setState(
                        () => _cutoverPlan = plan.updateAccount(
                          entry.$1,
                          account,
                        ),
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          DesktopSection(
            title: w.text('candidate_envelopes'),
            subtitle: w.format('envelope_positions', {
              'count': plan.envelopes.length,
            }),
            child: ResponsiveGrid(
              minItemWidth: 280,
              children: plan.envelopes
                  .map((item) => _CutoverEnvelopeCard(item: item))
                  .toList(growable: false),
            ),
          ),
          if (plan.blockingErrors.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            _NoticeCard(
              icon: Icons.error_outline,
              color: AppColors.dangerContainer,
              message: plan.blockingErrors.join('\n'),
            ),
          ],
          if (outsideHolderErrors.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            _NoticeCard(
              icon: Icons.error_outline,
              color: AppColors.dangerContainer,
              message: outsideHolderErrors.join('\n'),
            ),
          ],
          if (plan.confirmedAt == null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.md),
              child: Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  key: const Key('cutover-confirm-button'),
                  onPressed:
                      plan.canConfirm &&
                          householdMembers.hasValue &&
                          outsideHolderErrors.isEmpty
                      ? () => setState(
                          () => _cutoverPlan = plan.confirm(DateTime.now()),
                        )
                      : null,
                  icon: const Icon(Icons.verified_outlined),
                  label: Text(w.text('confirm_plan')),
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.md),
              child: CutoverExecutionPanel(
                confirmed: true,
                executing: _executingCutover,
                result: _cutoverResult,
                onExecute: () => _executeCutover(analysis, plan),
              ),
            ),
        ],
        if (_cutoverError case final error?) ...[
          const SizedBox(height: AppSpacing.sm),
          _NoticeCard(
            icon: Icons.error_outline,
            color: AppColors.dangerContainer,
            message: error,
          ),
        ],
      ],
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
      setState(
        () => _cutoverError = ImportPreviewWords.of(
          context,
        ).format('execution_error', {'error': error}),
      );
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
      if (existing == null) {
        final prepared = _cutoverPlan;
        if (prepared != null) {
          final resolved = await ref
              .read(cutoverOpeningImportRepositoryProvider)
              .resolveReferences(prepared);
          if (!mounted) return;
          setState(() => _cutoverPlan = resolved);
        }
      }
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _cutoverError = ImportPreviewWords.of(
          context,
        ).format('b1_error', {'error': error}),
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
    builder: (dialogContext) {
      final w = ImportPreviewWords.of(dialogContext);
      return AlertDialog(
        icon: const Icon(Icons.help_outline_rounded),
        title: Text(w.text('fix_title')),
        content: SizedBox(
          width: 580,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(w.text('fix_body')),
                const SizedBox(height: 16),
                ...previews.map(
                  (preview) => _ProblemsForSheet(preview: preview),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(w.text('fix_file')),
          ),
          FilledButton(
            onPressed: () {
              onSelectOnlyValid();
              Navigator.of(dialogContext).pop();
            },
            child: Text(w.text('valid_only')),
          ),
        ],
      );
    },
  );

  Future<void> _showUndoDialog(
    BuildContext context,
    WorkbookImportController controller,
  ) => showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final w = ImportPreviewWords.of(dialogContext);
      return AlertDialog(
        icon: const Icon(Icons.undo_rounded),
        title: Text(w.text('undo_title')),
        content: Text(w.text('undo_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(w.text('keep')),
          ),
          FilledButton(
            onPressed: () {
              controller.clearLastImport();
              Navigator.of(dialogContext).pop();
            },
            child: Text(w.text('undo_import')),
          ),
        ],
      );
    },
  );
}

class _SourceSummaryCard extends StatelessWidget {
  const _SourceSummaryCard({required this.analysis, required this.realCutover});

  final WorkbookImportAnalysis analysis;
  final bool realCutover;

  @override
  Widget build(BuildContext context) {
    final w = ImportPreviewWords.of(context);
    return Card(
      key: const Key('import-source-summary'),
      child: Padding(
        padding: AppSpacing.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.description_outlined,
                  color: AppColors.primary,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    analysis.fileName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                ImportDecisionBadge(
                  label: realCutover
                      ? w.text('real_cutover')
                      : w.text('analyzed_source'),
                  tone: realCutover
                      ? ImportDecisionTone.technical
                      : ImportDecisionTone.operational,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            SecondaryInfoText(
              w.format('sheet_summary', {
                'recognized': analysis.sheetPreviews.length,
                'unknown': analysis.unhandledSheetNames.length,
              }),
            ),
            ExpansionTile(
              key: const Key('import-technical-details'),
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: AppSpacing.xs),
              title: Text(w.text('technical_details')),
              subtitle: Text(w.text('sha_subtitle')),
              children: [SelectableText(analysis.sourceFingerprint)],
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanSummaryCard extends StatelessWidget {
  const _PlanSummaryCard({required this.plan, required this.household});

  final CutoverOpeningPlan plan;
  final CutoverEligibleHousehold? household;

  @override
  Widget build(BuildContext context) {
    final w = ImportPreviewWords.of(context);
    final accountsTotal = plan.accounts.fold<num>(
      0,
      (total, item) => total + item.openingAmount,
    );
    final envelopesTotal = plan.envelopes.fold<num>(
      0,
      (total, item) => total + item.openingAmount,
    );
    return DesktopSection(
      title: w.text('opening_plan'),
      subtitle: w.text('mandatory_review'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ResponsiveGrid(
            minItemWidth: 210,
            children: [
              _PlanMetric(
                label: w.text('effective_date'),
                value: CutoverOpeningPlan.formatDate(plan.effectiveDate),
              ),
              _PlanMetric(
                label: w.text('accounts'),
                value: '${plan.accounts.length} • $accountsTotal MAD',
              ),
              _PlanMetric(
                label: w.text('envelopes'),
                value: '${plan.envelopes.length} • $envelopesTotal MAD',
              ),
              _PlanMetric(
                label: w.text('destination'),
                value: household?.name ?? w.text('explicit_household'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          SecondaryInfoText(w.text('ledger_notice')),
        ],
      ),
    );
  }
}

class _PlanMetric extends StatelessWidget {
  const _PlanMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.sm),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: AppRadius.input,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          value,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleSmall,
        ),
      ],
    ),
  );
}

class _CutoverEnvelopeCard extends StatelessWidget {
  const _CutoverEnvelopeCard({required this.item});

  final CutoverOpeningEnvelope item;

  @override
  Widget build(BuildContext context) {
    final w = ImportPreviewWords.of(context);
    final conflict = item.referenceConflict != null;
    final match = item.conflictDecision == 'match';
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: AppSpacing.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.name,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                ImportDecisionBadge(
                  label: conflict
                      ? w.text('conflict')
                      : match
                      ? w.text('match')
                      : w.text('create'),
                  tone: conflict
                      ? ImportDecisionTone.conflict
                      : match
                      ? ImportDecisionTone.match
                      : ImportDecisionTone.create,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              NumberFormat.currency(
                locale: Localizations.localeOf(context).toLanguageTag(),
                symbol: 'MAD',
                decimalDigits: 2,
              ).format(item.openingAmount),
            ),
            if (item.isToAllocate) SecondaryInfoText(w.text('system_envelope')),
            if (item.referenceConflict != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                item.referenceConflict!,
                style: const TextStyle(color: AppColors.danger),
              ),
            ],
            if (item.matchedEnvelopeId != null)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(w.text('technical_reference')),
                children: [SelectableText(item.matchedEnvelopeId!)],
              ),
          ],
        ),
      ),
    );
  }
}

class CutoverAccountOwnershipCard extends StatelessWidget {
  const CutoverAccountOwnershipCard({
    super.key,
    required this.account,
    required this.members,
    required this.membersLoading,
    required this.membersError,
    required this.enabled,
    required this.onChanged,
  });

  final CutoverOpeningAccount account;
  final List<HouseholdMember> members;
  final bool membersLoading;
  final bool membersError;
  final bool enabled;
  final ValueChanged<CutoverOpeningAccount> onChanged;

  @override
  Widget build(BuildContext context) {
    final w = ImportPreviewWords.of(context);
    final ownership = account.ownershipType;
    final error = account.ownershipValidationError;
    final action = account.referenceConflict != null || error != null
        ? '${w.text('conflict')} — ${w.text('to_confirm')}'
        : account.conflictDecision == 'match'
        ? w.text('match')
        : w.text('create');
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: AppSpacing.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    // i18n-dynamic-only
                    '${account.name} • ${NumberFormat.currency(locale: Localizations.localeOf(context).toLanguageTag(), symbol: 'MAD', decimalDigits: 2).format(account.openingAmount)}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                ImportDecisionBadge(
                  label: account.referenceConflict != null || error != null
                      ? w.text('conflict')
                      : account.conflictDecision == 'match'
                      ? w.text('match')
                      : w.text('create'),
                  tone: account.referenceConflict != null || error != null
                      ? ImportDecisionTone.conflict
                      : account.conflictDecision == 'match'
                      ? ImportDecisionTone.match
                      : ImportDecisionTone.create,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xxs),
            SecondaryInfoText(w.format('account_type', {'type': account.kind})),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              key: ValueKey('cutover-ownership-${account.name}'),
              initialValue: ownership?.name ?? 'unconfirmed',
              decoration: InputDecoration(
                labelText: w.text('ownership'),
                border: const OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem(
                  value: 'unconfirmed',
                  child: Text(w.text('to_confirm')),
                ),
                DropdownMenuItem(
                  value: 'individual',
                  child: Text(w.text('individual')),
                ),
                DropdownMenuItem(
                  value: 'shared',
                  child: Text(w.text('shared')),
                ),
                DropdownMenuItem(
                  value: 'household',
                  child: Text(w.text('household')),
                ),
              ],
              onChanged: !enabled
                  ? null
                  : (value) {
                      final selectedOwnership = switch (value) {
                        'individual' => AccountOwnershipType.individual,
                        'shared' => AccountOwnershipType.shared,
                        'household' => AccountOwnershipType.household,
                        _ => null,
                      };
                      onChanged(
                        account.copyWith(
                          ownershipType: selectedOwnership,
                          clearOwnershipType: selectedOwnership == null,
                          holderUserIds:
                              selectedOwnership ==
                                  AccountOwnershipType.household
                              ? const []
                              : account.holderUserIds,
                        ),
                      );
                    },
            ),
            if (ownership != null &&
                ownership != AccountOwnershipType.household) ...[
              const SizedBox(height: 8),
              Text(
                ownership == AccountOwnershipType.individual
                    ? w.text('holder')
                    : w.text('holders'),
              ),
              if (membersLoading) const LinearProgressIndicator(),
              if (membersError) Text(w.text('members_error')),
              ...members.map(
                (member) => CheckboxListTile(
                  key: ValueKey('cutover-holder-${account.name}-${member.id}'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(member.displayName),
                  value: account.holderUserIds.contains(member.id),
                  onChanged: !enabled
                      ? null
                      : (selected) {
                          final holders = [...account.holderUserIds];
                          if (selected ?? false) {
                            if (ownership == AccountOwnershipType.individual) {
                              holders
                                ..clear()
                                ..add(member.id);
                            } else if (!holders.contains(member.id)) {
                              holders.add(member.id);
                            }
                          } else {
                            holders.remove(member.id);
                          }
                          onChanged(account.copyWith(holderUserIds: holders));
                        },
                ),
              ),
            ],
            const SizedBox(height: 6),
            Text(w.format('decision', {'action': action})),
            Text(
              w.format('ownership_summary', {
                'ownership': _ownershipLabel(w, ownership),
                'holders': _holderLabels(w, account.holderUserIds, members),
              }),
            ),
            if (account.matchedAccountId != null)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(w.text('technical_reference')),
                children: [SelectableText(account.matchedAccountId!)],
              ),
            if (error != null)
              Text(
                error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (account.referenceConflict != null)
              Text(
                account.referenceConflict!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    );
  }

  static String _ownershipLabel(
    ImportPreviewWords w,
    AccountOwnershipType? ownership,
  ) => switch (ownership) {
    AccountOwnershipType.individual => w.text('individual'),
    AccountOwnershipType.shared => w.text('shared'),
    AccountOwnershipType.household => w.text('household'),
    null => w.text('to_confirm'),
  };

  static String _holderLabels(
    ImportPreviewWords w,
    List<String> holderIds,
    List<HouseholdMember> members,
  ) {
    if (holderIds.isEmpty) return w.text('none');
    final labels = {
      for (final member in members) member.id: member.displayName,
    };
    return holderIds
        .map((id) => labels[id] ?? w.text('household_member'))
        .join(', ');
  }
}

class _ProblemsForSheet extends StatelessWidget {
  const _ProblemsForSheet({required this.preview});

  final SheetImportPreview preview;

  @override
  Widget build(BuildContext context) {
    final w = ImportPreviewWords.of(context);
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
                        w.format('line_field', {
                          'line': problem.rowNumber,
                          'field': problem.field,
                        }),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(problem.explanation),
                      const SizedBox(height: 6),
                      Text(
                        w.format('correction', {
                          'hint': problem.correctionHint,
                        }),
                      ),
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
  Widget build(BuildContext context) {
    final w = ImportPreviewWords.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        key: const Key('optional-archive-sheets-panel'),
        title: Text(w.text('browse_archive')),
        subtitle: Text(w.text('archive_optional')),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: [child],
      ),
    );
  }
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
  Widget build(BuildContext context) {
    final w = ImportPreviewWords.of(context);
    return Card(
      color: selected && !preview.canBeConfirmed
          ? Theme.of(context).colorScheme.errorContainer
          : null,
      child: CheckboxListTile(
        dense: true,
        value: selected,
        onChanged: (value) => onSelected(value ?? false),
        controlAffinity: ListTileControlAffinity.leading,
        secondary: ImportDecisionBadge(
          label: preview.canBeConfirmed ? w.text('ready') : w.text('review'),
          tone: preview.canBeConfirmed
              ? ImportDecisionTone.create
              : ImportDecisionTone.conflict,
        ),
        title: Text(preview.sourceSheetName),
        subtitle: Text(
          w.format('recognized_items', {
            'count': preview.detectedRecords,
            'issues': preview.issues.isEmpty
                ? ''
                : '\n${preview.issues.map((issue) => issue.message).join('\n')}',
          }),
        ),
        isThreeLine: preview.issues.isNotEmpty,
      ),
    );
  }
}
