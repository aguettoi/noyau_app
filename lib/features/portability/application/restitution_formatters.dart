import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/money/money.dart';
import '../../reporting/domain/business_reporting.dart';
import '../../wealth/domain/wealth_models.dart';
import '../domain/restitution_models.dart';

const _moneyFormat = '#,##0.00';
const _dateFormat = 'yyyy-mm-dd';

List<int> encodeStructuredHouseholdXlsx(RestitutionDataset data) {
  final book = Excel.createExcel()..delete('Sheet1');
  _writeSheet(
    book,
    'Solde enveloppes',
    const ['Enveloppe', 'Solde MAD', 'Période', 'État', 'Périmètre', 'Source'],
    [
      for (final row in data.envelopes)
        [
          TextCellValue(row.label),
          DoubleCellValue(row.balance.dirhams),
          TextCellValue(data.period.label),
          TextCellValue(row.status),
          TextCellValue(row.scope),
          TextCellValue(row.provenance),
        ],
    ],
    widths: const [28, 16, 18, 16, 24, 24],
    moneyColumns: const {1},
  );
  _writeSheet(
    book,
    'Journal',
    const [
      'Date',
      'Nature',
      'Libellé',
      'Montant MAD',
      'Statut',
      'Provenance',
      'Acteur',
    ],
    [
      for (final row in data.journal)
        [
          DateCellValue.fromDateTime(row.date),
          TextCellValue(row.kind),
          TextCellValue(row.label),
          DoubleCellValue(row.amount.dirhams),
          TextCellValue(_status(row.status)),
          TextCellValue(row.provenance),
          TextCellValue(row.actor ?? ''),
        ],
    ],
    widths: const [14, 20, 38, 16, 16, 24, 22],
    moneyColumns: const {3},
    dateColumns: const {0},
  );
  _writeSheet(
    book,
    'Soldes cash',
    const ['Compte', 'Type', 'Solde MAD', 'Périmètre', 'Source'],
    [
      for (final row in data.cashPositions)
        [
          TextCellValue(row.label),
          TextCellValue(row.kind),
          DoubleCellValue(row.balance.dirhams),
          TextCellValue(row.scope),
          TextCellValue(row.provenance),
        ],
    ],
    widths: const [30, 18, 16, 24, 28],
    moneyColumns: const {2},
  );
  _writeSheet(
    book,
    'Dettes et créances',
    const [
      'Nature',
      'Libellé',
      'Contrepartie',
      'Initial MAD',
      'Réglé MAD',
      'Restant MAD',
      'Échéance',
      'État',
      'Source',
    ],
    [
      for (final row in data.obligations)
        [
          TextCellValue(row.kind),
          TextCellValue(row.label),
          TextCellValue(row.counterparty ?? ''),
          DoubleCellValue(row.initialAmount.dirhams),
          DoubleCellValue(row.settledAmount.dirhams),
          DoubleCellValue(row.remainingAmount.dirhams),
          row.dueAt == null
              ? TextCellValue('')
              : DateCellValue.fromDateTime(row.dueAt!),
          TextCellValue(row.status),
          TextCellValue(row.provenance),
        ],
    ],
    widths: const [16, 34, 24, 16, 16, 16, 14, 18, 24],
    moneyColumns: const {3, 4, 5},
    dateColumns: const {6},
  );
  book.delete('Sheet1');
  return book.encode()!;
}

