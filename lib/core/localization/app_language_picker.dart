import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_locale.dart';

class AppLanguagePicker extends ConsumerWidget {
  const AppLanguagePicker({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(appLocaleProvider);
    final mode = ref.watch(appLocaleModeProvider);
    final words = AppWords(language);
    final value = mode == AppLocaleMode.automatic
        ? 'automatic'
        : language.storageCode;
    final picker = DropdownButton<String>(
      key: const Key('app-language-picker'),
      value: value,
      isExpanded: !compact,
      onChanged: (selection) {
        if (selection == null) return;
        if (selection == 'automatic') {
          ref.read(appLocaleProvider.notifier).useAutomatic();
        } else {
          ref
              .read(appLocaleProvider.notifier)
              .select(AppLanguageX.fromCode(selection));
        }
      },
      items: [
        DropdownMenuItem(
          value: 'automatic',
          child: Text(words.text('language.automatic')),
        ),
        for (final item in AppLanguage.values)
          DropdownMenuItem(value: item.storageCode, child: Text(item.label)),
      ],
    );
    return Semantics(
      label: words.text('landing.language'),
      child: compact ? DropdownButtonHideUnderline(child: picker) : picker,
    );
  }
}
