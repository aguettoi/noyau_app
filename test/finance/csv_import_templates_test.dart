import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/features/finance/application/csv_import_templates.dart';

void main() {
  const expected = [
    (
      'accounts',
      'Comptes',
      'template_comptes.csv',
      'external_id;nom;type;titulaire;statut;solde_initial_mad;date_solde_initial',
      '',
    ),
    (
      'envelopes',
      'Enveloppes',
      'template_enveloppes.csv',
      'external_id;nom;categorie;periode;montant_initial_centimes;statut',
      'EXEMPLE-001;Courses;Alimentation;mensuelle;300000;actif',
    ),
    (
      'expenses',
      'Journal des dépenses',
      'template_journal_depenses.csv',
      'external_id;date;libelle;montant_centimes;enveloppe;paye_par;saisi_par;compte_paiement;commentaire;historique_non_rapproche',
      'EXEMPLE-001;2026-01-15;Courses hebdomadaires;45000;Courses;Ibrahim;Ibrahim;Compte Ibrahim CIH;Exemple;non',
    ),
    (
      'revenues',
      'Revenus',
      'template_revenus.csv',
      'external_id;date;source;montant_centimes;beneficiaire;compte;commentaire',
      'EXEMPLE-001;2026-01-31;Salaire;1310000;Ibrahim;Compte Ibrahim CIH;Exemple',
    ),
    (
      'advances',
      'Avances',
      'template_avances.csv',
      'external_id;date;avance_par;pour_qui;montant_centimes;motif;statut;montant_rembourse_centimes',
      'EXEMPLE-001;2026-01-10;Ibrahim;Nora;50000;Achat commun;ouverte;0',
    ),
    (
      'historical_balances',
      'Soldes historiques',
      'template_soldes_historiques.csv',
      'external_id;date_reference;type_element;nom_element;solde_centimes;commentaire',
      'EXEMPLE-001;2026-01-01;compte;Compte Ibrahim CIH;250000;Solde initial',
    ),
    (
      'goals',
      'Objectifs',
      'template_objectifs.csv',
      'external_id;nom;montant_cible_centimes;montant_initial_centimes;date_cible;priorite;statut',
      'EXEMPLE-001;Voiture;18000000;3652075;2030-12-31;haute;actif',
    ),
  ];
  test('centralise sept templates ordonnés, uniques et complets', () {
    expect(csvImportTemplates, hasLength(7));
    expect(csvImportTemplates.map((x) => x.id), expected.map((x) => x.$1));
    expect(csvImportTemplates.map((x) => x.id).toSet(), hasLength(7));
    expect(csvImportTemplates.map((x) => x.fileName).toSet(), hasLength(7));
    for (final t in csvImportTemplates) {
      expect(t.id, isNotEmpty);
      expect(t.label, isNotEmpty);
      expect(t.description, isNotEmpty);
      expect(t.fileName, isNotEmpty);
      expect(t.columns, isNotEmpty);
      expect(t.columns.toSet(), hasLength(t.columns.length));
      expect(t.columns.every((x) => x.isNotEmpty), isTrue);
      expect(t.header, t.columns.join(';'));
      expect(
        t.csvContent,
        t.exampleRow.isEmpty
            ? '${t.header}\n'
            : '${t.header}\n${t.exampleRow}\n',
      );
      expect(byType(t.type), same(t));
      expect(byId(t.id), same(t));
    }
    expect(byId('unknown'), isNull);
  });
  for (final e in expected) {
    test('valeurs exactes ${e.$2}', () {
      final t = byId(e.$1)!;
      expect(t.label, e.$2);
      expect(t.fileName, e.$3);
      expect(t.header, e.$4);
      expect(t.exampleRow, e.$5);
    });
  }
}
