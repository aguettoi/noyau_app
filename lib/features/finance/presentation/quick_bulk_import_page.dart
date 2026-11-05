import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_locale.dart';
import '../../../core/theme/app_design_system.dart';
import '../../envelopes/application/providers/remote_envelopes_provider.dart';
import '../application/providers/active_household_provider.dart';
import '../application/providers/remote_accounts_provider.dart';
import '../application/providers/remote_household_members_provider.dart';
import '../application/providers/supabase_client_provider.dart';
import '../application/quick_bulk_import.dart';
import '../application/quick_bulk_template_download.dart';

typedef QuickImportCommit = Future<int> Function(List<QuickImportRow> rows);

class QuickBulkImportPage extends ConsumerStatefulWidget {
  const QuickBulkImportPage({
    super.key,
    this.pickBytes,
    this.commit,
    this.referenceCatalog,
  });
  final Future<Uint8List?> Function()? pickBytes;
  final QuickImportCommit? commit;
  final QuickImportReferenceCatalog? referenceCatalog;
  @override
  ConsumerState<QuickBulkImportPage> createState() =>
      _QuickBulkImportPageState();
}

class _QuickBulkImportPageState extends ConsumerState<QuickBulkImportPage> {
  QuickImportPreview? _preview;
  bool _busy = false;
  String? _fileName;
  String? _result;
  QuickImportReferenceCatalog? _catalog;
  String? _bulkMember;
  String? _bulkAccount;
  String? _bulkEnvelope;
  String? _idempotencyKey;

