import 'package:flutter/widgets.dart';

import '../../../core/localization/app_locale.dart';

class DashboardHomeWords {
  const DashboardHomeWords(this.language);
  final AppLanguage language;

  factory DashboardHomeWords.of(BuildContext context) => DashboardHomeWords(
    AppLanguageX.fromLocale(Localizations.localeOf(context)),
  );

  String text(String key) => _values[language]![key] ?? key;
  String format(String key, Map<String, Object> values) {
    var value = text(key);
    for (final entry in values.entries) {
      value = value.replaceAll('{${entry.key}}', '${entry.value}');
    }
    return value;
  }

  static Set<String> keysFor(AppLanguage language) =>
      _values[language]!.keys.toSet();

  static const _values = <AppLanguage, Map<String, String>>{
    AppLanguage.french: {
      'hello': 'Bonjour',
      'hello.name': 'Bonjour {name}',
      'intro': 'Voici ce qui mérite votre attention.',
      'month': 'Situation du mois',
      'available': 'Disponible dans le budget',
      'used': '{value} % du budget utilisé',
      'days': '{count} jours restants',
      'month.detail': 'Voir le détail du mois',
      'budget.setup': 'Préparer mon budget',
      'budget.empty':
          'Préparez votre budget pour suivre le disponible du mois.',
      'attention': 'À traiter',
      'attention.empty': 'Tout est à jour.',
      'examine': 'Examiner',
      'today': "Aujourd’hui",
      'today.empty': "Rien de prévu aujourd’hui.",
      'calendar': 'Voir le calendrier',
      'goals': 'Objectifs',
      'goals.empty': 'Aucun objectif actif.',
      'goals.all': 'Voir tous les objectifs',
      'secondary': 'Aperçu du mois',
      'income': 'Revenus',
      'expenses': 'Dépenses',
      'month.end': 'Clôturer le mois',
      'analytics': 'Voir les analyses',
      'empty.title': 'Votre foyer est prêt',
      'empty.body':
          'Ajoutez votre première opération ou configurez votre budget.',
      'empty.operation': 'Ajouter une opération',
      'partial': 'Certaines informations sont temporairement indisponibles.',
      'action.required': 'Action requise',
      'attention.level': 'Attention',
      'information': 'Information',
      'loading': 'Préparation de votre accueil…',
      'error':
          'Votre accueil ne peut pas être chargé. Vérifiez votre connexion.',
    },
    AppLanguage.english: {
      'hello': 'Hello',
      'hello.name': 'Hello {name}',
      'intro': 'Here is what deserves your attention.',
      'month': 'This month',
      'available': 'Available in the budget',
      'used': '{value}% of budget used',
      'days': '{count} days remaining',
      'month.detail': 'View month details',
      'budget.setup': 'Prepare my budget',
      'budget.empty':
          'Prepare your budget to track what is available this month.',
      'attention': 'To do',
      'attention.empty': 'Everything is up to date.',
      'examine': 'Review',
      'today': 'Today',
      'today.empty': 'Nothing planned today.',
      'calendar': 'View calendar',
      'goals': 'Goals',
      'goals.empty': 'No active goal.',
      'goals.all': 'View all goals',
      'secondary': 'Month overview',
      'income': 'Income',
      'expenses': 'Expenses',
      'month.end': 'Close the month',
      'analytics': 'View analytics',
      'empty.title': 'Your household is ready',
      'empty.body': 'Add your first transaction or configure your budget.',
      'empty.operation': 'Add a transaction',
      'partial': 'Some information is temporarily unavailable.',
      'action.required': 'Action required',
      'attention.level': 'Attention',
      'information': 'Information',
      'loading': 'Preparing your home…',
      'error': 'Your home cannot be loaded. Check your connection.',
    },
    AppLanguage.arabic: {
      'hello': 'مرحباً',
      'hello.name': 'مرحباً {name}',
      'intro': 'إليك ما يستحق انتباهك.',
      'month': 'وضع هذا الشهر',
      'available': 'المتاح في الميزانية',
      'used': 'تم استخدام {value}٪ من الميزانية',
      'days': 'متبقي {count} يوم',
      'month.detail': 'عرض تفاصيل الشهر',
      'budget.setup': 'إعداد ميزانيتي',
      'budget.empty': 'أعد ميزانيتك لمتابعة المتاح هذا الشهر.',
      'attention': 'ما يجب معالجته',
      'attention.empty': 'كل شيء محدّث.',
      'examine': 'مراجعة',
      'today': 'اليوم',
      'today.empty': 'لا شيء مقرراً اليوم.',
      'calendar': 'عرض التقويم',
      'goals': 'الأهداف',
      'goals.empty': 'لا يوجد هدف نشط.',
      'goals.all': 'عرض كل الأهداف',
      'secondary': 'نظرة على الشهر',
      'income': 'الدخل',
      'expenses': 'المصاريف',
      'month.end': 'إغلاق الشهر',
      'analytics': 'عرض التحليلات',
      'empty.title': 'أسرتك جاهزة',
      'empty.body': 'أضف أول عملية أو أعد ميزانيتك.',
      'empty.operation': 'إضافة عملية',
      'partial': 'بعض المعلومات غير متاحة مؤقتاً.',
      'action.required': 'إجراء مطلوب',
      'attention.level': 'انتباه',
      'information': 'معلومة',
      'loading': 'جارٍ إعداد الصفحة الرئيسية…',
      'error': 'تعذر تحميل الصفحة الرئيسية. تحقق من اتصالك.',
    },
    AppLanguage.darija: {
      'hello': 'مرحبا',
      'hello.name': 'مرحبا {name}',
      'intro': 'ها شنو خاصو الانتباه ديالك.',
      'month': 'وضعية هاد الشهر',
      'available': 'المتاح فالميزانية',
      'used': 'تصرفات {value}٪ من الميزانية',
      'days': 'باقي {count} يوم',
      'month.detail': 'شوف تفاصيل الشهر',
      'budget.setup': 'نوجد الميزانية',
      'budget.empty': 'وجد الميزانية باش تعرف شحال باقي متاح هاد الشهر.',
      'attention': 'خاص يتعالج',
      'attention.empty': 'كلشي موجد.',
      'examine': 'راجع',
      'today': 'اليوم',
      'today.empty': 'ما كاين والو مبرمج اليوم.',
      'calendar': 'شوف التقويم',
      'goals': 'الأهداف',
      'goals.empty': 'ما كاين حتى هدف خدام.',
      'goals.all': 'شوف كاع الأهداف',
      'secondary': 'نظرة على الشهر',
      'income': 'المداخيل',
      'expenses': 'المصاريف',
      'month.end': 'سد الشهر',
      'analytics': 'شوف التحليلات',
      'empty.title': 'داركم واجدة',
      'empty.body': 'زيد أول عملية ولا وجد الميزانية.',
      'empty.operation': 'زيد عملية',
      'partial': 'شي معلومات ما متوفراش مؤقتاً.',
      'action.required': 'خاص إجراء',
      'attention.level': 'انتباه',
      'information': 'معلومة',
      'loading': 'كنوجدو الصفحة الرئيسية…',
      'error': 'ما قدرناش نحملو الصفحة الرئيسية. شوف الريزو.',
    },
  };
}
