import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_design_system.dart';
import '../../../core/localization/envelopes_locale.dart';
import '../../budget_intelligence/presentation/budget_scenarios_page.dart';
import '../../finance/application/providers/payment_methods_provider.dart';
import '../../finance/application/providers/remote_accounts_provider.dart';
import '../../finance/domain/account_ownership.dart';
import '../../finance/domain/financial_account.dart';
import '../application/providers/remote_envelopes_provider.dart';

String _envelopeText(BuildContext context, String key) =>
    EnvelopesWords.of(context).text(key);
String _envelopeFormat(
  BuildContext context,
  String key,
  Map<String, Object> values,
) => EnvelopesWords.of(context).format(key, values);

class EnvelopeRecommendationsPage extends ConsumerWidget {
  const EnvelopeRecommendationsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final envelopes = ref.watch(remoteEnvelopeBalancesProvider);
    final accounts = ref.watch(remoteAccountsProvider);
    final methods = ref.watch(paymentMethodsProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(_envelopeText(context, 'envelopes.settings_title')),
      ),
      body: SafeArea(
        child: switch ((envelopes, accounts, methods)) {
          (
            AsyncData(value: final e),
            AsyncData(value: final a),
            AsyncData(value: final m),
          ) =>
            _RecommendationsBody(envelopes: e, accounts: a, methods: m),
          (AsyncError(), _, _) ||
          (_, AsyncError(), _) ||
          (_, _, AsyncError()) => Center(
            child: Text(_envelopeText(context, 'envelopes.settings_error')),
          ),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }
}

class _RecommendationsBody extends ConsumerWidget {
  const _RecommendationsBody({
    required this.envelopes,
    required this.accounts,
    required this.methods,
  });

  final List<RemoteEnvelopeBalance> envelopes;
  final List<FinancialAccount> accounts;
  final List<PaymentMethod> methods;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeAccounts = accounts.where((item) => !item.isArchived).toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        final content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _envelopeText(context, 'envelopes.structural_title'),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: AppSpacing.xs),
            SecondaryInfoText(
              _envelopeText(context, 'envelopes.settings_hint'),
            ),
            const SizedBox(height: AppSpacing.sm),
            Card(
              child: Padding(
                padding: AppSpacing.card,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_envelopeText(context, 'envelopes.rule_explanation')),
                    Text(
                      _envelopeText(
                        context,
                        'envelopes.recommendation_explanation',
                      ),
                    ),
                    Text(_envelopeText(context, 'envelopes.error_explanation')),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Card(
              child: ListTile(
                leading: const Icon(Icons.account_tree_outlined),
                title: Text(
                  _envelopeText(context, 'envelopes.multi_account_title'),
                ),
                subtitle: Text(
                  _envelopeText(context, 'envelopes.multi_account_hint'),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const BudgetScenariosPage(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (constraints.maxWidth >= 900)
              _DesktopRecommendations(
                envelopes: envelopes,
                accounts: activeAccounts,
                methods: methods,
              )
            else
              _MobileRecommendations(
                envelopes: envelopes,
                accounts: activeAccounts,
                methods: methods,
              ),
          ],
        );
        return SingleChildScrollView(
          padding: AppSpacing.page,
          child: DesktopPageContainer(child: content),
        );
      },
    );
  }
}

class _DesktopRecommendations extends StatelessWidget {
  const _DesktopRecommendations({
    required this.envelopes,
    required this.accounts,
    required this.methods,
  });
  final List<RemoteEnvelopeBalance> envelopes;
  final List<FinancialAccount> accounts;
  final List<PaymentMethod> methods;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: DataTable(
      columns: [
        DataColumn(label: Text(_envelopeText(context, 'envelopes.envelope'))),
        DataColumn(
          label: Text(
            _envelopeText(context, 'envelopes.current_balance_column'),
          ),
        ),
        DataColumn(
          label: Text(_envelopeText(context, 'envelopes.holder_rule')),
        ),
        DataColumn(
          label: Text(
            _envelopeText(context, 'envelopes.recommended_account_column'),
          ),
        ),
        DataColumn(
          label: Text(_envelopeText(context, 'envelopes.recommended_method')),
        ),
        DataColumn(label: Text(_envelopeText(context, 'envelopes.state'))),
      ],
      rows: [
        for (final envelope in envelopes)
          DataRow(
            cells: [
              DataCell(Text(envelope.name)),
              DataCell(
                Text(
                  // i18n-dynamic-only
                  '${envelope.balance.dirhams.toStringAsFixed(2)} MAD',
                ),
              ),
              DataCell(_OwnershipText(envelope: envelope)),
              DataCell(
                SizedBox(
                  width: 210,
                  child: _AccountField(
                    envelope: envelope,
                    accounts: accounts,
                    methods: methods,
                  ),
                ),
              ),
              DataCell(
                SizedBox(
                  width: 230,
                  child: _MethodField(
                    envelope: envelope,
                    accounts: accounts,
                    methods: methods,
                  ),
                ),
              ),
              DataCell(
                _StateChip(
                  envelope: envelope,
                  accounts: accounts,
                  methods: methods,
                ),
              ),
            ],
          ),
      ],
    ),
  );
}

