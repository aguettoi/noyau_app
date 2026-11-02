import 'package:flutter/widgets.dart';

import 'app_locale.dart';

class BudgetWords {
  const BudgetWords(this.language);
  final AppLanguage language;

  factory BudgetWords.of(BuildContext context) =>
      BudgetWords(AppLanguageX.fromLocale(Localizations.localeOf(context)));

  String text(String key) => _values[language]![key] ?? key;
  String format(String key, Map<String, Object> values) {
    var result = text(key);
    for (final entry in values.entries) {
      result = result.replaceAll('{${entry.key}}', '${entry.value}');
    }
    return result;
  }

  static Set<String> keysFor(AppLanguage language) =>
      Set.unmodifiable(_values[language]!.keys);
  static bool hasOwnTranslation(AppLanguage language, String key) =>
      _values[language]?[key]?.trim().isNotEmpty == true;

  static const _values = <AppLanguage, Map<String, String>>{
    AppLanguage.french: {
      'budget.title': 'Budget',
      'budget.navigation': 'Navigation Budget',
      'budget.prepare_month': 'Préparer mon mois',
      'budget.scenarios': 'Scénarios',
      'budget.history': 'Historique',
      'budget.periods_error': 'Périodes budgétaires indisponibles.',
      'budget.no_period': 'Aucune période budgétaire disponible.',
      'budget.steering': 'Pilotage du budget',
      'budget.steering_hint':
          'Suivez le prévu, le réel et les écarts de la période.',
      'budget.period': 'Période',
      'budget.month': 'Mois',
      'budget.ytd': 'YTD',
      'budget.ltd': 'LTD',
      'budget.preparation': 'Préparation budgétaire',
      'budget.preparation_hint':
          'Choisissez un scénario, ajustez le mois puis enregistrez un snapshot immuable.',
      'budget.reporting_error': 'Reporting indisponible.',
      'budget.envelopes_error': 'Enveloppes indisponibles.',
      'budget.envelope_distribution': 'Répartition des enveloppes',
      'budget.no_flow': 'Aucun flux pour cette période.',
      'budget.envelope': 'Enveloppe',
      'budget.quality_error': 'Qualité mensuelle indisponible.',
      'budget.quality_title': 'Qualité mensuelle et décisions',
      'budget.quality_totals':
          'Prévu {planned} • Réalisé {actual} • Attendu {expected} • Restant {remaining}',
      'budget.open_reconciliations': 'Rapprochements ouverts : {count}',
      'budget.missing_receipts': 'Justificatifs manquants : {count}',
      'budget.unresolved_expected': 'Attendus non résolus : {count}',
      'budget.unassigned': 'Non attribués : {count}',
      'budget.explanation':
          '{reason}\nSource : {source} • Période : {period}{action}',
      'budget.action': '\nAction : {action}',
      'budget.options': 'Options à arbitrer',
      'budget.simulation_hint':
          'Ces options sont des simulations. Aucune écriture financière n’est créée sans confirmation dans le module canonique concerné.',
      'budget.option_title': '{title} — {amount}',
      'budget.option_detail': '{consequence}\n{reason}',
      'budget.to_confirm': 'À confirmer',
      'budget.row': 'Prévu {planned} • Réel {actual}',
    },
    AppLanguage.english: {
      'budget.title': 'Budget',
      'budget.navigation': 'Budget navigation',
      'budget.prepare_month': 'Prepare my month',
      'budget.scenarios': 'Scenarios',
      'budget.history': 'History',
      'budget.periods_error': 'Budget periods are unavailable.',
      'budget.no_period': 'No budget period is available.',
      'budget.steering': 'Budget steering',
      'budget.steering_hint': 'Track planned, actual and period variances.',
      'budget.period': 'Period',
      'budget.month': 'Month',
      'budget.ytd': 'YTD',
      'budget.ltd': 'LTD',
      'budget.preparation': 'Budget preparation',
      'budget.preparation_hint':
          'Choose a scenario, adjust the month, then save an immutable snapshot.',
      'budget.reporting_error': 'Reporting is unavailable.',
      'budget.envelopes_error': 'Envelopes are unavailable.',
      'budget.envelope_distribution': 'Envelope allocation',
      'budget.no_flow': 'No flow for this period.',
      'budget.envelope': 'Envelope',
      'budget.quality_error': 'Monthly quality is unavailable.',
      'budget.quality_title': 'Monthly quality and decisions',
      'budget.quality_totals':
          'Planned {planned} • Actual {actual} • Expected {expected} • Remaining {remaining}',
      'budget.open_reconciliations': 'Open reconciliations: {count}',
      'budget.missing_receipts': 'Missing receipts: {count}',
      'budget.unresolved_expected': 'Unresolved expected items: {count}',
      'budget.unassigned': 'Unassigned: {count}',
      'budget.explanation':
          '{reason}\nSource: {source} • Period: {period}{action}',
      'budget.action': '\nAction: {action}',
      'budget.options': 'Options to decide',
      'budget.simulation_hint':
          'These options are simulations. No financial entry is created without confirmation in the relevant canonical module.',
      'budget.option_title': '{title} — {amount}',
      'budget.option_detail': '{consequence}\n{reason}',
      'budget.to_confirm': 'To confirm',
      'budget.row': 'Planned {planned} • Actual {actual}',
    },
    AppLanguage.arabic: {
      'budget.title': 'الميزانية',
      'budget.navigation': 'تنقل الميزانية',
      'budget.prepare_month': 'إعداد شهري',
      'budget.scenarios': 'السيناريوهات',
      'budget.history': 'السجل',
      'budget.periods_error': 'فترات الميزانية غير متاحة.',
      'budget.no_period': 'لا توجد فترة ميزانية.',
      'budget.steering': 'إدارة الميزانية',
      'budget.steering_hint': 'تابع المخطط والفعلي والفروق.',
      'budget.period': 'الفترة',
      'budget.month': 'الشهر',
      'budget.ytd': 'منذ بداية السنة',
      'budget.ltd': 'الكلي',
      'budget.preparation': 'إعداد الميزانية',
      'budget.preparation_hint': 'اختر سيناريو وعدل الشهر ثم احفظ لقطة ثابتة.',
      'budget.reporting_error': 'التقرير غير متاح.',
      'budget.envelopes_error': 'المغلفات غير متاحة.',
      'budget.envelope_distribution': 'توزيع المغلفات',
      'budget.no_flow': 'لا توجد حركة لهذه الفترة.',
      'budget.envelope': 'مغلف',
      'budget.quality_error': 'جودة الشهر غير متاحة.',
      'budget.quality_title': 'جودة الشهر والقرارات',
      'budget.quality_totals':
          'مخطط {planned} • فعلي {actual} • متوقع {expected} • متبقي {remaining}',
      'budget.open_reconciliations': 'مطابقات مفتوحة: {count}',
      'budget.missing_receipts': 'وثائق ناقصة: {count}',
      'budget.unresolved_expected': 'متوقعات غير محلولة: {count}',
      'budget.unassigned': 'غير مسند: {count}',
      'budget.explanation':
          '{reason}\nالمصدر: {source} • الفترة: {period}{action}',
      'budget.action': '\nالإجراء: {action}',
      'budget.options': 'خيارات للحسم',
      'budget.simulation_hint':
          'هذه الخيارات محاكاة. لا يُنشأ أي قيد مالي دون تأكيد.',
      'budget.option_title': '{title} — {amount}',
      'budget.option_detail': '{consequence}\n{reason}',
      'budget.to_confirm': 'للتأكيد',
      'budget.row': 'مخطط {planned} • فعلي {actual}',
    },
    AppLanguage.darija: {
      'budget.title': 'البودجي',
      'budget.navigation': 'التنقل فالبودجي',
      'budget.prepare_month': 'وجد الشهر ديالي',
      'budget.scenarios': 'السيناريوهات',
      'budget.history': 'التاريخ',
      'budget.periods_error': 'فترات البودجي ما متوفراش.',
      'budget.no_period': 'ما كاينا حتى فترة ديال البودجي.',
      'budget.steering': 'تدبير البودجي',
      'budget.steering_hint': 'تبع المخطط والفعلي والفرق.',
      'budget.period': 'الفترة',
      'budget.month': 'الشهر',
      'budget.ytd': 'من لول العام',
      'budget.ltd': 'الكل',
      'budget.preparation': 'توجيد البودجي',
      'budget.preparation_hint':
          'ختار سيناريو، صاوب الشهر وسجل لقطة ما كتبدلش.',
      'budget.reporting_error': 'التقرير ما متوفرش.',
      'budget.envelopes_error': 'الظروف ما متويرينش.',
      'budget.envelope_distribution': 'تقسيم الظروف',
      'budget.no_flow': 'ما كاينا حتى حركة فهاد الفترة.',
      'budget.envelope': 'ظرف',
      'budget.quality_error': 'جودة الشهر ما متوفراش.',
      'budget.quality_title': 'جودة الشهر والقرارات',
      'budget.quality_totals':
          'مخطط {planned} • تدار {actual} • متسني {expected} • باقي {remaining}',
      'budget.open_reconciliations': 'المطابقات المحلولين: {count}',
      'budget.missing_receipts': 'الجستيفيكات الناقصين: {count}',
      'budget.unresolved_expected': 'المتسنيات اللي ما تحلوش: {count}',
      'budget.unassigned': 'ما مسندينش: {count}',
      'budget.explanation':
          '{reason}\nالمصدر: {source} • الفترة: {period}{action}',
      'budget.action': '\nالإجراء: {action}',
      'budget.options': 'خيارات خاص يتقررو',
      'budget.simulation_hint':
          'هاد الخيارات غير محاكاة. ما كايتسجل حتى قيد مالي بلا تأكيد.',
      'budget.option_title': '{title} — {amount}',
      'budget.option_detail': '{consequence}\n{reason}',
      'budget.to_confirm': 'خاصو التأكيد',
      'budget.row': 'مخطط {planned} • تدار {actual}',
    },
  };
}
