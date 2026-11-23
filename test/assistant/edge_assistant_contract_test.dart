import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File(
    'supabase/functions/assistant-conversation/index.ts',
  ).readAsStringSync();
  final realtimeSource = File(
    'lib/features/portability/application/household_realtime_provider.dart',
  ).readAsStringSync();
  final authorizationSource = File(
    'lib/features/assistant/application/assistant_authorization_revision.dart',
  ).readAsStringSync();
  final capabilitySource = File(
    'lib/features/assistant/application/assistant_capabilities.dart',
  ).readAsStringSync();

  test('edge assistant authenticates caller and preserves RLS membership', () {
    expect(source, contains("client.auth.getUser"));
    expect(source, contains(".from('household_members')"));
    expect(source, contains(".eq('user_id', user.id)"));
    expect(source, isNot(contains('SERVICE_ROLE_KEY')));
  });

  test('provider credentials are server-only and runtime configurable', () {
    expect(source, contains("Deno.env.get('AI_BASE_URL')"));
    expect(source, contains("Deno.env.get('AI_API_KEY')"));
    expect(source, contains("Deno.env.get('AI_MODEL')"));
    expect(source, isNot(contains('sk-')));
  });

  test('global routing is sandbox-only until the production privacy gate', () {
    expect(source, contains('certifiedSandboxProjectRef'));
    expect(source, contains('productionAiGateAllows'));
    expect(source, contains('AI_PROD_DATA_RESIDENCY_PRIVACY_APPROVED'));
    expect(
      source,
      contains('ai_prod_data_residency_privacy_decision_required'),
    );
  });

  test('OpenAI-compatible free routers tolerate plain and fenced JSON', () {
    expect(source, isNot(contains('response_format')));
    expect(source, contains("replace(/^```(?:json)?\\s*/i, '')"));
    expect(source, contains('provider_empty_envelope'));
    expect(source, contains('provider_timeout'));
    expect(source, contains('for (let attempt = 1; attempt <= 2; attempt++)'));
    expect(source, isNot(contains('provider_gate')));
    expect(source, isNot(contains('AI_PROVIDER_GATE_TOKEN')));
    expect(source, isNot(contains('assistant-provider-structure')));
  });

  test('provider failures are classified without exposing raw details', () {
    for (final marker in const [
      'empty_content',
      'timeout',
      'rate_limited',
      'server_error',
      'invalid_json',
      'invalid_envelope',
      'partial_response',
      'model_unavailable',
      'network',
    ]) {
      expect(source, contains("'$marker'"));
    }
    expect(source, contains("failurePhase = phase === 'respond'"));
    expect(source, contains("phase: failurePhase"));
    expect(source, contains('category: publicProviderCategory(error)'));
    expect(source, contains("new Error('provider_partial_response')"));
    expect(source, contains("new Error('provider_network')"));
  });

  test('planner is composable rather than a closed intent switch', () {
    expect(source, contains('This is NOT a closed intent classifier'));
    expect(
      source,
      contains('select zero, one or more composable capabilities'),
    );
    expect(source, isNot(contains('CAN_BUY_CAR')));
    expect(
      source,
      contains('select zero, one or more composable capabilities'),
    );
    expect(source, contains('needs_clarification'));
    expect(
      source,
      contains('must never become a phrase, keyword or intent whitelist'),
    );
    expect(source, isNot(contains("question.includes(")));
  });

  test('planner resolves semantic scope without a phrase whitelist', () {
    expect(source, contains('semantic_scope'));
    expect(source, contains('allows_implicit_global_resolution'));
    expect(source, contains('scope_basis'));
    expect(source, contains('scope_evidence'));
    expect(source, contains('canonical_global_aggregate'));
    expect(source, contains('clarification_required'));
    expect(source, contains('Availability of a capability is never evidence'));
    expect(source, contains('capability_ids: mustClarify ? []'));
    expect(source, isNot(contains("question.includes('budget')")));
    expect(source, isNot(contains("question.includes('spend')")));
  });

  test('response contract blocks invention and privacy reconstruction', () {
    expect(source, contains('Never invent, estimate, reconstruct'));
    expect(source, contains('do not infer it by totals, deltas, comparisons'));
    expect(source, contains('A private account is absent'));
    expect(source, contains('Do not claim to have executed an action'));
    expect(source, contains('distinct from numeric zero'));
    expect(source, contains('canonical currency_code'));
    expect(source, contains('Never introduce a number absent'));
    expect(source, contains('Navigation is not an action proposal'));
  });

  test('raw prompts and financial context are not logged', () {
    expect(source, contains('Never log the question'));
    expect(source, isNot(contains('console.log(question')));
    expect(source, isNot(contains('console.log(body')));
  });

  test('sensitive realtime changes revoke retained assistant context', () {
    expect(realtimeSource, contains('invalidateAssistantAuthorization'));
    expect(realtimeSource, contains('account_privacy_settings'));
    expect(realtimeSource, contains('member_cycle_events'));
    expect(
      authorizationSource,
      contains('assistantAuthorizationRevisionProvider.notifier'),
    );
  });

  test('Cycle capability exposes only authorized dates and phases', () {
    expect(capabilitySource, contains("'starts_on': row['starts_on']"));
    expect(capabilitySource, contains("'ends_on': row['ends_on']"));
    expect(capabilitySource, contains("'phase': row['phase']"));
    expect(capabilitySource, isNot(contains("'symptoms': row")));
    expect(capabilitySource, isNot(contains("'notes': row")));
    expect(capabilitySource, isNot(contains("'flow': row")));
    expect(capabilitySource, isNot(contains("'libido': row")));
  });
}
