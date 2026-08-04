import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/theme/app_design_system.dart';
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
import '../domain/financial_account.dart';

typedef CsvFilePicker = Future<FilePickerResult?> Function();
typedef CsvTextLoader = Future<String> Function(String path);
typedef CsvImportValidation =
    CsvImportValidationResult Function({
      required String csvText,
      required CsvImportTemplateDefinition template,
    });
typedef AccountsImportPlanBuilder =
    AccountsImportPlan Function(CsvImportValidationResult validationResult);

enum OpeningBalanceConflictChoice { ignoreFileBalance, replaceOpeningBalance }

enum AccountsImportUiState { idle, importing, success, failure }

enum AccountsImportMode { initialImport, accountFunding }

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
    this.activeHousehold,
    this.importExecutionIdGenerator = _generateImportExecutionId,
  });
  final Future<void> Function(CsvImportTemplateDefinition) downloader;
  final ValueChanged<String>? onCsvFileSelected;
  final CsvFilePicker? pickCsvFile;
  final CsvTextLoader? readCsvText;
  final CsvImportValidation? validateCsvImport;
  final AccountsImportPlanBuilder? buildAccountsImportPlan;
  final AccountsImportExecutor? importExecutor;
  final ActiveHouseholdState? activeHousehold;
  final String Function() importExecutionIdGenerator;
  @override
  ConsumerState<ImportsPage> createState() => _ImportsPageState();
}

class _ImportsPageState extends ConsumerState<ImportsPage> {
  var _downloading = false;
  var _analyzing = false;
  var _mode = AccountsImportMode.initialImport;
  var _selectedType = ImportTemplateType.accounts;
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

  @override
  Widget build(BuildContext context) {
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
    final remoteAccountsAsync =
        widget.buildAccountsImportPlan == null &&
            activeHousehold?.hasActiveHousehold == true
        ? ref.watch(remoteAccountsProvider)
        : null;
    _scheduleRemotePlan(remoteAccountsAsync);
    return SafeArea(
      child: ListView(
        padding: AppSpacing.page,
        children: [
          Text(
            'Import des comptes',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: AppSpacing.md),
          const Text('Parcours'),
          DropdownButtonFormField<AccountsImportMode>(
            initialValue: _mode,
            items: const [
              DropdownMenuItem(
                value: AccountsImportMode.initialImport,
                child: Text('Import initial'),
              ),
              DropdownMenuItem(
                value: AccountsImportMode.accountFunding,
                child: Text('Alimentation de comptes'),
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
          const Text('Type d’import'),
          DropdownButtonFormField<ImportTemplateType>(
            initialValue: _selectedType,
            items: csvImportTemplates
                .map(
                  (item) => DropdownMenuItem(
                    value: item.type,
                    child: Text(item.label),
                  ),
                )
                .toList(),
            onChanged: _downloading
                ? null
                : (value) => setState(() => _selectedType = value!),
          ),
          const SizedBox(height: AppSpacing.sm),
          const Text('Import initial des comptes.'),
          const Text(
            'Crée les comptes absents et définit leur solde d’ouverture. '
            'Les comptes déjà existants sont détectés avant l’import.',
          ),
          Text('Fichier : ${template.fileName}'),
          const Text('Séparateur : point-virgule'),
          const Text('Encodage : UTF-8'),
          const Text('Dates acceptées : JJ/MM/AAAA ou AAAA-MM-JJ'),
          const Text('Montants saisis en MAD : 1000, 1000,50 ou 1000.50.'),
          const Text(
            'Les montants sont convertis automatiquement en centimes.',
          ),
          const Text('external_id : facultatif.'),
          const Text(
            'Types acceptés : banque, espèces, épargne, emprunt ; '
            'ou bank, cash, savings, loan.',
          ),
          SelectableText(template.header),
          if (_selectedType == ImportTemplateType.expenses)
            const Text(
              'Le compte de paiement peut rester vide pour un historique non rapproché.',
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _downloading ? null : () => _downloadTemplate(template),
            icon: const Icon(Icons.download_outlined),
            label: const Text('Télécharger le template'),
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
            label: const Text('Sélectionner un fichier CSV'),
          ),
          if (_selectedFilePath != null)
            Text(
              'Fichier sélectionné : ${_selectedFilePath!.split(RegExp(r'[\\/]')).last}',
            ),
          if (_selectedCsvText != null) const Text('Fichier lu avec succès.'),
          ..._validationMessages(),
          ..._accountsPreview(),
          ..._remoteAccountsState(remoteAccountsAsync),
          ..._importPlanSection(activeHousehold, remoteAccountsAsync),
          if (_validationResult == null && _selectionMessage != null)
            Text(_selectionMessage!),
          const SizedBox(height: AppSpacing.sm),
          if (_analyzing)
            const Padding(
              padding: EdgeInsets.only(top: AppSpacing.sm),
              child: Row(
                children: [
                  SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: AppSpacing.xs),
                  Text('Analyse en cours...'),
                ],
              ),
            ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _downloading ? null : _reset,
            child: const Text('Réinitialiser'),
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
          content: Text('${template.fileName} a été téléchargé avec succès'),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Téléchargement de ${template.fileName} impossible. Réessayez.',
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
        _selectionMessage = 'Sélection annulée.';
      });
      return;
    }
    final path = selection.files.single.path;
    if (path == null || !path.toLowerCase().endsWith('.csv')) {
      setState(() => _selectionMessage = 'Choisissez un fichier CSV valide.');
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
        final result = validator(
          csvText: content,
          template: byType(_selectedType),
        );
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
          _analyzing = false;
        });
      } catch (error) {
        if (!mounted) return;
        setState(() {
          _analyzing = false;
          _selectionMessage = 'Erreur de validation : $error';
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _analyzing = false;
        _selectionMessage = 'Erreur de lecture : $error';
      });
    }
  }

  Future<FilePickerResult?> _pickCsvFile() => FilePicker.platform.pickFiles(
    type: csvPickerConfiguration.type,
    allowedExtensions: csvPickerConfiguration.allowedExtensions,
  );

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
    _selectionMessage = null;
    _analyzing = false;
  }

