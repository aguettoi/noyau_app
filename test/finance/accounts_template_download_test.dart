import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/features/finance/application/accounts_template_download.dart';
void main(){test('génère le template Comptes exact en UTF-8',(){expect(accountsTemplateFileName,'template_comptes.csv');final csv=accountsTemplateCsv();expect(csv.split('\n').first,'external_id;nom;type;titulaire;statut;solde_initial_centimes;date_solde_initial');expect(csv,contains('EXEMPLE-001;Compte courant;banque;Ibrahim;actif;0;2026-01-01'));expect(utf8.decode(accountsTemplateUtf8()),csv);});}
