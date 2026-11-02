import 'package:flutter/widgets.dart';

import 'app_locale.dart';

class FinanceWords {
  const FinanceWords(this.language);

  final AppLanguage language;

  factory FinanceWords.of(BuildContext context) =>
      FinanceWords(AppLanguageX.fromLocale(Localizations.localeOf(context)));

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
      'common.add': 'Ajouter',
      'common.cancel': 'Annuler',
      'common.close': 'Fermer',
      'common.confirm': 'Confirmer',
      'common.create': 'Créer',
      'common.save': 'Enregistrer',
      'common.none': 'Aucun',
      'common.active': 'Actif',
      'common.archived': 'Archivé',
      'payment.title': 'Moyens de paiement',
      'payment.unavailable': 'Moyens de paiement indisponibles.',
      'payment.empty': 'Aucun moyen de paiement configuré.',
      'payment.kind.card': 'Carte bancaire',
      'payment.kind.cash': 'Espèces',
      'payment.kind.transfer': 'Virement',
      'payment.kind.other': 'Autre',
      'payment.linked_account': 'Compte associé',
      'payment.linked_holder': 'Titulaire associé',
      'payment.add_title': 'Ajouter un moyen de paiement',
      'payment.edit_title': 'Modifier le moyen de paiement',
      'payment.label': 'Libellé',
      'payment.type': 'Type',
      'payment.account_optional': 'Compte associé (facultatif)',
      'payment.holder_optional': 'Titulaire (facultatif)',
      'dashboard.loading': 'Chargement du pilotage…',
      'dashboard.unavailable':
          'Le tableau de bord ne peut pas être chargé. Vérifiez votre connexion.',
      'dashboard.title': 'Tableau de bord',
      'dashboard.subtitle':
          'Vue Foyer • comptes, enveloppes et projections restent distincts.',
      'dashboard.empty':
          'Aucune donnée financière réelle pour ce foyer. Les graphiques apparaîtront après les premières opérations.',
      'dashboard.month_end': 'Fin de mois',
      'dashboard.household_organization':
          'Organisation, calendrier et alertes du foyer',
      'dashboard.month_end_subtitle':
          'Santé, actions, rapprochements et clôture guidée',
      'dashboard.organization_summary':
          '{alerts} alerte(s) • {tasks} tâche(s) à échéance',
      'dashboard.no_spending': 'Aucune consommation sur cette période.',
      'dashboard.first_budget':
          'Préparez votre premier budget pour activer ce suivi.',
      'dashboard.no_active_goal': 'Aucun objectif actif.',
      'dashboard.secured_unavailable': 'Financement sécurisé non disponible.',
      'dashboard.secured': 'Sécurisé',
      'dashboard.debts': 'Dettes',
      'dashboard.receivables': 'Créances',
      'dashboard.recovery': 'Recovery',
      'dashboard.open_receivables': 'Voir les créances / Recovery',
      'dashboard.no_account': 'Aucun compte disponible.',
      'dashboard.open_cases': '{count} dossier(s) ouvert(s)',
      'dashboard.last_reconciliation': 'Dernier constat rapproché : {date}',
      'dashboard.check_accounts': 'Contrôler les comptes',
    },
    AppLanguage.english: {
      'common.add': 'Add',
      'common.cancel': 'Cancel',
      'common.close': 'Close',
      'common.confirm': 'Confirm',
      'common.create': 'Create',
      'common.save': 'Save',
      'common.none': 'None',
      'common.active': 'Active',
      'common.archived': 'Archived',
      'payment.title': 'Payment methods',
      'payment.unavailable': 'Payment methods are unavailable.',
      'payment.empty': 'No payment method configured.',
      'payment.kind.card': 'Bank card',
      'payment.kind.cash': 'Cash',
      'payment.kind.transfer': 'Bank transfer',
      'payment.kind.other': 'Other',
      'payment.linked_account': 'Linked account',
      'payment.linked_holder': 'Linked holder',
      'payment.add_title': 'Add a payment method',
      'payment.edit_title': 'Edit payment method',
      'payment.label': 'Label',
      'payment.type': 'Type',
      'payment.account_optional': 'Linked account (optional)',
      'payment.holder_optional': 'Holder (optional)',
      'dashboard.loading': 'Loading dashboard…',
      'dashboard.unavailable':
          'The dashboard cannot be loaded. Check your connection.',
      'dashboard.title': 'Dashboard',
      'dashboard.subtitle':
          'Household view • accounts, envelopes and projections remain distinct.',
      'dashboard.empty':
          'No actual financial data for this household yet. Charts will appear after the first transactions.',
      'dashboard.month_end': 'Month end',
      'dashboard.household_organization':
          'Household organization, calendar and alerts',
      'dashboard.month_end_subtitle':
          'Health, actions, reconciliations and guided closing',
      'dashboard.organization_summary':
          '{alerts} alert(s) • {tasks} task(s) due',
      'dashboard.no_spending': 'No spending during this period.',
      'dashboard.first_budget':
          'Prepare your first budget to enable this tracking.',
      'dashboard.no_active_goal': 'No active goal.',
      'dashboard.secured_unavailable': 'Secured financing unavailable.',
      'dashboard.secured': 'Secured',
      'dashboard.debts': 'Debts',
      'dashboard.receivables': 'Receivables',
      'dashboard.recovery': 'Recovery',
      'dashboard.open_receivables': 'View receivables / Recovery',
      'dashboard.no_account': 'No account available.',
      'dashboard.open_cases': '{count} open case(s)',
      'dashboard.last_reconciliation': 'Last reconciled observation: {date}',
      'dashboard.check_accounts': 'Review accounts',
    },
    AppLanguage.arabic: {
      'common.add': 'إضافة',
      'common.cancel': 'إلغاء',
      'common.close': 'إغلاق',
      'common.confirm': 'تأكيد',
      'common.create': 'إنشاء',
      'common.save': 'حفظ',
      'common.none': 'لا شيء',
      'common.active': 'نشط',
      'common.archived': 'مؤرشف',
      'payment.title': 'وسائل الدفع',
      'payment.unavailable': 'وسائل الدفع غير متاحة.',
      'payment.empty': 'لم يتم إعداد أي وسيلة دفع.',
      'payment.kind.card': 'بطاقة بنكية',
      'payment.kind.cash': 'نقداً',
      'payment.kind.transfer': 'تحويل بنكي',
      'payment.kind.other': 'أخرى',
      'payment.linked_account': 'الحساب المرتبط',
      'payment.linked_holder': 'صاحب الوسيلة المرتبط',
      'payment.add_title': 'إضافة وسيلة دفع',
      'payment.edit_title': 'تعديل وسيلة الدفع',
      'payment.label': 'التسمية',
      'payment.type': 'النوع',
      'payment.account_optional': 'الحساب المرتبط (اختياري)',
      'payment.holder_optional': 'صاحب الوسيلة (اختياري)',
      'dashboard.loading': 'جارٍ تحميل لوحة القيادة…',
      'dashboard.unavailable': 'تعذر تحميل لوحة القيادة. تحقق من اتصالك.',
      'dashboard.title': 'لوحة القيادة',
      'dashboard.subtitle':
          'عرض الأسرة • تبقى الحسابات والمظاريف والتوقعات منفصلة.',
      'dashboard.empty':
          'لا توجد بيانات مالية فعلية لهذه الأسرة. ستظهر الرسوم بعد العمليات الأولى.',
      'dashboard.month_end': 'نهاية الشهر',
      'dashboard.household_organization': 'تنظيم الأسرة والتقويم والتنبيهات',
      'dashboard.month_end_subtitle':
          'الحالة والإجراءات والمطابقات والإغلاق الموجّه',
      'dashboard.organization_summary': '{alerts} تنبيه • {tasks} مهمة ذات أجل',
      'dashboard.no_spending': 'لا توجد مصاريف خلال هذه الفترة.',
      'dashboard.first_budget': 'أعد ميزانيتك الأولى لتفعيل هذه المتابعة.',
      'dashboard.no_active_goal': 'لا يوجد هدف نشط.',
      'dashboard.secured_unavailable': 'التمويل المضمون غير متاح.',
      'dashboard.secured': 'مضمون',
      'dashboard.debts': 'الديون',
      'dashboard.receivables': 'المستحقات',
      'dashboard.recovery': 'الاسترداد',
      'dashboard.open_receivables': 'عرض المستحقات / الاسترداد',
      'dashboard.no_account': 'لا يوجد حساب متاح.',
      'dashboard.open_cases': '{count} ملف مفتوح',
      'dashboard.last_reconciliation': 'آخر رصيد تمت مطابقته: {date}',
      'dashboard.check_accounts': 'مراجعة الحسابات',
    },
    AppLanguage.darija: {
      'common.add': 'زيد',
      'common.cancel': 'إلغاء',
      'common.close': 'سد',
      'common.confirm': 'أكد',
      'common.create': 'صايب',
      'common.save': 'سجّل',
      'common.none': 'والو',
      'common.active': 'خدام',
      'common.archived': 'مأرشف',
      'payment.title': 'وسائل الخلاص',
      'payment.unavailable': 'وسائل الخلاص ما متوفراش.',
      'payment.empty': 'ما كاينة حتى وسيلة خلاص موجدّة.',
      'payment.kind.card': 'كارط بنكية',
      'payment.kind.cash': 'الكاش',
      'payment.kind.transfer': 'تحويل بنكي',
      'payment.kind.other': 'شي حاجة خرى',
      'payment.linked_account': 'الحساب المربوط',
      'payment.linked_holder': 'مول الوسيلة المربوط',
      'payment.add_title': 'زيد وسيلة خلاص',
      'payment.edit_title': 'بدّل وسيلة الخلاص',
      'payment.label': 'السّمية',
      'payment.type': 'النوع',
      'payment.account_optional': 'الحساب المربوط (اختياري)',
      'payment.holder_optional': 'مول الوسيلة (اختياري)',
      'dashboard.loading': 'كنحمّلو لوحة القيادة…',
      'dashboard.unavailable':
          'ما قدرناش نحمّلو لوحة القيادة. تأكد من الكونكسيون.',
      'dashboard.title': 'لوحة القيادة',
      'dashboard.subtitle':
          'نظرة ديال الدار • الحسابات والظروف والتوقعات باقين مفروقين.',
      'dashboard.empty':
          'ما كاينة حتى معلومة مالية حقيقية لهاد الدار. الرسوم غادي يبانوا من بعد أول العمليات.',
      'dashboard.month_end': 'آخر الشهر',
      'dashboard.household_organization': 'تنظيم الدار والتقويم والتنبيهات',
      'dashboard.month_end_subtitle':
          'الحالة والخطوات والمطابقات وسدّ الشهر بالتوجيه',
      'dashboard.organization_summary':
          '{alerts} تنبيه • {tasks} مهمة عندها أجل',
      'dashboard.no_spending': 'ما كاين حتى صرف فهاد المدة.',
      'dashboard.first_budget': 'وجد أول ميزانية باش تفعل هاد التتبع.',
      'dashboard.no_active_goal': 'ما كاين حتى هدف خدام.',
      'dashboard.secured_unavailable': 'التمويل المضمون ما متوفرش.',
      'dashboard.secured': 'مضمون',
      'dashboard.debts': 'الديون',
      'dashboard.receivables': 'الفلوس اللي خاصها ترجع',
      'dashboard.recovery': 'الاسترجاع',
      'dashboard.open_receivables': 'شوف المستحقات / الاسترجاع',
      'dashboard.no_account': 'ما كاين حتى حساب.',
      'dashboard.open_cases': '{count} ملف محلول',
      'dashboard.last_reconciliation': 'آخر رصيد تصالح: {date}',
      'dashboard.check_accounts': 'راجع الحسابات',
    },
  };
}
