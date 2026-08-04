import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/features/finance/application/accounts_template_download.dart';
import 'package:noyau_app/features/finance/application/accounts_template_download_stub.dart';

void main() {
  test('génère le template Comptes exact en UTF-8', () {
    expect(accountsTemplateFileName, 'template_comptes.csv');
    final csv = accountsTemplateCsv();
    expect(
      csv.split('\n').first,
      'external_id;nom;type;titulaire;statut;solde_initial_mad;date_solde_initial',
    );
    expect(
      csv,
      'external_id;nom;type;titulaire;statut;solde_initial_mad;date_solde_initial\n',
    );
    expect(utf8.decode(accountsTemplateUtf8()), csv);
  });

  test('annulation native ne crée aucun fichier', () async {
    var writeCalls = 0;
    final saver = NativeTemplateFileSaver(
      saveFile:
          ({
            required dialogTitle,
            required fileName,
            required type,
            required allowedExtensions,
          }) async => null,
      writeBytes: (_, _) async => writeCalls++,
    );

    await saver.save(utf8.encode('contenu'), 'template_comptes.csv');

    expect(writeCalls, 0);
  });

  test('écrit exactement les octets UTF-8 au chemin choisi', () async {
    final directory = await Directory.systemTemp.createTemp('noyau-template-');
    addTearDown(() => directory.delete(recursive: true));
    final path =
        '${directory.path}${Platform.pathSeparator}template_comptes.csv';
    final bytes = utf8.encode('nom;libellé\n1;Épargne\n');
    final saver = NativeTemplateFileSaver(
      saveFile:
          ({
            required dialogTitle,
            required fileName,
            required type,
            required allowedExtensions,
          }) async => path,
    );

    await saver.save(bytes, 'template_comptes.csv');

    expect(await File(path).readAsBytes(), bytes);
    expect(
      utf8.decode(await File(path).readAsBytes()),
      'nom;libellé\n1;Épargne\n',
    );
  });

  test('transmet le nom et le filtre CSV au sélecteur natif', () async {
    String? receivedName;
    String? receivedTitle;
    FileType? receivedType;
    List<String>? receivedExtensions;
    final saver = NativeTemplateFileSaver(
      saveFile:
          ({
            required dialogTitle,
            required fileName,
            required type,
            required allowedExtensions,
          }) async {
            receivedTitle = dialogTitle;
            receivedName = fileName;
            receivedType = type;
            receivedExtensions = allowedExtensions;
            return null;
          },
    );

    await saver.save(const [1], 'template_comptes.csv');

    expect(receivedTitle, 'Enregistrer le template CSV');
    expect(receivedName, 'template_comptes.csv');
    expect(receivedType, FileType.custom);
    expect(receivedExtensions, const ['csv']);
  });

  test('ajoute l’extension CSV lorsqu’elle est absente', () async {
    String? writtenPath;
    final saver = NativeTemplateFileSaver(
      saveFile:
          ({
            required dialogTitle,
            required fileName,
            required type,
            required allowedExtensions,
          }) async => 'C:\\imports\\template_comptes',
      writeBytes: (path, bytes) async => writtenPath = path,
    );

    await saver.save(const [1], 'template_comptes.csv');

    expect(writtenPath, 'C:\\imports\\template_comptes.csv');
  });

  test('propage une erreur d’écriture native', () async {
    final saver = NativeTemplateFileSaver(
      saveFile:
          ({
            required dialogTitle,
            required fileName,
            required type,
            required allowedExtensions,
          }) async => 'C:\\imports\\template_comptes.csv',
      writeBytes: (_, _) async => throw FileSystemException('écriture refusée'),
    );

    await expectLater(
      saver.save(const [1], 'template_comptes.csv'),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('configuration native CSV reste explicite', () {
    expect(nativeTemplateCsvSaveConfiguration.type, FileType.custom);
    expect(nativeTemplateCsvSaveConfiguration.allowedExtensions, const ['csv']);
  });
}
