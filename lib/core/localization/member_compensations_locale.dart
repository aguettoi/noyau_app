import 'package:flutter/widgets.dart';

import 'app_locale.dart';

class MemberCompensationWords {
  const MemberCompensationWords(this.language);
  final AppLanguage language;

  factory MemberCompensationWords.of(BuildContext context) =>
      MemberCompensationWords(
        AppLanguageX.fromLocale(Localizations.localeOf(context)),
      );

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
      'title': 'Compensations internes',
      'load_error': 'Impossible de charger les compensations.',
      'notice':
          'Une compensation suit un financement entre membres. Elle ne crée ni dépense, ni revenu, ni consommation d’enveloppe.',
      'empty': 'Aucune compensation en attente.',
      'transfer_due': '{debtor} doit verser à {creditor}',
      'parties': '{debtor} → {creditor}',
      'remaining_reason': '{reason}\nRestant : {amount}',
      'history': 'Historique',
      'status.to_pay': 'À verser',
      'status.transfer_sent': 'En attente de réception',
      'status.settled': 'Soldée',
      'status.abandoned': 'Abandonnée',
      'detail':
          'Montant initial : {initial}\nRestant : {remaining}\nEn attente de réception : {pending}\n{reason}',
      'debtor': 'Doit verser : {name}',
      'creditor': 'Doit recevoir : {name}',
      'initial_amount': 'Montant initial : {amount}',
      'remaining_amount': 'Montant restant : {amount}',
      'pending_amount': 'En attente de réception : {amount}',
      'reason': 'Motif : {reason}',
      'state': 'État : {state}',
      'close': 'Fermer',
      'make_transfer': 'Effectuer le virement',
      'declare_external': 'Déclarer effectué hors application',
      'external_title': 'Virement déclaré hors application',
      'confirm_receipt': 'Confirmer réception',
      'receipt_title': 'Réception confirmée',
      'abandon': 'Abandonner la compensation',
      'amount': 'Montant (MAD)',
      'cancel': 'Annuler',
      'confirm': 'Confirmer',
      'required_reason': 'Motif obligatoire',
      'continue': 'Continuer',
      'source_account': 'Compte source',
      'destination_account': 'Compte destination',
      'description': 'Description',
      'save_transfer': 'Enregistrer le virement',
      'default_description': 'Règlement compensation {debtor} → {creditor}',
    },
    AppLanguage.english: {
      'title': 'Internal compensations',
      'load_error': 'Unable to load compensations.',
      'notice':
          'A compensation tracks financing between members. It creates no expense, income, or envelope consumption.',
      'empty': 'No pending compensation.',
      'transfer_due': '{debtor} must pay {creditor}',
      'parties': '{debtor} → {creditor}',
      'remaining_reason': '{reason}\nRemaining: {amount}',
      'history': 'History',
      'status.to_pay': 'Payable',
      'status.transfer_sent': 'Awaiting receipt',
      'status.settled': 'Settled',
      'status.abandoned': 'Waived',
      'detail':
          'Initial amount: {initial}\nRemaining: {remaining}\nAwaiting receipt: {pending}\n{reason}',
      'debtor': 'Must pay: {name}',
      'creditor': 'Must receive: {name}',
      'initial_amount': 'Initial amount: {amount}',
      'remaining_amount': 'Remaining amount: {amount}',
      'pending_amount': 'Awaiting receipt: {amount}',
      'reason': 'Reason: {reason}',
      'state': 'Status: {state}',
      'close': 'Close',
      'make_transfer': 'Make the transfer',
      'declare_external': 'Declare completed outside the app',
      'external_title': 'Transfer declared outside the app',
      'confirm_receipt': 'Confirm receipt',
      'receipt_title': 'Receipt confirmed',
      'abandon': 'Waive the compensation',
      'amount': 'Amount (MAD)',
      'cancel': 'Cancel',
      'confirm': 'Confirm',
      'required_reason': 'Reason required',
      'continue': 'Continue',
      'source_account': 'Source account',
      'destination_account': 'Destination account',
      'description': 'Description',
      'save_transfer': 'Save transfer',
      'default_description': 'Compensation settlement {debtor} → {creditor}',
    },
    AppLanguage.arabic: {
      'title': 'التعويضات الداخلية',
      'load_error': 'تعذر تحميل التعويضات.',
      'notice':
          'يتتبع التعويض تمويلاً بين الأعضاء. ولا ينشئ مصروفًا أو دخلاً أو استهلاكًا لظرف.',
      'empty': 'لا توجد تعويضات معلقة.',
      'transfer_due': 'يجب على {debtor} الدفع إلى {creditor}',
      'parties': '{debtor} ← {creditor}',
      'remaining_reason': '{reason}\nالمتبقي: {amount}',
      'history': 'السجل',
      'status.to_pay': 'واجب الدفع',
      'status.transfer_sent': 'في انتظار الاستلام',
      'status.settled': 'مسوّاة',
      'status.abandoned': 'متنازل عنها',
      'detail':
          'المبلغ الأصلي: {initial}\nالمتبقي: {remaining}\nفي انتظار الاستلام: {pending}\n{reason}',
      'debtor': 'يجب أن يدفع: {name}',
      'creditor': 'يجب أن يستلم: {name}',
      'initial_amount': 'المبلغ الأصلي: {amount}',
      'remaining_amount': 'المبلغ المتبقي: {amount}',
      'pending_amount': 'في انتظار الاستلام: {amount}',
      'reason': 'السبب: {reason}',
      'state': 'الحالة: {state}',
      'close': 'إغلاق',
      'make_transfer': 'إجراء التحويل',
      'declare_external': 'التصريح بإنجازه خارج التطبيق',
      'external_title': 'تحويل مصرّح به خارج التطبيق',
      'confirm_receipt': 'تأكيد الاستلام',
      'receipt_title': 'تم تأكيد الاستلام',
      'abandon': 'التنازل عن التعويض',
      'amount': 'المبلغ (MAD)',
      'cancel': 'إلغاء',
      'confirm': 'تأكيد',
      'required_reason': 'السبب إلزامي',
      'continue': 'متابعة',
      'source_account': 'الحساب المصدر',
      'destination_account': 'الحساب الوجهة',
      'description': 'الوصف',
      'save_transfer': 'حفظ التحويل',
      'default_description': 'تسوية تعويض {debtor} ← {creditor}',
    },
    AppLanguage.darija: {
      'title': 'التعويضات الداخلية',
      'load_error': 'ما قدرناش نحملو التعويضات.',
      'notice':
          'التعويض كيتبع تمويل بين الأعضاء. ما كيدير لا مصروف لا مدخول لا استهلاك ديال ظرف.',
      'empty': 'ما كاين حتى تعويض كيتسنى.',
      'transfer_due': 'خاص {debtor} يخلص لـ {creditor}',
      'parties': '{debtor} ← {creditor}',
      'remaining_reason': '{reason}\nالباقي: {amount}',
      'history': 'التاريخ',
      'status.to_pay': 'خاصو يتخلص',
      'status.transfer_sent': 'كيتسنى التوصل',
      'status.settled': 'تسوات',
      'status.abandoned': 'تسامح فيها',
      'detail':
          'المبلغ اللول: {initial}\nالباقي: {remaining}\nكيتسنى التوصل: {pending}\n{reason}',
      'debtor': 'خاصو يخلص: {name}',
      'creditor': 'خاصو يتوصل: {name}',
      'initial_amount': 'المبلغ اللول: {amount}',
      'remaining_amount': 'المبلغ الباقي: {amount}',
      'pending_amount': 'كيتسنى التوصل: {amount}',
      'reason': 'السبب: {reason}',
      'state': 'الحالة: {state}',
      'close': 'سد',
      'make_transfer': 'دير التحويل',
      'declare_external': 'صرح بلي تدار برا التطبيق',
      'external_title': 'تحويل تصرح به برا التطبيق',
      'confirm_receipt': 'أكد التوصل',
      'receipt_title': 'تأكد التوصل',
      'abandon': 'تسامح فالتعويض',
      'amount': 'المبلغ (MAD)',
      'cancel': 'لغي',
      'confirm': 'أكد',
      'required_reason': 'السبب ضروري',
      'continue': 'كمل',
      'source_account': 'الحساب المصدر',
      'destination_account': 'الحساب الوجهة',
      'description': 'الوصف',
      'save_transfer': 'سجل التحويل',
      'default_description': 'تسوية تعويض {debtor} ← {creditor}',
    },
  };
}
