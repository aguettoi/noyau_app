import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppLanguage { french, arabic, darija, english }

enum AppLocaleMode { automatic, manual }

extension AppLanguageX on AppLanguage {
  Locale get locale => switch (this) {
    AppLanguage.french => const Locale('fr'),
    AppLanguage.arabic => const Locale('ar'),
    // Flutter's Material localizations do not expose an `ary` delegate.
    // Use its supported Moroccan Arabic locale for rendering while retaining
    // `ary` as the persisted product language code.
    AppLanguage.darija => const Locale('ar', 'MA'),
    AppLanguage.english => const Locale('en'),
  };

  String get storageCode => switch (this) {
    AppLanguage.french => 'fr',
    AppLanguage.arabic => 'ar',
    AppLanguage.darija => 'ary',
    AppLanguage.english => 'en',
  };

  String get label => switch (this) {
    AppLanguage.french => 'Français',
    AppLanguage.arabic => 'العربية',
    AppLanguage.darija => 'الدارجة',
    AppLanguage.english => 'English',
  };

  static AppLanguage fromCode(String? code) => switch (code) {
    'fr' => AppLanguage.french,
    'en' => AppLanguage.english,
    'ar' => AppLanguage.arabic,
    'ary' => AppLanguage.darija,
    _ => AppLanguage.french,
  };

  static AppLanguage fromLocale(Locale locale) =>
      locale.languageCode == 'ar' && locale.countryCode == 'MA'
      ? AppLanguage.darija
      : fromCode(locale.languageCode);

  static AppLanguage fromEnvironmentLocales(Iterable<Locale> locales) {
    for (final locale in locales) {
      final code = locale.languageCode.toLowerCase();
      if (code == 'ary') return AppLanguage.darija;
      if (code == 'fr') return AppLanguage.french;
      if (code == 'en') return AppLanguage.english;
      if (code == 'ar') return AppLanguage.arabic;
    }
    return AppLanguage.french;
  }
}

