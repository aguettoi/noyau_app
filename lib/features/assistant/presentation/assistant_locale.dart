import '../../../core/localization/app_locale.dart';

const _assistantTranslations = <AppLanguage, Map<String, String>>{
  AppLanguage.french: {
    'assistant.title': 'Assistant FINANCIEL',
    'assistant.subtitle':
        'Posez librement votre question. Les calculs restent ceux des moteurs FINANCIEL et seuls les éléments autorisés sont utilisés.',
    'assistant.deterministic_title': 'Assistant déterministe',
    'assistant.deterministic_description':
        'Consultez des synthèses locales fondées uniquement sur les moteurs FINANCIEL. L’assistant conversationnel génératif sera activé après certification d’un fournisseur adapté.',
    'assistant.question': 'Votre question',
    'assistant.question_hint': 'Ex. Puis-je encore épargner ce mois-ci ?',
    'assistant.send': 'Envoyer',
    'assistant.clear': 'Effacer la conversation',
    'assistant.conversation_welcome':
        'Je peux combiner plusieurs domaines et distinguer faits, calculs, hypothèses et recommandations. Aucune action sensible n’est exécutée sans confirmation.',
    'assistant.fallback_notice':
        'Les synthèses déterministes locales restent disponibles ci-dessous.',
    'assistant.status.providerUnavailable':
        'Assistant conversationnel indisponible.',
    'assistant.status.offline': 'Vous êtes hors ligne.',
    'assistant.status.timeout': 'Le fournisseur met trop de temps à répondre.',
    'assistant.status.failed': 'La réponse n’a pas pu être produite.',
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
    'assistant.action.open_help': 'Ouvrir l’aide',
    'assistant.action.review_help': 'Consulter le parcours d’aide approprié.',
    'assistant.confirm': 'Confirmer',
    'assistant.reject': 'Refuser',
    'assistant.proposal': 'Action proposée — aucune modification automatique',
    'assistant.kind.fact': 'FAIT',
    'assistant.kind.rule': 'CALCUL / RÈGLE',
    'assistant.kind.suggestion': 'SUGGESTION',
    'assistant.kind.uncertainty': 'INCERTITUDE',
  },
  AppLanguage.english: {
    'assistant.title': 'FINANCIEL assistant',
    'assistant.subtitle':
        'Ask freely. Calculations remain authoritative FINANCIEL results and only authorized information is used.',
    'assistant.deterministic_title': 'Deterministic assistant',
    'assistant.deterministic_description':
        'View local summaries based only on FINANCIEL engines. The generative conversational assistant will be enabled after a suitable provider is certified.',
    'assistant.question': 'Your question',
    'assistant.question_hint': 'E.g. Can I still save this month?',
    'assistant.send': 'Send',
    'assistant.clear': 'Clear conversation',
    'assistant.conversation_welcome':
        'I can combine several domains and distinguish facts, calculations, assumptions and recommendations. No sensitive action runs without confirmation.',
    'assistant.fallback_notice':
        'Local deterministic summaries remain available below.',
    'assistant.status.providerUnavailable':
        'Conversational assistant unavailable.',
    'assistant.status.offline': 'You are offline.',
    'assistant.status.timeout': 'The provider is taking too long to respond.',
    'assistant.status.failed': 'The answer could not be produced.',
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
    'assistant.action.open_help': 'Open help',
    'assistant.action.review_help': 'Review the relevant help workflow.',
    'assistant.confirm': 'Confirm',
    'assistant.reject': 'Reject',
    'assistant.proposal': 'Proposed action — no automatic change',
    'assistant.kind.fact': 'FACT',
    'assistant.kind.rule': 'CALCULATION / RULE',
    'assistant.kind.suggestion': 'SUGGESTION',
    'assistant.kind.uncertainty': 'UNCERTAINTY',
  },
  AppLanguage.arabic: {
    'assistant.title': 'مساعد FINANCIEL',
    'assistant.subtitle':
        'اطرح سؤالك بحرية. تبقى حسابات FINANCIEL هي المرجع ولا تُستخدم إلا المعلومات المصرح بها.',
    'assistant.deterministic_title': 'المساعد الحتمي',
    'assistant.deterministic_description':
        'اطّلع على ملخصات محلية مبنية فقط على محركات FINANCIEL. سيُفعّل المساعد الحواري التوليدي بعد اعتماد مزوّد مناسب.',
    'assistant.question': 'سؤالك',
    'assistant.question_hint': 'مثال: هل يمكنني الادخار أكثر هذا الشهر؟',
    'assistant.send': 'إرسال',
    'assistant.clear': 'مسح المحادثة',
    'assistant.conversation_welcome':
        'يمكنني الجمع بين عدة مجالات وشرح الحقائق والحسابات والافتراضات والتوصيات. لا يُنفذ أي إجراء حساس دون تأكيد.',
    'assistant.fallback_notice': 'تبقى الملخصات الحتمية المحلية متاحة أدناه.',
    'assistant.status.providerUnavailable': 'المساعد الحواري غير متاح.',
    'assistant.status.offline': 'أنت غير متصل بالإنترنت.',
    'assistant.status.timeout': 'تأخر المزود في الإجابة.',
    'assistant.status.failed': 'تعذر إنتاج الإجابة.',
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
    'assistant.action.open_help': 'فتح المساعدة',
    'assistant.action.review_help': 'راجع مسار المساعدة المناسب.',
    'assistant.confirm': 'تأكيد',
    'assistant.reject': 'رفض',
    'assistant.proposal': 'إجراء مقترح — لا تعديل تلقائي',
    'assistant.kind.fact': 'حقيقة',
    'assistant.kind.rule': 'حساب / قاعدة',
    'assistant.kind.suggestion': 'اقتراح',
    'assistant.kind.uncertainty': 'عدم يقين',
  },
  AppLanguage.darija: {
    'assistant.title': 'المساعد ديال FINANCIEL PILOTE',
    'assistant.subtitle':
        'سول بحرية. الحسابات ديال FINANCIEL كتبقى هي المرجع وكنستعملو غير المعطيات المسموح بها.',
    'assistant.deterministic_title': 'المساعد المضمون',
    'assistant.deterministic_description':
        'شوف خلاصات محلية مبنية غير على محركات FINANCIEL. المساعد ديال المحادثة التوليدية غادي يتفعل من بعد ما يتصادق على مزود مناسب.',
    'assistant.question': 'السؤال ديالك',
    'assistant.question_hint': 'مثلا: واش نقدر نزيد نوفر هاد الشهر؟',
    'assistant.send': 'صيفط',
    'assistant.clear': 'مسح المحادثة',
    'assistant.conversation_welcome':
        'نقدر نجمع كثر من مجال ونوضح الحقائق والحسابات والافتراضات والنصيحة. حتى خدمة حساسة ما كتدار بلا تأكيد.',
    'assistant.fallback_notice': 'الخلاصات المحلية المضمونة باقية متوفرة لتحت.',
    'assistant.status.providerUnavailable': 'المساعد ديال المحادثة ما متوفرش.',
    'assistant.status.offline': 'راك بلا نت.',
    'assistant.status.timeout': 'المزوّد طول فالجواب.',
    'assistant.status.failed': 'ما قدرناش نوجدو الجواب.',
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
        'حقيقة: كاينين {tasks} شغايل محلولين ومسموح بهم.',
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
    'assistant.action.open_help': 'حل المساعدة',
    'assistant.action.review_help': 'شوف مسار المساعدة المناسب.',
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