List<int> encodeAmortizationXlsx(AmortizationExportDataset data) {
  final book = Excel.createExcel()..rename('Sheet1', 'Amortissement');
  final structure = switch (data.financing.structure) {
    FinancingStructure.interestLoan => 'Financement à intérêt',
    FinancingStructure.murabaha => 'Murabaha',
    FinancingStructure.fixedCost => 'Coût fixe',
    FinancingStructure.other => 'Autre structure',
  };
  final sheet = book['Amortissement'];
  sheet.appendRow([TextCellValue(data.financing.label)]);
  sheet.appendRow([TextCellValue('Structure'), TextCellValue(structure)]);
  sheet.appendRow([
    TextCellValue('Capital initial MAD'),
    DoubleCellValue(data.financing.principalInitial.dirhams),
  ]);
  sheet.appendRow([
    TextCellValue('Capital restant MAD'),
    DoubleCellValue(data.financing.remainingLiability.dirhams),
  ]);
  sheet.appendRow([TextCellValue('')]);
  sheet.appendRow(
    const [
      'Échéance',
      'Date',
      'Paiement MAD',
      'Capital MAD',
      'Coût / marge MAD',
      'Restant MAD',
    ].map(TextCellValue.new).toList(),
  );
  for (final row in data.schedule) {
    sheet.appendRow([
      IntCellValue(row.number),
      DateCellValue.fromDateTime(row.date),
      DoubleCellValue(row.payment.dirhams),
      DoubleCellValue(row.principal.dirhams),
      DoubleCellValue(row.cost.dirhams),
      DoubleCellValue(row.remaining.dirhams),
    ]);
  }
  _styleSheet(
    sheet,
    headerRow: 5,
    widths: const [12, 14, 18, 18, 20, 18],
    moneyColumns: const {2, 3, 4, 5},
    dateColumns: const {1},
  );
  for (final row in [2, 3]) {
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row))
        .cellStyle = CellStyle(
      numberFormat: NumFormat.custom(formatCode: _moneyFormat),
    );
  }
  return book.encode()!;
}

List<int> encodeFiscalHousingXlsx(FiscalHousingExportDataset data) {
  final book = Excel.createExcel()..rename('Sheet1', 'Fiscalité logement');
  _writeSheet(
    book,
    'Fiscalité logement',
    const [
      'Début période',
      'Fin période',
      'Date effet',
      'Nature',
      'Base éligible MAD',
      'Taux',
      'Plafond MAD',
      'Montant MAD',
      'Source',
    ],
    [
      for (final row in data.rows)
        [
          row.periodStart == null
              ? TextCellValue('')
              : DateCellValue.fromDateTime(row.periodStart!),
          row.periodEnd == null
              ? TextCellValue('')
              : DateCellValue.fromDateTime(row.periodEnd!),
          row.effectiveDate == null
              ? TextCellValue('')
              : DateCellValue.fromDateTime(row.effectiveDate!),
          TextCellValue(row.recognition),
          row.eligibleBase == null
              ? TextCellValue('')
              : DoubleCellValue(row.eligibleBase!.dirhams),
          row.rate == null ? TextCellValue('') : DoubleCellValue(row.rate!),
          row.ceiling == null
              ? TextCellValue('')
              : DoubleCellValue(row.ceiling!.dirhams),
          DoubleCellValue(row.amount.dirhams),
          TextCellValue(row.source),
        ],
    ],
    widths: const [14, 14, 14, 24, 20, 12, 18, 18, 30],
    moneyColumns: const {4, 6, 7},
    dateColumns: const {0, 1, 2},
    percentageColumns: const {5},
  );
  return book.encode()!;
}

