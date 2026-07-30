import 'dart:convert';

import 'csv_import_templates.dart';
import 'accounts_template_download_stub.dart'
    if (dart.library.js_interop) 'accounts_template_download_web.dart'
    as platform;

final _accounts = byType(ImportTemplateType.accounts);
String get accountsTemplateFileName => _accounts.fileName;
String accountsTemplateCsv() => _accounts.csvContent;
List<int> accountsTemplateUtf8() => utf8.encode(accountsTemplateCsv());

Future<void> downloadCsvTemplate(CsvImportTemplateDefinition template) =>
    platform.download(utf8.encode(template.csvContent), template.fileName);

Future<void> downloadAccountsTemplate() => downloadCsvTemplate(_accounts);
