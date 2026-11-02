# D1.2-A — Foundation

## Scope

D1.2-A introduces the five-universe navigation contract (Home, Money,
Household, Projects, More), a contextual universal add action, shared visual
primitives and a consistent offline banner. It deliberately does not redesign
the feature pages or change any business/backend contract.

## Preserved contracts

- Existing feature pages and historical IndexedStack destinations remain.
- Ctrl+K remains available.
- Financial actions open canonical screens; the foundation never creates a
  FinancialEvent, GL posting or EnvelopeMovement.
- Privacy, RLS, anti-inference, 1/2/N, i18n and offline contracts are unchanged.
- No Supabase migration is required.

## Foundation components

- `FpAdaptiveNavigation`
- `FpUniversalAddSheet`
- `FpUniverseHub`
- `FpActionCard`
- `FpProgressCard`
- `FpMoneyDisplay`
- `FpPrivacyCard`
- `FpAdvancedDisclosure`
- `FpSearchFilterBar`
- `FpFormSection`
- `FpOfflineBanner`
- `FpWizard`
- `FpConfirmation`

The existing Material 3 theme, palette, typography, spacing, radius,
responsive breakpoints and state components remain canonical.

## Known boundaries

- Feature-level redesign belongs to D1.2-B onward.
- Mobile Projects is reached through More and contextual links, as specified.
- The existing route stack remains imperative; a router migration is not part
  of D1.2-A.
