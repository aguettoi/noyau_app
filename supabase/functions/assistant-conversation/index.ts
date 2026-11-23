import { createClient } from 'npm:@supabase/supabase-js@2.86.0'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info',
}

type Json = null | boolean | number | string | Json[] | { [key: string]: Json }

type ProviderReply = {
  content: string
  model: string
  latencyMs: number
  attempts: number
  usage?: { prompt_tokens?: number; completion_tokens?: number; total_tokens?: number }
}

const maxQuestionLength = 4000
const maxHistoryTurns = 12
const maxCapabilities = 6
const certifiedSandboxProjectRef = 'vojxsgcxgwasqlaxhhcd'

Deno.serve(async (request) => {
  const requestStarted = Date.now()
  let failurePhase = 'request'
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (request.method !== 'POST') return json({ error: 'method_not_allowed' }, 405)

  try {
    const authorization = request.headers.get('Authorization') ?? ''
    if (!authorization.startsWith('Bearer ')) return json({ error: 'unauthorized' }, 401)
    const supabaseUrl = Deno.env.get('SUPABASE_URL')
    const publishable = publishableKey()
    if (!supabaseUrl || !publishable) return json({ error: 'server_configuration' }, 503)
    if (!productionAiGateAllows(supabaseUrl)) {
      return json({ error: 'ai_prod_data_residency_privacy_decision_required' }, 503)
    }
    const client = createClient(supabaseUrl, publishable, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false, autoRefreshToken: false },
    })
    const { data: { user }, error: authError } = await client.auth.getUser(
      authorization.substring('Bearer '.length),
    )
    if (authError || !user) return json({ error: 'unauthorized' }, 401)

    const body = await request.json() as Record<string, unknown>
    const householdId = stringValue(body.household_id)
    const question = stringValue(body.question).trim()
    if (!householdId || !question || question.length > maxQuestionLength) {
      return json({ error: 'invalid_request' }, 400)
    }
    const { data: membership, error: membershipError } = await client
      .from('household_members')
      .select('user_id')
      .eq('household_id', householdId)
      .eq('user_id', user.id)
      .maybeSingle()
    if (membershipError || !membership) return json({ error: 'forbidden' }, 403)

    const phase = stringValue(body.phase)
    failurePhase = phase === 'respond' ? 'synthesis' : 'planning'
    if (phase === 'plan') return await plan(body, question)
    if (phase === 'respond') return await respond(body, question)
    return json({ error: 'invalid_phase' }, 400)
  } catch (error) {
    // Never log the question, financial context, token or provider payload.
    console.error('assistant-conversation failure', JSON.stringify({
      code: safeErrorCode(error),
      elapsed_ms: Date.now() - requestStarted,
    }))
    return json({
      error: 'assistant_unavailable',
      phase: failurePhase,
      category: publicProviderCategory(error),
    }, 503)
  }
})

