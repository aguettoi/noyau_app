import 'package:flutter/material.dart';

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
    final query = _query.trim().toLowerCase();
    final actions = widget.actions
        .where((item) => item.label.toLowerCase().contains(query))
        .toList();
    return AlertDialog(
      title: const Text('Aller rapidement à…'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('quick-action-search'),
              autofocus: true,
              onChanged: (value) => setState(() => _query = value),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Rechercher une action',
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
          child: const Text('Fermer'),
        ),
      ],
    );
  }
}
