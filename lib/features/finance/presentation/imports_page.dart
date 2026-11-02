import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/localization/imports_locale.dart';
import '../../../core/localization/app_locale.dart';
import '../../../core/theme/app_design_system.dart';
import '../../envelopes/application/envelope_business_import.dart';
import '../../envelopes/application/envelope_csv_business_validator.dart';
import '../../envelopes/application/providers/remote_envelopes_provider.dart';
import '../application/accounts_template_download.dart';
import '../application/csv_import_templates.dart';
import '../application/csv_import_validation_pipeline.dart';
import '../application/csv_text_reader.dart';
import '../application/import_models/accounts_import_plan.dart';
import '../application/import_models/accounts_import_model_builder.dart';
import '../application/import_models/accounts_import_planner.dart';
import '../application/import_execution/accounts_import_execution.dart';
import '../application/import_execution/accounts_import_executor.dart';
import '../application/providers/accounts_import_executor_provider.dart';
import '../application/providers/active_household_provider.dart';
import '../application/providers/remote_accounts_provider.dart';
import '../application/providers/remote_household_members_provider.dart';
import 'import_preview_page.dart';
import '../domain/financial_account.dart';
import '../domain/household_member.dart';

typedef CsvFilePicker = Future<FilePickerResult?> Function();
typedef CsvTextLoader = Future<String> Function(String path);
typedef CsvImportValidation =
    CsvImportValidationResult Function({
      required String csvText,
      required CsvImportTemplateDefinition template,
    });
typedef AccountsImportPlanBuilder =
    AccountsImportPlan Function(CsvImportValidationResult validationResult);
typedef EnvelopeImportExecutor =
    Future<EnvelopeBusinessImportResult> Function({
      required Iterable<String> names,
      String? importSessionId,
    });

enum OpeningBalanceConflictChoice { ignoreFileBalance, replaceOpeningBalance }

enum AccountsImportUiState { idle, importing, success, failure }

enum AccountsImportMode { initialImport, accountFunding }

const _legacyCsvMaterializationEnabled = false;

class CsvPickerConfiguration {
  const CsvPickerConfiguration(this.type, this.allowedExtensions);
  final FileType type;
  final List<String> allowedExtensions;
}

const csvPickerConfiguration = CsvPickerConfiguration(FileType.custom, ['csv']);

class ImportsPage extends ConsumerStatefulWidget {
  const ImportsPage({
    super.key,
    this.downloader = downloadCsvTemplate,
    this.onCsvFileSelected,
    this.pickCsvFile,
    this.readCsvText,
    this.validateCsvImport,
    this.buildAccountsImportPlan,
    this.importExecutor,
    this.importEnvelopes,
    this.activeHousehold,
    this.initialTemplateType = ImportTemplateType.accounts,
    this.importExecutionIdGenerator = _generateImportExecutionId,
  });
  final Future<void> Function(CsvImportTemplateDefinition) downloader;
  final ValueChanged<String>? onCsvFileSelected;
  final CsvFilePicker? pickCsvFile;
  final CsvTextLoader? readCsvText;
  final CsvImportValidation? validateCsvImport;
  final AccountsImportPlanBuilder? buildAccountsImportPlan;
  final AccountsImportExecutor? importExecutor;
  final EnvelopeImportExecutor? importEnvelopes;
  final ActiveHouseholdState? activeHousehold;
  final ImportTemplateType initialTemplateType;
  final String Function() importExecutionIdGenerator;
  @override
  ConsumerState<ImportsPage> createState() => _ImportsPageState();
}

class _ImportsPageState extends ConsumerState<ImportsPage> {
  var _downloading = false;
  var _analyzing = false;
  var _mode = AccountsImportMode.initialImport;
  late ImportTemplateType _selectedType;
  String? _selectedFilePath;
  String? _selectionMessage;
  String? _selectedCsvText;
  CsvImportValidationResult? _validationResult;
  AccountsImportPlan? _importPlan;
  List<FinancialAccount>? _plannedAgainstRemoteAccounts;
  var _planningRemotePlan = false;
  var _openingBalanceChoice = OpeningBalanceConflictChoice.ignoreFileBalance;
  String? _importExecutionId;
  var _accountsImportState = AccountsImportUiState.idle;
  String? _accountsImportMessage;
  List<EnvelopeImportCandidate>? _validatedEnvelopes;
  String? _envelopeImportSessionId;
  EnvelopeBusinessImportResult? _envelopeImportResult;
  String? _envelopeImportError;
  var _importingEnvelopes = false;

