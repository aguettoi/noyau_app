import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_locale.dart';
import '../../../core/theme/app_design_system.dart';
import '../application/assistant_providers.dart';
import '../domain/assistant_contract.dart';
import 'assistant_locale.dart';

class AssistantPage extends ConsumerStatefulWidget {
  const AssistantPage({super.key, this.onOpenBudget, this.onOpenPriorities});
  final VoidCallback? onOpenBudget;
  final VoidCallback? onOpenPriorities;

  @override
  ConsumerState<AssistantPage> createState() => _AssistantPageState();
}

class _AssistantPageState extends ConsumerState<AssistantPage> {
  var _useCase = AssistantUseCase.budget;
  final _proposalStates = <String, AssistantActionState>{};

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(appLocaleProvider);
    final words = AssistantWords(language);
    final response = ref.watch(assistantResponseProvider(_useCase));
    return Scaffold(
      appBar: AppBar(title: Text(words.text('assistant.title'))),
      body: FocusTraversalGroup(
        policy: ReadingOrderTraversalPolicy(),
        child: ListView(
          padding: AppSpacing.page,
          children: [
            Semantics(
              header: true,
              child: Text(words.text('assistant.subtitle')),
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final useCase in AssistantUseCase.values)
                  ChoiceChip(
                    label: Text(words.text('assistant.${useCase.name}')),
                    selected: _useCase == useCase,
                    onSelected: (_) => setState(() => _useCase = useCase),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            response.when(
              loading: () => Semantics(
                liveRegion: true,
                label: words.text('assistant.loading'),
                child: const Center(child: CircularProgressIndicator()),
              ),
              error: (_, _) => Text(words.text('assistant.error')),
              data: (answer) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final statement in answer.statements)
                    Card(
                      child: ListTile(
                        leading: Icon(_statementIcon(statement.kind)),
                        title: Text(
                          words.text('assistant.kind.${statement.kind.name}'),
                        ),
                        subtitle: Text(
                          words.format(
                            statement.messageKey,
                            statement.arguments,
                          ),
                        ),
                      ),
                    ),
                  for (final proposal in answer.proposals)
                    _ProposalCard(
                      proposal: proposal,
                      state: _proposalStates[proposal.id] ?? proposal.state,
                      words: words,
                      onReject: () => setState(
                        () => _proposalStates[proposal.id] =
                            AssistantActionState.rejected,
                      ),
                      onConfirm: () => _confirm(proposal),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirm(AssistantProposal proposal) {
    if (DateTime.now().toUtc().isAfter(proposal.expiresAt)) {
      setState(
        () => _proposalStates[proposal.id] = AssistantActionState.expired,
      );
      return;
    }
    setState(
      () => _proposalStates[proposal.id] = AssistantActionState.confirmed,
    );
    switch (proposal.parameters['target']) {
      case 'budget':
        widget.onOpenBudget?.call();
      case 'priorities':
        widget.onOpenPriorities?.call();
    }
    if (mounted) {
      setState(
        () => _proposalStates[proposal.id] = AssistantActionState.executed,
      );
    }
  }

  IconData _statementIcon(AssistantStatementKind kind) => switch (kind) {
    AssistantStatementKind.fact => Icons.fact_check_outlined,
    AssistantStatementKind.rule => Icons.calculate_outlined,
    AssistantStatementKind.suggestion => Icons.lightbulb_outline,
    AssistantStatementKind.uncertainty => Icons.help_outline,
  };
}

class _ProposalCard extends StatelessWidget {
  const _ProposalCard({
    required this.proposal,
    required this.state,
    required this.words,
    required this.onConfirm,
    required this.onReject,
  });
  final AssistantProposal proposal;
  final AssistantActionState state;
  final AssistantWords words;
  final VoidCallback onConfirm;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: AppSpacing.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(words.text('assistant.proposal')),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(words.text(proposal.objectiveKey)),
          Text(words.text(proposal.justificationKey)),
          if (state == AssistantActionState.proposed)
            Wrap(
              spacing: AppSpacing.xs,
              children: [
                OutlinedButton(
                  onPressed: onReject,
                  child: Text(words.text('assistant.reject')),
                ),
                FilledButton(
                  onPressed: onConfirm,
                  child: Text(words.text('assistant.confirm')),
                ),
              ],
            )
          else
            Text(_stateLabel(words.language, state)),
        ],
      ),
    ),
  );
}

String _stateLabel(AppLanguage language, AssistantActionState state) {
  const labels = {
    AppLanguage.french: [
      'Proposée',
      'Confirmée',
      'Refusée',
      'Expirée',
      'Exécutée',
      'Échec',
    ],
    AppLanguage.english: [
      'Proposed',
      'Confirmed',
      'Rejected',
      'Expired',
      'Executed',
      'Failed',
    ],
    AppLanguage.arabic: ['مقترح', 'مؤكد', 'مرفوض', 'منتهي', 'منفذ', 'فشل'],
    AppLanguage.darija: [
      'مقترحة',
      'تأكدات',
      'ترفضات',
      'سالات',
      'تدارت',
      'ما نجحاتش',
    ],
  };
  return labels[language]![state.index];
}
