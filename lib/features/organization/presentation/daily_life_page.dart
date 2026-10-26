import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../finance/application/providers/remote_household_members_provider.dart';
import '../../finance/application/providers/supabase_client_provider.dart';
import '../application/daily_life_provider.dart';

class DailyLifePage extends ConsumerWidget {
  const DailyLifePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => DefaultTabController(
    length: 4,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Vie quotidienne'),
        bottom: const TabBar(
          isScrollable: true,
          tabs: [
            Tab(text: 'Courses'),
            Tab(text: 'Maison'),
            Tab(text: 'Cycle privé'),
            Tab(text: 'Catégories'),
          ],
        ),
      ),
      body: const TabBarView(
        children: [_GroceriesTab(), _HomeTab(), _CycleTab(), _CategoriesTab()],
      ),
    ),
  );
}

class _GroceriesTab extends ConsumerWidget {
  const _GroceriesTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) => _AsyncList(
    value: ref.watch(groceryItemsProvider),
    empty: 'La liste de courses domestique est vide.',
    tile: (row) => CheckboxListTile(
      value: row['status'] == 'picked',
      title: Text(row['label'] as String),
      subtitle: Text('${row['quantity']} ${row['unit'] ?? ''}'.trim()),
      onChanged: (v) => ref
          .read(dailyLifeActionsProvider)
          .setGroceryStatus(
            row['id'] as String,
            v == true ? 'picked' : 'needed',
          ),
    ),
    onAdd: () => _groceryDialog(context, ref),
  );
}

class _HomeTab extends ConsumerWidget {
  const _HomeTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) => _AsyncList(
    value: ref.watch(homeRecordsProvider),
    empty: 'Aucun contrat, garantie ou entretien.',
    tile: (row) => ListTile(
      leading: const Icon(Icons.home_repair_service_outlined),
      title: Text(row['label'] as String),
      subtitle: Text(
        [
          row['kind'],
          if (row['provider'] != null) row['provider'],
          if (row['due_on'] != null) 'Échéance ${row['due_on']}',
        ].join(' • '),
      ),
    ),
    onAdd: () => _homeDialog(context, ref),
  );
}

class _CycleTab extends ConsumerWidget {
  const _CycleTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members =
        ref.watch(remoteHouseholdMembersProvider).valueOrNull ?? const [];
    final currentUser = ref.watch(currentUserIdProvider);
    final shares = ref.watch(ownCycleSharesProvider).valueOrNull ?? const {};
    return Column(
      children: [
        const MaterialBanner(
          content: Text(
            'Privé par défaut. Seules les dates et phases sont partageables explicitement ; notes, flux et symptômes restent personnels.',
          ),
          actions: [SizedBox.shrink()],
        ),
        Expanded(
          child: _AsyncList(
            value: ref.watch(ownCycleEventsProvider),
            empty: 'Aucune donnée de cycle enregistrée.',
            tile: (row) => ListTile(
              leading: const Icon(Icons.favorite_border),
              title: Text('${row['phase']} — ${row['starts_on']}'),
              subtitle: row['notes'] == null
                  ? null
                  : const Text('Notes privées enregistrées'),
            ),
            onAdd: () => _cycleDialog(context, ref),
          ),
        ),
        if (members.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              children: [
                const Text('Partager uniquement le calendrier :'),
                for (final member in members.where((m) => m.id != currentUser))
                  FilterChip(
                    label: Text(member.displayName),
                    selected: shares.contains(member.id),
                    onSelected: (value) => ref
                        .read(dailyLifeActionsProvider)
                        .setCycleShare(member.id, value),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _CategoriesTab extends ConsumerWidget {
  const _CategoriesTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) => _AsyncList(
    value: ref.watch(businessCategoriesProvider),
    empty: 'Aucune catégorie métier.',
    tile: (row) => ListTile(
      leading: const Icon(Icons.category_outlined),
      title: Text(row['name'] as String),
      trailing: IconButton(
        tooltip: 'Archiver la catégorie',
        icon: const Icon(Icons.archive_outlined),
        onPressed: () => ref
            .read(dailyLifeActionsProvider)
            .archiveCategory(row['id'] as String),
      ),
    ),
    onAdd: () => _textDialog(context, 'Nouvelle catégorie', 'Nom').then((v) {
      if (v != null) ref.read(dailyLifeActionsProvider).addCategory(v);
    }),
  );
}

class _AsyncList extends StatelessWidget {
  const _AsyncList({
    required this.value,
    required this.empty,
    required this.tile,
    required this.onAdd,
  });
  final AsyncValue<List<Map<String, Object?>>> value;
  final String empty;
  final Widget Function(Map<String, Object?>) tile;
  final VoidCallback onAdd;
  @override
  Widget build(BuildContext context) => Stack(
    children: [
      value.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Chargement impossible : $e')),
        data: (rows) => rows.isEmpty
            ? Center(child: Text(empty))
            : ListView(
                padding: const EdgeInsets.only(bottom: 88),
                children: [for (final row in rows) Card(child: tile(row))],
              ),
      ),
      Positioned(
        right: 16,
        bottom: 16,
        child: FloatingActionButton(
          onPressed: onAdd,
          child: const Icon(Icons.add),
        ),
      ),
    ],
  );
}

Future<String?> _textDialog(
  BuildContext context,
  String title,
  String label,
) async {
  final controller = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(labelText: label),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: const Text('Enregistrer'),
        ),
      ],
    ),
  );
  controller.dispose();
  return result == null || result.isEmpty ? null : result;
}

