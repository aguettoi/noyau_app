import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Windows runner registers the canonical deep-link protocol per user',
    () {
      final source = File('windows/runner/main.cpp').readAsStringSync();

      expect(source, contains('com.financielpilote.app'));
      expect(source, contains('project.set_dart_entrypoint_arguments'));
      expect(source, contains('HKEY_CURRENT_USER'));
      expect(source, contains(r'Software\\Classes\\'));
      expect(source, contains('URL Protocol'));
      expect(source, contains(r'\\shell\\open\\command'));
      expect(source, contains(r'L"\" \"%1\""'));
      expect(source, contains('SendAppLinkToInstance()'));
    },
  );
}
