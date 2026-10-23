import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/money/money.dart';
import '../../finance/application/providers/active_household_provider.dart';
import '../../finance/application/providers/supabase_client_provider.dart';
import '../domain/recurring_finance.dart';

abstract interface class RecurringFinanceGateway {
  Future<List<RecurringFinancialIntention>> fetchIntentions(String householdId);
  Future<List<ExpectedFinancialOccurrence>> fetchOccurrences(
    String householdId,
  );
  Future<List<ActualFinancialCandidate>> fetchCandidates(
    String householdId,
    DateTime from,
    DateTime through,
  );
  Future<String> save(String householdId, Map<String, Object?> values);
  Future<void> setStatus(String id, RecurringStatus status);
  Future<void> materialize(String id, DateTime through);
  Future<void> ignoreOccurrence(String occurrenceId, String reason);
  Future<void> decideMatch({
    required String occurrenceId,
    required String eventId,
    required Money amount,
    required MatchDecision decision,
    double? score,
    List<String> reasons,
  });
}

class SupabaseRecurringFinanceGateway implements RecurringFinanceGateway {
  SupabaseRecurringFinanceGateway(this.client);
  final SupabaseClient client;
  @override
  Future<List<RecurringFinancialIntention>> fetchIntentions(
    String householdId,
  ) async {
    final rows = await client
        .from('recurring_financial_intentions')
        .select()
        .eq('household_id', householdId)
        .order('next_occurrence_on', ascending: true);
    return [
      for (final raw in rows as List<dynamic>)
        _intention(Map<String, Object?>.from(raw as Map)),
    ];
  }

  @override
  Future<List<ExpectedFinancialOccurrence>> fetchOccurrences(
    String householdId,
  ) async {
    final rows = await client
        .from('expected_financial_occurrence_overview')
        .select()
        .eq('household_id', householdId)
        .order('expected_on', ascending: true)
        .limit(250);
    return [
      for (final raw in rows as List<dynamic>)
        _occurrence(Map<String, Object?>.from(raw as Map)),
    ];
  }

  @override
  Future<List<ActualFinancialCandidate>> fetchCandidates(
    String householdId,
    DateTime from,
    DateTime through,
  ) async {
    final rows = await client
        .from('recurring_financial_actual_candidates')
        .select()
        .eq('household_id', householdId)
        .gte('occurred_at', from.toUtc().toIso8601String())
        .lte('occurred_at', through.toUtc().toIso8601String())
        .order('occurred_at', ascending: false)
        .limit(500);
    return [
      for (final raw in rows as List<dynamic>)
        _candidate(Map<String, Object?>.from(raw as Map)),
    ];
  }

  @override
  Future<String> save(String householdId, Map<String, Object?> values) async =>
      (await client.rpc(
            'save_recurring_financial_intention',
            params: {
              'p_household_id': householdId,
              ...values,
              'p_idempotency_key': _uuid(),
            },
          ))
          as String;
  @override
  Future<void> setStatus(String id, RecurringStatus status) => client.rpc(
    'set_recurring_financial_intention_status',
    params: {
      'p_intention_id': id,
      'p_status': status.name,
      'p_idempotency_key': _uuid(),
    },
  );
  @override
  Future<void> materialize(String id, DateTime through) => client.rpc(
    'materialize_recurring_financial_occurrences',
    params: {'p_intention_id': id, 'p_through': _date(through)},
  );
  @override
  Future<void> ignoreOccurrence(String occurrenceId, String reason) =>
      client.rpc(
        'ignore_expected_financial_occurrence',
        params: {
          'p_occurrence_id': occurrenceId,
          'p_reason': reason,
          'p_idempotency_key': _uuid(),
        },
      );
  @override
  Future<void> decideMatch({
    required String occurrenceId,
    required String eventId,
    required Money amount,
    required MatchDecision decision,
    double? score,
    List<String> reasons = const [],
  }) => client.rpc(
    'record_expected_financial_match',
    params: {
      'p_occurrence_id': occurrenceId,
      'p_financial_event_id': eventId,
      'p_matched_amount': amount.dirhams,
      'p_decision': decision.name,
      'p_score': score,
      'p_reasons': reasons,
      'p_idempotency_key': _uuid(),
    },
  );
}

final recurringFinanceGatewayProvider = Provider<RecurringFinanceGateway>(
  (ref) => SupabaseRecurringFinanceGateway(ref.watch(supabaseClientProvider)),
);
final recurringIntentionsProvider =
    FutureProvider<List<RecurringFinancialIntention>>((ref) async {
      final h = await ref.watch(activeHouseholdProvider.future);
      if (h.householdId == null) return const [];
      return ref
          .watch(recurringFinanceGatewayProvider)
          .fetchIntentions(h.householdId!);
    });