  @override
  void initState() {
    super.initState();
    _selectedType = widget.initialTemplateType;
  }

  @override
  Widget build(BuildContext context) {
    final words = ImportsWords.of(context);
    final template = byType(_selectedType);
    final activeHouseholdAsync = ref.watch(activeHouseholdProvider);
    final activeHousehold =
        widget.activeHousehold ??
        activeHouseholdAsync.valueOrNull ??
        (activeHouseholdAsync.hasError
            ? ActiveHouseholdState(
                status: ActiveHouseholdStatus.error,
                error: activeHouseholdAsync.error,
              )
            : null);
    if (_mode == AccountsImportMode.accountFunding) {
      return _buildFundingUnavailablePage(context);
    }
    final isAccountsImport = _selectedType == ImportTemplateType.accounts;
    final remoteAccountsAsync =
        isAccountsImport &&
            widget.buildAccountsImportPlan == null &&
            activeHousehold?.hasActiveHousehold == true
        ? ref.watch(remoteAccountsProvider)
        : null;
    final remoteMembersAsync =
        isAccountsImport &&
            widget.buildAccountsImportPlan == null &&
            activeHousehold?.hasActiveHousehold == true
        ? ref.watch(remoteHouseholdMembersProvider)
        : null;
    if (isAccountsImport) {
      _scheduleRemotePlan(remoteAccountsAsync, remoteMembersAsync);
    }
    if (_selectedType == ImportTemplateType.envelopes) {
      ref.watch(remoteEnvelopeBalancesProvider);
    }
    return SafeArea(
      child: ListView(
        padding: AppSpacing.page,
        children: [
          Text(
            words.format('import_title', {
              'type': _templateTitleLabel(words, template.type),
            }),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(
            key: const Key('workbook-import-route-button'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const ImportPreviewPage(),
              ),
            ),
            icon: const Icon(Icons.table_view_outlined),
            label: Text(words.text('open_wizard')),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(words.text('journey')),
          DropdownButtonFormField<AccountsImportMode>(
            initialValue: _mode,
            items: [
              DropdownMenuItem(
                value: AccountsImportMode.initialImport,
                child: Text(words.text('initial')),
              ),
              DropdownMenuItem(
                value: AccountsImportMode.accountFunding,
                child: Text(words.text('transactions')),
              ),
            ],
            onChanged: _downloading || _analyzing
                ? null
                : (value) {
                    if (value != null && value != _mode) {
                      setState(() {
                        _mode = value;
                        _clearImportPreparation();
                      });
                    }
                  },
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(words.text('import_type')),
          DropdownButtonFormField<ImportTemplateType>(
            initialValue: _selectedType,
            items: csvImportTemplates
                .map(
                  (item) => DropdownMenuItem(
                    value: item.type,
                    child: Text(_templateLabel(words, item.type)),
                  ),
                )
                .toList(),
            onChanged: _downloading
                ? null
                : (value) => setState(() => _selectedType = value!),
          ),
          const SizedBox(height: AppSpacing.sm),
          ..._templateHelp(template),
          Text(words.format('file', {'file': template.fileName})),
          SelectableText(template.header),
          if (_selectedType == ImportTemplateType.expenses)
            Text(words.text('unreconciled')),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _downloading ? null : () => _downloadTemplate(template),
            icon: const Icon(Icons.download_outlined),
            label: Text(words.text('download_template')),
          ),
          if (_downloading) ...[
            const SizedBox(height: AppSpacing.sm),
            const Center(
              child: CircularProgressIndicator(
                key: Key('template-download-progress'),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: _downloading ? null : _selectCsv,
            icon: const Icon(Icons.upload_file_outlined),
            label: Text(words.text('select_csv')),
          ),
          if (_selectedFilePath != null)
            Text(
              words.format('selected_file', {
                'file': _selectedFilePath!.split(RegExp(r'[\\/]')).last,
              }),
            ),
          if (_selectedCsvText != null) Text(words.text('read_success')),
          ..._validationMessages(),
          if (isAccountsImport) ...[
            ..._accountsPreview(),
            ..._remoteAccountsState(remoteAccountsAsync, remoteMembersAsync),
            ..._importPlanSection(activeHousehold, remoteAccountsAsync),
          ] else if (_selectedType == ImportTemplateType.envelopes) ...[
            ..._envelopeImportSection(),
          ],
          if (_validationResult == null && _selectionMessage != null)
            Text(_selectionMessage!),
          const SizedBox(height: AppSpacing.sm),
          if (_analyzing)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Row(
                children: [
                  const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(words.text('analyzing')),
                ],
              ),
            ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _downloading ? null : _reset,
            child: Text(words.text('reset')),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadTemplate(CsvImportTemplateDefinition template) async {
    setState(() => _downloading = true);
    try {
      await widget.downloader(template);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ImportsWords.of(
              context,
            ).format('download_success', {'file': template.fileName}),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ImportsWords.of(
              context,
            ).format('download_error', {'file': template.fileName}),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _downloading = false);
      }
    }
  }

  Future<void> _selectCsv() async {
    final selection = await (widget.pickCsvFile?.call() ?? _pickCsvFile());
    if (!mounted) return;
    if (selection == null) {
      setState(() {
        _selectedCsvText = null;
        _validationResult = null;
        _importPlan = null;
        _plannedAgainstRemoteAccounts = null;
        _planningRemotePlan = false;
        _analyzing = false;
        _importExecutionId = null;
        _accountsImportState = AccountsImportUiState.idle;
        _accountsImportMessage = null;
        _openingBalanceChoice = OpeningBalanceConflictChoice.ignoreFileBalance;
        _clearEnvelopeImportPreparation();
        _selectionMessage = ImportsWords.of(
          context,
        ).text('selection_cancelled');
      });
      return;
    }
    final path = selection.files.single.path;
    if (path == null || !path.toLowerCase().endsWith('.csv')) {
      setState(
        () => _selectionMessage = ImportsWords.of(context).text('invalid_csv'),
      );
      return;
    }
    setState(() {
      _selectedFilePath = path;
      _selectedCsvText = null;
      _validationResult = null;
      _importPlan = null;
      _plannedAgainstRemoteAccounts = null;
      _importExecutionId = null;
      _accountsImportState = AccountsImportUiState.idle;
      _accountsImportMessage = null;
      _openingBalanceChoice = OpeningBalanceConflictChoice.ignoreFileBalance;
      _clearEnvelopeImportPreparation();
      _selectionMessage = null;
      _analyzing = true;
    });
    widget.onCsvFileSelected?.call(path);
    try {
      final loader = widget.readCsvText ?? CsvTextReader().readCsvFileAsUtf8;
      final content = await loader(path);
      if (!mounted) return;
      setState(() {
        _selectedCsvText = content;
        _selectionMessage = null;
      });
      try {
        final validator =
            widget.validateCsvImport ?? CsvImportValidationPipeline().validate;
        final selectedTemplate = byType(_selectedType);
        final result = validator(csvText: content, template: selectedTemplate);
        final plan =
            result.stage == CsvImportValidationStage.valid &&
                result.isValid &&
                widget.buildAccountsImportPlan != null
            ? widget.buildAccountsImportPlan!(result)
            : null;
        if (!mounted) return;
        setState(() {
          _validationResult = result;
          _importPlan = plan;
          _plannedAgainstRemoteAccounts = null;
          _importExecutionId = plan == null
              ? null
              : widget.importExecutionIdGenerator();
          _accountsImportState = AccountsImportUiState.idle;
          _accountsImportMessage = null;
          if (selectedTemplate.type == ImportTemplateType.envelopes &&
              result.stage == CsvImportValidationStage.valid &&
              result.isValid) {
            _validatedEnvelopes = result.envelopeBusinessResult?.rows;
            _envelopeImportSessionId = _generateImportExecutionId();
          }
          _analyzing = false;
        });
      } catch (error) {
        if (!mounted) return;
        setState(() {
          _analyzing = false;
          _selectionMessage = ImportsWords.of(context).text('validation_error');
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _analyzing = false;
        _selectionMessage = ImportsWords.of(context).text('read_error');
      });
    }
  }

  Future<FilePickerResult?> _pickCsvFile() => FilePicker.platform.pickFiles(
    type: csvPickerConfiguration.type,
    allowedExtensions: csvPickerConfiguration.allowedExtensions,
  );

  List<Widget> _templateHelp(CsvImportTemplateDefinition template) {
    final words = ImportsWords.of(context);
    if (template.type == ImportTemplateType.envelopes) {
      return [
        Text(words.text('envelope_initial')),
        Text(words.text('envelope_intro')),
        Text(words.text('separator')),
        Text(words.text('encoding')),
        Text(words.text('envelope_columns')),
      ];
    }

    return [
      Text(words.text('account_initial')),
      Text(words.text('account_intro')),
      Text(words.text('separator')),
      Text(words.text('encoding')),
      Text(words.text('accepted_dates')),
      Text(words.text('accepted_amounts')),
      Text(words.text('minor_units')),
      Text(words.text('external_optional')),
      Text(words.text('accepted_types')),
    ];
  }

  void _clearImportPreparation() {
    _selectedType = ImportTemplateType.accounts;
    _selectedFilePath = null;
    _selectedCsvText = null;
    _validationResult = null;
    _importPlan = null;
    _plannedAgainstRemoteAccounts = null;
    _planningRemotePlan = false;
    _importExecutionId = null;
    _accountsImportState = AccountsImportUiState.idle;
    _accountsImportMessage = null;
    _openingBalanceChoice = OpeningBalanceConflictChoice.ignoreFileBalance;
    _clearEnvelopeImportPreparation();
    _selectionMessage = null;
    _analyzing = false;
  }

  void _clearEnvelopeImportPreparation() {
    _validatedEnvelopes = null;
    _envelopeImportSessionId = null;
    _envelopeImportResult = null;
    _envelopeImportError = null;
    _importingEnvelopes = false;
  }

  List<Widget> _envelopeImportSection() {
    final words = ImportsWords.of(context);
    final envelopes = _validatedEnvelopes;
    if (envelopes == null) {
      return const [];
    }
    return [
      const Divider(),
      Text(words.text('envelope_import')),
      Text(words.format('detected_envelopes', {'count': envelopes.length})),
      Text(words.text('opening_immutable')),
      if (_envelopeImportResult != null)
        Text(
          words.format('envelope_result', {
            'created': _envelopeImportResult!.created,
            'initialized': _envelopeImportResult!.initializedExisting,
            'existing': _envelopeImportResult!.existing,
            'ignored': _envelopeImportResult!.ignored,
          }),
        ),
      if (_envelopeImportError != null) Text(_envelopeImportError!),
      FilledButton(
        key: const Key('envelope-csv-import-button'),
        onPressed:
            !_legacyCsvMaterializationEnabled ||
                envelopes.isEmpty ||
                _importingEnvelopes
            ? null
            : _confirmEnvelopeImport,
        child: Text(
          !_legacyCsvMaterializationEnabled
              ? words.text('legacy_disabled')
              : _importingEnvelopes
              ? words.text('importing_envelopes')
              : words.text('import_envelopes'),
        ),
      ),
    ];
  }

  Future<void> _confirmEnvelopeImport() async {
    final words = ImportsWords.of(context);
    final envelopes = _validatedEnvelopes;
    if (envelopes == null || envelopes.isEmpty || _importingEnvelopes) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(words.text('import_envelopes')),
        content: Text(
          words.format('confirm_envelopes', {'count': envelopes.length}),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(words.text('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(words.text('import_envelopes')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() {
      _importingEnvelopes = true;
      _envelopeImportError = null;
    });
    try {
      final importer = widget.importEnvelopes;
      final EnvelopeBusinessImportResult result;
      if (importer != null) {
        result = await importer(
          names: envelopes.map((envelope) => envelope.name),
          importSessionId: _envelopeImportSessionId,
        );
      } else {
        result = await ref.read(importHouseholdEnvelopesProvider)(
          names: envelopes.map((envelope) => envelope.name),
          candidates: envelopes,
          importSessionId: _envelopeImportSessionId,
        );
      }
      if (!mounted) {
        return;
      }
      ref.invalidate(remoteEnvelopeBalancesProvider);
      setState(() => _envelopeImportResult = result);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _envelopeImportError = words.text('envelope_failed'));
    } finally {
      if (mounted) {
        setState(() => _importingEnvelopes = false);
      }
    }
  }

  void _reset() {
    setState(() {
      _mode = AccountsImportMode.initialImport;
      _clearImportPreparation();
    });
  }

  void _scheduleRemotePlan(
    AsyncValue<List<FinancialAccount>>? accountsAsync,
    AsyncValue<List<HouseholdMember>>? membersAsync,
  ) {
    final validation = _validationResult;
    if (validation == null ||
        validation.stage != CsvImportValidationStage.valid ||
        !validation.isValid ||
        accountsAsync == null ||
        _accountsImportState == AccountsImportUiState.success) {
      return;
    }
    final accounts = accountsAsync.valueOrNull;
    final members = membersAsync?.valueOrNull;
    if (accounts == null || members == null) {
      if (_importPlan != null && !_planningRemotePlan) {
        _planningRemotePlan = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) {
            return;
          }
          setState(() {
            _importPlan = null;
            _plannedAgainstRemoteAccounts = null;
            _importExecutionId = null;
            _planningRemotePlan = false;
          });
        });
      }
      return;
    }
    if (_planningRemotePlan ||
        identical(_plannedAgainstRemoteAccounts, accounts)) {
      return;
    }
    _planningRemotePlan = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _validationResult != validation) {
        return;
      }
      setState(() {
        try {
          _importPlan = _buildImportPlan(validation, accounts, members);
          _accountsImportMessage = null;
        } on StateError catch (error) {
          _importPlan = null;
          _accountsImportMessage = error.message.toString();
        }
        _plannedAgainstRemoteAccounts = accounts;
        _importExecutionId ??= widget.importExecutionIdGenerator();
        _accountsImportState = AccountsImportUiState.idle;
        _planningRemotePlan = false;
      });
    });
  }

