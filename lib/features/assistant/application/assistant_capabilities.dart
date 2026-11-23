import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../organization/application/daily_life_provider.dart';
import '../domain/assistant_contract.dart';
import '../domain/conversation_contract.dart';
import 'assistant_providers.dart';

/// A registry of composable tools, not a closed intent list. The planner may
/// select zero, one, or many capabilities for any free-form question.
class CanonicalAssistantCapabilityExecutor
    implements AssistantCapabilityExecutor {
  const CanonicalAssistantCapabilityExecutor(this.ref);

  final Ref ref;

  static const _mapping = <String, AssistantUseCase>{
    'budget.summary': AssistantUseCase.budget,
    'month.summary': AssistantUseCase.monthlySummary,
    'alerts.summary': AssistantUseCase.anomalies,
    'priorities.summary': AssistantUseCase.priorities,
    'organization.tasks': AssistantUseCase.organization,
    'shopping.availability': AssistantUseCase.shopping,
    'wealth.explanation': AssistantUseCase.wealth,
    'product.help': AssistantUseCase.productHelp,
  };

  @override
  List<AssistantCapabilityDescriptor> get descriptors => const [
    AssistantCapabilityDescriptor(
      id: 'budget.summary',
      description:
          'Canonical authorized budget remaining and budget tension summary.',
      operationLevel: AssistantOperationLevel.read,
      semanticScope:
          'Prepared global household monthly budget remainder only. Excludes a specific envelope or category, personal-only spending scope, cash availability and purchase affordability.',
    ),
    AssistantCapabilityDescriptor(
      id: 'month.summary',
      description:
          'Authorized monthly dashboard summary, goals and hidden-data marker.',
      operationLevel: AssistantOperationLevel.read,
      semanticScope:
          'Global authorized household month overview, not a specific account, envelope, member or affordability answer.',
      allowsImplicitGlobalResolution: true,
    ),
    AssistantCapabilityDescriptor(
      id: 'alerts.summary',
      description: 'Count of authorized alerts and anomalies.',
      operationLevel: AssistantOperationLevel.read,
      semanticScope: 'Authorized alerts and anomalies only.',
    ),
    AssistantCapabilityDescriptor(
      id: 'priorities.summary',
      description: 'Authorized current household priority summary.',
      operationLevel: AssistantOperationLevel.read,
      semanticScope: 'Current authorized household priorities only.',
    ),
    AssistantCapabilityDescriptor(
      id: 'organization.tasks',
      description: 'Authorized open household task count.',
      operationLevel: AssistantOperationLevel.read,
      semanticScope: 'Open household organization tasks only.',
    ),
    AssistantCapabilityDescriptor(
      id: 'shopping.availability',
      description:
          'Bounded canonical purchase availability without exposing a balance.',
      operationLevel: AssistantOperationLevel.recommend,
      semanticScope:
          'Affordability of a contemplated purchase from bounded authorized availability. Distinct from a budget remainder or an account balance.',
    ),
    AssistantCapabilityDescriptor(
      id: 'wealth.explanation',
      description:
          'Explains canonical wealth results; does not recalculate wealth.',
      operationLevel: AssistantOperationLevel.read,
      semanticScope: 'Canonical wealth explanation only.',
    ),
    AssistantCapabilityDescriptor(
      id: 'cycle.authorized_projection',
      description:
          'Only Cycle dates and phases already shared with the current user, plus the owner own forecast when already authorized.',
      operationLevel: AssistantOperationLevel.read,
      semanticScope: 'Authorized Cycle dates and phases only.',
    ),
    AssistantCapabilityDescriptor(
      id: 'product.help',
      description: 'Local product navigation and workflow help.',
      operationLevel: AssistantOperationLevel.read,
      semanticScope: 'Product help and navigation only.',
    ),
  ];

  @override
  Future<List<AuthorizedCapabilityResult>> execute(
    Set<String> capabilityIds,
  ) async {
    final knownIds = descriptors.map((item) => item.id).toSet();
    final requested = capabilityIds.intersection(knownIds);
    final results = <AuthorizedCapabilityResult>[];
    for (final capabilityId in requested) {
      if (capabilityId == 'cycle.authorized_projection') {
        results.add(await _cycleProjection());
        continue;
      }
      final useCase = _mapping[capabilityId];
      if (useCase == null) continue;
      final context = await ref
          .read(assistantContextBuilderProvider)
          .build(useCase);
      final unavailableReason =
          capabilityId == 'budget.summary' &&
              !context.visibleFacts.containsKey('budget_remaining_minor')
          ? 'budget_not_prepared_or_unavailable'
          : null;
      results.add(
        AuthorizedCapabilityResult(
          capabilityId: capabilityId,
          generatedAt: context.generatedAt,
          facts: {
            ...context.visibleFacts,
            ...context.flags,
            'availability': unavailableReason == null
                ? 'available'
                : 'unavailable',
            if (context.flags['has_hidden_financial_data'] == true)
              'privacy_notice': 'hidden_financial_data_excluded',
          },
          sourceCategories: context.sourceCategories,
          unavailableReason: unavailableReason,
        ),
      );
    }
    return results;
  }

  Future<AuthorizedCapabilityResult> _cycleProjection() async {
    final now = DateTime.now().toUtc();
    final sharedRows = await ref.read(cycleEventsProvider.future);
    final ownForecast = ref.read(ownCycleForecastProvider).valueOrNull;
    final upcoming = sharedRows
        .where((row) {
          final raw = row['ends_on'] ?? row['starts_on'];
          final date = raw == null ? null : DateTime.tryParse('$raw');
          return date == null ||
              !date.isBefore(DateTime(now.year, now.month, now.day));
        })
        .take(3)
        .map(
          (row) => <String, Object?>{
            'starts_on': row['starts_on'],
            'ends_on': row['ends_on'],
            'phase': row['phase'],
          },
        )
        .toList(growable: false);
    return AuthorizedCapabilityResult(
      capabilityId: 'cycle.authorized_projection',
      generatedAt: now,
      facts: {
        'authorized_shared_events': upcoming,
        if (ownForecast != null && ownForecast.hasEstimate) ...{
          'own_next_period_earliest': ownForecast.nextPeriodFrom
              ?.toIso8601String(),
          'own_next_period_latest': ownForecast.nextPeriodTo?.toIso8601String(),
          'own_forecast_confidence': ownForecast.confidence.name,
        },
      },
      sourceCategories: const {'authorized_cycle_dates_phases'},
    );
  }
}

final assistantCapabilityExecutorProvider =
    Provider<AssistantCapabilityExecutor>(
      (ref) => CanonicalAssistantCapabilityExecutor(ref),
    );
