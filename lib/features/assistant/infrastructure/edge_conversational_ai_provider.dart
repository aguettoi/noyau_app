import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/conversation_contract.dart';

abstract interface class AssistantFunctionGateway {
  Future<Map<String, Object?>> invoke(Map<String, Object?> body);
}

class SupabaseAssistantFunctionGateway implements AssistantFunctionGateway {
  const SupabaseAssistantFunctionGateway(this.client);

  final SupabaseClient client;

  @override
  Future<Map<String, Object?>> invoke(Map<String, Object?> body) async {
    final response = await client.functions.invoke(
      'assistant-conversation',
      body: body,
    );
    if (response.status < 200 || response.status >= 300) {
      final data = response.data;
      final details = data is Map ? Map<String, Object?>.from(data) : const {};
      throw AssistantProviderException(
        phase: _failurePhase(details['phase']),
        category: _failureCategory(details['category']),
      );
    }
    final data = response.data;
    if (data is! Map) throw const FormatException('Invalid assistant response');
    return Map<String, Object?>.from(data);
  }
}

class EdgeConversationalAIProvider implements ConversationalAIProvider {
  const EdgeConversationalAIProvider(this.gateway);

  final AssistantFunctionGateway gateway;

  @override
  String get providerId => 'server-managed';

  @override
  Future<AssistantConversationPlan> plan({
    required AssistantConversationRequest request,
    required List<AssistantCapabilityDescriptor> availableCapabilities,
  }) async {
    final json = await gateway.invoke({
      'phase': 'plan',
      'question': request.question,
      'ui_locale': request.uiLocale,
      'household_id': request.householdId,
      'history': _safeHistory(request),
      'capabilities': availableCapabilities
          .map((item) => item.toJson())
          .toList(),
    });
    final rawIds = json['capability_ids'];
    final ids = rawIds is List
        ? rawIds.whereType<String>().toSet()
        : const <String>{};
    return AssistantConversationPlan(
      language: (json['language'] as String?)?.trim().isNotEmpty == true
          ? json['language']! as String
          : request.uiLocale,
      capabilityIds: ids,
      operationLevel: _operationLevel(json['operation_level']),
      needsClarification: json['needs_clarification'] == true,
      clarificationQuestion: (json['clarification_question'] as String?)
          ?.trim(),
      scopeBasis: _scopeBasis(json['scope_basis']),
      scopeEvidence: (json['scope_evidence'] as String?)?.trim(),
    );
  }

  @override
  Future<AssistantConversationAnswer> respond({
    required AssistantConversationRequest request,
    required AssistantConversationPlan plan,
    required List<AuthorizedCapabilityResult> authorizedResults,
  }) async {
    final watch = Stopwatch()..start();
    final json = await gateway.invoke({
      'phase': 'respond',
      'question': request.question,
      'ui_locale': request.uiLocale,
      'household_id': request.householdId,
      'history': _safeHistory(request),
      'plan': {
        'language': plan.language,
        'capability_ids': plan.capabilityIds.toList()..sort(),
        'operation_level': plan.operationLevel.name,
      },
      'authorized_results': authorizedResults
          .map((item) => item.toJson())
          .toList(),
    });
    final sourceCategories = <String>{
      for (final result in authorizedResults) ...result.sourceCategories,
    };
    final text = (json['text'] as String?)?.trim() ?? '';
    if (text.isEmpty) {
      throw const AssistantProviderException(
        phase: AssistantFailurePhase.synthesis,
        category: AssistantProviderErrorCategory.emptyContent,
      );
    }
    _validateGeneratedFacts(text, authorizedResults);
    final navigations = _safeNavigations(
      json['navigations'] ?? json['proposals'],
    );
    final usage = json['usage'] is Map
        ? Map<String, Object?>.from(json['usage'] as Map)
        : const <String, Object?>{};
    return AssistantConversationAnswer(
      text: text,
      language: (json['language'] as String?) ?? plan.language,
      status: json['fallback'] == true
          ? AssistantConversationStatus.providerUnavailable
          : AssistantConversationStatus.ready,
      provider: (json['provider'] as String?) ?? providerId,
      model: (json['model'] as String?) ?? 'unknown',
      capabilityIds: plan.capabilityIds,
      sourceCategories: sourceCategories,
      operationLevel: plan.operationLevel,
      duration: Duration(
        milliseconds:
            (json['latency_ms'] as num?)?.toInt() ?? watch.elapsedMilliseconds,
      ),
      navigations: navigations,
      fallbackUsed: json['fallback'] == true,
      promptTokens: (usage['prompt_tokens'] as num?)?.toInt(),
      completionTokens: (usage['completion_tokens'] as num?)?.toInt(),
      totalTokens: (usage['total_tokens'] as num?)?.toInt(),
      estimatedCostMinor: (json['estimated_cost_minor'] as num?)?.toInt(),
    );
  }

  List<Map<String, Object?>> _safeHistory(
    AssistantConversationRequest request,
  ) {
    final userTurns = request.history
        .where((message) => message.role == 'user')
        .toList(growable: false);
    final start = userTurns.length > 12 ? userTurns.length - 12 : 0;
    return userTurns
        .skip(start)
        .map((message) => message.toJson())
        .toList(growable: false);
  }
}

List<AssistantNavigationLink> _safeNavigations(Object? raw) {
  if (raw is! List) return const [];
  const targets = {'budget', 'priorities', 'help'};
  return [
    for (final item in raw.whereType<Map>())
      if (item['type'] == 'navigate' && targets.contains(item['target']))
        AssistantNavigationLink(
          target: item['target'] as String,
          labelKey: 'assistant.action.open_${item['target']}',
        ),
  ];
}