  List<Widget> _remoteAccountsState(
    AsyncValue<List<FinancialAccount>>? accountsAsync,
    AsyncValue<List<HouseholdMember>>? membersAsync,
  ) {
    if (_validationResult?.isValid != true || accountsAsync == null) {
      return const [];
    }
    if (accountsAsync.isLoading) {
      return [
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.sm),
          child: Text(ImportsWords.of(context).text('loading_accounts')),
        ),
      ];
    }
    if (accountsAsync.hasError) {
      return [
        Text(ImportsWords.of(context).text('accounts_error')),
        OutlinedButton(
          onPressed: () => ref.invalidate(remoteAccountsProvider),
          child: Text(ImportsWords.of(context).text('retry')),
        ),
      ];
    }
    if (membersAsync?.isLoading == true) {
      return [Text(ImportsWords.of(context).text('loading_members'))];
    }
    if (membersAsync?.hasError == true) {
      return [Text(ImportsWords.of(context).text('members_error'))];
    }
    return const [];
  }

  Widget _buildFundingUnavailablePage(BuildContext context) {
    final words = ImportsWords.of(context);
    return SafeArea(
      child: ListView(
        padding: AppSpacing.page,
        children: [
          Text(
            words.format('import_title', {
              'type': _templateTitleLabel(words, ImportTemplateType.accounts),
            }),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(words.text('journey')),
          DropdownButtonFormField<AccountsImportMode>(
            initialValue: _mode,
            items: [
              DropdownMenuItem(
                value: AccountsImportMode.initialImport,
                child: Text(words.text('initial')),
              ),
              DropdownMenuItem(
                value: AccountsImportMode.accountFunding,
                child: Text(words.text('transactions')),
              ),
            ],
            onChanged: (value) {
              if (value != null && value != _mode) {
                setState(() {
                  _mode = value;
                  _clearImportPreparation();
                });
              }
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(words.text('transaction_intro')),
          const SizedBox(height: AppSpacing.sm),
          Card(
            child: ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(words.text('transactions_unavailable')),
              subtitle: Text(words.text('transactions_future')),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _validationMessages() {
    final words = ImportsWords.of(context);
    final result = _validationResult;
    if (result == null) {
      return const [];
    }
    switch (result.stage) {
      case CsvImportValidationStage.parsingFailed:
        return [
          Text(words.text('parsing_errors')),
          ...result.errors.map(
            (error) => Text(
              error.startsWith('Erreur de parsing :')
                  ? error.substring('Erreur de parsing :'.length).trim()
                  : error,
            ),
          ),
        ];
      case CsvImportValidationStage.structureInvalid:
        return [
          Text(words.text('structure_errors')),
          ...result.errors.map(Text.new),
        ];
      case CsvImportValidationStage.businessInvalid:
        return [
          Text(words.text('business_errors')),
          ...result.errors.map(Text.new),
        ];
      case CsvImportValidationStage.unsupportedTemplate:
        return [
          Text(words.text('validation_unavailable')),
          ...result.errors.map(Text.new),
        ];
      case CsvImportValidationStage.valid:
        return result.isValid ? [Text(words.text('valid_data'))] : const [];
    }
  }

  List<Widget> _accountsPreview() {
    final words = ImportsWords.of(context);
    final result = _validationResult;
    final businessResult = result?.accountsBusinessResult;
    final parsedRows = result?.parsedRows;
    if (result?.stage != CsvImportValidationStage.valid ||
        result?.isValid != true ||
        businessResult == null ||
        parsedRows == null ||
        parsedRows.isEmpty) {
      return const [];
    }

    final indexes = <String, int>{
      for (var index = 0; index < parsedRows.first.length; index++)
        parsedRows.first[index].trim().toLowerCase(): index,
    };
    return [
      const Divider(),
      Text(words.text('preview')),
      Text(
        words.format('account_count', {'count': businessResult.rows.length}),
      ),
      const Divider(),
      ...businessResult.rows.map((rowResult) {
        final sourceIndex = rowResult.lineNumber - 1;
        final sourceRow = sourceIndex >= 0 && sourceIndex < parsedRows.length
            ? parsedRows[sourceIndex]
            : const <String>[];
        final name = _previewValue(sourceRow, indexes, 'nom');
        final type = _previewValue(sourceRow, indexes, 'type');
        final balance = rowResult.initialBalanceCents == null
            ? '—'
            : _formatMad(rowResult.initialBalanceCents!);
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [Text(name), Text(type.toUpperCase()), Text(balance)],
          ),
        );
      }),
    ];
  }

  static String _previewValue(
    List<String> row,
    Map<String, int> indexes,
    String column,
  ) {
    final index = indexes[column];
    if (index == null || index >= row.length) {
      return '';
    }
    return row[index].trim();
  }

  static String _formatMad(int cents) {
    final sign = cents < 0 ? '-' : '';
    final absolute = cents.abs();
    final dirhams = (absolute ~/ 100).toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ' ',
    );
    final centimes = (absolute % 100).toString().padLeft(2, '0');
    return '$sign$dirhams,$centimes MAD';
  }

  AccountsImportPlan _buildImportPlan(
    CsvImportValidationResult validationResult,
    Iterable<FinancialAccount> existingAccounts,
    Iterable<HouseholdMember> householdMembers,
  ) => AccountsImportPlanner().plan(
    importedAccounts: AccountsImportModelBuilder().build(
      validationResult,
      householdMembers: householdMembers,
    ),
    existingAccounts: existingAccounts,
  );

  List<Widget> _importPlanSection(
    ActiveHouseholdState? activeHousehold,
    AsyncValue<List<FinancialAccount>>? remoteAccountsAsync,
  ) {
    final words = ImportsWords.of(context);
    final plan = _importPlan;
    if (plan == null) {
      return [
        if (_accountsImportMessage != null) Text(_accountsImportMessage!),
        FilledButton(
          key: const Key('accounts-import-button'),
          onPressed: null,
          child: Text(words.text('import')),
        ),
      ];
    }
    final householdMessage = _activeHouseholdMessage(activeHousehold, words);
    final remoteAccountsReady =
        widget.buildAccountsImportPlan != null ||
        remoteAccountsAsync?.hasValue == true;
    final canImport =
        _mode == AccountsImportMode.initialImport &&
        activeHousehold?.hasActiveHousehold == true &&
        remoteAccountsReady &&
        _accountsImportState != AccountsImportUiState.importing &&
        _accountsImportState != AccountsImportUiState.success &&
        _importExecutionId != null;
    return [
      const Divider(),
      Text(words.text('plan')),
      Text(words.format('create_count', {'count': plan.createCount})),
      Text(words.format('existing_count', {'count': plan.alreadyExistsCount})),
      Text(words.format('total', {'count': plan.decisions.length})),
      Text(
        plan.hasConflicts
            ? words.text('existing_notice')
            : words.text('no_conflict'),
      ),
      const Divider(),
      Column(
        key: const Key('accounts-import-plan-list'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: plan.decisions
            .map(
              (decision) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(decision.account.name),
                    Text(decision.account.type.name.toUpperCase()),
                    Text(
                      decision.action == AccountImportAction.create
                          ? words.text('to_create')
                          : words.text('already_exists'),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
      if (plan.alreadyExistsCount > 0) Text(words.text('existing_protected')),
      if (householdMessage != null) Text(householdMessage),
      if (_accountsImportState == AccountsImportUiState.importing) ...[
        const SizedBox(height: 12),
        Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                key: Key('accounts-import-progress'),
                strokeWidth: 2,
              ),
            ),
            const SizedBox(width: 8),
            Text(words.text('importing_accounts')),
          ],
        ),
      ],
      if (_accountsImportMessage != null) Text(_accountsImportMessage!),
      FilledButton(
        key: const Key('accounts-import-button'),
        onPressed: _legacyCsvMaterializationEnabled && canImport
            ? () => _executeAccountsImport(activeHousehold!)
            : null,
        child: Text(
          !_legacyCsvMaterializationEnabled
              ? words.text('legacy_disabled')
              : _accountsImportState == AccountsImportUiState.importing
              ? words.text('importing_accounts')
              : words.text('import'),
        ),
      ),
    ];
  }

  String? _activeHouseholdMessage(
    ActiveHouseholdState? household,
    ImportsWords words,
  ) {
    if (household == null) {
      return words.text('loading_household');
    }
    return switch (household.status) {
      ActiveHouseholdStatus.noAuthenticatedUser => words.text('sign_in'),
      ActiveHouseholdStatus.noHousehold => words.text('no_household'),
      ActiveHouseholdStatus.multipleHouseholds => words.text(
        'select_household',
      ),
      ActiveHouseholdStatus.error => words.text('household_unavailable'),
      ActiveHouseholdStatus.singleHousehold => null,
    };
  }

  Future<void> _executeAccountsImport(
    ActiveHouseholdState activeHousehold,
  ) async {
    final words = ImportsWords.of(context);
    final plan = _importPlan;
    final importExecutionId = _importExecutionId;
    if (plan == null ||
        importExecutionId == null ||
        !activeHousehold.hasActiveHousehold ||
        _accountsImportState == AccountsImportUiState.importing ||
        _accountsImportState == AccountsImportUiState.success) {
      return;
    }

    setState(() {
      _accountsImportState = AccountsImportUiState.importing;
      _accountsImportMessage = null;
    });
    try {
      final AccountsImportExecutor executor =
          widget.importExecutor ?? ref.read(accountsImportExecutorProvider);
      final result = await executor.execute(
        plan: plan,
        openingBalancePolicy:
            _openingBalanceChoice ==
                OpeningBalanceConflictChoice.ignoreFileBalance
            ? ExistingAccountOpeningBalancePolicy.ignoreCsvValue
            : ExistingAccountOpeningBalancePolicy.replaceExistingOpeningBalance,
        importExecutionId: importExecutionId,
      );
      if (!mounted) {
        return;
      }
      if (result.isSuccess) {
        ref.invalidate(remoteAccountsProvider);
        setState(() {
          _accountsImportState = AccountsImportUiState.success;
          _importPlan = null;
          _plannedAgainstRemoteAccounts = null;
          _importExecutionId = null;
          _accountsImportMessage = _successMessage(result, words);
        });
      } else {
        setState(() {
          _accountsImportState = AccountsImportUiState.failure;
          _accountsImportMessage = result.errors.isEmpty
              ? words.text('accounts_failed')
              : result.errors.first;
        });
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _accountsImportState = AccountsImportUiState.failure;
        _accountsImportMessage = words.text('accounts_failed');
      });
    }
  }

  static String _successMessage(
    AccountsImportExecutionResult result,
    ImportsWords words,
  ) => words.format('success', {
    'created': result.createdCount,
    'kept': result.keptExistingCount,
    'replaced': result.replacedOpeningBalanceCount,
    'missing': result.skippedMissingOpeningBalanceCount,
  });

  static String _templateLabel(ImportsWords words, ImportTemplateType type) =>
      words.text('type_${type.name}');

  static String _templateTitleLabel(
    ImportsWords words,
    ImportTemplateType type,
  ) {
    final label = _templateLabel(words, type);
    if (words.language != AppLanguage.french || label.isEmpty) return label;
    return '${label[0].toLowerCase()}${label.substring(1)}';
  }
}

String _generateImportExecutionId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
