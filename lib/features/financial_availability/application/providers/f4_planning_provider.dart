import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../finance/application/providers/active_household_provider.dart';
import '../../../finance/application/providers/supabase_client_provider.dart';

enum ShoppingFundingStrategy {
  surplus,
  projectedBonus,
  savings,
  selectedEnvelope,
  combined,
}

extension ShoppingFundingStrategyLabel on ShoppingFundingStrategy {
  String get databaseValue => switch (this) {
    ShoppingFundingStrategy.projectedBonus => 'projected_bonus',
    ShoppingFundingStrategy.selectedEnvelope => 'selected_envelope',
    _ => name,
  };

  String get label => switch (this) {
    ShoppingFundingStrategy.surplus => 'Surplus budgétaire projeté',
    ShoppingFundingStrategy.projectedBonus => 'Prime projetée',
    ShoppingFundingStrategy.savings => 'Épargne réelle',
    ShoppingFundingStrategy.selectedEnvelope => 'Enveloppe choisie',
    ShoppingFundingStrategy.combined => 'Combinaison',
  };
}

enum PriorityDecision { buyNow, wait, fundProgressively }

extension PriorityDecisionLabel on PriorityDecision {
  String get databaseValue => switch (this) {
    PriorityDecision.buyNow => 'buy_now',
    PriorityDecision.fundProgressively => 'fund_progressively',
    PriorityDecision.wait => 'wait',
  };

  String get label => switch (this) {
    PriorityDecision.buyNow => 'Acheter maintenant',
    PriorityDecision.wait => 'Attendre',
    PriorityDecision.fundProgressively => 'Financer progressivement',
  };
}

class ShoppingFundingPlan {
  const ShoppingFundingPlan({
    required this.itemId,
    required this.strategy,
    this.plannedAmount,
    this.projectedBonusAmount,
    this.sourceEnvelopeId,
    this.scenarioId,
  });
  final String itemId;
  final ShoppingFundingStrategy strategy;
  final double? plannedAmount;
  final double? projectedBonusAmount;
  final String? sourceEnvelopeId;
  final String? scenarioId;
}

final shoppingFundingPlansProvider =
    FutureProvider<Map<String, ShoppingFundingPlan>>((ref) async {
      final household = await ref.watch(activeHouseholdProvider.future);
      final id = household.householdId;
      if (id == null) return const {};
      final rows = await ref
          .watch(supabaseClientProvider)
          .from('shopping_financing_plans')
          .select()
          .eq('household_id', id);
      return {
        for (final raw in rows)
          raw['shopping_item_id'] as String: ShoppingFundingPlan(
            itemId: raw['shopping_item_id'] as String,
            strategy: ShoppingFundingStrategy.values.firstWhere(
              (value) => value.databaseValue == raw['strategy'],
            ),
            plannedAmount: (raw['planned_amount'] as num?)?.toDouble(),
            projectedBonusAmount: (raw['projected_bonus_amount'] as num?)
                ?.toDouble(),
            sourceEnvelopeId: raw['source_envelope_id'] as String?,
            scenarioId: raw['scenario_id'] as String?,
          ),
      };
    });

Future<void> saveShoppingFundingPlan(
  WidgetRef ref, {
  required String itemId,
  required ShoppingFundingStrategy strategy,
  double? plannedAmount,
  double? projectedBonusAmount,
  String? sourceEnvelopeId,
  String? scenarioId,
}) async {
  final household = await ref.read(activeHouseholdProvider.future);
  await ref
      .read(supabaseClientProvider)
      .rpc(
        'set_shopping_financing_plan',
        params: {
          'p_household_id': household.householdId,
          'p_shopping_item_id': itemId,
          'p_strategy': strategy.databaseValue,
          'p_planned_amount': plannedAmount,
          'p_projected_bonus_amount': projectedBonusAmount,
          'p_source_envelope_id': sourceEnvelopeId,
          'p_scenario_id': scenarioId,
        },
      );
  ref.invalidate(shoppingFundingPlansProvider);
}

final priorityItemDecisionsProvider = FutureProvider<Map<String, String>>((
  ref,
) async {
  final household = await ref.watch(activeHouseholdProvider.future);
  final id = household.householdId;
  if (id == null) return const {};
  final rows = await ref
      .watch(supabaseClientProvider)
      .from('priority_item_decisions')
      .select('priority_plan_item_id, decision')
      .eq('household_id', id);
  return {
    for (final raw in rows)
      raw['priority_plan_item_id'] as String: raw['decision'] as String,
  };
});

Future<void> savePriorityDecision(
  WidgetRef ref, {
  required String itemId,
  required PriorityDecision decision,
}) async {
  final household = await ref.read(activeHouseholdProvider.future);
  await ref
      .read(supabaseClientProvider)
      .rpc(
        'set_priority_item_decision',
        params: {
          'p_household_id': household.householdId,
          'p_priority_plan_item_id': itemId,
          'p_decision': decision.databaseValue,
        },
      );
  ref.invalidate(priorityItemDecisionsProvider);
}
