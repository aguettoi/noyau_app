import '../../../core/localization/app_locale.dart';

const _assistantTranslations = <AppLanguage, Map<String, String>>{
  AppLanguage.french: {
    'assistant.title': 'Assistant déterministe',
    'assistant.subtitle':
        'Conseils explicables fondés uniquement sur vos données autorisées.',
    'assistant.loading': 'Analyse des sources autorisées…',
    'assistant.error':
        'Le contexte autorisé est indisponible. Aucune conclusion n’a été inventée.',
    'assistant.insufficient':
        'Les données autorisées sont insuffisantes pour une conclusion fiable.',
    'assistant.hidden_excluded':
        'Des données masquées existent et ont été exclues de cette réponse.',
    'assistant.budget': 'Budget',
    'assistant.monthlySummary': 'Résumé mensuel',
    'assistant.anomalies': 'Anomalies',
    'assistant.priorities': 'PRIOS',
    'assistant.organization': 'Organisation',
    'assistant.shopping': 'Achats',
    'assistant.wealth': 'Patrimoine',
    'assistant.productHelp': 'Aide produit',
    'assistant.budget.tension':
        'Fait : le budget autorisé présente un reste négatif.',
    'assistant.budget.rule':
        'Règle : examinez les enveloppes dépassées avant toute nouvelle affectation.',
    'assistant.budget.stable':
        'Fait : le budget autorisé ne présente pas de tension négative.',
    'assistant.summary':
        'Fait : {alerts} alerte(s) et {goals} objectif(s) actifs sont visibles.',
    'assistant.anomaly.none':
        'Fait : aucune anomalie autorisée n’est actuellement signalée.',
    'assistant.anomaly.present':
        'Fait : des alertes autorisées nécessitent une vérification.',
    'assistant.priorities.next': 'Fait : une prochaine priorité est définie.',
    'assistant.priorities.none':
        'Incertitude : aucune prochaine priorité exploitable n’est disponible.',
    'assistant.organization.summary':
        'Fait : {tasks} tâche(s) ouvertes sont autorisées dans le contexte.',
    'assistant.shopping.compatible':
        'Règle : la disponibilité autorisée est compatible avec une étude d’achat, sans révéler de solde.',
    'assistant.shopping.unknown':
        'Incertitude : la disponibilité autorisée ne permet pas de conclure.',
    'assistant.wealth.explain_only':
        'Règle : l’assistant explique les résultats patrimoniaux canoniques sans les recalculer.',
    'assistant.help':
        'Suggestion : ouvrez l’aide pour retrouver le parcours adapté.',
    'assistant.action.open_budget': 'Ouvrir le budget',
    'assistant.action.review_budget':
        'Examiner la source canonique avant toute décision.',
    'assistant.action.open_priorities': 'Ouvrir les PRIOS',
    'assistant.action.review_priorities':
        'Vérifier le classement canonique sans le modifier.',
    'assistant.confirm': 'Confirmer',
    'assistant.reject': 'Refuser',
    'assistant.proposal': 'Action proposée — aucune modification automatique',
    'assistant.kind.fact': 'FAIT',
    'assistant.kind.rule': 'CALCUL / RÈGLE',
    'assistant.kind.suggestion': 'SUGGESTION',
    'assistant.kind.uncertainty': 'INCERTITUDE',
  },
  AppLanguage.english: {
    'assistant.title': 'Deterministic assistant',
    'assistant.subtitle':
        'Explainable advice based only on data you are allowed to access.',
    'assistant.loading': 'Analyzing authorized sources…',
    'assistant.error':
        'The authorized context is unavailable. No conclusion was invented.',
    'assistant.insufficient':
        'Authorized data is insufficient for a reliable conclusion.',
    'assistant.hidden_excluded':
        'Hidden data exists and was excluded from this answer.',
    'assistant.budget': 'Budget',
    'assistant.monthlySummary': 'Monthly summary',
    'assistant.anomalies': 'Anomalies',
    'assistant.priorities': 'PRIOS',
    'assistant.organization': 'Organization',
    'assistant.shopping': 'Shopping',
    'assistant.wealth': 'Wealth',
    'assistant.productHelp': 'Product help',
    'assistant.budget.tension':
        'Fact: the authorized budget has a negative remainder.',
    'assistant.budget.rule':
        'Rule: review overspent envelopes before any new allocation.',
    'assistant.budget.stable':
        'Fact: the authorized budget has no negative tension.',
    'assistant.summary':
        'Fact: {alerts} alert(s) and {goals} active goal(s) are visible.',
    'assistant.anomaly.none':
        'Fact: no authorized anomaly is currently reported.',
    'assistant.anomaly.present': 'Fact: authorized alerts require review.',
    'assistant.priorities.next': 'Fact: a next priority is defined.',
    'assistant.priorities.none':
        'Uncertainty: no usable next priority is available.',
    'assistant.organization.summary':
        'Fact: {tasks} open task(s) are authorized in this context.',
    'assistant.shopping.compatible':
        'Rule: authorized availability supports reviewing a purchase without revealing a balance.',
    'assistant.shopping.unknown':
        'Uncertainty: authorized availability is insufficient.',
    'assistant.wealth.explain_only':
        'Rule: the assistant explains canonical wealth results without recalculating them.',
    'assistant.help': 'Suggestion: open Help to find the relevant workflow.',
    'assistant.action.open_budget': 'Open budget',
    'assistant.action.review_budget':
        'Review the canonical source before deciding.',
    'assistant.action.open_priorities': 'Open PRIOS',
    'assistant.action.review_priorities':
        'Review canonical ranking without changing it.',
    'assistant.confirm': 'Confirm',
    'assistant.reject': 'Reject',
    'assistant.proposal': 'Proposed action — no automatic change',
    'assistant.kind.fact': 'FACT',
    'assistant.kind.rule': 'CALCULATION / RULE',
    'assistant.kind.suggestion': 'SUGGESTION',
    'assistant.kind.uncertainty': 'UNCERTAINTY',
  },
  AppLanguage.arabic: {
    'assistant.title': 'المساعد الحتمي',
    'assistant.subtitle':
        'نصائح قابلة للتفسير مبنية فقط على بياناتك المصرح بها.',
    'assistant.loading': 'جارٍ تحليل المصادر المصرح بها…',
    'assistant.error': 'السياق المصرح به غير متاح. لم يتم اختلاق أي نتيجة.',
    'assistant.insufficient': 'البيانات المصرح بها غير كافية لنتيجة موثوقة.',
    'assistant.hidden_excluded': 'توجد بيانات مخفية وتم استبعادها من الإجابة.',
    'assistant.budget': 'الميزانية',
    'assistant.monthlySummary': 'الملخص الشهري',
    'assistant.anomalies': 'الشذوذ',
    'assistant.priorities': 'الأولويات',
    'assistant.organization': 'التنظيم',
    'assistant.shopping': 'المشتريات',
    'assistant.wealth': 'الثروة',
    'assistant.productHelp': 'مساعدة المنتج',
    'assistant.budget.tension':
        'حقيقة: الميزانية المصرح بها لها رصيد متبقٍ سلبي.',
    'assistant.budget.rule': 'قاعدة: راجع الأظرف المتجاوزة قبل أي تخصيص جديد.',
    'assistant.budget.stable':
        'حقيقة: الميزانية المصرح بها لا تظهر ضغطاً سلبياً.',
    'assistant.summary': 'حقيقة: تظهر {alerts} تنبيهات و{goals} أهداف نشطة.',
    'assistant.anomaly.none': 'حقيقة: لا يوجد شذوذ مصرح به حالياً.',
    'assistant.anomaly.present': 'حقيقة: توجد تنبيهات مصرح بها تحتاج للمراجعة.',
    'assistant.priorities.next': 'حقيقة: توجد أولوية تالية.',
    'assistant.priorities.none':
        'عدم يقين: لا توجد أولوية تالية قابلة للاستخدام.',
    'assistant.organization.summary':
        'حقيقة: توجد {tasks} مهام مفتوحة مصرح بها.',
    'assistant.shopping.compatible':
        'قاعدة: التوفر المصرح به يسمح بدراسة شراء دون كشف الرصيد.',
    'assistant.shopping.unknown': 'عدم يقين: التوفر المصرح به غير كافٍ.',
    'assistant.wealth.explain_only':
        'قاعدة: يشرح المساعد النتائج الأصلية دون إعادة حسابها.',
    'assistant.help': 'اقتراح: افتح المساعدة للعثور على المسار المناسب.',
    'assistant.action.open_budget': 'فتح الميزانية',
    'assistant.action.review_budget': 'راجع المصدر الأصلي قبل القرار.',
    'assistant.action.open_priorities': 'فتح الأولويات',
    'assistant.action.review_priorities': 'راجع الترتيب الأصلي دون تغييره.',
    'assistant.confirm': 'تأكيد',
    'assistant.reject': 'رفض',
    'assistant.proposal': 'إجراء مقترح — لا تعديل تلقائي',
    'assistant.kind.fact': 'حقيقة',
    'assistant.kind.rule': 'حساب / قاعدة',
    'assistant.kind.suggestion': 'اقتراح',
    'assistant.kind.uncertainty': 'عدم يقين',
  },
  AppLanguage.darija: {
    'assistant.title': 'المساعد الحتمي',
    'assistant.subtitle':
        'نصائح مفهومة مبنية غير على المعطيات المسموح ليك تشوف.',
    'assistant.loading': 'كنحللو المصادر المسموح بها…',
    'assistant.error': 'المعطيات المسموح بها ما متوفراش. ما اخترعنا حتى نتيجة.',
    'assistant.insufficient':
        'المعطيات المسموح بها ما كافياش باش نعطيو نتيجة موثوقة.',
    'assistant.hidden_excluded': 'كاينة معطيات مخبية وما دخلناهاش فالجواب.',
    'assistant.budget': 'الميزانية',
    'assistant.monthlySummary': 'الخلاصة الشهرية',
    'assistant.anomalies': 'الحوايج الغير عادية',
    'assistant.priorities': 'الأولويات',
    'assistant.organization': 'تنظيم الدار',
    'assistant.shopping': 'الشرا',
    'assistant.wealth': 'الممتلكات',
    'assistant.productHelp': 'مساعدة التطبيق',
    'assistant.budget.tension':
        'حقيقة: الميزانية المسموح بها بقا فيها مبلغ سلبي.',
    'assistant.budget.rule': 'قاعدة: شوف الظروف اللي تفوتو قبل أي توزيع جديد.',
    'assistant.budget.stable':
        'حقيقة: الميزانية المسموح بها ما فيهاش ضغط سلبي.',
    'assistant.summary':
        'حقيقة: باينين {alerts} تنبيهات و{goals} أهداف خدامين.',
    'assistant.anomaly.none': 'حقيقة: ما كاين حتى مشكل مسموح باين دابا.',
    'assistant.anomaly.present':
        'حقيقة: كاينين تنبيهات مسموح بها خاصها المراجعة.',
    'assistant.priorities.next': 'حقيقة: كاينة أولوية جاية.',
    'assistant.priorities.none': 'ما متأكدينش: ما كايناش أولوية جاية صالحة.',
    'assistant.organization.summary':
        'حقيقة: كاينين {tasks} مهام محلولين ومسموح بهم.',
    'assistant.shopping.compatible':
        'قاعدة: المتاح المسموح به كيخلي دراسة الشرا ممكنة بلا ما نبينو الرصيد.',
    'assistant.shopping.unknown': 'ما متأكدينش: المتاح المسموح به ما كافيش.',
    'assistant.wealth.explain_only':
        'قاعدة: المساعد كيشرح النتائج الأصلية بلا ما يعاود يحسبها.',
    'assistant.help': 'اقتراح: حل المساعدة باش تلقى المسار المناسب.',
    'assistant.action.open_budget': 'حل الميزانية',
    'assistant.action.review_budget': 'راجع المصدر الأصلي قبل القرار.',
    'assistant.action.open_priorities': 'حل الأولويات',
    'assistant.action.review_priorities': 'راجع الترتيب الأصلي بلا ما تبدلو.',
    'assistant.confirm': 'أكد',
    'assistant.reject': 'رفض',
    'assistant.proposal': 'خدمة مقترحة — ما كاين حتى تبديل بوحدو',
    'assistant.kind.fact': 'حقيقة',
    'assistant.kind.rule': 'حساب / قاعدة',
    'assistant.kind.suggestion': 'اقتراح',
    'assistant.kind.uncertainty': 'ما متأكدينش',
  },
};

class AssistantWords {
  const AssistantWords(this.language);
  final AppLanguage language;
  String text(String key) => _assistantTranslations[language]?[key] ?? key;
  String format(String key, Map<String, Object> arguments) {
    var value = text(key);
    for (final entry in arguments.entries) {
      value = value.replaceAll('{${entry.key}}', '${entry.value}');
    }
    return value;
  }

  static Set<String> keysFor(AppLanguage language) =>
      _assistantTranslations[language]!.keys.toSet();
}
