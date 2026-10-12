import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_design_system.dart';
import '../../budget_intelligence/presentation/budget_scenarios_page.dart';
import '../../finance/application/providers/payment_methods_provider.dart';
import '../../finance/application/providers/remote_accounts_provider.dart';
import '../../finance/domain/account_ownership.dart';
import '../../finance/domain/financial_account.dart';
import '../application/providers/remote_envelopes_provider.dart';

class EnvelopeRecommendationsPage extends ConsumerWidget {
  const EnvelopeRecommendationsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final envelopes = ref.watch(remoteEnvelopeBalancesProvider);
    final accounts = ref.watch(remoteAccountsProvider);
    final methods = ref.watch(paymentMethodsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Paramétrage des enveloppes')),
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
          (_, _, AsyncError()) => const Center(
            child: Text('Impossible de charger le paramétrage.'),
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
              'Configuration structurelle',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: AppSpacing.xs),
            const SecondaryInfoText(
              'Ces recommandations alimentent les paiements quotidiens et les cibles automatiques. Elles ne déplacent aucun argent.',
            ),
            const SizedBox(height: AppSpacing.sm),
            Card(
              child: ListTile(
                leading: const Icon(Icons.account_tree_outlined),
                title: const Text(
                  'Enveloppes réparties entre plusieurs comptes',
                ),
                subtitle: const Text(
                  'La répartition structurelle multi-comptes reste portée par le scénario budgétaire actif, jamais par une dérogation mensuelle.',
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
      columns: const [
        DataColumn(label: Text('Enveloppe')),
        DataColumn(label: Text('Solde actuel')),
        DataColumn(label: Text('Titulaire / règle')),
        DataColumn(label: Text('Compte recommandé')),
        DataColumn(label: Text('Moyen recommandé')),
        DataColumn(label: Text('État')),
      ],
      rows: [
        for (final envelope in envelopes)
          DataRow(
            cells: [
              DataCell(Text(envelope.name)),
              DataCell(
                Text('${envelope.balance.dirhams.toStringAsFixed(2)} MAD'),
              ),
              DataCell(_OwnershipText(envelope: envelope, accounts: accounts)),
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
                  'Solde actuel : ${envelope.balance.dirhams.toStringAsFixed(2)} MAD',
                ),
                _OwnershipText(envelope: envelope, accounts: accounts),
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
        decoration: const InputDecoration(labelText: 'Compte recommandé'),
        child: Text(_structuralAccountLabel(envelope)),
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
      decoration: const InputDecoration(labelText: 'Compte recommandé'),
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('Aucun')),
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
      return const InputDecorator(
        decoration: InputDecoration(labelText: 'Moyen recommandé'),
        child: Text('Facultatif — selon l’opération'),
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
      decoration: const InputDecoration(labelText: 'Moyen recommandé'),
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('Aucun')),
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
  const _OwnershipText({required this.envelope, required this.accounts});
  final RemoteEnvelopeBalance envelope;
  final List<FinancialAccount> accounts;

  @override
  Widget build(BuildContext context) {
    final structuralLabel = switch (envelope.effectiveRecommendationKind) {
      'scenario_split' => 'Règle commune — plusieurs comptes',
      'member_beneficiary' => 'Selon le bénéficiaire / membre',
      'system' => 'Enveloppe système — sans objet',
      _ => null,
    };
    if (structuralLabel != null) return Text(structuralLabel);
    final account = accounts
        .where((item) => item.id == envelope.recommendedAccountId)
        .firstOrNull;
    final label = switch (account?.ownershipType) {
      AccountOwnershipType.individual => 'Individuel',
      AccountOwnershipType.shared =>
        'Partagé (${account!.holders.length} titulaires)',
      AccountOwnershipType.household => 'Foyer',
      null => 'À définir',
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
      return const Chip(label: Text('Configurée'));
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
        ? 'À configurer'
        : !methodValid
        ? 'Moyen inactif'
        : 'Configurée';
    return Chip(label: Text(label));
  }
}

String _structuralAccountLabel(RemoteEnvelopeBalance envelope) =>
    switch (envelope.effectiveRecommendationKind) {
      'scenario_split' => 'Répartition sur plusieurs comptes',
      'member_beneficiary' => 'Compte du bénéficiaire de la prime',
      'system' => 'Sans objet',
      _ => 'Aucun',
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
        const SnackBar(content: Text('Recommandation enregistrée.')),
      );
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enregistrement impossible.')),
      );
    }
  }
}