  void _reset() {
    setState(() {
      _mode = AccountsImportMode.initialImport;
      _clearImportPreparation();
    });
  }

  void _scheduleRemotePlan(AsyncValue<List<FinancialAccount>>? accountsAsync) {
    final validation = _validationResult;
    if (validation == null ||
        validation.stage != CsvImportValidationStage.valid ||
        !validation.isValid ||
        accountsAsync == null ||
        _accountsImportState == AccountsImportUiState.success) {
      return;
    }
    final accounts = accountsAsync.valueOrNull;
    if (accounts == null) {
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
        _importPlan = _buildImportPlan(validation, accounts);
        _plannedAgainstRemoteAccounts = accounts;
        _importExecutionId ??= widget.importExecutionIdGenerator();
        _accountsImportState = AccountsImportUiState.idle;
        _accountsImportMessage = null;
        _planningRemotePlan = false;
      });
    });
  }

  List<Widget> _remoteAccountsState(
    AsyncValue<List<FinancialAccount>>? accountsAsync,
  ) {
    if (_validationResult?.isValid != true || accountsAsync == null) {
      return const [];
    }
    if (accountsAsync.isLoading) {
      return const [
        Padding(
          padding: EdgeInsets.only(top: AppSpacing.sm),
          child: Text('Chargement des comptes existants...'),
        ),
      ];
    }
    if (accountsAsync.hasError) {
      return [
        const Text('Impossible de lire les comptes existants.'),
        OutlinedButton(
          onPressed: () => ref.invalidate(remoteAccountsProvider),
          child: const Text('Réessayer'),
        ),
      ];
    }
    return const [];
  }

  Widget _buildFundingUnavailablePage(BuildContext context) => SafeArea(
    child: ListView(
      padding: AppSpacing.page,
      children: [
        Text(
          'Import des comptes',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: AppSpacing.md),
        const Text('Parcours'),
        DropdownButtonFormField<AccountsImportMode>(
          initialValue: _mode,
          items: const [
            DropdownMenuItem(
              value: AccountsImportMode.initialImport,
              child: Text('Import initial'),
            ),
            DropdownMenuItem(
              value: AccountsImportMode.accountFunding,
              child: Text('Alimentation de comptes'),
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
        const Text(
          'Ajoutez des mouvements à des comptes existants sans modifier leur '
          'solde d’ouverture.',
        ),
        const SizedBox(height: AppSpacing.sm),
        const Card(
          child: ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Import de mouvements indisponible'),
            subtitle: Text(
              'L’import de mouvements sera disponible dans une prochaine étape.',
            ),
          ),
        ),
      ],
    ),
  );

  List<Widget> _validationMessages() {
    final result = _validationResult;
    if (result == null) {
      return const [];
    }
    switch (result.stage) {
      case CsvImportValidationStage.parsingFailed:
        return [
          const Text('Erreur de parsing :'),
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
          const Text('Erreurs de structure :'),
          ...result.errors.map(Text.new),
        ];
      case CsvImportValidationStage.businessInvalid:
        return [const Text('Erreurs métier :'), ...result.errors.map(Text.new)];
      case CsvImportValidationStage.unsupportedTemplate:
        return [
          const Text('Validation métier indisponible.'),
          ...result.errors.map(Text.new),
        ];
      case CsvImportValidationStage.valid:
        return result.isValid
            ? const [Text('Données métier valides.')]
            : const [];
    }
  }

  List<Widget> _accountsPreview() {
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
      const Text("Aperçu de l'import"),
      Text('Nombre de comptes : ${businessResult.rows.length}'),
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
  ) => AccountsImportPlanner().plan(
    importedAccounts: AccountsImportModelBuilder().build(validationResult),
    existingAccounts: existingAccounts,
  );

  List<Widget> _importPlanSection(
    ActiveHouseholdState? activeHousehold,
    AsyncValue<List<FinancialAccount>>? remoteAccountsAsync,
  ) {
    final plan = _importPlan;
    if (plan == null) {
      return [
        if (_accountsImportMessage != null) Text(_accountsImportMessage!),
        const FilledButton(
          key: Key('accounts-import-button'),
          onPressed: null,
          child: Text('Importer'),
        ),
      ];
    }
    final householdMessage = _activeHouseholdMessage(activeHousehold);
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
      const Text("Plan d'import"),
      Text('Comptes à créer : ${plan.createCount}'),
      Text('Comptes déjà existants : ${plan.alreadyExistsCount}'),
      Text('Total : ${plan.decisions.length}'),
      Text(
        plan.hasConflicts
            ? 'Des comptes existent déjà.'
            : 'Aucun conflit détecté.',
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
                          ? 'À créer'
                          : 'Existe déjà',
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
      if (plan.alreadyExistsCount > 0) ...[
        const Text('Comptes existants'),
        RadioGroup<OpeningBalanceConflictChoice>(
          groupValue: _openingBalanceChoice,
          onChanged: (value) {
            if (value != null) {
              setState(() => _openingBalanceChoice = value);
            }
          },
          child: Column(
            children: [
              RadioListTile<OpeningBalanceConflictChoice>(
                key: const Key('opening-balance-ignore-option'),
                title: const Text('Ignorer le solde initial du fichier'),
                value: OpeningBalanceConflictChoice.ignoreFileBalance,
              ),
              RadioListTile<OpeningBalanceConflictChoice>(
                key: const Key('opening-balance-replace-option'),
                title: const Text('Remplacer le solde initial existant'),
                value: OpeningBalanceConflictChoice.replaceOpeningBalance,
              ),
            ],
          ),
        ),
      ],
      if (householdMessage != null) Text(householdMessage),
      if (_accountsImportState == AccountsImportUiState.importing) ...[
        const SizedBox(height: 12),
        const Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                key: Key('accounts-import-progress'),
                strokeWidth: 2,
              ),
            ),
            SizedBox(width: 8),
            Text('Import des comptes en cours...'),
          ],
        ),
      ],
      if (_accountsImportMessage != null) Text(_accountsImportMessage!),
      FilledButton(
        key: const Key('accounts-import-button'),
        onPressed: canImport
            ? () => _executeAccountsImport(activeHousehold!)
            : null,
        child: Text(
          _accountsImportState == AccountsImportUiState.importing
              ? 'Import en cours...'
              : 'Importer',
        ),
      ),
    ];
  }

  String? _activeHouseholdMessage(ActiveHouseholdState? household) {
    if (household == null) {
      return 'Chargement du foyer actif...';
    }
    return switch (household.status) {
      ActiveHouseholdStatus.noAuthenticatedUser =>
        'Connectez-vous pour importer des comptes.',
      ActiveHouseholdStatus.noHousehold =>
        'Aucun foyer n’est disponible pour cet import.',
      ActiveHouseholdStatus.multipleHouseholds =>
        'Sélectionnez un foyer avant d’importer.',
      ActiveHouseholdStatus.error =>
        'Le foyer actif est indisponible pour le moment.',
      ActiveHouseholdStatus.singleHousehold => null,
    };
  }

  Future<void> _executeAccountsImport(
    ActiveHouseholdState activeHousehold,
  ) async {
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
          _accountsImportMessage = _successMessage(result);
        });
      } else {
        setState(() {
          _accountsImportState = AccountsImportUiState.failure;
          _accountsImportMessage = result.errors.isEmpty
              ? 'L’import des comptes a échoué. Réessayez.'
              : result.errors.first;
        });
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _accountsImportState = AccountsImportUiState.failure;
        _accountsImportMessage = 'L’import des comptes a échoué. Réessayez.';
      });
    }
  }

  static String _successMessage(AccountsImportExecutionResult result) =>
      'Import terminé dans Supabase : ${result.createdCount} compte(s) créé(s), '
      '${result.keptExistingCount} existant(s) conservé(s), '
      '${result.replacedOpeningBalanceCount} solde(s) remplacé(s), '
      '${result.skippedMissingOpeningBalanceCount} solde(s) non renseigné(s). '
      'La liste locale des comptes n’est pas encore synchronisée.';
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