void _validateGeneratedFacts(
  String text,
  List<AuthorizedCapabilityResult> results,
) {
  final authorizedNumbers = <num>{};
  final authorizedMonetaryNumbers = <num>{};
  final authorizedCurrencies = <String>{};
  final authorizedExactStrings = <String>{};
  var monetaryFactAvailable = false;

  void collect(Object? value, {String key = ''}) {
    if (value is Map) {
      for (final entry in value.entries) {
        collect(entry.value, key: '${entry.key}');
      }
      return;
    }
    if (value is List) {
      for (final item in value) {
        collect(item, key: key);
      }
      return;
    }
    final normalizedKey = key.toLowerCase();
    if (value is num) {
      authorizedNumbers.add(value);
      if (normalizedKey.endsWith('_minor')) {
        monetaryFactAvailable = true;
        authorizedNumbers.add(value / 100);
        authorizedMonetaryNumbers.addAll({value, value / 100});
      }
    }
    if (value is String &&
        (normalizedKey == 'currency' || normalizedKey == 'currency_code') &&
        RegExp(r'^[A-Z]{3}$').hasMatch(value)) {
      authorizedCurrencies.add(value);
    } else if (value is String && value.trim().length >= 3) {
      authorizedExactStrings.add(value.trim());
    }
  }

  for (final result in results) {
    collect(result.facts);
  }

  final unavailableWithoutMoney =
      !monetaryFactAvailable &&
      results.any(
        (result) =>
            result.unavailableReason != null ||
            result.facts['availability'] == 'unavailable' ||
            result.facts['availability'] == 'unauthorized',
      );

  final currencyClaims = RegExp(
    r'(?:[€$£¥₹₽₩₺₫₪₴₦₱₲₡₵]|\b[A-Z]{3}\b|\bDH\b)',
  ).allMatches(text).map((match) => match.group(0)!).toList();
  if (currencyClaims.any((claim) => !authorizedCurrencies.contains(claim))) {
    throw const FormatException('assistant.generated_currency_not_authorized');
  }

  var textWithoutExactFacts = text;
  for (final exact in authorizedExactStrings) {
    textWithoutExactFacts = textWithoutExactFacts.replaceAll(exact, '');
  }
  final numberMatches = RegExp(
    r'(?<![\p{L}\p{N}])[-+]?\d+(?:[.,]\d+)?',
    unicode: true,
  ).allMatches(textWithoutExactFacts);
  for (final match in numberMatches) {
    final value = num.tryParse(match.group(0)!.replaceAll(',', '.'));
    if (value == null) continue;
    if (!authorizedNumbers.any(
      (allowed) => (allowed - value).abs() < 0.000001,
    )) {
      throw const FormatException('assistant.generated_number_not_authorized');
    }
    final neighborhoodStart = match.start < 24 ? 0 : match.start - 24;
    final neighborhoodEnd = match.end + 24 > textWithoutExactFacts.length
        ? textWithoutExactFacts.length
        : match.end + 24;
    final neighborhood = textWithoutExactFacts.substring(
      neighborhoodStart,
      neighborhoodEnd,
    );
    final isMonetaryClaim = currencyClaims.any(neighborhood.contains);
    if (isMonetaryClaim &&
        !authorizedMonetaryNumbers.any(
          (allowed) => (allowed - value).abs() < 0.000001,
        )) {
      throw const FormatException(
        'assistant.generated_monetary_amount_not_authorized',
      );
    }
  }
  if (!monetaryFactAvailable && currencyClaims.isNotEmpty) {
    throw const FormatException('assistant.generated_money_not_authorized');
  }
  if (unavailableWithoutMoney &&
      RegExp(
        r'\b(?:zero|zéro)\b|\breste\s+à\s+0\b|\b(?:plus|aucun)\s+de?\s*budget\b|\brien\s+à\s+dépenser\b|\bnothing\s+left\b|\bno\s+budget\b|صفر|ما\s*بقا\s*والو',
        caseSensitive: false,
        unicode: true,
      ).hasMatch(text)) {
    throw const FormatException('assistant.unavailable_rendered_as_zero');
  }
}

AssistantOperationLevel _operationLevel(Object? value) => switch (value) {
  'recommend' => AssistantOperationLevel.recommend,
  'prepare' => AssistantOperationLevel.prepare,
  'execute' => AssistantOperationLevel.execute,
  _ => AssistantOperationLevel.read,
};

AssistantScopeBasis _scopeBasis(Object? value) => switch (value) {
  'explicit_context' => AssistantScopeBasis.explicitContext,
  'canonical_global_aggregate' => AssistantScopeBasis.canonicalGlobalAggregate,
  'clarification_required' => AssistantScopeBasis.clarificationRequired,
  _ => AssistantScopeBasis.unspecified,
};

AssistantFailurePhase _failurePhase(Object? value) => switch (value) {
  'synthesis' => AssistantFailurePhase.synthesis,
  _ => AssistantFailurePhase.planning,
};

AssistantProviderErrorCategory _failureCategory(Object? value) =>
    switch (value) {
      'empty_content' => AssistantProviderErrorCategory.emptyContent,
      'timeout' => AssistantProviderErrorCategory.timeout,
      'rate_limited' => AssistantProviderErrorCategory.rateLimited,
      'server_error' => AssistantProviderErrorCategory.serverError,
      'invalid_json' => AssistantProviderErrorCategory.invalidJson,
      'invalid_envelope' => AssistantProviderErrorCategory.invalidEnvelope,
      'partial_response' => AssistantProviderErrorCategory.partialResponse,
      'model_unavailable' => AssistantProviderErrorCategory.modelUnavailable,
      'network' => AssistantProviderErrorCategory.network,
      'unsafe_output' => AssistantProviderErrorCategory.unsafeOutput,
      _ => AssistantProviderErrorCategory.unknown,
    };