  @override
  Widget build(BuildContext context) {
    final w = _QuickWords.of(context);
    final useRemoteReferences = widget.referenceCatalog == null;
    final AsyncValue<List<dynamic>> accounts = useRemoteReferences
        ? ref
              .watch(remoteAccountsProvider)
              .whenData((items) => items.cast<dynamic>())
        : const AsyncData([]);
    final AsyncValue<List<dynamic>> members = useRemoteReferences
        ? ref
              .watch(remoteHouseholdMembersProvider)
              .whenData((items) => items.cast<dynamic>())
        : const AsyncData([]);
    final AsyncValue<List<dynamic>> envelopes = useRemoteReferences
        ? ref
              .watch(remoteEnvelopeBalancesProvider)
              .whenData((items) => items.cast<dynamic>())
        : const AsyncData([]);
    return Scaffold(
      appBar: AppBar(title: Text(w('title'))),
      body: SafeArea(
        child: ListView(
          padding: AppSpacing.page,
          children: [
            Text(w('subtitle'), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.md),
            _StepCard(
              number: 1,
              title: w('download'),
              body: w('download_help'),
              action: FilledButton.icon(
                onPressed: _busy ? null : _download,
                icon: const Icon(Icons.download_outlined),
                label: Text(w('download_button')),
              ),
            ),
            _StepCard(
              number: 2,
              title: w('upload'),
              body: w('upload_help'),
              action: OutlinedButton.icon(
                key: const Key('quick-import-file-picker'),
                onPressed:
                    _busy ||
                        accounts.isLoading ||
                        members.isLoading ||
                        envelopes.isLoading
                    ? null
                    : () => _pick(
                        accounts.requireValue,
                        members.requireValue,
                        envelopes.requireValue,
                      ),
                icon: const Icon(Icons.upload_file_outlined),
                label: Text(w('choose')),
              ),
            ),
            if (_fileName != null) Text('${w('file')} : $_fileName'),
            if (_busy) const Center(child: CircularProgressIndicator()),
            if (_preview != null) ..._buildPreview(w),
            if (_result != null)
              Semantics(
                liveRegion: true,
                child: Text(
                  _result!,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildPreview(_QuickWords w) {
    final preview = _preview!;
    final blockedRows = preview.issues
        .where((issue) => issue.severity == QuickImportSeverity.blocking)
        .map((issue) => issue.row)
        .whereType<int>()
        .toSet();
    final valid = preview.rows
        .where((row) => !blockedRows.contains(row.sourceRow))
        .length;
    return [
      const SizedBox(height: AppSpacing.md),
      Text(w('control'), style: Theme.of(context).textTheme.titleLarge),
      Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: [
          Chip(label: Text('${w('valid')} : $valid')),
          Chip(label: Text('${w('blocking')} : ${preview.blockingCount}')),
          Chip(label: Text('${w('warnings')} : ${preview.warningCount}')),
        ],
      ),
      for (final issue in preview.issues)
        ListTile(
          leading: Icon(
            issue.severity == QuickImportSeverity.blocking
                ? Icons.error_outline
                : Icons.warning_amber_outlined,
            color: issue.severity == QuickImportSeverity.blocking
                ? Theme.of(context).colorScheme.error
                : null,
          ),
          title: Text(issue.message),
          subtitle: issue.row == null ? null : Text('${w('row')} ${issue.row}'),
        ),
      if (preview.blockingCount > 0 && _catalog != null) ...[
        Text(w('bulk_fix'), style: Theme.of(context).textTheme.titleMedium),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            _choice(
              w('member'),
              _catalog!.members,
              _bulkMember,
              (value) => setState(() => _bulkMember = value),
            ),
            _choice(
              w('account'),
              _catalog!.accounts,
              _bulkAccount,
              (value) => setState(() => _bulkAccount = value),
            ),
            _choice(
              w('envelope'),
              _catalog!.envelopes,
              _bulkEnvelope,
              (value) => setState(() => _bulkEnvelope = value),
            ),
            FilledButton.tonal(
              onPressed: _applyBulkCorrection,
              child: Text(w('apply_all')),
            ),
          ],
        ),
      ],
      if (preview.rows.isNotEmpty) ...[
        Text(w('preview'), style: Theme.of(context).textTheme.titleLarge),
        for (final row in preview.rows.take(20))
          ListTile(
            title: Text(row.description),
            subtitle: Text(
              '${row.date.toIso8601String().substring(0, 10)} • ${row.account} • ${row.member}',
            ),
            trailing: Text('${row.amount.toStringAsFixed(2)} ${row.currency}'),
          ),
        Text(w('no_mutation')),
        FilledButton.icon(
          key: const Key('quick-import-confirm'),
          onPressed: preview.canConfirm && !_busy ? () => _confirm(w) : null,
          icon: const Icon(Icons.verified_outlined),
          label: Text(w('confirm')),
        ),
      ],
    ];
  }

  Future<void> _download() => saveQuickImportTemplate(
    buildQuickImportTemplate(),
    'FINANCIEL_PILOTE_import_rapide.xlsx',
  );

  Future<void> _pick(
    List<dynamic> accounts,
    List<dynamic> members,
    List<dynamic> envelopes,
  ) async {
    final bytes = await (widget.pickBytes?.call() ?? _pickFile());
    if (bytes == null || !mounted) return;
    setState(() {
      _busy = true;
      _result = null;
    });
    final catalog =
        widget.referenceCatalog ??
        QuickImportReferenceCatalog(
          members: {for (final m in members) m.displayName as String},
          accounts: {for (final a in accounts) a.name as String},
          envelopes: {for (final e in envelopes) e.name as String},
        );
    final parsed = QuickBulkImportParser().parse(bytes, catalog);
    if (mounted) {
      setState(() {
        _catalog = catalog;
        _idempotencyKey = sha256.convert(bytes).toString();
        _preview = parsed;
        _busy = false;
      });
    }
  }

  Widget _choice(
    String label,
    Set<String> values,
    String? value,
    ValueChanged<String?> changed,
  ) => SizedBox(
    width: 220,
    child: DropdownButtonFormField<String>(
      isExpanded: true,
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final item in values)
          DropdownMenuItem(value: item, child: Text(item)),
      ],
      onChanged: changed,
    ),
  );

  void _applyBulkCorrection() {
    final preview = _preview;
    final catalog = _catalog;
    if (preview == null || catalog == null) return;
    setState(
      () => _preview = QuickBulkImportParser().applyBulkCorrection(
        preview,
        catalog,
        member: _bulkMember,
        account: _bulkAccount,
        envelope: _bulkEnvelope,
      ),
    );
  }

  Future<Uint8List?> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
      withData: true,
    );
    if (result == null) return null;
    _fileName = result.files.single.name;
    return result.files.single.bytes;
  }

