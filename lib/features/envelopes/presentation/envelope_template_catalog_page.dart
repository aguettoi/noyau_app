import 'package:flutter/material.dart';

import '../../../core/theme/app_design_system.dart';
import 'envelope_template_catalog.dart';

class EnvelopeTemplateSelection {
  const EnvelopeTemplateSelection({
    required this.names,
    this.customRequested = false,
  });
  final List<String> names;
  final bool customRequested;
}

class EnvelopeTemplateCatalogPage extends StatefulWidget {
  const EnvelopeTemplateCatalogPage({super.key, this.existingNames = const {}});
  final Set<String> existingNames;

  @override
  State<EnvelopeTemplateCatalogPage> createState() =>
      _EnvelopeTemplateCatalogPageState();
}

class _EnvelopeTemplateCatalogPageState
    extends State<EnvelopeTemplateCatalogPage> {
  final _search = TextEditingController();
  final _selected = <String>{};

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final words = EnvelopeTemplateWords.of(context);
    final query = _search.text.trim().toLowerCase();
    final filtered = envelopeTemplates
        .where((template) {
          final label = envelopeTemplateLabel(words, template);
          return query.isEmpty || label.toLowerCase().contains(query);
        })
        .toList(growable: false);
    final families = <String, List<EnvelopeTemplate>>{};
    for (final template in filtered) {
      (families[template.family] ??= []).add(template);
    }
    return Scaffold(
      appBar: AppBar(title: Text(words.text('title'))),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: AppSpacing.page,
                children: [
                  Text(
                    words.text('title'),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(words.text('subtitle')),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    key: const Key('envelope-template-search'),
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      labelText: words.text('search'),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (filtered.isEmpty)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.search_off),
                        title: Text(words.text('none')),
                      ),
                    ),
                  for (final entry in families.entries) ...[
                    Text(
                      words.text(entry.key),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      children: [
                        for (final template in entry.value)
                          FilterChip(
                            key: Key('envelope-template-${template.id}'),
                            avatar: Icon(template.icon, size: 18),
                            label: Text(envelopeTemplateLabel(words, template)),
                            selected: _selected.contains(template.id),
                            onSelected:
                                widget.existingNames.contains(
                                  envelopeTemplateLabel(
                                    words,
                                    template,
                                  ).toLowerCase(),
                                )
                                ? null
                                : (value) => setState(() {
                                    value
                                        ? _selected.add(template.id)
                                        : _selected.remove(template.id);
                                  }),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                ],
              ),
            ),
            Padding(
              padding: AppSpacing.page,
              child: Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                alignment: WrapAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(
                      context,
                      const EnvelopeTemplateSelection(names: []),
                    ),
                    child: Text(words.text('skip')),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.pop(
                      context,
                      const EnvelopeTemplateSelection(
                        names: [],
                        customRequested: true,
                      ),
                    ),
                    icon: const Icon(Icons.edit_outlined),
                    label: Text(words.text('custom')),
                  ),
                  FilledButton.icon(
                    onPressed: _selected.isEmpty
                        ? null
                        : () => Navigator.pop(
                            context,
                            EnvelopeTemplateSelection(
                              names: envelopeTemplates
                                  .where((e) => _selected.contains(e.id))
                                  .map((e) => envelopeTemplateLabel(words, e))
                                  .toList(),
                            ),
                          ),
                    icon: const Icon(Icons.add),
                    label: Text(words.text('selected')),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
