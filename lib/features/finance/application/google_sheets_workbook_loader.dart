import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

class DownloadedWorkbook {
  const DownloadedWorkbook({required this.fileName, required this.bytes});

  final String fileName;
  final Uint8List bytes;
}

/// Downloads a workbook from a Google Sheets sharing link.
///
/// The sheet must be shared with the user or configured as accessible through
/// its link. No Google password or secret is stored by the application.
class GoogleSheetsWorkbookLoader {
  GoogleSheetsWorkbookLoader({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  Future<DownloadedWorkbook> download(
    String source, {
    void Function(int receivedBytes, int? totalBytes)? onProgress,
  }) async {
    final spreadsheetId = _spreadsheetIdFrom(source);
    if (spreadsheetId == null) {
      throw const FormatException(
        'Le lien Google Sheets est incomplet. Collez le lien qui contient /spreadsheets/d/...',
      );
    }
    late final http.StreamedResponse response;
    try {
      response = await _client
          .send(
            http.Request(
              'GET',
              Uri.https(
                'docs.google.com',
                '/spreadsheets/d/$spreadsheetId/export',
                const {'format': 'xlsx'},
              ),
            ),
          )
          .timeout(const Duration(seconds: 45));
    } on TimeoutException {
      throw const FormatException(
        'Google Sheets ne repond pas apres 45 secondes. Verifiez votre connexion ou utilisez le fichier Excel telecharge depuis Google Sheets.',
      );
    }
    if (response.statusCode != 200) {
      throw FormatException(
        'Google Sheets n a pas fourni le fichier (code ${response.statusCode}). Verifiez que le document est partage avec ce lien, puis reessayez.',
      );
    }
    final bytes = <int>[];
    var received = 0;
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 45),
    )) {
      bytes.addAll(chunk);
      received += chunk.length;
      onProgress?.call(received, response.contentLength);
    }
    if (bytes.isEmpty) {
      throw const FormatException(
        'Google Sheets n a fourni aucun contenu. Verifiez le partage du document.',
      );
    }
    if (bytes.length < 4 || bytes[0] != 0x50 || bytes[1] != 0x4b) {
      throw const FormatException(
        'Google a renvoye une page d acces au lieu du classeur Excel. Dans Google Sheets, ouvrez Partager puis choisissez Toute personne ayant le lien, ou telechargez le fichier Excel et choisissez-le ici.',
      );
    }
    return DownloadedWorkbook(
      fileName: 'Google Sheet $spreadsheetId.xlsx',
      bytes: Uint8List.fromList(bytes),
    );
  }

  String? _spreadsheetIdFrom(String source) {
    final trimmed = source.trim();
    final match = RegExp(
      r'/spreadsheets/d/([a-zA-Z0-9_-]+)',
    ).firstMatch(trimmed);
    if (match != null) {
      return match.group(1);
    }
    if (RegExp(r'^[a-zA-Z0-9_-]{20,}$').hasMatch(trimmed)) {
      return trimmed;
    }
    return null;
  }
}
