import 'package:flutter/widgets.dart';

import 'app_locale.dart';

class PrioritiesWords {
  const PrioritiesWords(this.language);

  final AppLanguage language;

  factory PrioritiesWords.of(BuildContext context) =>
      PrioritiesWords(AppLanguageX.fromLocale(Localizations.localeOf(context)));

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
      'priorities.load_error': 'Impossible de lire les priorités.',
      'priorities.title': 'Priorités',
      'priorities.subtitle':
          'Organisez les achats et objectifs existants. Cette projection ne crée aucune écriture financière.',
      'priorities.create_plan': 'Créer un plan',
      'priorities.empty_title': 'Aucun plan de priorités',
      'priorities.empty_subtitle':
          'Créez un plan pour ordonner vos achats prévus et vos objectifs.',
      'priorities.projection_loading': 'Projection en cours de chargement.',
      'priorities.projection_planned':
          'Plan prévu — utilisez-le comme référence pour obtenir les projections.',
      'priorities.projection_unavailable_data':
          'Projection indisponible — les données nécessaires ne peuvent pas être lues.',
      'priorities.projection_unavailable_capacity':
          'Projection indisponible — ce plan ne fournit aucune capacité applicable.',
      'priorities.projection_missing_item':
          'Projection indisponible — élément absent du plan.',
      'priorities.use_for_projection': 'Utiliser pour mes projections',
      'priorities.edit_plan': 'Modifier le plan',
      'priorities.plan_status': 'Statut du plan',
      'priorities.pause': 'Mettre en pause',
      'priorities.archive': 'Archiver',
      'priorities.capacity_missing':
          'Capacité mensuelle simulée : à renseigner',
      'priorities.capacity_value': 'Capacité mensuelle simulée : {amount}',
      'priorities.planning_disclaimer':
          'Hypothèse de planification uniquement — aucun budget, compte ou solde n’est modifié.',
      'priorities.add_project': 'Ajouter un achat ou un objectif',
      'priorities.no_project': 'Aucun projet dans ce plan.',
      'priorities.activate_title': 'Utiliser ce plan pour mes projections',
      'priorities.activate_first':
          'Ce plan deviendra la référence de vos projections. Aucun mouvement financier ne sera créé.',
      'priorities.activate_replace':
          'Ce plan remplacera « {plan} » comme référence de vos projections. Aucun mouvement financier ne sera créé.',
      'priorities.cancel': 'Annuler',
      'priorities.use_plan': 'Utiliser ce plan',
      'priorities.estimated_need': 'Besoin estimé : {amount}',
      'priorities.progress': 'Progression : {progress} %',
      'priorities.funding_month.one': '1 mois de financement estimé',
      'priorities.funding_month.many': '{count} mois de financement estimés',
      'priorities.forecast': 'Prévision : {date}',
      'priorities.decision': 'Décision : {decision}',
      'priorities.status': 'Statut : {status}',
      'priorities.financial_decision': 'Décision financière',
      'priorities.remove': 'Retirer du plan',
      'priorities.plan_name': 'Nom du plan *',
      'priorities.monthly_capacity': 'Capacité mensuelle simulée (MAD)',
      'priorities.capacity_helper':
          'Hypothèse de planification, sans écriture financière.',
      'priorities.notes': 'Notes',
      'priorities.invalid_capacity': 'La capacité mensuelle est invalide.',
      'priorities.invalid_name':
          'Le nom du plan doit contenir entre 1 et 120 caractères.',
      'priorities.positive_capacity':
          'La capacité mensuelle doit être strictement positive.',
      'priorities.notes_too_long':
          'Les notes ne peuvent pas dépasser 2 000 caractères.',
      'priorities.create': 'Créer',
      'priorities.save': 'Enregistrer',
      'priorities.add_priority': 'Ajouter une priorité',
      'priorities.no_eligible_project':
          'Aucun achat ou objectif éligible. Les projets déjà liés entre eux ne peuvent pas être ajoutés deux fois.',
      'priorities.project': 'Projet *',
      'priorities.add': 'Ajouter',
      'priorities.shopping_candidate': 'Achat · {name}',
      'priorities.goal_candidate': 'Objectif · {name}',
      'priorities.action_failed': 'Impossible d’effectuer cette action.',
      'priorities.status.planned': 'Prévu',
      'priorities.status.active': 'Actif',
      'priorities.status.paused': 'En pause',
      'priorities.status.archived': 'Archivé',
      'priorities.source.shopping': 'Achat',
      'priorities.source.goal': 'Objectif',
      'priorities.decision.buy_now': 'Acheter maintenant',
      'priorities.decision.wait': 'Attendre',
      'priorities.decision.fund_progressively': 'Financer progressivement',
      'priorities.source_status.planned': 'Prévu',
      'priorities.source_status.active': 'Actif',
      'priorities.source_status.paused': 'En pause',
      'priorities.source_status.completed': 'Clôturé',
      'priorities.source_status.purchased': 'Acheté',
      'priorities.source_status.cancelled': 'Annulé',
      'priorities.source_status.archived': 'Archivé',
    },
    AppLanguage.english: {
      'priorities.load_error': 'Unable to load priorities.',
      'priorities.title': 'Priorities',
      'priorities.subtitle':
          'Organize existing purchases and goals. This projection creates no financial entry.',
      'priorities.create_plan': 'Create a plan',
      'priorities.empty_title': 'No priority plan',
      'priorities.empty_subtitle':
          'Create a plan to order your planned purchases and goals.',
      'priorities.projection_loading': 'Loading projection.',
      'priorities.projection_planned':
          'Planned plan — use it as the reference for projections.',
      'priorities.projection_unavailable_data':
          'Projection unavailable — required data cannot be read.',
      'priorities.projection_unavailable_capacity':
          'Projection unavailable — this plan provides no applicable capacity.',
      'priorities.projection_missing_item':
          'Projection unavailable — item missing from the plan.',
      'priorities.use_for_projection': 'Use for my projections',
      'priorities.edit_plan': 'Edit plan',
      'priorities.plan_status': 'Plan status',
      'priorities.pause': 'Pause',
      'priorities.archive': 'Archive',
      'priorities.capacity_missing': 'Simulated monthly capacity: not set',
      'priorities.capacity_value': 'Simulated monthly capacity: {amount}',
      'priorities.planning_disclaimer':
          'Planning assumption only — no budget, account, or balance is changed.',
      'priorities.add_project': 'Add a purchase or goal',
      'priorities.no_project': 'No project in this plan.',
      'priorities.activate_title': 'Use this plan for my projections',
      'priorities.activate_first':
          'This plan will become the reference for your projections. No financial movement will be created.',
      'priorities.activate_replace':
          'This plan will replace “{plan}” as the reference for your projections. No financial movement will be created.',
      'priorities.cancel': 'Cancel',
      'priorities.use_plan': 'Use this plan',
      'priorities.estimated_need': 'Estimated need: {amount}',
      'priorities.progress': 'Progress: {progress}%',
      'priorities.funding_month.one': '1 estimated funding month',
      'priorities.funding_month.many': '{count} estimated funding months',
      'priorities.forecast': 'Forecast: {date}',
      'priorities.decision': 'Decision: {decision}',
      'priorities.status': 'Status: {status}',
      'priorities.financial_decision': 'Financial decision',
      'priorities.remove': 'Remove from plan',
      'priorities.plan_name': 'Plan name *',
      'priorities.monthly_capacity': 'Simulated monthly capacity (MAD)',
      'priorities.capacity_helper':
          'Planning assumption, with no financial entry.',
      'priorities.notes': 'Notes',
      'priorities.invalid_capacity': 'The monthly capacity is invalid.',
      'priorities.invalid_name':
          'The plan name must contain between 1 and 120 characters.',
      'priorities.positive_capacity': 'The monthly capacity must be positive.',
      'priorities.notes_too_long': 'Notes cannot exceed 2,000 characters.',
      'priorities.create': 'Create',
      'priorities.save': 'Save',
      'priorities.add_priority': 'Add a priority',
      'priorities.no_eligible_project':
          'No eligible purchase or goal. Projects already linked together cannot be added twice.',
      'priorities.project': 'Project *',
      'priorities.add': 'Add',
      'priorities.shopping_candidate': 'Purchase · {name}',
      'priorities.goal_candidate': 'Goal · {name}',
      'priorities.action_failed': 'Unable to perform this action.',
      'priorities.status.planned': 'Planned',
      'priorities.status.active': 'Active',
      'priorities.status.paused': 'Paused',
      'priorities.status.archived': 'Archived',
      'priorities.source.shopping': 'Purchase',
      'priorities.source.goal': 'Goal',
      'priorities.decision.buy_now': 'Buy now',
      'priorities.decision.wait': 'Wait',
      'priorities.decision.fund_progressively': 'Fund progressively',
      'priorities.source_status.planned': 'Planned',
      'priorities.source_status.active': 'Active',
      'priorities.source_status.paused': 'Paused',
      'priorities.source_status.completed': 'Completed',
      'priorities.source_status.purchased': 'Purchased',
      'priorities.source_status.cancelled': 'Cancelled',
      'priorities.source_status.archived': 'Archived',
    },
    AppLanguage.arabic: {
      'priorities.load_error': 'تعذر تحميل الأولويات.',
      'priorities.title': 'الأولويات',
      'priorities.subtitle':
          'نظّم المشتريات والأهداف الحالية. هذا التوقع لا ينشئ أي قيد مالي.',
      'priorities.create_plan': 'إنشاء خطة',
      'priorities.empty_title': 'لا توجد خطة أولويات',
      'priorities.empty_subtitle':
          'أنشئ خطة لترتيب مشترياتك المخطط لها وأهدافك.',
      'priorities.projection_loading': 'جارٍ تحميل التوقع.',
      'priorities.projection_planned':
          'خطة مخططة — استخدمها كمرجع للحصول على التوقعات.',
      'priorities.projection_unavailable_data':
          'التوقع غير متاح — تعذرت قراءة البيانات المطلوبة.',
      'priorities.projection_unavailable_capacity':
          'التوقع غير متاح — لا توفر هذه الخطة قدرة قابلة للتطبيق.',
      'priorities.projection_missing_item':
          'التوقع غير متاح — العنصر غير موجود في الخطة.',
      'priorities.use_for_projection': 'استخدامها لتوقعاتي',
      'priorities.edit_plan': 'تعديل الخطة',
      'priorities.plan_status': 'حالة الخطة',
      'priorities.pause': 'إيقاف مؤقت',
      'priorities.archive': 'أرشفة',
      'priorities.capacity_missing': 'القدرة الشهرية المحاكية: غير محددة',
      'priorities.capacity_value': 'القدرة الشهرية المحاكية: {amount}',
      'priorities.planning_disclaimer':
          'افتراض للتخطيط فقط — لا يتم تعديل أي ميزانية أو حساب أو رصيد.',
      'priorities.add_project': 'إضافة عملية شراء أو هدف',
      'priorities.no_project': 'لا يوجد مشروع في هذه الخطة.',
      'priorities.activate_title': 'استخدام هذه الخطة لتوقعاتي',
      'priorities.activate_first':
          'ستصبح هذه الخطة مرجع توقعاتك. لن يتم إنشاء أي حركة مالية.',
      'priorities.activate_replace':
          'ستحل هذه الخطة محل «{plan}» كمرجع لتوقعاتك. لن يتم إنشاء أي حركة مالية.',
      'priorities.cancel': 'إلغاء',
      'priorities.use_plan': 'استخدام هذه الخطة',
      'priorities.estimated_need': 'الحاجة المقدرة: {amount}',
      'priorities.progress': 'التقدم: {progress}٪',
      'priorities.funding_month.one': 'شهر تمويل مقدر واحد',
      'priorities.funding_month.many': '{count} أشهر تمويل مقدرة',
      'priorities.forecast': 'التوقع: {date}',
      'priorities.decision': 'القرار: {decision}',
      'priorities.status': 'الحالة: {status}',
      'priorities.financial_decision': 'القرار المالي',
      'priorities.remove': 'إزالة من الخطة',
      'priorities.plan_name': 'اسم الخطة *',
      'priorities.monthly_capacity': 'القدرة الشهرية المحاكية (MAD)',
      'priorities.capacity_helper': 'افتراض للتخطيط، دون قيد مالي.',
      'priorities.notes': 'ملاحظات',
      'priorities.invalid_capacity': 'القدرة الشهرية غير صالحة.',
      'priorities.invalid_name':
          'يجب أن يحتوي اسم الخطة على ما بين حرف واحد و120 حرفًا.',
      'priorities.positive_capacity': 'يجب أن تكون القدرة الشهرية موجبة.',
      'priorities.notes_too_long': 'لا يمكن أن تتجاوز الملاحظات 2000 حرف.',
      'priorities.create': 'إنشاء',
      'priorities.save': 'حفظ',
      'priorities.add_priority': 'إضافة أولوية',
      'priorities.no_eligible_project':
          'لا توجد عملية شراء أو هدف مؤهل. لا يمكن إضافة المشاريع المرتبطة مرتين.',
      'priorities.project': 'المشروع *',
      'priorities.add': 'إضافة',
      'priorities.shopping_candidate': 'شراء · {name}',
      'priorities.goal_candidate': 'هدف · {name}',
      'priorities.action_failed': 'تعذر تنفيذ هذا الإجراء.',
      'priorities.status.planned': 'مخطط',
      'priorities.status.active': 'نشط',
      'priorities.status.paused': 'متوقف مؤقتًا',
      'priorities.status.archived': 'مؤرشف',
      'priorities.source.shopping': 'شراء',
      'priorities.source.goal': 'هدف',
      'priorities.decision.buy_now': 'الشراء الآن',
      'priorities.decision.wait': 'الانتظار',
      'priorities.decision.fund_progressively': 'التمويل تدريجيًا',
      'priorities.source_status.planned': 'مخطط',
      'priorities.source_status.active': 'نشط',
      'priorities.source_status.paused': 'متوقف مؤقتًا',
      'priorities.source_status.completed': 'مكتمل',
      'priorities.source_status.purchased': 'تم شراؤه',
      'priorities.source_status.cancelled': 'ملغى',
      'priorities.source_status.archived': 'مؤرشف',
    },
    AppLanguage.darija: {
      'priorities.load_error': 'ما قدرناش نحملو الأولويات.',
      'priorities.title': 'الأولويات',
      'priorities.subtitle':
          'رتب الشريات والأهداف اللي كاينين. هاد التوقع ما كيخلق حتى قيد مالي.',
      'priorities.create_plan': 'دير خطة',
      'priorities.empty_title': 'ما كاينة حتى خطة ديال الأولويات',
      'priorities.empty_subtitle': 'دير خطة باش ترتب الشريات والأهداف ديالك.',
      'priorities.projection_loading': 'التوقع كيتحمل.',
      'priorities.projection_planned':
          'الخطة مبرمجة — استعملها كمرجع باش تشوف التوقعات.',
      'priorities.projection_unavailable_data':
          'التوقع ما متوفرش — ما قدرناش نقراو المعطيات اللازمة.',
      'priorities.projection_unavailable_capacity':
          'التوقع ما متوفرش — هاد الخطة ما فيهاش قدرة قابلة للتطبيق.',
      'priorities.projection_missing_item':
          'التوقع ما متوفرش — العنصر ما كاينش فالخطة.',
      'priorities.use_for_projection': 'استعملها فالتوقعات ديالي',
      'priorities.edit_plan': 'بدل الخطة',
      'priorities.plan_status': 'حالة الخطة',
      'priorities.pause': 'وقف مؤقتا',
      'priorities.archive': 'أرشف',
      'priorities.capacity_missing': 'القدرة الشهرية المحاكية: خاصها تعمر',
      'priorities.capacity_value': 'القدرة الشهرية المحاكية: {amount}',
      'priorities.planning_disclaimer':
          'غير فرضية ديال التخطيط — ما كيتبدل لا بودجي لا حساب لا رصيد.',
      'priorities.add_project': 'زيد شرية ولا هدف',
      'priorities.no_project': 'ما كاين حتى مشروع فهاد الخطة.',
      'priorities.activate_title': 'استعمل هاد الخطة فالتوقعات ديالي',
      'priorities.activate_first':
          'هاد الخطة غادي تولي المرجع ديال توقعاتك. ما غادي تخلق حتى حركة مالية.',
      'priorities.activate_replace':
          'هاد الخطة غادي تعوض «{plan}» كمرجع ديال توقعاتك. ما غادي تخلق حتى حركة مالية.',
      'priorities.cancel': 'إلغاء',
      'priorities.use_plan': 'استعمل هاد الخطة',
      'priorities.estimated_need': 'الحاجة المقدرة: {amount}',
      'priorities.progress': 'التقدم: {progress}٪',
      'priorities.funding_month.one': 'شهر واحد ديال التمويل المقدر',
      'priorities.funding_month.many': '{count} شهور ديال التمويل المقدر',
      'priorities.forecast': 'التوقع: {date}',
      'priorities.decision': 'القرار: {decision}',
      'priorities.status': 'الحالة: {status}',
      'priorities.financial_decision': 'القرار المالي',
      'priorities.remove': 'حيد من الخطة',
      'priorities.plan_name': 'سمية الخطة *',
      'priorities.monthly_capacity': 'القدرة الشهرية المحاكية (MAD)',
      'priorities.capacity_helper': 'فرضية ديال التخطيط، بلا قيد مالي.',
      'priorities.notes': 'ملاحظات',
      'priorities.invalid_capacity': 'القدرة الشهرية ما صالحةش.',
      'priorities.invalid_name': 'سمية الخطة خاصها تكون بين حرف واحد و120 حرف.',
      'priorities.positive_capacity': 'القدرة الشهرية خاصها تكون موجبة.',
      'priorities.notes_too_long': 'الملاحظات ما يفوتوش 2000 حرف.',
      'priorities.create': 'دير',
      'priorities.save': 'سجل',
      'priorities.add_priority': 'زيد أولوية',
      'priorities.no_eligible_project':
          'ما كاينة لا شرية لا هدف صالح. المشاريع المربوطين ما يمكنش يتزادو جوج مرات.',
      'priorities.project': 'المشروع *',
      'priorities.add': 'زيد',
      'priorities.shopping_candidate': 'شرية · {name}',
      'priorities.goal_candidate': 'هدف · {name}',
      'priorities.action_failed': 'ما قدرناش نديرو هاد العملية.',
      'priorities.status.planned': 'مبرمج',
      'priorities.status.active': 'خدام',
      'priorities.status.paused': 'موقف مؤقتا',
      'priorities.status.archived': 'مأرشف',
      'priorities.source.shopping': 'شرية',
      'priorities.source.goal': 'هدف',
      'priorities.decision.buy_now': 'شري دابا',
      'priorities.decision.wait': 'تسنى',
      'priorities.decision.fund_progressively': 'مول بشوية بشوية',
      'priorities.source_status.planned': 'مبرمج',
      'priorities.source_status.active': 'خدام',
      'priorities.source_status.paused': 'موقف مؤقتا',
      'priorities.source_status.completed': 'تسالى',
      'priorities.source_status.purchased': 'تشرا',
      'priorities.source_status.cancelled': 'تلغى',
      'priorities.source_status.archived': 'مأرشف',
    },
  };
}