Future<void> _groceryDialog(BuildContext context, WidgetRef ref) async {
  final label = TextEditingController();
  final quantity = TextEditingController(text: '1');
  final unit = TextEditingController();
  final members = await ref.read(remoteHouseholdMembersProvider.future);
  if (!context.mounted) return;
  String? assignee;
  final save = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Ajouter aux courses domestiques'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: label,
              decoration: const InputDecoration(labelText: 'Article'),
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: quantity,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Quantité'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: unit,
                    decoration: const InputDecoration(labelText: 'Unité'),
                  ),
                ),
              ],
            ),
            DropdownButtonFormField<String?>(
              initialValue: assignee,
              decoration: const InputDecoration(labelText: 'Responsable'),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('Tout le foyer'),
                ),
                for (final member in members)
                  DropdownMenuItem(
                    value: member.id,
                    child: Text(member.displayName),
                  ),
              ],
              onChanged: (value) => setState(() => assignee = value),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Ajouter'),
          ),
        ],
      ),
    ),
  );
  if (save == true && label.text.trim().isNotEmpty) {
    await ref
        .read(dailyLifeActionsProvider)
        .addGrocery(
          label.text,
          assignee: assignee,
          quantity: double.tryParse(quantity.text.replaceAll(',', '.')) ?? 1,
          unit: unit.text,
        );
  }
  label.dispose();
  quantity.dispose();
  unit.dispose();
}