final expectedOccurrencesProvider =
    FutureProvider<List<ExpectedFinancialOccurrence>>((ref) async {
      final h = await ref.watch(activeHouseholdProvider.future);
      if (h.householdId == null) return const [];
      return ref
          .watch(recurringFinanceGatewayProvider)
          .fetchOccurrences(h.householdId!);
    });
final actualRecurringCandidatesProvider =
    FutureProvider<List<ActualFinancialCandidate>>((ref) async {
      final h = await ref.watch(activeHouseholdProvider.future);
      if (h.householdId == null) return const [];
      final now = DateTime.now();
      return ref
          .watch(recurringFinanceGatewayProvider)
          .fetchCandidates(
            h.householdId!,
            now.subtract(const Duration(days: 400)),
            now.add(const Duration(days: 31)),
          );
    });
final recurringPatternSuggestionsProvider =
    FutureProvider<List<RecurringPatternSuggestion>>(
      (ref) async => detectRecurringPatterns(
        await ref.watch(actualRecurringCandidatesProvider.future),
      ),
    );
final recurringFinanceActionsProvider = Provider(
  (ref) => RecurringFinanceActions(ref),
);

class RecurringFinanceActions {
  RecurringFinanceActions(this.ref);
  final Ref ref;
  Future<void> create({
    required RecurringEconomicType type,
    required String label,
    required Money amount,
    required RecurringFrequency frequency,
    required DateTime startsOn,
    DateTime? endsOn,
    RecurringCertainty certainty = RecurringCertainty.certain,
    String? sourceAccountId,
    String? destinationAccountId,
    String? envelopeId,
    String? memberId,
  }) async {
    final h = await ref.read(activeHouseholdProvider.future);
    if (h.householdId == null) throw StateError('Aucun foyer actif.');
    final id = await ref
        .read(recurringFinanceGatewayProvider)
        .save(h.householdId!, {
          'p_intention_id': null,
          'p_economic_type': _snakeType(type),
          'p_label': label.trim(),
          'p_expected_amount': amount.dirhams,
          'p_currency_code': 'MAD',
          'p_frequency': frequency.name,
          'p_starts_on': _date(startsOn),
          'p_ends_on': endsOn == null ? null : _date(endsOn),
          'p_concerned_member_id': memberId,
          'p_source_account_id': sourceAccountId,
          'p_destination_account_id': destinationAccountId,
          'p_envelope_id': envelopeId,
          'p_certainty': certainty.name,
          'p_source_kind': 'manual',
          'p_source_id': null,
          'p_source_metadata': <String, Object?>{},
        });
    await ref
        .read(recurringFinanceGatewayProvider)
        .materialize(
          id,
          DateTime(startsOn.year, startsOn.month + 4, startsOn.day),
        );
    ref.invalidate(recurringIntentionsProvider);
    ref.invalidate(expectedOccurrencesProvider);
  }

  Future<void> update({
    required RecurringFinancialIntention current,
    required String label,
    required Money amount,
    required RecurringFrequency frequency,
    required RecurringCertainty certainty,
    required String? sourceAccountId,
    required String? destinationAccountId,
    required String? envelopeId,
    required String? memberId,
  }) async {
    final h = await ref.read(activeHouseholdProvider.future);
    if (h.householdId == null) throw StateError('Aucun foyer actif.');
    await ref.read(recurringFinanceGatewayProvider).save(h.householdId!, {
      'p_intention_id': current.id,
      'p_economic_type': _snakeType(current.type),
      'p_label': label.trim(),
      'p_expected_amount': amount.dirhams,
      'p_currency_code': current.currency,
      'p_frequency': frequency.name,
      'p_starts_on': _date(current.startsOn),
      'p_ends_on': current.endsOn == null ? null : _date(current.endsOn!),
      'p_concerned_member_id': memberId,
      'p_source_account_id': sourceAccountId,
      'p_destination_account_id': destinationAccountId,
      'p_envelope_id': envelopeId,
      'p_certainty': certainty.name,
      'p_source_kind': current.sourceKind,
      'p_source_id': null,
      'p_source_metadata': <String, Object?>{},
    });
    ref.invalidate(recurringIntentionsProvider);
    ref.invalidate(expectedOccurrencesProvider);
  }

  Future<void> status(String id, RecurringStatus status) async {
    await ref.read(recurringFinanceGatewayProvider).setStatus(id, status);
    ref.invalidate(recurringIntentionsProvider);
    ref.invalidate(expectedOccurrencesProvider);
  }

