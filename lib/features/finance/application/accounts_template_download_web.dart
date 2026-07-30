import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

Future<void> download(List<int> bytes, String name) async {
  final blob = web.Blob([Uint8List.fromList(bytes).toJS].toJS, web.BlobPropertyBag(type: 'text/csv;charset=utf-8'));
  final url = web.URL.createObjectURL(blob);
  (web.HTMLAnchorElement()..href = url..download = name).click();
  web.URL.revokeObjectURL(url);
}
