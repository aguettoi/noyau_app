import 'package:flutter/material.dart';

import '../../../core/localization/app_locale.dart';

@immutable
class EnvelopeTemplate {
  const EnvelopeTemplate({
    required this.id,
    required this.family,
    required this.icon,
  });

  final String id;
  final String family;
  final IconData icon;
}

const envelopeTemplates = <EnvelopeTemplate>[
  EnvelopeTemplate(
    id: 'groceries',
    family: 'essential',
    icon: Icons.shopping_cart_outlined,
  ),
  EnvelopeTemplate(
    id: 'transport',
    family: 'essential',
    icon: Icons.directions_bus_outlined,
  ),
  EnvelopeTemplate(
    id: 'utilities',
    family: 'essential',
    icon: Icons.bolt_outlined,
  ),
  EnvelopeTemplate(
    id: 'phone_internet',
    family: 'essential',
    icon: Icons.wifi_outlined,
  ),
  EnvelopeTemplate(id: 'housing', family: 'housing', icon: Icons.home_outlined),
  EnvelopeTemplate(
    id: 'condo',
    family: 'housing',
    icon: Icons.apartment_outlined,
  ),
  EnvelopeTemplate(
    id: 'home_maintenance',
    family: 'housing',
    icon: Icons.home_repair_service_outlined,
  ),
  EnvelopeTemplate(
    id: 'health',
    family: 'personal',
    icon: Icons.health_and_safety_outlined,
  ),
  EnvelopeTemplate(
    id: 'clothing',
    family: 'personal',
    icon: Icons.checkroom_outlined,
  ),
  EnvelopeTemplate(
    id: 'sport',
    family: 'personal',
    icon: Icons.fitness_center_outlined,
  ),
  EnvelopeTemplate(
    id: 'outings',
    family: 'leisure',
    icon: Icons.celebration_outlined,
  ),
  EnvelopeTemplate(
    id: 'restaurants',
    family: 'leisure',
    icon: Icons.restaurant_outlined,
  ),
  EnvelopeTemplate(
    id: 'travel',
    family: 'leisure',
    icon: Icons.flight_outlined,
  ),
  EnvelopeTemplate(id: 'school', family: 'family', icon: Icons.school_outlined),
  EnvelopeTemplate(
    id: 'gifts',
    family: 'family',
    icon: Icons.card_giftcard_outlined,
  ),
  EnvelopeTemplate(
    id: 'family_support',
    family: 'family',
    icon: Icons.volunteer_activism_outlined,
  ),
  EnvelopeTemplate(
    id: 'savings',
    family: 'savings',
    icon: Icons.savings_outlined,
  ),
  EnvelopeTemplate(
    id: 'emergency',
    family: 'savings',
    icon: Icons.shield_outlined,
  ),
  EnvelopeTemplate(
    id: 'investment',
    family: 'savings',
    icon: Icons.trending_up_outlined,
  ),
  EnvelopeTemplate(
    id: 'subscriptions',
    family: 'other',
    icon: Icons.subscriptions_outlined,
  ),
  EnvelopeTemplate(id: 'events', family: 'other', icon: Icons.event_outlined),
];

class EnvelopeTemplateWords {
  const EnvelopeTemplateWords(this.language);
  final AppLanguage language;

  factory EnvelopeTemplateWords.of(BuildContext context) =>
      EnvelopeTemplateWords(
        AppLanguageX.fromLocale(Localizations.localeOf(context)),
      );

  String text(String key) => _values[language]![key] ?? key;
  static Set<String> keysFor(AppLanguage language) =>
      _values[language]!.keys.toSet();

  static const _values = <AppLanguage, Map<String, String>>{
    AppLanguage.french: _fr,
    AppLanguage.english: _en,
    AppLanguage.arabic: _ar,
    AppLanguage.darija: _ary,
  };
}