class AppLocaleController extends StateNotifier<AppLanguage>
    with WidgetsBindingObserver {
  AppLocaleController({
    List<Locale> Function()? environmentLocales,
    this._onModeChanged,
  }) : _environmentLocales =
           environmentLocales ??
           (() => WidgetsBinding.instance.platformDispatcher.locales),
       super(
         AppLanguageX.fromEnvironmentLocales(
           (environmentLocales ??
               (() => WidgetsBinding.instance.platformDispatcher.locales))(),
         ),
       ) {
    WidgetsBinding.instance.addObserver(this);
    _onModeChanged?.call(AppLocaleMode.automatic);
    _restore();
  }

  static const languageKey = 'l4.language';
  static const modeKey = 'l4.language.mode';

  final List<Locale> Function() _environmentLocales;
  final void Function(AppLocaleMode mode)? _onModeChanged;
  var _mode = AppLocaleMode.automatic;
  var _revision = 0;

  AppLocaleMode get mode => _mode;

  Future<void> _restore() async {
    final revision = _revision;
    final preferences = await SharedPreferences.getInstance();
    if (revision != _revision) return;
    final storedLanguage = preferences.getString(languageKey);
    final storedMode = preferences.getString(modeKey);
    // A language saved by versions predating explicit automatic mode is a
    // deliberate manual preference and must remain stable after upgrade.
    if (storedMode == AppLocaleMode.manual.name ||
        (storedMode == null && storedLanguage != null)) {
      _mode = AppLocaleMode.manual;
      state = AppLanguageX.fromCode(storedLanguage);
    } else {
      _mode = AppLocaleMode.automatic;
      state = AppLanguageX.fromEnvironmentLocales(_environmentLocales());
    }
    _onModeChanged?.call(_mode);
  }

  Future<void> select(AppLanguage language) async {
    _revision++;
    _mode = AppLocaleMode.manual;
    state = language;
    _onModeChanged?.call(_mode);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(modeKey, AppLocaleMode.manual.name);
    await preferences.setString(languageKey, language.storageCode);
  }

  Future<void> useAutomatic() async {
    _revision++;
    _mode = AppLocaleMode.automatic;
    state = AppLanguageX.fromEnvironmentLocales(_environmentLocales());
    _onModeChanged?.call(_mode);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(modeKey, AppLocaleMode.automatic.name);
    await preferences.remove(languageKey);
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    if (_mode != AppLocaleMode.automatic) return;
    state = AppLanguageX.fromEnvironmentLocales(
      locales ?? _environmentLocales(),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

final appLocaleModeProvider = StateProvider<AppLocaleMode>(
  (ref) => AppLocaleMode.automatic,
);

final appLocaleProvider =
    StateNotifierProvider<AppLocaleController, AppLanguage>(
      (ref) => AppLocaleController(
        onModeChanged: (mode) =>
            ref.read(appLocaleModeProvider.notifier).state = mode,
      ),
    );

class AppWords {
  const AppWords(this.language);
  final AppLanguage language;

  factory AppWords.of(BuildContext context) =>
      AppWords(AppLanguageX.fromLocale(Localizations.localeOf(context)));

  String text(String key) =>
      (_values[language] ?? _values[AppLanguage.french]!)[key] ??
      _values[AppLanguage.french]![key] ??
      key;

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
      'title': 'FINANCIEL PILOTE',
      'tagline': 'Le pilotage complet de votre foyer, de 1 à N membres.',
      'login': 'Se connecter',
      'signup': 'Créer un compte',
      'invitation': 'J’ai une invitation au foyer',
      'discover': 'Découvrir les modules',
      'help': 'Aide et mode d’emploi',
      'continue': 'Continuer',
      'skip': 'Passer pour le moment',
      'landing.language': 'Langue',
      'language.automatic': 'Automatique / langue de l’appareil',
      'language.settings.title': 'Langue de l’application',
      'landing.module.finance.title': 'Finances',
      'landing.module.finance.description':
          'Comptes, enveloppes, budget et projections.',
      'landing.module.household.title': 'Foyer',
      'landing.module.household.description':
          'Membres, tâches, courses et calendrier.',
      'landing.module.projects.title': 'Projets',
      'landing.module.projects.description':
          'Objectifs, priorités et patrimoine.',
      'landing.module.privacy.title': 'Confidentialité',
      'landing.module.privacy.description':
          'Partage explicite et données privées protégées.',
      'landing.platform.windows': 'Windows',
      'landing.platform.android': 'Android APK',
      'landing.coming_soon': '{platform} — bientôt disponible',
      'nav.dashboard': 'Pilotage',
      'nav.accounts': 'Comptes',
      'nav.foundation': 'Fondation',
      'nav.envelopes': 'Enveloppes',
      'nav.goals': 'Objectifs',
      'nav.shopping': 'Achats',
      'nav.priorities': 'Priorités',
      'nav.import': 'Import',
      'nav.search': 'Recherche et portabilité',
      'nav.members': 'Membres du foyer',
      'nav.logout': 'Se déconnecter',
      'nav.more': 'Plus',
      'nav.more_spaces': 'Autres espaces de FINANCIEL PILOTE',
      'shell.offline':
          'Hors ligne — aucune mutation non confirmée ne sera présentée comme réussie.',
      'shell.reconnecting': 'Reconnexion en cours…',
      'shell.refresh.success': 'Données actualisées.',
      'shell.refresh.error':
          'Actualisation impossible. Vérifiez votre connexion puis réessayez.',
      'shell.refresh.in_progress': 'Actualisation en cours',
      'shell.refresh.action': 'Actualiser',
      'shell.help_configuration': 'Aide et configuration',
      'shell.profile_settings': 'Profil et paramètres',
      'shell.quick.ctrl_k': 'Actions rapides (Ctrl+K)',
      'shell.quick.title': 'Aller rapidement à…',
      'shell.quick.search': 'Rechercher une action',
      'shell.close': 'Fermer',
      'shell.onboarding.household_settings': 'Paramètres du foyer',
      'shell.onboarding.accounts_positions': 'Comptes et positions',
      'shell.onboarding.envelopes_budget': 'Enveloppes et budget',
      'shell.onboarding.goals_priorities': 'Objectifs et priorités',
      'common.configure': 'Configurer',
      'common.later': 'Plus tard',
      'common.finish': 'Terminer',
      'common.email': 'E-mail',
      'auth.first_name': 'Prénom',
      'auth.last_name_optional': 'Nom (facultatif)',
      'auth.password': 'Mot de passe',
      'auth.confirm_password': 'Confirmer le mot de passe',
      'auth.forgot': 'Mot de passe oublié ?',
      'auth.create': 'Créer un compte',
      'auth.create_mine': 'Créer mon compte',
      'auth.have_account': 'J’ai déjà un compte',
      'auth.signup_success_session':
          'Compte créé. Vous pouvez maintenant créer ou rejoindre votre foyer.',
      'auth.signup_success_confirmation':
          'Compte créé. Confirmez votre adresse e-mail puis connectez-vous.',
      'auth.error.email_used': 'Cette adresse e-mail est déjà utilisée.',
      'auth.error.weak_password':
          'Le mot de passe ne respecte pas les règles de sécurité.',
      'auth.error.signup':
          'Création impossible. Vérifiez les informations et votre connexion.',
      'auth.validation.reset_email':
          'Saisissez votre adresse e-mail avant de demander un nouveau mot de passe.',
      'auth.reset_sent':
          'Si cette adresse existe, un e-mail de réinitialisation a été envoyé.',
      'auth.error.reset':
          'Demande impossible pour le moment. Vérifiez votre connexion.',
      'auth.error.configuration':
          'Configuration de connexion indisponible. Relancez une version configurée de FINANCIEL PILOTE.',
      'auth.error.credentials':
          'Connexion impossible. Vérifiez votre e-mail et votre mot de passe.',
      'auth.error.email_unconfirmed':
          'Votre adresse e-mail doit être confirmée avant la connexion.',
      'auth.error.banned':
          'Ce compte ne peut pas se connecter. Contactez le responsable du foyer.',
      'auth.error.rate_limit':
          'Trop de tentatives. Patientez quelques instants puis réessayez.',
      'auth.error.service':
          'Le service de connexion est momentanément indisponible. Réessayez plus tard.',
      'auth.error.network':
          'Connexion au service impossible. Vérifiez votre réseau puis réessayez.',
      'auth.invitation_help':
          'Connectez-vous ou créez le compte correspondant à l’adresse qui a reçu l’invitation. Vous pourrez ensuite la consulter et l’accepter.',
      'auth.signup_intro':
          'Créez votre identité personnelle. Votre foyer sera configuré ensuite.',
      'auth.login_intro':
          'Pilotez. Planifiez. Épargnez. Prospérez.\nConnectez-vous pour accéder à votre foyer.',
      'auth.validation.first_name': 'Saisissez votre prénom.',
      'auth.validation.email': 'Saisissez une adresse e-mail valide.',
      'auth.validation.password': 'Saisissez votre mot de passe.',
      'auth.validation.password_length': 'Utilisez au moins 8 caractères.',
      'auth.validation.password_match':
          'Les mots de passe ne correspondent pas.',
      'onboarding.title': 'Configuration guidée',
      'onboarding.step': 'Étape {current} sur {total}',
      'onboarding.not_started': 'Pas commencé',
      'onboarding.in_progress': 'En cours',
      'onboarding.configured': 'Configuré',
      'onboarding.skipped': 'Passé pour le moment',
      'onboarding.welcome.title': 'Bienvenue',
      'onboarding.welcome.description':
          'Choisissez uniquement les modules utiles aujourd’hui.',
      'onboarding.household.title': 'Votre foyer',
      'onboarding.household.description':
          'Créez ou rejoignez le foyer avec les fonctions de connexion existantes.',
      'onboarding.members.title': 'Membres',
      'onboarding.members.description':
          'Ajoutez un, deux ou plusieurs membres selon votre situation.',
      'onboarding.finance.title': 'Finances',
      'onboarding.finance.description':
          'Comptes, enveloppes et budget peuvent être configurés maintenant ou plus tard.',
      'onboarding.organization.title': 'Organisation',
      'onboarding.organization.description':
          'Activez tâches, courses, calendrier et rappels à votre rythme.',
      'onboarding.privacy.title': 'Confidentialité',
      'onboarding.privacy.description':
          'Vérifiez qui peut voir chaque donnée sensible ou financière.',
      'onboarding.done.title': 'Terminé',
      'onboarding.done.description':
          'Vous pourrez reprendre ou ajuster chaque module depuis les paramètres.',
      'onboarding.module.organization': 'Organisation domestique',
      'onboarding.module.reminders': 'Rappels et calendrier',
      'onboarding.module.privacy': 'Confidentialité et partage',
      'onboarding.module.other': 'Autre module',
      'household.welcome': 'Bienvenue dans FINANCIEL PILOTE',
      'household.configure': 'Configurer votre foyer',
      'household.create': 'Créer mon foyer',
      'household.name': 'Nom du foyer',
      'household.join': 'Rejoindre un foyer',
      'household.join_action': 'Rejoindre',
      'household.invited_by': 'Invitation de {name}',
      'household.validation.name': 'Donnez un nom à votre foyer.',
      'household.error.create':
          'Création impossible. Confirmez votre e-mail puis réessayez.',
      'household.error.invitation':
          'Cette invitation n’est plus disponible ou ne correspond pas à ce compte.',
      'household.intro':
          'Créez votre foyer principal ou acceptez une invitation reçue. Aucune donnée financière n’est créée ici.',
      'household.error.load_invitations':
          'Impossible de vérifier les invitations pour le moment.',
      'household.empty_invitations':
          'Aucune invitation en attente pour cette adresse e-mail.',
      'household.multiple.title':
          'Plusieurs foyers opérationnels sont accessibles',
      'household.multiple.description':
          'FINANCIEL PILOTE ne choisira jamais un foyer arbitrairement. Déconnectez-vous et contactez l’assistance pour régulariser cet accès.',
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
      'landing.language': 'Language',
      'language.automatic': 'Automatic / device language',
      'language.settings.title': 'Application language',
      'landing.module.finance.title': 'Finances',
      'landing.module.finance.description':
          'Accounts, envelopes, budget, and projections.',
      'landing.module.household.title': 'Household',
      'landing.module.household.description':
          'Members, tasks, groceries, and calendar.',
      'landing.module.projects.title': 'Projects',
      'landing.module.projects.description':
          'Goals, priorities, and net worth.',
      'landing.module.privacy.title': 'Privacy',
      'landing.module.privacy.description':
          'Explicit sharing and protected private data.',
      'landing.platform.windows': 'Windows',
      'landing.platform.android': 'Android APK',
      'landing.coming_soon': '{platform} — coming soon',
      'nav.dashboard': 'Dashboard',
      'nav.accounts': 'Accounts',
      'nav.foundation': 'Foundation',
      'nav.envelopes': 'Envelopes',
      'nav.goals': 'Goals',
      'nav.shopping': 'Shopping',
      'nav.priorities': 'Priorities',
      'nav.import': 'Import',
      'nav.search': 'Search and portability',
      'nav.members': 'Household members',
      'nav.logout': 'Sign out',
      'nav.more': 'More',
      'nav.more_spaces': 'Other FINANCIEL PILOTE areas',
      'shell.offline':
          'Offline — no unconfirmed change will be shown as successful.',
      'shell.reconnecting': 'Reconnecting…',
      'shell.refresh.success': 'Data refreshed.',
      'shell.refresh.error':
          'Refresh failed. Check your connection and try again.',
      'shell.refresh.in_progress': 'Refreshing',
      'shell.refresh.action': 'Refresh',
      'shell.help_configuration': 'Help and settings',
      'shell.profile_settings': 'Profile and settings',
      'shell.quick.ctrl_k': 'Quick actions (Ctrl+K)',
      'shell.quick.title': 'Go quickly to…',
      'shell.quick.search': 'Search for an action',
      'shell.close': 'Close',
      'shell.onboarding.household_settings': 'Household settings',
      'shell.onboarding.accounts_positions': 'Accounts and positions',
      'shell.onboarding.envelopes_budget': 'Envelopes and budget',
      'shell.onboarding.goals_priorities': 'Goals and priorities',
      'common.configure': 'Configure',
      'common.later': 'Later',
      'common.finish': 'Finish',
      'common.email': 'Email',
      'auth.first_name': 'First name',
      'auth.last_name_optional': 'Last name (optional)',
      'auth.password': 'Password',
      'auth.confirm_password': 'Confirm password',
      'auth.forgot': 'Forgot password?',
      'auth.create': 'Create an account',
      'auth.create_mine': 'Create my account',
      'auth.have_account': 'I already have an account',
      'auth.signup_success_session':
          'Account created. You can now create or join your household.',
      'auth.signup_success_confirmation':
          'Account created. Confirm your email address, then sign in.',
      'auth.error.email_used': 'This email address is already in use.',
      'auth.error.weak_password':
          'The password does not meet the security requirements.',
      'auth.error.signup':
          'Account creation failed. Check your information and connection.',
      'auth.validation.reset_email':
          'Enter your email address before requesting a new password.',
      'auth.reset_sent':
          'If this address exists, a password reset email has been sent.',
      'auth.error.reset':
          'The request is currently unavailable. Check your connection.',
      'auth.error.configuration':
          'Sign-in configuration is unavailable. Restart a configured version of FINANCIEL PILOTE.',
      'auth.error.credentials':
          'Sign-in failed. Check your email and password.',
      'auth.error.email_unconfirmed':
          'Confirm your email address before signing in.',
      'auth.error.banned':
          'This account cannot sign in. Contact the household owner.',
      'auth.error.rate_limit':
          'Too many attempts. Wait a moment and try again.',
      'auth.error.service':
          'The sign-in service is temporarily unavailable. Try again later.',
      'auth.error.network':
          'Cannot reach the sign-in service. Check your network and try again.',
      'auth.invitation_help':
          'Sign in or create the account matching the address that received the invitation. You can then review and accept it.',
      'auth.signup_intro':
          'Create your personal identity. Your household will be configured next.',
      'auth.login_intro':
          'Control. Plan. Save. Prosper.\nSign in to access your household.',
      'auth.validation.first_name': 'Enter your first name.',
      'auth.validation.email': 'Enter a valid email address.',
      'auth.validation.password': 'Enter your password.',
      'auth.validation.password_length': 'Use at least 8 characters.',
      'auth.validation.password_match': 'Passwords do not match.',
      'onboarding.title': 'Guided setup',
      'onboarding.step': 'Step {current} of {total}',
      'onboarding.not_started': 'Not started',
      'onboarding.in_progress': 'In progress',
      'onboarding.configured': 'Configured',
      'onboarding.skipped': 'Skipped for now',
      'onboarding.welcome.title': 'Welcome',
      'onboarding.welcome.description':
          'Choose only the modules you need today.',
      'onboarding.household.title': 'Your household',
      'onboarding.household.description':
          'Create or join your household using the existing sign-in features.',
      'onboarding.members.title': 'Members',
      'onboarding.members.description':
          'Add one, two, or more members to match your situation.',
      'onboarding.finance.title': 'Finances',
      'onboarding.finance.description':
          'Accounts, envelopes, and budget can be configured now or later.',
      'onboarding.organization.title': 'Organization',
      'onboarding.organization.description':
          'Enable tasks, groceries, calendar, and reminders at your pace.',
      'onboarding.privacy.title': 'Privacy',
      'onboarding.privacy.description':
          'Check who can see each sensitive or financial item.',
      'onboarding.done.title': 'Done',
      'onboarding.done.description':
          'You can resume or adjust each module later from settings.',
      'onboarding.module.organization': 'Household organization',
      'onboarding.module.reminders': 'Reminders and calendar',
      'onboarding.module.privacy': 'Privacy and sharing',
      'onboarding.module.other': 'Other module',
      'household.welcome': 'Welcome to FINANCIEL PILOTE',
      'household.configure': 'Configure your household',
      'household.create': 'Create my household',
      'household.name': 'Household name',
      'household.join': 'Join a household',
      'household.join_action': 'Join',
      'household.invited_by': 'Invitation from {name}',
      'household.validation.name': 'Enter a name for your household.',
      'household.error.create':
          'Creation failed. Confirm your email, then try again.',
      'household.error.invitation':
          'This invitation is no longer available or does not match this account.',
      'household.intro':
          'Create your main household or accept an invitation. No financial data is created here.',
      'household.error.load_invitations':
          'Invitations cannot be checked right now.',
      'household.empty_invitations':
          'No pending invitation exists for this email address.',
      'household.multiple.title': 'Multiple active households are available',
      'household.multiple.description':
          'FINANCIEL PILOTE will never choose a household arbitrarily. Sign out and contact support to resolve this access.',
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
      'landing.language': 'اللغة',
      'language.automatic': 'تلقائي / لغة الجهاز',
      'language.settings.title': 'لغة التطبيق',
      'landing.module.finance.title': 'المالية',
      'landing.module.finance.description':
          'الحسابات والأظرف والميزانية والتوقعات.',
      'landing.module.household.title': 'الأسرة',
      'landing.module.household.description':
          'الأعضاء والمهام والتسوق والتقويم.',
      'landing.module.projects.title': 'المشاريع',
      'landing.module.projects.description': 'الأهداف والأولويات وصافي الثروة.',
      'landing.module.privacy.title': 'الخصوصية',
      'landing.module.privacy.description':
          'مشاركة صريحة وحماية للبيانات الخاصة.',
      'landing.platform.windows': 'Windows',
      'landing.platform.android': 'Android APK',
      'landing.coming_soon': '{platform} — متوفر قريباً',
      'nav.dashboard': 'لوحة القيادة',
      'nav.accounts': 'الحسابات',
      'nav.foundation': 'الأساس',
      'nav.envelopes': 'الأظرف',
      'nav.goals': 'الأهداف',
      'nav.shopping': 'المشتريات',
      'nav.priorities': 'الأولويات',
      'nav.import': 'الاستيراد',
      'nav.search': 'البحث ونقل البيانات',
      'nav.members': 'أفراد الأسرة',
      'nav.logout': 'تسجيل الخروج',
      'nav.more': 'المزيد',
      'nav.more_spaces': 'مساحات أخرى',
      'shell.offline': 'غير متصل — لن يُعرض أي تغيير غير مؤكد على أنه نجح.',
      'shell.reconnecting': 'جارٍ إعادة الاتصال…',
      'shell.refresh.success': 'تم تحديث البيانات.',
      'shell.refresh.error': 'تعذر التحديث. تحقق من اتصالك ثم حاول مجدداً.',
      'shell.refresh.in_progress': 'جارٍ التحديث',
      'shell.refresh.action': 'تحديث',
      'shell.help_configuration': 'المساعدة والإعدادات',
      'shell.profile_settings': 'الملف الشخصي والإعدادات',
      'shell.quick.ctrl_k': 'إجراءات سريعة (Ctrl+K)',
      'shell.quick.title': 'انتقل سريعاً إلى…',
      'shell.quick.search': 'ابحث عن إجراء',
      'shell.close': 'إغلاق',
      'shell.onboarding.household_settings': 'إعدادات الأسرة',
      'shell.onboarding.accounts_positions': 'الحسابات والأرصدة',
      'shell.onboarding.envelopes_budget': 'الأظرف والميزانية',
      'shell.onboarding.goals_priorities': 'الأهداف والأولويات',
      'common.configure': 'إعداد',
      'common.later': 'لاحقاً',
      'common.finish': 'إنهاء',
      'common.email': 'البريد الإلكتروني',
      'auth.first_name': 'الاسم',
      'auth.last_name_optional': 'النسب (اختياري)',
      'auth.password': 'كلمة المرور',
      'auth.confirm_password': 'تأكيد كلمة المرور',
      'auth.forgot': 'نسيت كلمة المرور؟',
      'auth.create': 'إنشاء حساب',
      'auth.create_mine': 'إنشاء حسابي',
      'auth.have_account': 'لدي حساب',
      'auth.signup_success_session':
          'تم إنشاء الحساب. يمكنك الآن إنشاء أسرتك أو الانضمام إليها.',
      'auth.signup_success_confirmation':
          'تم إنشاء الحساب. أكد بريدك الإلكتروني ثم سجل الدخول.',
      'auth.error.email_used': 'هذا البريد الإلكتروني مستخدم بالفعل.',
      'auth.error.weak_password': 'كلمة المرور لا تستوفي قواعد الأمان.',
      'auth.error.signup': 'تعذر إنشاء الحساب. تحقق من المعلومات والاتصال.',
      'auth.validation.reset_email':
          'أدخل بريدك الإلكتروني قبل طلب كلمة مرور جديدة.',
      'auth.reset_sent':
          'إذا كان العنوان موجوداً، فقد تم إرسال رسالة إعادة التعيين.',
      'auth.error.reset': 'تعذر الطلب حالياً. تحقق من اتصالك.',
      'auth.error.configuration':
          'إعداد الاتصال غير متاح. أعد تشغيل نسخة معدة من FINANCIEL PILOTE.',
      'auth.error.credentials':
          'تعذر تسجيل الدخول. تحقق من البريد وكلمة المرور.',
      'auth.error.email_unconfirmed': 'يجب تأكيد بريدك الإلكتروني قبل الدخول.',
      'auth.error.banned':
          'لا يمكن لهذا الحساب تسجيل الدخول. اتصل بمسؤول الأسرة.',
      'auth.error.rate_limit': 'محاولات كثيرة. انتظر قليلاً ثم حاول مجدداً.',
      'auth.error.service': 'خدمة الدخول غير متاحة مؤقتاً. حاول لاحقاً.',
      'auth.error.network': 'تعذر الاتصال بالخدمة. تحقق من الشبكة ثم حاول.',
      'auth.invitation_help':
          'سجل الدخول أو أنشئ الحساب المطابق للعنوان الذي استلم الدعوة، ثم راجعها واقبلها.',
      'auth.signup_intro': 'أنشئ هويتك الشخصية. سيتم إعداد أسرتك بعد ذلك.',
      'auth.login_intro':
          'قُد. خطط. ادخر. ازدهر.\nسجل الدخول للوصول إلى أسرتك.',
      'auth.validation.first_name': 'أدخل اسمك.',
      'auth.validation.email': 'أدخل عنوان بريد صحيحاً.',
      'auth.validation.password': 'أدخل كلمة المرور.',
      'auth.validation.password_length': 'استخدم 8 أحرف على الأقل.',
      'auth.validation.password_match': 'كلمتا المرور غير متطابقتين.',
      'onboarding.title': 'الإعداد الموجّه',
      'onboarding.step': 'الخطوة {current} من {total}',
      'onboarding.not_started': 'لم يبدأ',
      'onboarding.in_progress': 'قيد الإنجاز',
      'onboarding.configured': 'تم الإعداد',
      'onboarding.skipped': 'مؤجل',
      'onboarding.welcome.title': 'مرحباً',
      'onboarding.welcome.description': 'اختر فقط الوحدات التي تحتاجها اليوم.',
      'onboarding.household.title': 'أسرتك',
      'onboarding.household.description':
          'أنشئ أسرتك أو انضم إليها باستخدام وظائف الدخول المتاحة.',
      'onboarding.members.title': 'الأعضاء',
      'onboarding.members.description':
          'أضف عضواً واحداً أو عضوين أو أكثر حسب وضعك.',
      'onboarding.finance.title': 'المالية',
      'onboarding.finance.description':
          'يمكن إعداد الحسابات والأظرف والميزانية الآن أو لاحقاً.',
      'onboarding.organization.title': 'التنظيم',
      'onboarding.organization.description':
          'فعّل المهام والتسوق والتقويم والتذكيرات بوتيرتك.',
      'onboarding.privacy.title': 'الخصوصية',
      'onboarding.privacy.description':
          'تحقق ممن يمكنه رؤية كل بيان حساس أو مالي.',
      'onboarding.done.title': 'اكتمل',
      'onboarding.done.description':
          'يمكنك العودة إلى كل وحدة أو تعديلها من الإعدادات.',
      'onboarding.module.organization': 'تنظيم المنزل',
      'onboarding.module.reminders': 'التذكيرات والتقويم',
      'onboarding.module.privacy': 'الخصوصية والمشاركة',
      'onboarding.module.other': 'وحدة أخرى',
      'household.welcome': 'مرحباً بك في FINANCIEL PILOTE',
      'household.configure': 'إعداد أسرتك',
      'household.create': 'إنشاء أسرتي',
      'household.name': 'اسم الأسرة',
      'household.join': 'الانضمام إلى أسرة',
      'household.join_action': 'انضمام',
      'household.invited_by': 'دعوة من {name}',
      'household.validation.name': 'أدخل اسماً لأسرتك.',
      'household.error.create':
          'تعذر الإنشاء. أكد بريدك الإلكتروني ثم حاول مجدداً.',
      'household.error.invitation':
          'لم تعد هذه الدعوة متاحة أو لا تطابق هذا الحساب.',
      'household.intro':
          'أنشئ أسرتك الرئيسية أو اقبل دعوة. لا تُنشأ أي بيانات مالية هنا.',
      'household.error.load_invitations': 'تعذر التحقق من الدعوات حالياً.',
      'household.empty_invitations':
          'لا توجد دعوة معلقة لهذا البريد الإلكتروني.',
      'household.multiple.title': 'تتوفر عدة أسر نشطة',
      'household.multiple.description':
          'لن يختار FINANCIEL PILOTE أسرة بشكل عشوائي. سجل الخروج واتصل بالدعم.',
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
      'landing.language': 'اللغة',
      'language.automatic': 'أوتوماتيكي / لغة الجهاز',
      'language.settings.title': 'لغة التطبيق',
      'landing.module.finance.title': 'الفلوس',
      'landing.module.finance.description':
          'الحسابات والظروف والميزانية والتوقعات.',
      'landing.module.household.title': 'الدار',
      'landing.module.household.description':
          'الأعضاء والمهام والقضيان والتقويم.',
      'landing.module.projects.title': 'المشاريع',
      'landing.module.projects.description': 'الأهداف والأولويات والممتلكات.',
      'landing.module.privacy.title': 'الخصوصية',
      'landing.module.privacy.description':
          'المشاركة غير بالموافقة والمعطيات الخاصة محمية.',
      'landing.platform.windows': 'Windows',
      'landing.platform.android': 'Android APK',
      'landing.coming_soon': '{platform} — غادي يتوفر قريباً',
      'nav.dashboard': 'القيادة',
      'nav.accounts': 'الحسابات',
      'nav.foundation': 'الأساس',
      'nav.envelopes': 'الظروف',
      'nav.goals': 'الأهداف',
      'nav.shopping': 'الشريان',
      'nav.priorities': 'الأولويات',
      'nav.import': 'الاستيراد',
      'nav.search': 'القليب ونقل المعطيات',
      'nav.members': 'أعضاء الدار',
      'nav.logout': 'خرج',
      'nav.more': 'كتر',
      'nav.more_spaces': 'فضاءات خرين',
      'shell.offline':
          'ما كاينش الريزو — حتى تبديل ما تأكدش ما غاديش يبان ناجح.',
      'shell.reconnecting': 'كنعاودو نتاصلو…',
      'shell.refresh.success': 'تحدّثات المعطيات.',
      'shell.refresh.error': 'ما قدرناش نحدّثو. شوف الريزو وعاود جرّب.',
      'shell.refresh.in_progress': 'كنحدّثو دابا',
      'shell.refresh.action': 'حدّث',
      'shell.help_configuration': 'المساعدة والإعدادات',
      'shell.profile_settings': 'البروفايل والإعدادات',
      'shell.quick.ctrl_k': 'خدمات سريعة (Ctrl+K)',
      'shell.quick.title': 'مشي دغيا لـ…',
      'shell.quick.search': 'قلّب على شي خدمة',
      'shell.close': 'سدّ',
      'shell.onboarding.household_settings': 'إعدادات الدار',
      'shell.onboarding.accounts_positions': 'الحسابات والأرصدة',
      'shell.onboarding.envelopes_budget': 'الظروف والميزانية',
      'shell.onboarding.goals_priorities': 'الأهداف والأولويات',
      'common.configure': 'وجّد',
      'common.later': 'من بعد',
      'common.finish': 'سالي',
      'common.email': 'الإيميل',
      'auth.first_name': 'السمية',
      'auth.last_name_optional': 'النسب (اختياري)',
      'auth.password': 'كلمة السر',
      'auth.confirm_password': 'عاود كلمة السر',
      'auth.forgot': 'نسيتي كلمة السر؟',
      'auth.create': 'صايب حساب',
      'auth.create_mine': 'صايب حسابي',
      'auth.have_account': 'عندي ديجا حساب',
      'auth.signup_success_session':
          'تصايب الحساب. دابا تقدر تصايب داركم ولا تدخل ليها.',
      'auth.signup_success_confirmation':
          'تصايب الحساب. أكد الإيميل ديالك ومن بعد دخل.',
      'auth.error.email_used': 'هاد الإيميل مستعمل ديجا.',
      'auth.error.weak_password': 'كلمة السر ما فيهاش شروط الأمان.',
      'auth.error.signup': 'ما تصايبش الحساب. راجع المعلومات والكونيكسيون.',
      'auth.validation.reset_email': 'دخل الإيميل قبل ما تطلب كلمة سر جديدة.',
      'auth.reset_sent':
          'إلا كان هاد الإيميل موجود، راه تصيفط ليه إيميل ديال التبديل.',
      'auth.error.reset': 'الطلب ما خدمش دابا. شوف الكونيكسيون.',
      'auth.error.configuration':
          'إعدادات الدخول ما موجوداش. عاود خدّم نسخة موجّدة ديال FINANCIEL PILOTE.',
      'auth.error.credentials': 'الدخول ما خدمش. راجع الإيميل وكلمة السر.',
      'auth.error.email_unconfirmed': 'خصك تأكد الإيميل قبل ما تدخل.',
      'auth.error.banned': 'هاد الحساب ما يقدرش يدخل. تاصل مع مسؤول الدار.',
      'auth.error.rate_limit': 'كاينين بزاف ديال المحاولات. تسنى شوية وعاود.',
      'auth.error.service': 'خدمة الدخول ما خداماش دابا. عاود من بعد.',
      'auth.error.network': 'ما قدرناش نتاصلو بالخدمة. شوف الريزو وعاود.',
      'auth.invitation_help':
          'دخل ولا صايب الحساب ديال الإيميل لي جاتو الدعوة، ومن بعد شوفها وقبلها.',
      'auth.signup_intro': 'صايب الهوية ديالك. من بعد غادي توجّد داركم.',
      'auth.login_intro': 'دبّر. خطّط. وفّر. تقدّم.\nدخل باش توصل لداركم.',
      'auth.validation.first_name': 'دخل السمية ديالك.',
      'auth.validation.email': 'دخل إيميل صحيح.',
      'auth.validation.password': 'دخل كلمة السر.',
      'auth.validation.password_length': 'استعمل 8 حروف على الأقل.',
      'auth.validation.password_match': 'كلمات السر ما متشابهينش.',
      'onboarding.title': 'الإعداد بالخطوات',
      'onboarding.step': 'الخطوة {current} من {total}',
      'onboarding.not_started': 'ما بداش',
      'onboarding.in_progress': 'خدام',
      'onboarding.configured': 'موجّد',
      'onboarding.skipped': 'مدوّز دابا',
      'onboarding.welcome.title': 'مرحبا',
      'onboarding.welcome.description': 'ختار غير الخدمات لي محتاج اليوم.',
      'onboarding.household.title': 'داركم',
      'onboarding.household.description':
          'صايب داركم ولا دخل ليها بخدمات الدخول لي كاينين.',
      'onboarding.members.title': 'الأعضاء',
      'onboarding.members.description':
          'زيد عضو ولا جوج ولا كتر على حساب الوضع ديالكم.',
      'onboarding.finance.title': 'الفلوس',
      'onboarding.finance.description':
          'تقدر توجّد الحسابات والظروف والميزانية دابا ولا من بعد.',
      'onboarding.organization.title': 'التنظيم',
      'onboarding.organization.description':
          'خدّم المهام والقضيان والتقويم والتذكيرات بالشوية عليك.',
      'onboarding.privacy.title': 'الخصوصية',
      'onboarding.privacy.description':
          'شوف شكون يقدر يشوف كل معلومة حساسة ولا مالية.',
      'onboarding.done.title': 'سالي',
      'onboarding.done.description':
          'تقدر ترجع ولا تبدّل أي خدمة من الإعدادات.',
      'onboarding.module.organization': 'تنظيم الدار',
      'onboarding.module.reminders': 'التذكيرات والتقويم',
      'onboarding.module.privacy': 'الخصوصية والمشاركة',
      'onboarding.module.other': 'خدمة خرى',
      'household.welcome': 'مرحبا بيك فـ FINANCIEL PILOTE',
      'household.configure': 'وجّد داركم',
      'household.create': 'صايب داري',
      'household.name': 'سمية الدار',
      'household.join': 'دخل لشي دار',
      'household.join_action': 'دخل',
      'household.invited_by': 'دعوة من {name}',
      'household.validation.name': 'عطي سمية لداركم.',
      'household.error.create': 'ما تصايباتش. أكد الإيميل وعاود جرّب.',
      'household.error.invitation':
          'هاد الدعوة ما بقاتش موجودة ولا ما كاتخصّش هاد الحساب.',
      'household.intro':
          'صايب داركم الرئيسية ولا قبل شي دعوة. ما كايتصايب حتى معطى مالي هنا.',
      'household.error.load_invitations': 'ما قدرناش نشوفو الدعوات دابا.',
      'household.empty_invitations': 'ما كاينة حتى دعوة كاتسنى هاد الإيميل.',
      'household.multiple.title': 'كاينين كتر من دار خدامة',
      'household.multiple.description':
          'FINANCIEL PILOTE ما غاديش يختار شي دار بالزهر. خرج وتاصل مع المساعدة.',
    },
  };
}
