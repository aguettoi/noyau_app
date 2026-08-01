import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../application/accounts_template_download.dart';
import '../application/csv_import_templates.dart';
import '../application/csv_import_validation_pipeline.dart';
import '../application/csv_text_reader.dart';
import '../application/import_models/accounts_import_plan.dart';
import '../application/import_models/accounts_import_model_builder.dart';
import '../application/import_models/accounts_import_planner.dart';

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

class CsvPickerConfiguration {
  const CsvPickerConfiguration(this.type, this.allowedExtensions);
  final FileType type;
  final List<String> allowedExtensions;
}

const csvPickerConfiguration = CsvPickerConfiguration(FileType.custom, ['csv']);

class ImportsPage extends StatefulWidget {
  const ImportsPage({
    super.key,
    this.downloader = downloadCsvTemplate,
    this.onCsvFileSelected,
    this.pickCsvFile,
    this.readCsvText,
    this.validateCsvImport,
    this.buildAccountsImportPlan,
  });
  final Future<void> Function(CsvImportTemplateDefinition) downloader;
  final ValueChanged<String>? onCsvFileSelected;
  final CsvFilePicker? pickCsvFile;
  final CsvTextLoader? readCsvText;
  final CsvImportValidation? validateCsvImport;
  final AccountsImportPlanBuilder? buildAccountsImportPlan;
  @override
  State<ImportsPage> createState() => _ImportsPageState();
}

class _ImportsPageState extends State<ImportsPage> {
  var _downloading = false;
  var _selectedType = ImportTemplateType.accounts;
  String? _selectedFilePath;
  String? _selectionMessage;
  String? _selectedCsvText;
  CsvImportValidationResult? _validationResult;
  AccountsImportPlan? _importPlan;
  var _openingBalanceChoice = OpeningBalanceConflictChoice.ignoreFileBalance;

  @override
  Widget build(BuildContext context) {
    final template = byType(_selectedType);
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Import des comptes',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 20),
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
          const SizedBox(height: 12),
          Text(template.description),
          Text('Fichier : ${template.fileName}'),
          const Text('Séparateur : point-virgule'),
          const Text('Encodage : UTF-8'),
          const Text('Dates : YYYY-MM-DD'),
          const Text('Montants : centimes entiers'),
          SelectableText(template.header),
          SelectableText(template.exampleRow),
          const Text('La ligne EXEMPLE-001 est une ligne d’exemple.'),
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
            const SizedBox(height: 12),
            const Center(
              child: CircularProgressIndicator(
                key: Key('template-download-progress'),
              ),
            ),
          ],
          const SizedBox(height: 12),
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
          ..._importPlanSection(),
          if (_validationResult == null && _selectionMessage != null)
            Text(_selectionMessage!),
          const SizedBox(height: 12),
          FilledButton(onPressed: null, child: const Text('Analyser')),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () =>
                setState(() => _selectedType = ImportTemplateType.accounts),
            child: const Text('Réinitialiser'),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: null,
            child: const Text('Injection disponible dans l’étape suivante'),
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
      _openingBalanceChoice = OpeningBalanceConflictChoice.ignoreFileBalance;
      _selectionMessage = null;
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
            result.stage == CsvImportValidationStage.valid && result.isValid
            ? (widget.buildAccountsImportPlan ?? _buildImportPlan)(result)
            : null;
        if (!mounted) return;
        setState(() {
          _validationResult = result;
          _importPlan = plan;
        });
      } catch (error) {
        if (!mounted) return;
        setState(() => _selectionMessage = 'Erreur de validation : $error');
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _selectionMessage = 'Erreur de lecture : $error');
    }
  }

  Future<FilePickerResult?> _pickCsvFile() => FilePicker.platform.pickFiles(
    type: csvPickerConfiguration.type,
    allowedExtensions: csvPickerConfiguration.allowedExtensions,
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
          padding: const EdgeInsets.only(bottom: 8),
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
  ) => AccountsImportPlanner().plan(
    importedAccounts: AccountsImportModelBuilder().build(validationResult),
    existingAccounts: const [],
  );

  List<Widget> _importPlanSection() {
    final plan = _importPlan;
    if (plan == null) {
      return const [];
    }
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
                padding: const EdgeInsets.only(bottom: 8),
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
      FilledButton(
        key: const Key('accounts-import-button'),
        onPressed: null,
        child: const Text('Importer'),
      ),
    ];
  }
}
