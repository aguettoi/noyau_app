import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_locale.dart';
import '../../../core/theme/app_design_system.dart';
import '../application/assistant_providers.dart';
import '../domain/assistant_contract.dart';
import '../domain/conversation_contract.dart';
import 'assistant_locale.dart';

class AssistantPage extends ConsumerStatefulWidget {
  const AssistantPage({super.key, this.onOpenBudget, this.onOpenPriorities});
  final VoidCallback? onOpenBudget;
  final VoidCallback? onOpenPriorities;

  @override
  ConsumerState<AssistantPage> createState() => _AssistantPageState();
}

class _AssistantPageState extends ConsumerState<AssistantPage> {
  final _question = TextEditingController();
  final _scroll = ScrollController();
  var _fallbackUseCase = AssistantUseCase.budget;

  @override
  void dispose() {
    _question.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(appLocaleProvider);
    final words = AssistantWords(language);
    final generativeEnabled = ref.watch(assistantGenerativeEnabledProvider);
    final conversation = ref.watch(assistantConversationProvider);
    final fallback = ref.watch(assistantResponseProvider(_fallbackUseCase));
    ref.listen(assistantConversationProvider, (_, next) {
      if (next.messages.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) {
            _scroll.animateTo(
              _scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            );
          }
        });
      }
    });
    return Scaffold(
      appBar: AppBar(
        title: Text(words.text('assistant.title')),
        actions: generativeEnabled
            ? [
                IconButton(
                  tooltip: words.text('assistant.clear'),
                  onPressed: conversation.messages.isEmpty
                      ? null
                      : () => ref
                            .read(assistantConversationProvider.notifier)
                            .clear(),
                  icon: const Icon(Icons.delete_outline),
                ),
              ]
            : null,
      ),
      body: generativeEnabled
          ? FocusTraversalGroup(
              policy: ReadingOrderTraversalPolicy(),
              child: Column(
                children: [
                  Expanded(
                    child: ListView(
                      controller: _scroll,
                      padding: AppSpacing.page,
                      children: [
                        Semantics(
                          header: true,
                          child: Text(words.text('assistant.subtitle')),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        if (conversation.messages.isEmpty)
                          _ConversationWelcome(words: words),
                        for (final message in conversation.messages)
                          _MessageBubble(message: message),
                        for (final navigation in conversation.navigations)
                          _ConversationNavigationLink(
                            navigation: navigation,
                            words: words,
                            onOpen: () => _openNavigation(navigation.target),
                          ),
                        for (final proposal in conversation.proposals)
                          _ConversationProposalCard(
                            proposal: proposal,
                            words: words,
                            onReject: () => ref
                                .read(assistantConversationProvider.notifier)
                                .dismissProposal(proposal.id),
                            onConfirm: () => _confirmProposal(proposal),
                          ),
                        if (conversation.isSending)
                          Semantics(
                            liveRegion: true,
                            label: words.text('assistant.loading'),
                            child: const Padding(
                              padding: EdgeInsets.all(AppSpacing.md),
                              child: LinearProgressIndicator(),
                            ),
                          ),
                        if (conversation.lastStatus case final status?
                            when status != AssistantConversationStatus.ready)
                          _FallbackPanel(
                            status: status,
                            words: words,
                            useCase: _fallbackUseCase,
                            onUseCaseChanged: (value) =>
                                setState(() => _fallbackUseCase = value),
                            response: fallback,
                          ),
                      ],
                    ),
                  ),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: AppSpacing.card,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: TextField(
                              key: const ValueKey('assistant-question-field'),
                              controller: _question,
                              minLines: 1,
                              maxLines: 5,
                              textInputAction: TextInputAction.send,
                              onSubmitted: (_) => _send(language),
                              decoration: InputDecoration(
                                labelText: words.text('assistant.question'),
                                hintText: words.text('assistant.question_hint'),
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          IconButton.filled(
                            key: const ValueKey('assistant-send'),
                            tooltip: words.text('assistant.send'),
                            onPressed: conversation.isSending
                                ? null
                                : () => _send(language),
                            icon: const Icon(Icons.send),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            )
          : FocusTraversalGroup(
              policy: ReadingOrderTraversalPolicy(),
              child: ListView(
                padding: AppSpacing.page,
                children: [
                  Semantics(
                    header: true,
                    child: Text(words.text('assistant.deterministic_title')),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(words.text('assistant.deterministic_description')),
                  const SizedBox(height: AppSpacing.md),
                  _FallbackPanel(
                    status: AssistantConversationStatus.providerUnavailable,
                    words: words,
                    useCase: _fallbackUseCase,
                    onUseCaseChanged: (value) =>
                        setState(() => _fallbackUseCase = value),
                    response: fallback,
                    showProviderStatus: false,
                  ),
                ],
              ),
            ),
    );
  }

  Future<void> _send(AppLanguage language) async {
    final value = _question.text;
    if (value.trim().isEmpty) return;
    _question.clear();
    await ref
        .read(assistantConversationProvider.notifier)
        .send(value, uiLocale: language.storageCode);
  }

  void _confirmProposal(AssistantProposal proposal) {
    if (!DateTime.now().toUtc().isBefore(proposal.expiresAt)) {
      ref
          .read(assistantConversationProvider.notifier)
          .dismissProposal(proposal.id);
      return;
    }
    switch (proposal.parameters['target']) {
      case 'budget':
        widget.onOpenBudget?.call();
      case 'priorities':
        widget.onOpenPriorities?.call();
      case 'help':
        // Help is already reachable from the containing Plus shell.
        break;
    }
    ref
        .read(assistantConversationProvider.notifier)
        .dismissProposal(proposal.id);
  }

  void _openNavigation(String target) {
    switch (target) {
      case 'budget':
        widget.onOpenBudget?.call();
      case 'priorities':
        widget.onOpenPriorities?.call();
      case 'help':
        break;
    }
  }
}

class _ConversationNavigationLink extends StatelessWidget {
  const _ConversationNavigationLink({
    required this.navigation,
    required this.words,
    required this.onOpen,
  });

  final AssistantNavigationLink navigation;
  final AssistantWords words;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: TextButton.icon(
      key: ValueKey('assistant-navigation-${navigation.target}'),
      onPressed: onOpen,
      icon: const Icon(Icons.arrow_forward),
      label: Text(words.text(navigation.labelKey)),
    ),
  );
}

class _ConversationWelcome extends StatelessWidget {
  const _ConversationWelcome({required this.words});
  final AssistantWords words;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: AppSpacing.card,
      child: Text(words.text('assistant.conversation_welcome')),
    ),
  );
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});
  final AssistantConversationMessage message;
  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    return Semantics(
      liveRegion: !isUser,
      label: message.content,
      child: Align(
        alignment: isUser
            ? AlignmentDirectional.centerEnd
            : AlignmentDirectional.centerStart,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Card(
            color: isUser
                ? Theme.of(context).colorScheme.primaryContainer
                : null,
            child: Padding(
              padding: AppSpacing.card,
              child: SelectableText(message.content),
            ),
          ),
        ),
      ),
    );
  }
}