Future<List<int>> encodePeriodReportPdf(RestitutionDataset data) async {
  final pdf = pw.Document(
    title: 'FINANCIEL PILOTE - rapport ${data.period.fileKey}',
    author: 'FINANCIEL PILOTE',
    subject: 'Restitution financière autorisée',
  );
  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      footer: (context) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          'Page ${context.pageNumber}/${context.pagesCount}',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
        ),
      ),
      build: (_) => [
        pw.Text(
          'FINANCIEL PILOTE',
          style: pw.TextStyle(fontSize: 12, color: PdfColors.blueGrey700),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'Rapport ${data.period.label}',
          style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
        ),
        pw.Text(
          'Période du ${_date(data.period.start)} au ${_date(data.period.endExclusive.subtract(const Duration(days: 1)))}',
        ),
        pw.SizedBox(height: 18),
        _pdfHeading('Synthèse'),
        _pdfKeyValues([
          ('Revenus réalisés', data.totalFor('Revenus réalisés')),
          ('Dépenses réalisées', data.totalFor('Dépenses réalisées')),
          ('Valeur nette visible', data.netWorth),
          (
            'Dettes et créances visibles',
            Money.fromMinorUnits(
              data.obligations.fold(
                0,
                (sum, row) => sum + row.remainingAmount.minorUnits,
              ),
            ),
          ),
        ]),
        pw.SizedBox(height: 14),
        _pdfHeading('Enveloppes'),
        if (data.envelopes.isEmpty)
          pw.Text('Aucune enveloppe visible pour cette restitution.')
        else
          _pdfTable(
            const ['Enveloppe', 'Solde MAD', 'Périmètre'],
            [
              for (final row in data.envelopes)
                [row.label, _amount(row.balance), row.scope],
            ],
          ),
        pw.SizedBox(height: 14),
        _pdfHeading('Faits significatifs'),
        if (data.timeline.isEmpty)
          pw.Text('Aucun fait significatif visible sur la période.')
        else
          for (final fact in data.timeline.take(20))
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 5),
              child: pw.Text(
                '${_date(fact.date)} - ${fact.title}${fact.amount == null ? '' : ' (${_amount(fact.amount!)})'} - ${fact.reason}',
              ),
            ),
        pw.SizedBox(height: 14),
        _pdfHeading('Dettes, créances et échéances'),
        if (data.obligations.isEmpty)
          pw.Text('Aucune dette ou créance visible.')
        else
          _pdfTable(
            const ['Nature', 'Libellé', 'Restant MAD', 'Échéance'],
            [
              for (final row in data.obligations)
                [
                  row.kind,
                  row.label,
                  _amount(row.remainingAmount),
                  row.dueAt == null ? '' : _date(row.dueAt!),
                ],
            ],
          ),
        pw.SizedBox(height: 14),
        _pdfHeading('Patrimoine visible'),
        pw.Text(
          '${data.assets.length} actif(s) et ${data.financings.length} financement(s) autorisé(s). Valeur nette visible : ${_amount(data.netWorth)}.',
        ),
        pw.SizedBox(height: 14),
        _pdfHeading('Limites de complétude'),
        for (final limitation in data.limitations) pw.Bullet(text: limitation),
      ],
    ),
  );
  return pdf.save();
}

List<int> encodePeriodPresentationPptx(RestitutionDataset data) {
  final slides = <_PptSlide>[
    _PptSlide('Rapport ${data.period.label}', [
      'FINANCIEL PILOTE',
      'Période du ${_date(data.period.start)} au ${_date(data.period.endExclusive.subtract(const Duration(days: 1)))}',
    ]),
    _PptSlide('Synthèse de période', [
      'Revenus réalisés : ${_amount(data.totalFor('Revenus réalisés'))}',
      'Dépenses réalisées : ${_amount(data.totalFor('Dépenses réalisées'))}',
      'Valeur nette visible : ${_amount(data.netWorth)}',
    ]),
    _PptSlide('Budget et enveloppes', [
      if (data.envelopes.isEmpty)
        'Aucune enveloppe visible'
      else
        ...data.envelopes
            .take(8)
            .map((row) => '${row.label} : ${_amount(row.balance)}'),
    ]),
    _PptSlide('Événements significatifs', [
      if (data.timeline.isEmpty)
        'Aucun fait significatif visible sur la période'
      else
        ...data.timeline
            .take(7)
            .map((fact) => '${_date(fact.date)} - ${fact.title}'),
    ]),
    _PptSlide('Patrimoine et dettes', [
      'Actifs visibles : ${data.assets.length}',
      'Financements visibles : ${data.financings.length}',
      'Valeur nette visible : ${_amount(data.netWorth)}',
      'Dettes et créances visibles : ${data.obligations.length}',
    ]),
    _PptSlide('Échéances', [
      if (data.obligations.where((row) => row.dueAt != null).isEmpty)
        'Aucune échéance datée visible'
      else
        ...data.obligations
            .where((row) => row.dueAt != null)
            .take(7)
            .map(
              (row) =>
                  '${_date(row.dueAt!)} - ${row.label} : ${_amount(row.remainingAmount)}',
            ),
    ]),
    _PptSlide('Points d’attention', [
      ...data.limitations.take(6),
      if (data.limitations.isEmpty)
        'Aucune limite de complétude signalée par le dataset',
    ]),
    const _PptSlide('Conclusion', [
      'Les montants présentés proviennent des lectures autorisées au moment de la génération.',
      'Les données absentes ou privées ne sont ni estimées ni reconstituées.',
    ]),
  ];
  return _buildPptx(slides);
}