  Future<void> _confirm(_QuickWords w) async {
    final preview = _preview!;
    final accepted = preview.rows
        .where((r) => !r.ignored)
        .toList(growable: false);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(w('confirm_title')),
        content: Text(w.format('confirm_body', {'count': accepted.length})),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(w('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(w('confirm')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final count =
          await (widget.commit?.call(accepted) ?? _commitServer(accepted));
      if (mounted) {
        setState(() => _result = w.format('success', {'count': count}));
      }
    } catch (_) {
      if (mounted) setState(() => _result = w('failure'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<int> _commitServer(List<QuickImportRow> rows) async {
    final household = await ref.read(activeHouseholdProvider.future);
    final id = household.householdId;
    if (!household.hasActiveHousehold || id == null) {
      throw StateError('No active household');
    }
    final result = await ref
        .read(supabaseClientProvider)
        .rpc(
          'quick_bulk_import_financial_events',
          params: {
            'p_household_id': id,
            'p_rows': [
              for (final r in rows)
                {
                  'source_row': r.sourceRow,
                  'kind': r.kind.name,
                  'occurred_on': r.date.toIso8601String().substring(0, 10),
                  'amount': r.amount.toStringAsFixed(2),
                  'currency': r.currency,
                  'member_name': r.member,
                  'account_name': r.account,
                  'envelope_name': r.envelope.isEmpty ? null : r.envelope,
                  'category': r.category.isEmpty ? null : r.category,
                  'description': r.description,
                  'external_reference': r.reference.isEmpty
                      ? null
                      : r.reference,
                },
            ],
            'p_idempotency_key': _idempotencyKey,
          },
        );
    return (result as num).toInt();
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.number,
    required this.title,
    required this.body,
    required this.action,
  });
  final int number;
  final String title;
  final String body;
  final Widget action;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: AppSpacing.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$number. $title',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(body),
          const SizedBox(height: 10),
          action,
        ],
      ),
    ),
  );
}

class _QuickWords {
  const _QuickWords(this.language);
  final AppLanguage language;
  factory _QuickWords.of(BuildContext context) =>
      _QuickWords(AppLanguageX.fromLocale(Localizations.localeOf(context)));
  String call(String key) => _v[language]![key]!;
  String format(String key, Map<String, Object> values) {
    var out = call(key);
    for (final e in values.entries) {
      out = out.replaceAll('{${e.key}}', '${e.value}');
    }
    return out;
  }

