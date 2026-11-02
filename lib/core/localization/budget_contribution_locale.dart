import 'package:flutter/widgets.dart';
import 'app_locale.dart';

class BudgetContributionWords {
  const BudgetContributionWords(this.language);
  final AppLanguage language;
  factory BudgetContributionWords.of(BuildContext context) =>
      BudgetContributionWords(
        AppLanguageX.fromLocale(Localizations.localeOf(context)),
      );
  String text(String key) => _v[language]![key] ?? key;
  String format(String key, Map<String, Object> values) {
    var value = text(key);
    for (final entry in values.entries) {
      value = value.replaceAll('{${entry.key}}', '${entry.value}');
    }
    return value;
  }

  static Set<String> keysFor(AppLanguage language) =>
      Set.unmodifiable(_v[language]!.keys);
  static bool hasOwnTranslation(AppLanguage language, String key) =>
      _v[language]?[key]?.trim().isNotEmpty == true;

  static const _v = <AppLanguage, Map<String, String>>{
    AppLanguage.french: {
      'contribution.title': 'Contributions du foyer',
      'contribution.members_error': 'Membres indisponibles.',
      'contribution.incomes_error': 'Revenus indisponibles.',
      'contribution.save_error': 'Impossible d’enregistrer les revenus.',
      'contribution.finish': 'Terminer',
      'contribution.continue': 'Continuer',
      'contribution.previous': 'Précédent',
      'contribution.incomes': 'Revenus',
      'contribution.personal_charges': 'Charges personnelles',
      'contribution.rules_error': 'Règles indisponibles.',
      'contribution.shared_distribution': 'Répartition commune',
      'contribution.simulation': 'Simulation',
      'contribution.summary': 'Synthèse',
      'contribution.bonus_hint':
          'Les primes ne sont jamais considérées comme un salaire récurrent.',
      'contribution.salary': 'Salaire récurrent (MAD)',
      'contribution.other_income': 'Autres revenus récurrents (MAD)',
      'contribution.exceptional_income': 'Revenu exceptionnel (MAD)',
      'contribution.exceptional_treatment': 'Traitement du revenu exceptionnel',
      'contribution.include_shared': 'Inclure dans la capacité commune',
      'contribution.exclude_monthly': 'Exclure de l’allocation mensuelle',
      'contribution.direct_envelope': 'Affecter directement à une enveloppe',
      'contribution.no_personal': 'Aucune charge personnelle configurée.',
      'contribution.no_shared': 'Aucune charge commune configurée.',
      'contribution.envelope': 'Enveloppe',
      'contribution.member_choose': 'Membre à choisir',
      'contribution.household_member': 'Membre du foyer',
      'contribution.personal': 'Personnel',
      'contribution.shared_auto': 'Commun — répartition automatique',
      'contribution.shared_custom': 'Commun — répartition personnalisée',
      'contribution.fixed_member': 'Montant fixe par membre',
      'contribution.exceptional': 'Revenu exceptionnel',
      'contribution.capacity':
          'Revenus retenus : {income}\nCharges directes : {charges}\nCapacité contributive : {capacity}{deficit}{share}',
      'contribution.deficit': '\nDéficit personnel : {value}',
      'contribution.auto_share': '\nClé automatique : {value} %',
      'contribution.shared_rule':
          'Budget : {budget}\nMode : {mode}{payment}\n{members}',
      'contribution.usual_payment': '\nPaiement habituel configuré',
      'contribution.member_amount': '{member} : {amount}',
      'contribution.member_summary':
          'Revenus retenus : {income}\nCharges personnelles : {charges}\nCapacité finale : {capacity}',
      'contribution.by_member': 'Synthèse par membre',
      'contribution.household_summary': 'Synthèse du foyer',
      'contribution.recurring_total': 'Revenus récurrents : {value}',
      'contribution.exceptional_total':
          'Revenus exceptionnels inclus : {value}',
      'contribution.resources_total': 'Total ressources retenues : {value}',
      'contribution.personal_total': 'Charges personnelles : {value}',
      'contribution.shared_total': 'Charges communes : {value}',
      'contribution.remaining': 'Reste non affecté : {value}',
      'contribution.no_write_hint':
          'La simulation globale, sans écriture financière, est disponible depuis la page Budget.',
      'contribution.funding_member': '{mode} — {member}',
    },
    AppLanguage.english: {
      'contribution.title': 'Household contributions',
      'contribution.members_error': 'Members are unavailable.',
      'contribution.incomes_error': 'Income is unavailable.',
      'contribution.save_error': 'Unable to save income.',
      'contribution.finish': 'Finish',
      'contribution.continue': 'Continue',
      'contribution.previous': 'Previous',
      'contribution.incomes': 'Income',
      'contribution.personal_charges': 'Personal expenses',
      'contribution.rules_error': 'Rules are unavailable.',
      'contribution.shared_distribution': 'Shared allocation',
      'contribution.simulation': 'Simulation',
      'contribution.summary': 'Summary',
      'contribution.bonus_hint':
          'Bonuses are never treated as recurring salary.',
      'contribution.salary': 'Recurring salary (MAD)',
      'contribution.other_income': 'Other recurring income (MAD)',
      'contribution.exceptional_income': 'Exceptional income (MAD)',
      'contribution.exceptional_treatment': 'Exceptional income treatment',
      'contribution.include_shared': 'Include in shared capacity',
      'contribution.exclude_monthly': 'Exclude from monthly allocation',
      'contribution.direct_envelope': 'Allocate directly to an envelope',
      'contribution.no_personal': 'No personal expense configured.',
      'contribution.no_shared': 'No shared expense configured.',
      'contribution.envelope': 'Envelope',
      'contribution.member_choose': 'Member to select',
      'contribution.household_member': 'Household member',
      'contribution.personal': 'Personal',
      'contribution.shared_auto': 'Shared — automatic allocation',
      'contribution.shared_custom': 'Shared — custom allocation',
      'contribution.fixed_member': 'Fixed amount per member',
      'contribution.exceptional': 'Exceptional income',
      'contribution.capacity':
          'Eligible income: {income}\nDirect expenses: {charges}\nContribution capacity: {capacity}{deficit}{share}',
      'contribution.deficit': '\nPersonal deficit: {value}',
      'contribution.auto_share': '\nAutomatic share: {value}%',
      'contribution.shared_rule':
          'Budget: {budget}\nMode: {mode}{payment}\n{members}',
      'contribution.usual_payment': '\nUsual payment configured',
      'contribution.member_amount': '{member}: {amount}',
      'contribution.member_summary':
          'Eligible income: {income}\nPersonal expenses: {charges}\nFinal capacity: {capacity}',
      'contribution.by_member': 'Summary by member',
      'contribution.household_summary': 'Household summary',
      'contribution.recurring_total': 'Recurring income: {value}',
      'contribution.exceptional_total': 'Exceptional income included: {value}',
      'contribution.resources_total': 'Total eligible resources: {value}',
      'contribution.personal_total': 'Personal expenses: {value}',
      'contribution.shared_total': 'Shared expenses: {value}',
      'contribution.remaining': 'Unallocated remainder: {value}',
      'contribution.no_write_hint':
          'The global simulation, with no financial entry, is available from the Budget page.',
      'contribution.funding_member': '{mode} — {member}',
    },
    AppLanguage.arabic: {
      'contribution.title': 'مساهمات الأسرة',
      'contribution.members_error': 'الأعضاء غير متاحين.',
      'contribution.incomes_error': 'الدخل غير متاح.',
      'contribution.save_error': 'تعذر حفظ الدخل.',
      'contribution.finish': 'إنهاء',
      'contribution.continue': 'متابعة',
      'contribution.previous': 'السابق',
      'contribution.incomes': 'الدخل',
      'contribution.personal_charges': 'المصاريف الشخصية',
      'contribution.rules_error': 'القواعد غير متاحة.',
      'contribution.shared_distribution': 'التوزيع المشترك',
      'contribution.simulation': 'محاكاة',
      'contribution.summary': 'ملخص',
      'contribution.bonus_hint': 'لا تعتبر المكافآت راتباً متكرراً.',
      'contribution.salary': 'الراتب المتكرر (MAD)',
      'contribution.other_income': 'دخل متكرر آخر (MAD)',
      'contribution.exceptional_income': 'دخل استثنائي (MAD)',
      'contribution.exceptional_treatment': 'معالجة الدخل الاستثنائي',
      'contribution.include_shared': 'إدراجه في القدرة المشتركة',
      'contribution.exclude_monthly': 'استبعاده من التوزيع الشهري',
      'contribution.direct_envelope': 'تخصيصه مباشرة لمغلف',
      'contribution.no_personal': 'لا توجد مصاريف شخصية معدة.',
      'contribution.no_shared': 'لا توجد مصاريف مشتركة معدة.',
      'contribution.envelope': 'مغلف',
      'contribution.member_choose': 'عضو للاختيار',
      'contribution.household_member': 'عضو الأسرة',
      'contribution.personal': 'شخصي',
      'contribution.shared_auto': 'مشترك — توزيع تلقائي',
      'contribution.shared_custom': 'مشترك — توزيع مخصص',
      'contribution.fixed_member': 'مبلغ ثابت لكل عضو',
      'contribution.exceptional': 'دخل استثنائي',
      'contribution.capacity':
          'الدخل المعتمد: {income}\nالمصاريف المباشرة: {charges}\nقدرة المساهمة: {capacity}{deficit}{share}',
      'contribution.deficit': '\nعجز شخصي: {value}',
      'contribution.auto_share': '\nالحصة التلقائية: {value}%',
      'contribution.shared_rule':
          'الميزانية: {budget}\nالنمط: {mode}{payment}\n{members}',
      'contribution.usual_payment': '\nالدفع المعتاد معد',
      'contribution.member_amount': '{member}: {amount}',
      'contribution.member_summary':
          'الدخل المعتمد: {income}\nالمصاريف الشخصية: {charges}\nالقدرة النهائية: {capacity}',
      'contribution.by_member': 'ملخص حسب العضو',
      'contribution.household_summary': 'ملخص الأسرة',
      'contribution.recurring_total': 'الدخل المتكرر: {value}',
      'contribution.exceptional_total': 'الدخل الاستثنائي المدرج: {value}',
      'contribution.resources_total': 'إجمالي الموارد المعتمدة: {value}',
      'contribution.personal_total': 'المصاريف الشخصية: {value}',
      'contribution.shared_total': 'المصاريف المشتركة: {value}',
      'contribution.remaining': 'المتبقي غير المخصص: {value}',
      'contribution.no_write_hint':
          'المحاكاة الإجمالية بدون قيد مالي متاحة من صفحة الميزانية.',
      'contribution.funding_member': '{mode} — {member}',
    },
    AppLanguage.darija: {
      'contribution.title': 'مساهمات الدار',
      'contribution.members_error': 'الأعضاء ما متوفرينش.',
      'contribution.incomes_error': 'الدخل ما متوفرش.',
      'contribution.save_error': 'ما قدرناش نسجلو الدخل.',
      'contribution.finish': 'سالي',
      'contribution.continue': 'كمل',
      'contribution.previous': 'رجع',
      'contribution.incomes': 'المداخيل',
      'contribution.personal_charges': 'المصاريف الشخصية',
      'contribution.rules_error': 'القواعد ما متوفرينش.',
      'contribution.shared_distribution': 'التقسيم المشترك',
      'contribution.simulation': 'محاكاة',
      'contribution.summary': 'الخلاصة',
      'contribution.bonus_hint': 'البريمات عمرهم ما كيتحسبو صالير متكرر.',
      'contribution.salary': 'الصالير المتكرر (MAD)',
      'contribution.other_income': 'مداخيل متكررة خرين (MAD)',
      'contribution.exceptional_income': 'دخل استثنائي (MAD)',
      'contribution.exceptional_treatment': 'كيفاش يتعالج الدخل الاستثنائي',
      'contribution.include_shared': 'دخلو فالقدرة المشتركة',
      'contribution.exclude_monthly': 'خرج من التقسيم الشهري',
      'contribution.direct_envelope': 'خصصو مباشرة لظرف',
      'contribution.no_personal': 'ما كايناش مصاريف شخصية مضبوطة.',
      'contribution.no_shared': 'ما كايناش مصاريف مشتركة مضبوطة.',
      'contribution.envelope': 'ظرف',
      'contribution.member_choose': 'خاص تختار عضو',
      'contribution.household_member': 'عضو فالدار',
      'contribution.personal': 'شخصي',
      'contribution.shared_auto': 'مشترك — تقسيم أوتوماتيكي',
      'contribution.shared_custom': 'مشترك — تقسيم مخصص',
      'contribution.fixed_member': 'مبلغ ثابت لكل عضو',
      'contribution.exceptional': 'دخل استثنائي',
      'contribution.capacity':
          'الدخل المحتسب: {income}\nالمصاريف المباشرة: {charges}\nقدرة المساهمة: {capacity}{deficit}{share}',
      'contribution.deficit': '\nالعجز الشخصي: {value}',
      'contribution.auto_share': '\nالقسمة الأوتوماتيكية: {value}%',
      'contribution.shared_rule':
          'البودجي: {budget}\nالطريقة: {mode}{payment}\n{members}',
      'contribution.usual_payment': '\nطريقة الأداء المعتادة مضبوطة',
      'contribution.member_amount': '{member}: {amount}',
      'contribution.member_summary':
          'الدخل المحتسب: {income}\nالمصاريف الشخصية: {charges}\nالقدرة النهائية: {capacity}',
      'contribution.by_member': 'الخلاصة حسب كل عضو',
      'contribution.household_summary': 'خلاصة الدار',
      'contribution.recurring_total': 'المداخيل المتكررة: {value}',
      'contribution.exceptional_total':
          'المداخيل الاستثنائية المحتسبة: {value}',
      'contribution.resources_total': 'مجموع الموارد المحتسبة: {value}',
      'contribution.personal_total': 'المصاريف الشخصية: {value}',
      'contribution.shared_total': 'المصاريف المشتركة: {value}',
      'contribution.remaining': 'الباقي ما تخصصش: {value}',
      'contribution.no_write_hint':
          'المحاكاة العامة بلا حتى تسجيل مالي كاينة فصفحة البودجي.',
      'contribution.funding_member': '{mode} — {member}',
    },
  };
}