void _writeSheet(
  Excel book,
  String name,
  List<String> headers,
  List<List<CellValue>> rows, {
  required List<double> widths,
  Set<int> moneyColumns = const {},
  Set<int> dateColumns = const {},
  Set<int> percentageColumns = const {},
}) {
  final sheet = book[name];
  sheet.appendRow(headers.map(TextCellValue.new).toList());
  for (final row in rows) {
    sheet.appendRow(row);
  }
  _styleSheet(
    sheet,
    widths: widths,
    moneyColumns: moneyColumns,
    dateColumns: dateColumns,
    percentageColumns: percentageColumns,
  );
}

void _styleSheet(
  Sheet sheet, {
  int headerRow = 0,
  required List<double> widths,
  Set<int> moneyColumns = const {},
  Set<int> dateColumns = const {},
  Set<int> percentageColumns = const {},
}) {
  final header = CellStyle(
    bold: true,
    fontColorHex: ExcelColor.white,
    backgroundColorHex: ExcelColor.fromHexString('#1F4E78'),
    verticalAlign: VerticalAlign.Center,
  );
  for (var column = 0; column < widths.length; column++) {
    sheet.setColumnWidth(column, widths[column]);
    sheet
            .cell(
              CellIndex.indexByColumnRow(
                columnIndex: column,
                rowIndex: headerRow,
              ),
            )
            .cellStyle =
        header;
  }
  for (var row = headerRow + 1; row < sheet.maxRows; row++) {
    for (final column in moneyColumns) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: column, rowIndex: row))
          .cellStyle = CellStyle(
        numberFormat: NumFormat.custom(formatCode: _moneyFormat),
      );
    }
    for (final column in dateColumns) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: column, rowIndex: row))
          .cellStyle = CellStyle(
        numberFormat: NumFormat.custom(formatCode: _dateFormat),
      );
    }
    for (final column in percentageColumns) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: column, rowIndex: row))
          .cellStyle = CellStyle(
        numberFormat: NumFormat.custom(formatCode: '0.00%'),
      );
    }
  }
}

pw.Widget _pdfHeading(String text) => pw.Text(
  text,
  style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
);

pw.Widget _pdfKeyValues(List<(String, Money)> values) => pw.Wrap(
  spacing: 18,
  runSpacing: 8,
  children: [
    for (final value in values)
      pw.Container(
        width: 230,
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey400),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(value.$1, style: const pw.TextStyle(fontSize: 9)),
            pw.Text(
              _amount(value.$2),
              style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
            ),
          ],
        ),
      ),
  ],
);

pw.Widget _pdfTable(List<String> headers, List<List<String>> rows) =>
    pw.TableHelper.fromTextArray(
      headers: headers,
      data: rows,
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey100),
      cellStyle: const pw.TextStyle(fontSize: 9),
      cellAlignment: pw.Alignment.centerLeft,
    );

String _status(ReportFactStatus value) => switch (value) {
  ReportFactStatus.observed => 'Réalisé',
  ReportFactStatus.expected => 'Attendu',
  ReportFactStatus.projected => 'Projeté',
  ReportFactStatus.imported => 'Importé',
};

