# Governed conversational assistant

Authenticated two-phase Edge Function:

1. `plan`: semantically selects any combination of registered capabilities.
2. `respond`: synthesizes only the freshly authorized deterministic results.

Required server secrets (never commit their values):

- `AI_BASE_URL`: OpenAI-compatible provider base URL.
- `AI_API_KEY`: provider secret.
- `AI_MODEL`: model identifier.

If they are absent, the function returns an explicit fallback response and the
Flutter client keeps the deterministic assistant available. Raw questions and
financial context are never written to logs or analytics by this function.

## Blocking production gate

Global OpenRouter routing is authorized only for the current synthetic-data
Sandbox. Every other Supabase project fails closed unless the explicit server
secret `AI_PROD_DATA_RESIDENCY_PRIVACY_APPROVED=true` is present.

That secret must not be configured until the formal gate
`AI PROD DATA-RESIDENCY & PRIVACY DECISION` has selected and certified the
production provider, fixed model, processing region, retention policy,
contractual protections, context minimization and CERT-L1H non-regression.