class _ConversationProposalCard extends StatelessWidget {
  const _ConversationProposalCard({
    required this.proposal,
    required this.words,
    required this.onReject,
    required this.onConfirm,
  });
  final AssistantProposal proposal;
  final AssistantWords words;
  final VoidCallback onReject;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: AppSpacing.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(words.text('assistant.proposal')),
          Text(words.text(proposal.objectiveKey)),
          Text(words.text(proposal.justificationKey)),
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
          ),
        ],
      ),
    ),
  );
}

class _FallbackPanel extends StatelessWidget {
  const _FallbackPanel({
    required this.status,
    required this.words,
    required this.useCase,
    required this.onUseCaseChanged,
    required this.response,
    this.showProviderStatus = true,
  });
  final AssistantConversationStatus status;
  final AssistantWords words;
  final AssistantUseCase useCase;
  final ValueChanged<AssistantUseCase> onUseCaseChanged;
  final AsyncValue<AssistantResponse> response;
  final bool showProviderStatus;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: AppSpacing.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showProviderStatus) ...[
            Text(words.text('assistant.status.${status.name}')),
            Text(words.text('assistant.fallback_notice')),
            const SizedBox(height: AppSpacing.sm),
          ],
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final item in AssistantUseCase.values)
                ChoiceChip(
                  label: Text(words.text('assistant.${item.name}')),
                  selected: useCase == item,
                  onSelected: (_) => onUseCaseChanged(item),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          response.when(
            loading: () => const LinearProgressIndicator(),
            error: (_, _) => Text(words.text('assistant.error')),
            data: (answer) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final statement in answer.statements)
                  ListTile(
                    leading: Icon(_statementIcon(statement.kind)),
                    title: Text(
                      words.text('assistant.kind.${statement.kind.name}'),
                    ),
                    subtitle: Text(
                      words.format(statement.messageKey, statement.arguments),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

IconData _statementIcon(AssistantStatementKind kind) => switch (kind) {
  AssistantStatementKind.fact => Icons.fact_check_outlined,
  AssistantStatementKind.rule => Icons.calculate_outlined,
  AssistantStatementKind.suggestion => Icons.lightbulb_outline,
  AssistantStatementKind.uncertainty => Icons.help_outline,
};
