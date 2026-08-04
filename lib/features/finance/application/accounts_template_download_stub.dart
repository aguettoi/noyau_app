import 'dart:io';

import 'package:file_picker/file_picker.dart';

typedef SaveTemplateFile =
    Future<String?> Function({
      required String dialogTitle,
      required String fileName,
      required FileType type,
      required List<String> allowedExtensions,
    });

typedef WriteTemplateBytes =
    Future<void> Function(String path, List<int> bytes);

class NativeTemplateSaveConfiguration {
  const NativeTemplateSaveConfiguration({
    required this.dialogTitle,
    required this.type,
    required this.allowedExtensions,
  });

  final String dialogTitle;
  final FileType type;
  final List<String> allowedExtensions;
}

const nativeTemplateCsvSaveConfiguration = NativeTemplateSaveConfiguration(
  dialogTitle: 'Enregistrer le template CSV',
  type: FileType.custom,
  allowedExtensions: ['csv'],
);

/// Enregistre un template CSV sur une plateforme native compatible.
class NativeTemplateFileSaver {
  NativeTemplateFileSaver({
    SaveTemplateFile? saveFile,
    WriteTemplateBytes? writeBytes,
  }) : _saveFile = saveFile ?? _saveFileFromPlatform,
       _writeBytes = writeBytes ?? _writeBytesToFile;

  final SaveTemplateFile _saveFile;
  final WriteTemplateBytes _writeBytes;

  Future<void> save(List<int> bytes, String name) async {
    final selectedPath = await _saveFile(
      dialogTitle: nativeTemplateCsvSaveConfiguration.dialogTitle,
      fileName: name,
      type: nativeTemplateCsvSaveConfiguration.type,
      allowedExtensions: nativeTemplateCsvSaveConfiguration.allowedExtensions,
    );
    if (selectedPath == null) {
      return;
    }
    await _writeBytes(_withCsvExtension(selectedPath), bytes);
  }

  static Future<String?> _saveFileFromPlatform({
    required String dialogTitle,
    required String fileName,
    required FileType type,
    required List<String> allowedExtensions,
  }) => FilePicker.platform.saveFile(
    dialogTitle: dialogTitle,
    fileName: fileName,
    type: type,
    allowedExtensions: allowedExtensions,
  );

  static Future<void> _writeBytesToFile(String path, List<int> bytes) =>
      File(path).writeAsBytes(bytes, flush: true);

  static String _withCsvExtension(String path) =>
      path.toLowerCase().endsWith('.csv') ? path : '$path.csv';
}

/// Signature partagée avec l'implémentation Web conditionnelle.
Future<void> download(List<int> bytes, String name) =>
    NativeTemplateFileSaver().save(bytes, name);