async function plan(body: Record<string, unknown>, question: string): Promise<Response> {
  const available = arrayValue(body.capabilities)
    .filter(isRecord)
    .map((item) => ({
      id: stringValue(item.id),
      description: stringValue(item.description),
      operation_level: stringValue(item.operation_level),
      semantic_scope: stringValue(item.semantic_scope),
      allows_implicit_global_resolution: item.allows_implicit_global_resolution === true,
    }))
    .filter((item) => item.id)
  const allowed = new Set(available.map((item) => item.id))
  if (!providerConfigured()) {
    return json({
      language: stringValue(body.ui_locale) || 'fr',
      capability_ids: [],
      operation_level: 'read',
      fallback: true,
    })
  }
  const reply = await callProvider([
    {
      role: 'system',
      content: `You are the semantic planner for FINANCIEL PILOTE. This is NOT a closed intent classifier and must never become a phrase, keyword or intent whitelist. Dynamically decompose the user's free-form request and select zero, one or more composable capabilities from the supplied registry. Never invent a capability. Availability of a capability is never evidence that its business scope matches the request. Compare the intended business perimeter with every semantic_scope. If one concept can materially refer to different authorized scopes and the conversation does not name one, clarify before selecting any capability. Choose silently only when the conversation explicitly identifies the perimeter, or when a capability is marked allows_implicit_global_resolution and genuinely answers the broad concept. For explicit_context, return a short verbatim scope_evidence substring from the latest question that names the business perimeter; a time expression alone is not scope evidence. For canonical_global_aggregate, use only capabilities marked as allowing implicit global resolution. Otherwise use clarification_required, select no capability and ask one natural question before retrieving financial data. Use user-authored history to resolve the next answer, then re-plan and revalidate permissions. Return strict JSON only: {"language":"...","capability_ids":["..."],"operation_level":"read|recommend|prepare|execute","needs_clarification":false,"clarification_question":null,"scope_basis":"explicit_context|canonical_global_aggregate|clarification_required","scope_evidence":null}.`,
    },
    {
      role: 'user',
      content: JSON.stringify({
        history: safeHistory(body.history),
        question,
        available_capabilities: available,
      }),
    },
  ], 300)
  const parsed = parseObject(reply.content)
  const capabilityIds = arrayValue(parsed.capability_ids)
    .map(stringValue)
    .filter((id) => allowed.has(id))
    .slice(0, maxCapabilities)
  const needsClarification = parsed.needs_clarification === true
  const clarificationQuestion = stringValue(parsed.clarification_question).trim()
  const scopeBasis = allowedScopeBasis(stringValue(parsed.scope_basis))
  const scopeEvidence = stringValue(parsed.scope_evidence).trim()
  const selected = capabilityIds
    .map((id) => available.find((item) => item.id === id))
    .filter(Boolean)
  const implicitAggregateAllowed = selected.length > 0 &&
    selected.every((item) => item?.allows_implicit_global_resolution === true)
  const evidenceIsVerbatim = scopeEvidence.length > 0 &&
    question.toLocaleLowerCase().includes(scopeEvidence.toLocaleLowerCase())
  const scopeValidated = scopeBasis === 'explicit_context'
    ? evidenceIsVerbatim
    : scopeBasis === 'canonical_global_aggregate'
      ? implicitAggregateAllowed
      : false
  const mustClarify = needsClarification ||
    scopeBasis === 'clarification_required' ||
    (capabilityIds.length > 0 && !scopeValidated)
  return json({
    language: stringValue(parsed.language) || stringValue(body.ui_locale) || 'fr',
    capability_ids: mustClarify ? [] : capabilityIds,
    operation_level: allowedOperation(stringValue(parsed.operation_level)),
    needs_clarification: mustClarify,
    clarification_question: mustClarify
      ? (clarificationQuestion || defaultClarification(stringValue(body.ui_locale)))
      : null,
    scope_basis: mustClarify ? 'clarification_required' : scopeBasis,
    scope_evidence: mustClarify ? null : scopeEvidence,
    provider: 'configured-provider',
    model: reply.model,
    latency_ms: reply.latencyMs,
    usage: minimizedUsage(reply.usage),
    attempts: reply.attempts,
  })
}

async function respond(body: Record<string, unknown>, question: string): Promise<Response> {
  if (!providerConfigured()) {
    return json({
      text: '',
      language: stringValue(body.ui_locale) || 'fr',
      fallback: true,
      provider: 'none',
      model: 'none',
      latency_ms: 0,
    })
  }
  const plan = isRecord(body.plan) ? body.plan : {}
  const results = sanitizeCapabilityResults(body.authorized_results)
  const reply = await callProvider([
    {
      role: 'system',
      content: `You are FINANCIEL PILOTE's governed conversational layer. FINANCIEL deterministic data and calculations below are the sole source of truth. Never invent, estimate, reconstruct, or replace a missing amount with zero. Treat null, unavailable, unauthorized, not_configured and not_applicable as distinct from numeric zero. Use a currency only when the same authorized fact explicitly supplies its canonical currency_code; otherwise express the answer without any currency, symbol or inferred unit. Never introduce a number absent from the authorized facts. A privacy marker means excluded data must remain excluded; do not infer it by totals, deltas, comparisons, projections, language changes, or conversation history. A private account is absent, not something to mention. Distinguish facts, deterministic calculations, assumptions, estimates, and AI recommendations. If information is unavailable, say naturally that no reliable amount can be given from the available data. Reply mainly in the user's latest language unless explicitly asked otherwise. For Cycle data, use only supplied dates/phases or the owner's supplied forecast and never infer intimate details. Do not claim to have executed an action. For prepare/execute requests, explain that explicit confirmation and canonical revalidation are required. You may optionally return a low-risk informational navigation to one of: budget, priorities, help. Navigation is not an action proposal and never needs confirmation. Never propose a financial mutation. Return strict JSON only: {"text":"...","language":"...","navigations":[{"type":"navigate","target":"budget|priorities|help"}]}.`,
    },
    {
      role: 'user',
      content: JSON.stringify({
        history: safeHistory(body.history),
        latest_question: question,
        plan,
        authorized_deterministic_results: results,
      }),
    },
  ], 700)
  const parsed = parseObject(reply.content)
  const text = stringValue(parsed.text).trim()
  if (!text) throw new Error('provider_invalid_response')
  return json({
    text,
    language: stringValue(parsed.language) || stringValue(plan.language) || stringValue(body.ui_locale),
    fallback: false,
    provider: 'configured-provider',
    model: reply.model,
    latency_ms: reply.latencyMs,
    usage: minimizedUsage(reply.usage),
    attempts: reply.attempts,
    navigations: safeNavigations(parsed.navigations),
  })
}

