import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;
import '../domain/portability_models.dart';

Future<void> save(PortableFile file) async {
  final blob = web.Blob(
    [Uint8List.fromList(file.bytes).toJS].toJS,
    web.BlobPropertyBag(type: file.mimeType),
  );
  final url = web.URL.createObjectURL(blob);
  (web.HTMLAnchorElement()
        ..href = url
        ..download = file.name)
      .click();
  web.URL.revokeObjectURL(url);
}
