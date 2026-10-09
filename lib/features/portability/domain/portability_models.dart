enum SearchResultType {
  financialEvent,
  account,
  envelope,
  obligation,
  receivable,
  compensation,
  goal,
  shopping,
  priority,
  task,
  asset,
}

class GlobalSearchResult {
  const GlobalSearchResult({
    required this.type,
    required this.id,
    required this.title,
    required this.subtitle,
    this.date,
    this.amount,
  });
  final SearchResultType type;
  final String id, title, subtitle;
  final DateTime? date;
  final double? amount;
}

class ImportHistoryEntry {
  const ImportHistoryEntry({
    required this.id,
    required this.fileName,
    required this.status,
    required this.createdAt,
    required this.detectedRecords,
    required this.actorId,
    this.error,
  });
  final String id, fileName, status, actorId;
  final DateTime createdAt;
  final int detectedRecords;
  final String? error;
}

class PortableFile {
  const PortableFile(this.name, this.mimeType, this.bytes);
  final String name, mimeType;
  final List<int> bytes;
}

String safeExportName(String value) => value
    .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
    .replaceAll(RegExp('_+'), '_')
    .replaceAll(RegExp(r'^_|_$'), '');