function safeNavigations(value: unknown): Array<{ type: 'navigate'; target: string }> {
  const targets = new Set(['budget', 'priorities', 'help'])
  return arrayValue(value).filter(isRecord)
    .filter((item) => item.type === 'navigate' && targets.has(stringValue(item.target)))
    .slice(0, 1)
    .map((item) => ({ type: 'navigate' as const, target: stringValue(item.target) }))
}

async function callProvider(
  messages: Array<{ role: string; content: string }>,
  maxTokens: number,
): Promise<ProviderReply> {
  const baseUrl = Deno.env.get('AI_BASE_URL')?.replace(/\/$/, '')
  const apiKey = Deno.env.get('AI_API_KEY')
  const model = Deno.env.get('AI_MODEL')
  if (!baseUrl || !apiKey || !model) throw new Error('provider_unconfigured')
  const started = Date.now()
  let lastError: unknown
  for (let attempt = 1; attempt <= 2; attempt++) {
    const controller = new AbortController()
    const timeout = setTimeout(() => controller.abort(), 28_000)
    try {
      const response = await fetch(`${baseUrl}/chat/completions`, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${apiKey}`,
          'Content-Type': 'application/json',
          'HTTP-Referer': 'https://financielpilote.app',
          'X-Title': 'FINANCIEL PILOTE',
        },
        body: JSON.stringify({
          model,
          messages,
          temperature: 0.1,
          max_tokens: maxTokens,
        }),
        signal: controller.signal,
      })
      const raw = await response.text()
      if (!response.ok) throw new Error(`provider_http_${response.status}`)
      if (!raw.trim()) throw new Error('provider_empty_envelope')
      let payload: Record<string, unknown>
      try {
        const decoded = JSON.parse(raw) as unknown
        if (!isRecord(decoded)) throw new Error('not_object')
        payload = decoded
      } catch {
        throw new Error('provider_invalid_envelope')
      }
      const choices = arrayValue(payload.choices)
      const first = choices[0]
      if (!isRecord(first) || !isRecord(first.message)) {
        throw new Error('provider_partial_response')
      }
      const message = first.message
      const content = providerContent(message.content)
      if (!content.trim()) throw new Error('provider_empty_content')
      return {
        content,
        model: stringValue(payload.model) || model,
        latencyMs: Date.now() - started,
        attempts: attempt,
        usage: isRecord(payload.usage) ? payload.usage as ProviderReply['usage'] : undefined,
      }
    } catch (error) {
      lastError = error instanceof DOMException && error.name === 'AbortError'
        ? new Error('provider_timeout')
        : error instanceof TypeError
          ? new Error('provider_network')
          : error
      if (attempt === 2 || !retryableProviderError(lastError)) throw lastError
    } finally {
      clearTimeout(timeout)
    }
  }
  throw lastError ?? new Error('provider_unavailable')
}

function sanitizeCapabilityResults(value: unknown): Json[] {
  return arrayValue(value).filter(isRecord).slice(0, maxCapabilities).map((item) => ({
    capability_id: stringValue(item.capability_id),
    generated_at: stringValue(item.generated_at),
    source_categories: arrayValue(item.source_categories).map(stringValue).slice(0, 20),
    unavailable_reason: stringValue(item.unavailable_reason) || null,
    facts: sanitizeJson(item.facts, 0),
  }))
}

function sanitizeJson(value: unknown, depth: number): Json {
  if (depth > 4) return null
  if (value === null || typeof value === 'boolean' || typeof value === 'number') return value
  if (typeof value === 'string') return value.slice(0, 500)
  if (Array.isArray(value)) return value.slice(0, 30).map((item) => sanitizeJson(item, depth + 1))
  if (isRecord(value)) {
    return Object.fromEntries(Object.entries(value).slice(0, 60).map(([key, item]) => [key, sanitizeJson(item, depth + 1)]))
  }
  return null
}

function safeHistory(value: unknown): Array<{ role: 'user'; content: string }> {
  return arrayValue(value).filter(isRecord).filter((item) => item.role === 'user')
    .slice(-maxHistoryTurns).map((item) => ({ role: 'user', content: stringValue(item.content).slice(0, maxQuestionLength) }))
}

function providerConfigured(): boolean {
  return Boolean(Deno.env.get('AI_BASE_URL') && Deno.env.get('AI_API_KEY') && Deno.env.get('AI_MODEL'))
}

function productionAiGateAllows(supabaseUrl: string): boolean {
  try {
    const projectRef = new URL(supabaseUrl).hostname.split('.')[0]
    if (projectRef === certifiedSandboxProjectRef) return true
  } catch {
    return false
  }
  return Deno.env.get('AI_PROD_DATA_RESIDENCY_PRIVACY_APPROVED') === 'true'
}

function publishableKey(): string | undefined {
  const direct = Deno.env.get('SUPABASE_ANON_KEY')
  if (direct) return direct
  const raw = Deno.env.get('SUPABASE_PUBLISHABLE_KEYS')
  if (!raw) return undefined
  try { return stringValue((JSON.parse(raw) as Record<string, unknown>).default) || undefined } catch { return undefined }
}

function minimizedUsage(usage?: ProviderReply['usage']): Record<string, number> | undefined {
  if (!usage) return undefined
  return {
    prompt_tokens: Number(usage.prompt_tokens ?? 0),
    completion_tokens: Number(usage.completion_tokens ?? 0),
    total_tokens: Number(usage.total_tokens ?? 0),
  }
}

function parseObject(value: string): Record<string, unknown> {
  const normalized = value.trim()
    .replace(/^```(?:json)?\s*/i, '')
    .replace(/\s*```$/, '')
  const start = normalized.indexOf('{')
  const end = normalized.lastIndexOf('}')
  if (start < 0 || end < start) throw new Error('provider_invalid_json')
  const parsed = JSON.parse(normalized.slice(start, end + 1)) as unknown
  if (!isRecord(parsed)) throw new Error('provider_invalid_json')
  return parsed
}

function allowedOperation(value: string): string {
  return ['read', 'recommend', 'prepare', 'execute'].includes(value) ? value : 'read'
}

function allowedScopeBasis(value: string): string {
  return ['explicit_context', 'canonical_global_aggregate', 'clarification_required'].includes(value)
    ? value
    : 'clarification_required'
}

function defaultClarification(locale: string): string {
  if (locale === 'en') return 'Which financial scope do you mean: a global overview or a more specific budget, category, or purpose?'
  if (locale === 'ar') return 'ما هو النطاق المالي المقصود: نظرة عامة أم ميزانية أو فئة أو غرض محدد؟'
  if (locale === 'ary' || locale === 'ar-MA') return 'شنو هو النطاق المالي اللي كتعني: نظرة عامة ولا بودجي ولا فئة ولا غرض محدد؟'
  return 'De quel périmètre financier parlez-vous : une vue globale ou un budget, une catégorie ou un objectif précis ?'
}

function json(body: unknown, status = 200): Response {
  return Response.json(body, { status, headers: { ...corsHeaders, 'Cache-Control': 'no-store' } })
}

function arrayValue(value: unknown): unknown[] { return Array.isArray(value) ? value : [] }
function stringValue(value: unknown): string { return typeof value === 'string' ? value : '' }
function isRecord(value: unknown): value is Record<string, unknown> { return typeof value === 'object' && value !== null && !Array.isArray(value) }
function safeErrorCode(error: unknown): string { return error instanceof Error ? error.message.slice(0, 80) : 'unknown' }

function providerContent(value: unknown): string {
  if (typeof value === 'string') return value
  return arrayValue(value).filter(isRecord)
    .map((item) => stringValue(item.text) || stringValue(item.content))
    .filter(Boolean).join('\n')
}

function retryableProviderError(error: unknown): boolean {
  const code = safeErrorCode(error)
  return code === 'provider_timeout' ||
    code === 'provider_empty_envelope' ||
    code === 'provider_invalid_envelope' ||
    code === 'provider_partial_response' ||
    code === 'provider_empty_content' ||
    code === 'provider_network' ||
    /^provider_http_(408|409|425|429|5\d\d)$/.test(code)
}

function publicProviderCategory(error: unknown): string {
  const code = safeErrorCode(error)
  if (code === 'provider_empty_content') return 'empty_content'
  if (code === 'provider_timeout') return 'timeout'
  if (code === 'provider_invalid_json') return 'invalid_json'
  if (code === 'provider_invalid_envelope' || code === 'provider_empty_envelope') return 'invalid_envelope'
  if (code === 'provider_partial_response') return 'partial_response'
  if (code === 'provider_http_429') return 'rate_limited'
  if (/^provider_http_5\d\d$/.test(code)) return 'server_error'
  if (code === 'provider_http_404') return 'model_unavailable'
  if (code === 'provider_network') return 'network'
  return 'unknown'
}
