import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../application/accounts_template_download.dart';
import '../application/csv_import_templates.dart';
import '../application/csv_text_reader.dart';
import '../application/csv_text_parser.dart';

typedef CsvFilePicker = Future<FilePickerResult?> Function();
typedef CsvTextLoader = Future<String> Function(String path);
typedef CsvTextParse = List<List<String>> Function(String csvText);

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
    this.parseCsvText,
  });
  final Future<void> Function(CsvImportTemplateDefinition) downloader;
  final ValueChanged<String>? onCsvFileSelected;
  final CsvFilePicker? pickCsvFile;
  final CsvTextLoader? readCsvText;
  final CsvTextParse? parseCsvText;
  @override
  State<ImportsPage> createState() => _ImportsPageState();
}

class _ImportsPageState extends State<ImportsPage> {
  var _downloading = false;
  var _selectedType = ImportTemplateType.accounts;
  String? _selectedFilePath;
  String? _selectionMessage;
  String? _selectedCsvText;
  List<List<String>>? _parsedCsvRows;

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
          if (_parsedCsvRows != null)
            const Text('CSV analysé avec succès.')
          else if (_selectionMessage != null)
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
        _parsedCsvRows = null;
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
      _parsedCsvRows = null;
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
        final parser = widget.parseCsvText ?? CsvTextParser().parse;
        final rows = parser(content);
        if (!mounted) return;
        setState(() {
          _parsedCsvRows = rows;
        });
      } catch (error) {
        if (!mounted) return;
        setState(() => _selectionMessage = 'Erreur de parsing : $error');
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
}