  Future<void> ignoreOccurrence(String id, String reason) async {
    await ref
        .read(recurringFinanceGatewayProvider)
        .ignoreOccurrence(id, reason.trim());
    ref.invalidate(expectedOccurrencesProvider);
  }

  Future<void> decideMatch(
    ExpectedFinancialOccurrence occurrence,
    ActualFinancialCandidate candidate,
    MatchDecision decision,
  ) async {
    final assessment = assessExpectedMatch(
      occurrence,
      candidate,
      const MatchingTolerance(),
    );
    if (!assessment.eligible && decision != MatchDecision.rejected) {
      throw StateError('Ce candidat est incompatible avec l’attente.');
    }
    final matched =
        candidate.amount.minorUnits > occurrence.remaining.minorUnits
        ? occurrence.remaining
        : candidate.amount;
    await ref
        .read(recurringFinanceGatewayProvider)
        .decideMatch(
          occurrenceId: occurrence.id,
          eventId: candidate.id,
          amount: matched,
          decision: decision,
          score: assessment.score,
          reasons: assessment.reasons,
        );
    ref.invalidate(expectedOccurrencesProvider);
  }
}

RecurringFinancialIntention _intention(Map<String, Object?> r) =>
    RecurringFinancialIntention(
      id: r['id']! as String,
      householdId: r['household_id']! as String,
      type: _type(r['economic_type']! as String),
      label: r['label']! as String,
      amount: Money.fromDirhams(r['expected_amount'] as num),
      currency: r['currency_code']! as String,
      frequency: RecurringFrequency.values.byName(r['frequency']! as String),
      startsOn: DateTime.parse(r['starts_on']! as String),
      nextOccurrenceOn: DateTime.parse(r['next_occurrence_on']! as String),
      endsOn: r['ends_on'] == null
          ? null
          : DateTime.parse(r['ends_on']! as String),
      memberId: r['concerned_member_id'] as String?,
      sourceAccountId: r['source_account_id'] as String?,
      destinationAccountId: r['destination_account_id'] as String?,
      envelopeId: r['envelope_id'] as String?,
      certainty: RecurringCertainty.values.byName(r['certainty']! as String),
      status: RecurringStatus.values.byName(r['status']! as String),
      sourceKind: r['source_kind']! as String,
    );
ExpectedFinancialOccurrence _occurrence(Map<String, Object?> r) =>
    ExpectedFinancialOccurrence(
      id: r['id']! as String,
      intentionId: r['intention_id']! as String,
      expectedOn: DateTime.parse(r['expected_on']! as String),
      type: _type(r['economic_type']! as String),
      label: r['label']! as String,
      expectedAmount: Money.fromDirhams(r['expected_amount'] as num),
      confirmedAmount: Money.fromDirhams(r['confirmed_amount'] as num),
      status: _occurrenceStatus(r['occurrence_status']! as String),
      sourceAccountId: r['source_account_id'] as String?,
      destinationAccountId: r['destination_account_id'] as String?,
      envelopeId: r['envelope_id'] as String?,
      memberId: r['concerned_member_id'] as String?,
    );
ActualFinancialCandidate _candidate(Map<String, Object?> r) =>
    ActualFinancialCandidate(
      id: r['financial_event_id']! as String,
      type: _type(r['economic_type']! as String),
      occurredAt: DateTime.parse(r['occurred_at']! as String),
      amount: Money.fromDirhams(r['amount'] as num),
      description: r['description']! as String,
      accountId: r['source_account_id'] as String?,
      destinationAccountId: r['destination_account_id'] as String?,
      envelopeId: r['envelope_id'] as String?,
      memberId: r['member_id'] as String?,
    );
RecurringEconomicType _type(String value) => switch (value) {
  'income' => RecurringEconomicType.income,
  'expense' => RecurringEconomicType.expense,
  _ => RecurringEconomicType.accountTransfer,
};
String _snakeType(RecurringEconomicType value) =>
    value == RecurringEconomicType.accountTransfer
    ? 'account_transfer'
    : value.name;
ExpectedOccurrenceStatus _occurrenceStatus(String value) => switch (value) {
  'partially_realized' => ExpectedOccurrenceStatus.partiallyRealized,
  'realized' => ExpectedOccurrenceStatus.realized,
  'ignored' => ExpectedOccurrenceStatus.ignored,
  'overdue' => ExpectedOccurrenceStatus.overdue,
  _ => ExpectedOccurrenceStatus.expected,
};
String _date(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
String _uuid() {
  final random = Random.secure(),
      b = List<int>.generate(16, (_) => random.nextInt(256));
  b[6] = (b[6] & 15) | 64;
  b[8] = (b[8] & 63) | 128;
  final h = b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}
