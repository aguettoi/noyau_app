import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppLanguage { french, arabic, darija, english }

extension AppLanguageX on AppLanguage {
  Locale get locale => switch (this) {
    AppLanguage.french => const Locale('fr'),
    AppLanguage.arabic => const Locale('ar'),
    AppLanguage.darija => const Locale('ary'),
    AppLanguage.english => const Locale('en'),
  };

  String get label => switch (this) {
    AppLanguage.french => 'Français',
    AppLanguage.arabic => 'العربية',
    AppLanguage.darija => 'الدارجة',
    AppLanguage.english => 'English',
  };

  static AppLanguage fromCode(String? code) => AppLanguage.values.firstWhere(
    (value) => value.locale.languageCode == code,
    orElse: () => AppLanguage.french,
  );
}

class AppLocaleController extends StateNotifier<AppLanguage> {
  AppLocaleController() : super(AppLanguage.french) {
    _restore();
  }

  static const _key = 'l4.language';

  Future<void> _restore() async {
    final preferences = await SharedPreferences.getInstance();
    state = AppLanguageX.fromCode(preferences.getString(_key));
  }

  Future<void> select(AppLanguage language) async {
    state = language;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_key, language.locale.languageCode);
  }
}

final appLocaleProvider =
    StateNotifierProvider<AppLocaleController, AppLanguage>(
      (ref) => AppLocaleController(),
    );

class AppWords {
  const AppWords(this.language);
  final AppLanguage language;

  String text(String key) =>
      (_values[language] ?? _values[AppLanguage.french]!)[key] ??
      _values[AppLanguage.french]![key] ??
      key;

  static const _values = <AppLanguage, Map<String, String>>{
    AppLanguage.french: {
      'title': 'FINANCIEL PILOTE',
      'tagline': 'Le pilotage complet de votre foyer, de 1 à N membres.',
      'login': 'Se connecter',
      'signup': 'Créer un compte',
      'invitation': 'J’ai une invitation au foyer',
      'discover': 'Découvrir les modules',
      'help': 'Aide et mode d’emploi',
      'continue': 'Continuer',
      'skip': 'Passer pour le moment',
    },
    AppLanguage.english: {
      'title': 'FINANCIEL PILOTE',
      'tagline': 'Complete household management, for one to many members.',
      'login': 'Sign in',
      'signup': 'Create an account',
      'invitation': 'I have a household invitation',
      'discover': 'Discover the modules',
      'help': 'Help and guides',
      'continue': 'Continue',
      'skip': 'Skip for now',
    },
    AppLanguage.arabic: {
      'title': 'المدبّر المالي',
      'tagline': 'تدبير شامل للأسرة، من عضو واحد إلى عدة أعضاء.',
      'login': 'تسجيل الدخول',
      'signup': 'إنشاء حساب',
      'invitation': 'لدي دعوة للانضمام إلى أسرة',
      'discover': 'اكتشاف الوحدات',
      'help': 'المساعدة ودليل الاستخدام',
      'continue': 'متابعة',
      'skip': 'تخطي الآن',
    },
    AppLanguage.darija: {
      'title': 'FINANCIEL PILOTE',
      'tagline': 'دبّر داركم كاملة، من عضو واحد حتى لعدة أعضاء.',
      'login': 'دخل للحساب',
      'signup': 'صايب حساب',
      'invitation': 'عندي دعوة لدار',
      'discover': 'شوف الخدمات',
      'help': 'المساعدة وطريقة الاستعمال',
      'continue': 'كمّل',
      'skip': 'دوز دابا',
    },
  };
}
