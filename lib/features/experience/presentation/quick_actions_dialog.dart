import 'package:flutter/material.dart';

import '../../../core/localization/app_locale.dart';

class QuickActionItem {
  const QuickActionItem({
    required this.label,
    required this.icon,
    required this.run,
  });
  final String label;
  final IconData icon;
  final VoidCallback run;
}

class QuickActionsDialog extends StatefulWidget {
  const QuickActionsDialog({super.key, required this.actions});
  final List<QuickActionItem> actions;

  @override
  State<QuickActionsDialog> createState() => _QuickActionsDialogState();
}

class _QuickActionsDialogState extends State<QuickActionsDialog> {
  var _query = '';
  @override
  Widget build(BuildContext context) {
    final words = AppWords.of(context);
    final query = _query.trim().toLowerCase();
    final actions = widget.actions
        .where((item) => item.label.toLowerCase().contains(query))
        .toList();
    return AlertDialog(
      title: Text(words.text('shell.quick.title')),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('quick-action-search'),
              autofocus: true,
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: words.text('shell.quick.search'),
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final item in actions)
                    ListTile(
                      leading: Icon(item.icon),
                      title: Text(item.label),
                      onTap: () {
                        Navigator.of(context).pop();
                        item.run();
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(words.text('shell.close')),
        ),
      ],
    );
  }
}
