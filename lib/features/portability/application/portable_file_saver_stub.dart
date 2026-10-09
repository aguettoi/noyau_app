import 'dart:io';
import 'package:file_picker/file_picker.dart';
import '../domain/portability_models.dart';

Future<void> save(PortableFile file) async {
  final extension = file.name.split('.').last;
  final path = await FilePicker.platform.saveFile(
    dialogTitle: 'Exporter les données',
    fileName: file.name,
    type: FileType.custom,
    allowedExtensions: [extension],
  );
  if (path == null) return;
  final target = path.toLowerCase().endsWith('.$extension')
      ? path
      : '$path.$extension';
  await File(target).writeAsBytes(file.bytes, flush: true);
}