Future<void> _homeDialog(BuildContext context, WidgetRef ref) async {
  final label = TextEditingController();
  var kind = 'maintenance';
  var renewal = 'none';
  String? responsible;
  DateTime? due;
  final members = await ref.read(remoteHouseholdMembersProvider.future);
  if (!context.mounted) return;
  final save = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Maison'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: label,
              decoration: const InputDecoration(labelText: 'Libellé'),
            ),
            DropdownButtonFormField(
              initialValue: kind,
              decoration: const InputDecoration(labelText: 'Type'),
              items: const [
                DropdownMenuItem(value: 'contract', child: Text('Contrat')),
                DropdownMenuItem(value: 'warranty', child: Text('Garantie')),
                DropdownMenuItem(
                  value: 'maintenance',
                  child: Text('Entretien'),
                ),
              ],
              onChanged: (v) => setState(() => kind = v!),
            ),
            DropdownButtonFormField<String?>(
              initialValue: responsible,
              decoration: const InputDecoration(labelText: 'Responsable'),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('Tout le foyer'),
                ),
                for (final member in members)
                  DropdownMenuItem(
                    value: member.id,
                    child: Text(member.displayName),
                  ),
              ],
              onChanged: (value) => setState(() => responsible = value),
            ),
            DropdownButtonFormField(
              initialValue: renewal,
              decoration: const InputDecoration(labelText: 'Renouvellement'),
              items: const [
                DropdownMenuItem(value: 'none', child: Text('Aucun')),
                DropdownMenuItem(value: 'monthly', child: Text('Mensuel')),
                DropdownMenuItem(value: 'yearly', child: Text('Annuel')),
              ],
              onChanged: (value) => setState(() => renewal = value!),
            ),
            ListTile(
              title: Text(
                due == null
                    ? 'Ajouter une échéance'
                    : DateFormat.yMd('fr').format(due!),
              ),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                );
                if (picked != null) setState(() => due = picked);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    ),
  );
  if (save == true && label.text.trim().isNotEmpty) {
    await ref.read(dailyLifeActionsProvider).addHomeRecord({
      'label': label.text.trim(),
      'kind': kind,
      'responsible_user_id': responsible,
      'renewal': renewal,
      'due_on': due == null ? null : DateFormat('yyyy-MM-dd').format(due!),
    });
  }
  label.dispose();
}

Future<void> _cycleDialog(BuildContext context, WidgetRef ref) async {
  var start = DateTime.now();
  DateTime? end;
  var phase = 'period';
  String? flow;
  final notes = TextEditingController();
  final symptoms = TextEditingController();
  final save = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Événement personnel'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField(
              initialValue: phase,
              decoration: const InputDecoration(labelText: 'Phase'),
              items: const [
                DropdownMenuItem(value: 'period', child: Text('Règles')),
                DropdownMenuItem(
                  value: 'follicular',
                  child: Text('Folliculaire'),
                ),
                DropdownMenuItem(value: 'ovulation', child: Text('Ovulation')),
                DropdownMenuItem(value: 'luteal', child: Text('Lutéale')),
                DropdownMenuItem(value: 'other', child: Text('Autre')),
              ],
              onChanged: (v) => setState(() => phase = v!),
            ),
            ListTile(
              title: Text(DateFormat.yMd('fr').format(start)),
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                  initialDate: start,
                );
                if (d != null) setState(() => start = d);
              },
            ),
            ListTile(
              title: Text(
                end == null
                    ? 'Ajouter une date de fin'
                    : DateFormat.yMd('fr').format(end!),
              ),
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  firstDate: start,
                  lastDate: DateTime(2100),
                  initialDate: end ?? start,
                );
                if (d != null) setState(() => end = d);
              },
            ),
            DropdownButtonFormField<String?>(
              initialValue: flow,
              decoration: const InputDecoration(labelText: 'Flux (privé)'),
              items: const [
                DropdownMenuItem(value: null, child: Text('Non précisé')),
                DropdownMenuItem(value: 'light', child: Text('Léger')),
                DropdownMenuItem(value: 'medium', child: Text('Moyen')),
                DropdownMenuItem(value: 'heavy', child: Text('Abondant')),
              ],
              onChanged: (value) => setState(() => flow = value),
            ),
            TextField(
              controller: symptoms,
              decoration: const InputDecoration(
                labelText: 'Symptômes privés (séparés par des virgules)',
              ),
            ),
            TextField(
              controller: notes,
              decoration: const InputDecoration(labelText: 'Notes privées'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    ),
  );
  if (save == true) {
    await ref.read(dailyLifeActionsProvider).addCycleEvent({
      'starts_on': DateFormat('yyyy-MM-dd').format(start),
      'ends_on': end == null ? null : DateFormat('yyyy-MM-dd').format(end!),
      'phase': phase,
      'flow': flow,
      'symptoms': symptoms.text
          .split(',')
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList(),
      'notes': notes.text.trim().isEmpty ? null : notes.text.trim(),
    });
  }
  notes.dispose();
  symptoms.dispose();
}