class _MobileRecommendations extends StatelessWidget {
  const _MobileRecommendations({
    required this.envelopes,
    required this.accounts,
    required this.methods,
  });
  final List<RemoteEnvelopeBalance> envelopes;
  final List<FinancialAccount> accounts;
  final List<PaymentMethod> methods;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final envelope in envelopes)
        Card(
          key: Key('envelope-recommendation-${envelope.id}'),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        envelope.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    _StateChip(
                      envelope: envelope,
                      accounts: accounts,
                      methods: methods,
                    ),
                  ],
                ),
                Text(
                  _envelopeFormat(context, 'envelopes.current_balance', {
                    'value':
                        '${envelope.balance.dirhams.toStringAsFixed(2)} MAD',
                  }),
                ),
                _OwnershipText(envelope: envelope),
                const SizedBox(height: AppSpacing.xs),
                _AccountField(
                  envelope: envelope,
                  accounts: accounts,
                  methods: methods,
                ),
                const SizedBox(height: AppSpacing.xs),
                _MethodField(
                  envelope: envelope,
                  accounts: accounts,
                  methods: methods,
                ),
              ],
            ),
          ),
        ),
    ],
  );
}

class _AccountField extends ConsumerWidget {
  const _AccountField({
    required this.envelope,
    required this.accounts,
    required this.methods,
  });
  final RemoteEnvelopeBalance envelope;
  final List<FinancialAccount> accounts;
  final List<PaymentMethod> methods;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (envelope.effectiveRecommendationKind != 'single_account' &&
        envelope.effectiveRecommendationKind != 'unconfigured') {
      return InputDecorator(
        decoration: InputDecoration(
          labelText: _envelopeText(
            context,
            'envelopes.recommended_account_column',
          ),
        ),
        child: Text(_structuralAccountLabel(context, envelope)),
      );
    }
    final selected =
        accounts.any((item) => item.id == envelope.recommendedAccountId)
        ? envelope.recommendedAccountId
        : null;
    return DropdownButtonFormField<String?>(
      key: Key('recommended-account-${envelope.id}'),
      initialValue: selected,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: _envelopeText(
          context,
          'envelopes.recommended_account_column',
        ),
      ),
      items: [
        DropdownMenuItem<String?>(
          value: null,
          child: Text(_envelopeText(context, 'envelopes.none')),
        ),
        for (final account in accounts)
          DropdownMenuItem<String?>(
            value: account.id,
            child: Text(account.name),
          ),
      ],
      onChanged: (value) async {
        final compatibleMethod = methods
            .where((item) => item.id == envelope.recommendedPaymentMethodId)
            .where(
              (item) =>
                  item.active &&
                  (item.accountId == null || item.accountId == value),
            )
            .firstOrNull;
        await _saveRecommendation(
          context,
          ref,
          envelope.id,
          value,
          compatibleMethod?.id,
        );
      },
    );
  }
}