  static const _v = <AppLanguage, Map<String, String>>{
    AppLanguage.french: {
      'title': 'Import rapide Excel',
      'subtitle': 'Importer plusieurs dépenses et revenus en toute sécurité.',
      'bulk_fix': 'Correction en masse',
      'member': 'Membre',
      'account': 'Compte',
      'envelope': 'Enveloppe',
      'apply_all': 'Appliquer aux lignes',
      'download': 'Télécharger le modèle',
      'download_help':
          'Utilisez le modèle officiel, sans identifiant technique.',
      'download_button': 'Télécharger le modèle Excel',
      'upload': 'Vérifier mon fichier',
      'upload_help': 'Le fichier est contrôlé avant toute écriture.',
      'choose': 'Choisir un fichier .xlsx',
      'file': 'Fichier',
      'control': 'Résultat du contrôle',
      'valid': 'Lignes lues',
      'blocking': 'À corriger',
      'warnings': 'Avertissements',
      'row': 'Ligne',
      'preview': 'Prévisualisation',
      'no_mutation':
          'Aucune opération ne sera créée avant votre confirmation explicite.',
      'confirm': 'Confirmer l’import',
      'confirm_title': 'Créer ces opérations ?',
      'confirm_body':
          '{count} opération(s) seront créées via les règles financières sécurisées.',
      'cancel': 'Annuler',
      'success': '{count} opération(s) importée(s).',
      'failure':
          'Import impossible. Aucune opération partielle n’a été conservée.',
    },
    AppLanguage.english: {
      'title': 'Quick Excel import',
      'subtitle': 'Import multiple expenses and income securely.',
      'bulk_fix': 'Bulk correction',
      'member': 'Member',
      'account': 'Account',
      'envelope': 'Envelope',
      'apply_all': 'Apply to rows',
      'download': 'Download the template',
      'download_help':
          'Use the official template with no technical identifier.',
      'download_button': 'Download Excel template',
      'upload': 'Check my file',
      'upload_help': 'The file is checked before any write.',
      'choose': 'Choose an .xlsx file',
      'file': 'File',
      'control': 'Check result',
      'valid': 'Rows read',
      'blocking': 'To fix',
      'warnings': 'Warnings',
      'row': 'Row',
      'preview': 'Preview',
      'no_mutation':
          'No operation will be created before your explicit confirmation.',
      'confirm': 'Confirm import',
      'confirm_title': 'Create these operations?',
      'confirm_body':
          '{count} operation(s) will be created through secure financial rules.',
      'cancel': 'Cancel',
      'success': '{count} operation(s) imported.',
      'failure': 'Import failed. No partial operation was retained.',
    },
    AppLanguage.arabic: {
      'title': 'استيراد سريع من Excel',
      'subtitle': 'استورد عدة مصاريف ومداخيل بأمان.',
      'bulk_fix': 'تصحيح جماعي',
      'member': 'العضو',
      'account': 'الحساب',
      'envelope': 'المظروف',
      'apply_all': 'تطبيق على الأسطر',
      'download': 'تنزيل النموذج',
      'download_help': 'استعمل النموذج الرسمي بدون أي معرّف تقني.',
      'download_button': 'تنزيل نموذج Excel',
      'upload': 'فحص ملفي',
      'upload_help': 'يتم فحص الملف قبل أي كتابة.',
      'choose': 'اختيار ملف xlsx.',
      'file': 'الملف',
      'control': 'نتيجة الفحص',
      'valid': 'الأسطر المقروءة',
      'blocking': 'تحتاج إلى تصحيح',
      'warnings': 'تنبيهات',
      'row': 'السطر',
      'preview': 'معاينة',
      'no_mutation': 'لن يتم إنشاء أي عملية قبل تأكيدك الصريح.',
      'confirm': 'تأكيد الاستيراد',
      'confirm_title': 'إنشاء هذه العمليات؟',
      'confirm_body': 'سيتم إنشاء {count} عملية عبر القواعد المالية الآمنة.',
      'cancel': 'إلغاء',
      'success': 'تم استيراد {count} عملية.',
      'failure': 'تعذر الاستيراد. لم يتم الاحتفاظ بأي عملية جزئية.',
    },
    AppLanguage.darija: {
      'title': 'إدخال سريع من Excel',
      'subtitle': 'دخل بزاف ديال المصاريف والمداخيل بأمان.',
      'bulk_fix': 'تصحيح بالجملة',
      'member': 'العضو',
      'account': 'الحساب',
      'envelope': 'الظرف',
      'apply_all': 'طبق على السطور',
      'download': 'هبط النموذج',
      'download_help': 'استعمل النموذج الرسمي بلا حتى معرّف تقني.',
      'download_button': 'هبط نموذج Excel',
      'upload': 'فحص الملف ديالي',
      'upload_help': 'الملف كيتفحص قبل أي كتابة.',
      'choose': 'اختار ملف xlsx.',
      'file': 'الملف',
      'control': 'نتيجة الفحص',
      'valid': 'السطور المقرويين',
      'blocking': 'خاصها التصحيح',
      'warnings': 'تنبيهات',
      'row': 'السطر',
      'preview': 'معاينة',
      'no_mutation': 'ما غادي تتخلق حتى عملية قبل التأكيد الصريح ديالك.',
      'confirm': 'أكد الإدخال',
      'confirm_title': 'نخلقو هاد العمليات؟',
      'confirm_body': 'غادي يتخلقو {count} عملية بالقواعد المالية المؤمنة.',
      'cancel': 'إلغاء',
      'success': 'تدخلو {count} عملية.',
      'failure': 'ما قدرناش ندخلو الملف. ما تخزنت حتى عملية ناقصة.',
    },
  };
}
