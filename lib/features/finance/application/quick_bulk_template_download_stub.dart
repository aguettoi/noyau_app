import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

Future<void> saveQuickImportTemplate(Uint8List bytes, String fileName) async {
  final path = await FilePicker.platform.saveFile(
    dialogTitle: 'Enregistrer le modèle FINANCIEL PILOTE',
    fileName: fileName,
    type: FileType.custom,
    allowedExtensions: const ['xlsx'],
  );
  if (path == null) return;
  final target = path.toLowerCase().endsWith('.xlsx') ? path : '$path.xlsx';
  await File(target).writeAsBytes(bytes, flush: true);
}