const _fr = <String, String>{
  'title': 'Choisir des enveloppes',
  'subtitle': 'Une base de départ facultative, entièrement personnalisable.',
  'search': 'Rechercher une enveloppe',
  'none': 'Aucun modèle ne correspond à cette recherche.',
  'selected': 'Créer la sélection',
  'skip': 'Continuer sans modèle',
  'custom': 'Créer une enveloppe personnalisée',
  'essential': 'Essentiel',
  'housing': 'Logement',
  'personal': 'Vie personnelle',
  'leisure': 'Loisirs',
  'family': 'Famille',
  'savings': 'Épargne',
  'other': 'Autres',
  'groceries': 'Courses',
  'transport': 'Transport',
  'utilities': 'Eau et électricité',
  'phone_internet': 'Téléphone / Internet',
  'housing_item': 'Loyer / crédit logement',
  'condo': 'Syndic / copropriété',
  'home_maintenance': 'Entretien logement',
  'health': 'Santé',
  'clothing': 'Vêtements',
  'sport': 'Sport',
  'outings': 'Sorties',
  'restaurants': 'Restaurants',
  'travel': 'Voyages / vacances',
  'school': 'Enfants / école',
  'gifts': 'Cadeaux',
  'family_support': 'Aide familiale',
  'savings_item': 'Épargne',
  'emergency': 'Fonds d’urgence',
  'investment': 'Projet / investissement',
  'subscriptions': 'Abonnements',
  'events': 'Événements / célébrations',
};
const _en = <String, String>{
  'title': 'Choose envelopes',
  'subtitle': 'An optional, fully customizable starting point.',
  'search': 'Search envelopes',
  'none': 'No template matches this search.',
  'selected': 'Create selection',
  'skip': 'Continue without templates',
  'custom': 'Create a custom envelope',
  'essential': 'Essentials',
  'housing': 'Housing',
  'personal': 'Personal life',
  'leisure': 'Leisure',
  'family': 'Family',
  'savings': 'Savings',
  'other': 'Other',
  'groceries': 'Groceries',
  'transport': 'Transport',
  'utilities': 'Water and electricity',
  'phone_internet': 'Phone / Internet',
  'housing_item': 'Rent / home loan',
  'condo': 'Condo fees',
  'home_maintenance': 'Home maintenance',
  'health': 'Health',
  'clothing': 'Clothing',
  'sport': 'Sport',
  'outings': 'Outings',
  'restaurants': 'Restaurants',
  'travel': 'Travel / holidays',
  'school': 'Children / school',
  'gifts': 'Gifts',
  'family_support': 'Family support',
  'savings_item': 'Savings',
  'emergency': 'Emergency fund',
  'investment': 'Project / investment',
  'subscriptions': 'Subscriptions',
  'events': 'Events / celebrations',
};
const _ar = <String, String>{
  'title': 'اختيار المظاريف',
  'subtitle': 'نقطة بداية اختيارية وقابلة للتخصيص بالكامل.',
  'search': 'البحث عن مظروف',
  'none': 'لا يوجد نموذج يطابق البحث.',
  'selected': 'إنشاء المحدد',
  'skip': 'المتابعة دون نماذج',
  'custom': 'إنشاء مظروف مخصص',
  'essential': 'الأساسيات',
  'housing': 'السكن',
  'personal': 'الحياة الشخصية',
  'leisure': 'الترفيه',
  'family': 'العائلة',
  'savings': 'الادخار',
  'other': 'أخرى',
  'groceries': 'البقالة',
  'transport': 'النقل',
  'utilities': 'الماء والكهرباء',
  'phone_internet': 'الهاتف والإنترنت',
  'housing_item': 'الإيجار / قرض السكن',
  'condo': 'رسوم الملكية المشتركة',
  'home_maintenance': 'صيانة المنزل',
  'health': 'الصحة',
  'clothing': 'الملابس',
  'sport': 'الرياضة',
  'outings': 'الخروج',
  'restaurants': 'المطاعم',
  'travel': 'السفر / العطلات',
  'school': 'الأطفال / المدرسة',
  'gifts': 'الهدايا',
  'family_support': 'مساعدة العائلة',
  'savings_item': 'الادخار',
  'emergency': 'صندوق الطوارئ',
  'investment': 'مشروع / استثمار',
  'subscriptions': 'الاشتراكات',
  'events': 'المناسبات / الاحتفالات',
};
const _ary = <String, String>{
  'title': 'اختار الظروف',
  'subtitle': 'بداية اختيارية وتقدر تبدل فيها كيف بغيتي.',
  'search': 'قلب على ظرف',
  'none': 'ما كاين حتى نموذج مناسب للبحث.',
  'selected': 'صايب المختارين',
  'skip': 'كمل بلا نماذج',
  'custom': 'صايب ظرف ديالك',
  'essential': 'الضروريات',
  'housing': 'السكن',
  'personal': 'الحياة الشخصية',
  'leisure': 'الترفيه',
  'family': 'العائلة',
  'savings': 'التوفير',
  'other': 'آخرين',
  'groceries': 'القضية',
  'transport': 'النقل',
  'utilities': 'الما والضو',
  'phone_internet': 'التلفون والإنترنت',
  'housing_item': 'الكراء / كريدي الدار',
  'condo': 'السانديك',
  'home_maintenance': 'تصليحات الدار',
  'health': 'الصحة',
  'clothing': 'الحوايج',
  'sport': 'الرياضة',
  'outings': 'الخروجات',
  'restaurants': 'المطاعم',
  'travel': 'السفر / العطلة',
  'school': 'الدراري / المدرسة',
  'gifts': 'الهدايا',
  'family_support': 'مساعدة العائلة',
  'savings_item': 'التوفير',
  'emergency': 'صندوق الطوارئ',
  'investment': 'مشروع / استثمار',
  'subscriptions': 'الاشتراكات',
  'events': 'المناسبات / الحفلات',
};

String envelopeTemplateLabel(
  EnvelopeTemplateWords words,
  EnvelopeTemplate template,
) {
  if (template.id == 'housing') return words.text('housing_item');
  if (template.id == 'savings') return words.text('savings_item');
  return words.text(template.id);
}