String _amount(Money value) => '${value.dirhams.toStringAsFixed(2)} MAD';
String _date(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';

class _PptSlide {
  const _PptSlide(this.title, this.lines);
  final String title;
  final List<String> lines;
}

List<int> _buildPptx(List<_PptSlide> slides) {
  final archive = Archive();
  void add(String name, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  add('[Content_Types].xml', _contentTypes(slides.length));
  add('_rels/.rels', _packageRelationships);
  add('docProps/core.xml', _coreProperties);
  add('docProps/app.xml', _appProperties(slides.length));
  add('ppt/presentation.xml', _presentation(slides.length));
  add(
    'ppt/_rels/presentation.xml.rels',
    _presentationRelationships(slides.length),
  );
  add('ppt/presProps.xml', _presentationProperties);
  add('ppt/viewProps.xml', _viewProperties);
  add('ppt/tableStyles.xml', _tableStyles);
  add('ppt/theme/theme1.xml', _theme);
  add('ppt/slideMasters/slideMaster1.xml', _slideMaster);
  add(
    'ppt/slideMasters/_rels/slideMaster1.xml.rels',
    _slideMasterRelationships,
  );
  add('ppt/slideLayouts/slideLayout1.xml', _slideLayout);
  add(
    'ppt/slideLayouts/_rels/slideLayout1.xml.rels',
    _slideLayoutRelationships,
  );
  for (var index = 0; index < slides.length; index++) {
    add('ppt/slides/slide${index + 1}.xml', _slideXml(slides[index]));
    add('ppt/slides/_rels/slide${index + 1}.xml.rels', _slideRelationships);
  }
  return ZipEncoder().encode(archive)!;
}

String _xml(String value) => const HtmlEscape(
  HtmlEscapeMode.element,
).convert(value).replaceAll('&#39;', '&apos;');

String _contentTypes(int count) =>
    '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/><Override PartName="/ppt/presProps.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presProps+xml"/><Override PartName="/ppt/viewProps.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.viewProps+xml"/><Override PartName="/ppt/tableStyles.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.tableStyles+xml"/><Override PartName="/ppt/slideMasters/slideMaster1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml"/><Override PartName="/ppt/slideLayouts/slideLayout1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"/><Override PartName="/ppt/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>${List.generate(count, (i) => '<Override PartName="/ppt/slides/slide${i + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>').join()}<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/><Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/></Types>''';

const _packageRelationships =
    '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="ppt/presentation.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/><Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/></Relationships>''';

const _coreProperties =
    '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><dc:title>FINANCIEL PILOTE</dc:title><dc:creator>FINANCIEL PILOTE</dc:creator><cp:lastModifiedBy>FINANCIEL PILOTE</cp:lastModifiedBy></cp:coreProperties>''';

String _appProperties(int count) =>
    '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes"><Application>FINANCIEL PILOTE</Application><PresentationFormat>On-screen Show (16:9)</PresentationFormat><Slides>$count</Slides><Notes>0</Notes><HiddenSlides>0</HiddenSlides></Properties>''';

String _presentation(int count) =>
    '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:presentation xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"><p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/></p:sldMasterIdLst><p:sldIdLst>${List.generate(count, (i) => '<p:sldId id="${256 + i}" r:id="rId${i + 2}"/>').join()}</p:sldIdLst><p:sldSz cx="12192000" cy="6858000" type="screen16x9"/><p:notesSz cx="6858000" cy="9144000"/></p:presentation>''';

String _presentationRelationships(int count) =>
    '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="slideMasters/slideMaster1.xml"/>${List.generate(count, (i) => '<Relationship Id="rId${i + 2}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide${i + 1}.xml"/>').join()}</Relationships>''';

const _presentationProperties =
    '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?><p:presentationPr xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"/>''';
const _viewProperties =
    '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?><p:viewPr xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" lastView="sldView"><p:normalViewPr/><p:slideViewPr/><p:notesTextViewPr/><p:gridSpacing cx="72008" cy="72008"/></p:viewPr>''';
const _tableStyles =
    '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?><a:tblStyleLst xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" def="{5C22544A-7EE6-4342-B048-85BDC9FD1C3A}"/>''';

const _slideMaster =
    '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?><p:sldMaster xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"><p:cSld name="FINANCIEL PILOTE"><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr></p:spTree></p:cSld><p:sldLayoutIdLst><p:sldLayoutId id="1" r:id="rId1"/></p:sldLayoutIdLst><p:txStyles><p:titleStyle/><p:bodyStyle/><p:otherStyle/></p:txStyles></p:sldMaster>''';
const _slideMasterRelationships =
    '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" Target="../theme/theme1.xml"/></Relationships>''';
const _slideLayout =
    '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?><p:sldLayout xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" type="blank" preserve="1"><p:cSld name="Blank"><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr></p:spTree></p:cSld></p:sldLayout>''';
const _slideLayoutRelationships =
    '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="../slideMasters/slideMaster1.xml"/></Relationships>''';
const _slideRelationships =
    '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/></Relationships>''';

const _theme =
    '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?><a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="FINANCIEL PILOTE"><a:themeElements><a:clrScheme name="FINANCIEL PILOTE"><a:dk1><a:srgbClr val="17243A"/></a:dk1><a:lt1><a:srgbClr val="FFFFFF"/></a:lt1><a:dk2><a:srgbClr val="1F4E78"/></a:dk2><a:lt2><a:srgbClr val="F3F6F8"/></a:lt2><a:accent1><a:srgbClr val="1F4E78"/></a:accent1><a:accent2><a:srgbClr val="2E75B6"/></a:accent2><a:accent3><a:srgbClr val="70AD47"/></a:accent3><a:accent4><a:srgbClr val="FFC000"/></a:accent4><a:accent5><a:srgbClr val="A5A5A5"/></a:accent5><a:accent6><a:srgbClr val="4472C4"/></a:accent6><a:hlink><a:srgbClr val="0563C1"/></a:hlink><a:folHlink><a:srgbClr val="954F72"/></a:folHlink></a:clrScheme><a:fontScheme name="FINANCIEL PILOTE"><a:majorFont><a:latin typeface="Aptos Display"/></a:majorFont><a:minorFont><a:latin typeface="Aptos"/></a:minorFont></a:fontScheme><a:fmtScheme name="FINANCIEL PILOTE"><a:fillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:fillStyleLst><a:lnStyleLst><a:ln w="6350"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln></a:lnStyleLst><a:effectStyleLst><a:effectStyle><a:effectLst/></a:effectStyle></a:effectStyleLst><a:bgFillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:bgFillStyleLst></a:fmtScheme></a:themeElements></a:theme>''';

String _slideXml(_PptSlide slide) {
  final body = slide.lines.isEmpty
      ? const ['Aucune donnée visible']
      : slide.lines;
  return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?><p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"><p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>${_textShape(2, 'Titre', slide.title, 700000, 500000, 10800000, 900000, 2800, true)}${_textShape(3, 'Contenu', body.map((line) => '• $line').join('\n'), 900000, 1650000, 10200000, 4300000, 1800, false)}</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>''';
}

String _textShape(
  int id,
  String name,
  String text,
  int x,
  int y,
  int cx,
  int cy,
  int size,
  bool bold,
) {
  final paragraphs = text
      .split('\n')
      .map(
        (line) =>
            '<a:p><a:r><a:rPr lang="fr-FR" sz="$size"${bold ? ' b="1"' : ''}/><a:t>${_xml(line)}</a:t></a:r><a:endParaRPr lang="fr-FR" sz="$size"/></a:p>',
      )
      .join();
  return '<p:sp><p:nvSpPr><p:cNvPr id="$id" name="$name"/><p:cNvSpPr txBox="1"/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x="$x" y="$y"/><a:ext cx="$cx" cy="$cy"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:noFill/><a:ln><a:noFill/></a:ln></p:spPr><p:txBody><a:bodyPr wrap="square"/><a:lstStyle/>$paragraphs</p:txBody></p:sp>';
}