class _MethodField extends ConsumerWidget {
  const _MethodField({
    required this.envelope,
    required this.accounts,
    required this.methods,
  });
  final RemoteEnvelopeBalance envelope;
  final List<FinancialAccount> accounts;
  final List<PaymentMethod> methods;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (envelope.effectiveRecommendationKind != 'single_account' &&
        envelope.effectiveRecommendationKind != 'unconfigured') {
      return InputDecorator(
        decoration: InputDecoration(
          labelText: _envelopeText(context, 'envelopes.recommended_method'),
        ),
        child: Text(_envelopeText(context, 'envelopes.optional_by_operation')),
      );
    }
    final account = accounts
        .where((item) => item.id == envelope.recommendedAccountId)
        .firstOrNull;
    final compatible = methods
        .where((item) => _compatible(item, account))
        .toList();
    final selected =
        compatible.any((item) => item.id == envelope.recommendedPaymentMethodId)
        ? envelope.recommendedPaymentMethodId
        : null;
    return DropdownButtonFormField<String?>(
      key: Key('recommended-method-${envelope.id}'),
      initialValue: selected,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: _envelopeText(context, 'envelopes.recommended_method'),
      ),
      items: [
        DropdownMenuItem<String?>(
          value: null,
          child: Text(_envelopeText(context, 'envelopes.none')),
        ),
        for (final method in compatible)
          DropdownMenuItem<String?>(
            value: method.id,
            child: Text(method.label),
          ),
      ],
      onChanged: (value) => _saveRecommendation(
        context,
        ref,
        envelope.id,
        envelope.recommendedAccountId,
        value,
      ),
    );
  }

  bool _compatible(PaymentMethod method, FinancialAccount? account) {
    if (!method.active) return false;
    if (method.accountId != null && method.accountId != account?.id) {
      return false;
    }
    if (method.holderUserId != null &&
        account != null &&
        account.ownershipType == AccountOwnershipType.individual) {
      return account.holders.any(
        (holder) => holder.userId == method.holderUserId,
      );
    }
    return true;
  }
}

class _OwnershipText extends StatelessWidget {
  const _OwnershipText({required this.envelope});
  final RemoteEnvelopeBalance envelope;

  @override
  Widget build(BuildContext context) {
    final label = switch (envelope.economicRule) {
      'individual' => _envelopeFormat(context, 'envelopes.rule.individual', {
        'member':
            envelope.economicMemberName ??
            _envelopeText(context, 'envelopes.member'),
      }),
      'household_scenario' => _envelopeText(
        context,
        'envelopes.rule.household',
      ),
      'household_multi_account' => _envelopeText(
        context,
        'envelopes.rule.household_multi',
      ),
      'member_beneficiary' => _envelopeText(context, 'envelopes.rule.member'),
      'system' => _envelopeText(context, 'envelopes.rule.system'),
      _ => _envelopeText(context, 'envelopes.rule.undefined'),
    };
    return Text(label);
  }
}

class _StateChip extends StatelessWidget {
  const _StateChip({
    required this.envelope,
    required this.accounts,
    required this.methods,
  });
  final RemoteEnvelopeBalance envelope;
  final List<FinancialAccount> accounts;
  final List<PaymentMethod> methods;

  @override
  Widget build(BuildContext context) {
    final kind = envelope.effectiveRecommendationKind;
    if (kind == 'scenario_split' ||
        kind == 'member_beneficiary' ||
        kind == 'system') {
      return Chip(label: Text(_envelopeText(context, 'envelopes.configured')));
    }
    final accountValid =
        envelope.recommendedAccountId != null &&
        accounts.any((item) => item.id == envelope.recommendedAccountId);
    final methodValid =
        envelope.recommendedPaymentMethodId == null ||
        methods.any(
          (item) =>
              item.id == envelope.recommendedPaymentMethodId && item.active,
        );
    final label = !accountValid
        ? _envelopeText(context, 'envelopes.to_configure')
        : !methodValid
        ? _envelopeText(context, 'envelopes.inactive_method')
        : _envelopeText(context, 'envelopes.configured');
    return Chip(label: Text(label));
  }
}

String _structuralAccountLabel(
  BuildContext context,
  RemoteEnvelopeBalance envelope,
) => switch (envelope.effectiveRecommendationKind) {
  'scenario_split' => _envelopeText(context, 'envelopes.scenario_split'),
  'member_beneficiary' => _envelopeText(
    context,
    'envelopes.beneficiary_account',
  ),
  'system' => _envelopeText(context, 'envelopes.not_applicable'),
  _ => _envelopeText(context, 'envelopes.none'),
};

Future<void> _saveRecommendation(
  BuildContext context,
  WidgetRef ref,
  String envelopeId,
  String? accountId,
  String? paymentMethodId,
) async {
  try {
    await ref.read(setEnvelopeRecommendationProvider)(
      envelopeId: envelopeId,
      accountId: accountId,
      paymentMethodId: paymentMethodId,
    );
    ref.invalidate(remoteEnvelopeHistoryProvider);
    ref.invalidate(remoteEnvelopeBalancesProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _envelopeText(context, 'envelopes.recommendation_saved'),
          ),
        ),
      );
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_envelopeText(context, 'envelopes.save_error'))),
      );
    }
  }
}
