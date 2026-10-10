import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_design_system.dart';
import '../application/monthly_close_provider.dart';
import '../domain/monthly_close.dart';

class MonthlyClosePage extends ConsumerWidget {
  const MonthlyClosePage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(monthlyCloseProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Fin de mois')),
      body: SafeArea(
        child: value.when(
          loading: () => const FpLoadingState(label: 'Analyse du mois…'),
          error: (_, _) => const FpErrorState(
            message: 'La préparation de clôture ne peut pas être chargée.',
          ),
          data: (snapshot) => LayoutBuilder(
            builder: (context, box) => ListView(
              key: const Key('monthly-close-page'),
              padding: AppLayout.pagePaddingFor(box.maxWidth),
              children: [
                FpPageHeader(
                  title: 'Clôture mensuelle',
                  subtitle:
                      'Checklist explicable • ${snapshot.month.month.toString().padLeft(2, '0')}/${snapshot.month.year}',
                ),
                const SizedBox(height: AppSpacing.md),
                _Health(snapshot),
                const SizedBox(height: AppSpacing.md),
                _Kpis(snapshot.kpis),
                const SizedBox(height: AppSpacing.md),
                const _Workflow(),
                const SizedBox(height: AppSpacing.md),
                _Todo(snapshot),
                const SizedBox(height: AppSpacing.md),
                const _Regularization(),
                const SizedBox(height: AppSpacing.md),
                _CloseAction(snapshot),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Kpis extends StatelessWidget {
  const _Kpis(this.kpis);
  final ReliabilityKpis? kpis;
  @override
  Widget build(BuildContext context) {
    final value = kpis;
    if (value == null) return const SizedBox.shrink();
    String percent(int count) => '${(value.ratio(count) * 100).round()} %';
    return FpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Fiabilité des saisies',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.xs,
            children: [
              Text('J+0 ${percent(value.sameDay)}'),
              Text('J+1 ${percent(value.withinOneDay)}'),
              Text('J+3 ${percent(value.withinThreeDays)}'),
              Text('${value.late} saisie(s) tardive(s)'),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          const SecondaryInfoText(
            'Attribution : FOYER / NON ATTRIBUÉ lorsque la responsabilité ne peut pas être démontrée.',
          ),
        ],
      ),
    );
  }
}

class _Health extends StatelessWidget {
  const _Health(this.snapshot);
  final MonthlyCloseSnapshot snapshot;
  @override
  Widget build(BuildContext context) => FpCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Santé du mois',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Text(
              '${snapshot.healthPercent} %',
              key: const Key('month-health-percent'),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        LinearProgressIndicator(value: snapshot.healthPercent / 100),
        const SizedBox(height: AppSpacing.sm),
        Text(
          snapshot.ready
              ? 'Prêt sous réserve des avertissements'
              : '${snapshot.blockers} condition(s) bloquante(s) à traiter',
        ),
        Text(
          '${snapshot.warnings} avertissement(s)',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
  );
}

class _Workflow extends StatelessWidget {
  const _Workflow();
  static const labels = [
    'Saisies',
    'Justificatifs',
    'Rapprochements',
    'Inventaire espèces',
    'Traitement des écarts',
    'Compensations',
    'Régularisations',
    'Virements / retraits',
    'Contrôle final',
    'Clôture',
  ];
  @override
  Widget build(BuildContext context) => FpCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Parcours guidé', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (var i = 0; i < labels.length; i++)
              Chip(
                avatar: CircleAvatar(child: Text('${i + 1}')),
                label: Text(labels[i]),
              ),
          ],
        ),
      ],
    ),
  );
}

class _Todo extends StatelessWidget {
  const _Todo(this.snapshot);
  final MonthlyCloseSnapshot snapshot;
  @override
  Widget build(BuildContext context) {
    final active = snapshot.issues.where((issue) => issue.count > 0);
    return FpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'À faire financier',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (active.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: AppSpacing.xs),
              child: SecondaryInfoText('Aucune anomalie actionnable détectée.'),
            ),
          for (final issue in active)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                issue.severity == CloseIssueSeverity.blocker
                    ? Icons.block
                    : Icons.warning_amber,
                color: issue.severity == CloseIssueSeverity.blocker
                    ? AppColors.danger
                    : AppColors.warning,
              ),
              title: Text(issue.label),
              subtitle: Text(
                '${issue.count} élément(s) • ${issue.destination}',
              ),
              trailing: const Icon(Icons.chevron_right),
            ),
        ],
      ),
    );
  }
}

class _Regularization extends StatelessWidget {
  const _Regularization();
  @override
  Widget build(BuildContext context) => const FpCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Régularisation de fin de mois'),
        SizedBox(height: AppSpacing.xs),
        SecondaryInfoText(
          'Les cibles compte × enveloppe proposent les transferts nécessaires. Rien n’est exécuté automatiquement.',
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.account_tree_outlined),
          title: Text('Membre → compte → enveloppe'),
          subtitle: Text(
            'Soldes issus du Grand Ledger et du journal des enveloppes.',
          ),
        ),
      ],
    ),
  );
}

class _CloseAction extends ConsumerWidget {
  const _CloseAction(this.snapshot);
  final MonthlyCloseSnapshot snapshot;
  @override
  Widget build(BuildContext context, WidgetRef ref) => FpCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Contrôle final', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        Text(
          snapshot.blockers > 0
              ? 'Clôture impossible tant que les conditions bloquantes subsistent.'
              : snapshot.warnings > 0
              ? 'Clôture possible par un OWNER avec motif de dérogation.'
              : 'Tous les contrôles obligatoires sont satisfaits.',
        ),
        const SizedBox(height: AppSpacing.sm),
        FilledButton.icon(
          key: const Key('close-month-button'),
          onPressed: snapshot.blockers > 0
              ? null
              : () => _confirm(context, ref),
          icon: const Icon(Icons.lock_outline),
          label: const Text('Clôturer le mois'),
        ),
      ],
    ),
  );

  Future<void> _confirm(BuildContext context, WidgetRef ref) async {
    final reason = TextEditingController();
    final override = snapshot.warnings > 0;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          override ? 'Dérogation de clôture' : 'Confirmer la clôture',
        ),
        content: override
            ? TextField(
                key: const Key('close-override-reason'),
                controller: reason,
                decoration: const InputDecoration(
                  labelText: 'Motif obligatoire',
                ),
              )
            : const Text(
                'La clôture sera historisée et une réouverture exigera un motif.',
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              !override || reason.text.trim().isNotEmpty,
            ),
            child: const Text('Confirmer'),
          ),
        ],
      ),
    );
    if (accepted != true) return;
    await ref
        .read(monthlyCloseGatewayProvider)
        .close(
          snapshot.month,
          overrideWarnings: override,
          reason: reason.text.trim(),
        );
    ref.invalidate(monthlyCloseProvider);
  }
}
