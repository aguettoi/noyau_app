import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

String _sha256(String path) =>
    sha256.convert(File(path).readAsBytesSync()).toString();

void main() {
  test('native and web surfaces no longer ship Flutter placeholder branding', () {
    const brandedAssets = <String, String>{
      'assets/branding/financial_pilote_app_icon.png':
          '30e0513a988d2446010ffb893205dbb8542236543ee4d43e87e7e2cbdb732bb0',
      'web/favicon.png':
          '91d128a8813a92d6ea525edbafe07d42c0935272e12c8a73d870d1b11a9a633e',
      'web/icons/Icon-192.png':
          '47883f1ddbe6a4c771222ba164e080ad3c5f04e23e8fbd1b0f3a5c5357b9e18a',
      'web/icons/Icon-512.png':
          '1059caa64dfe80320efe00bc1d54295ba47e733eca3e6c1f51b2235aa7c7a48f',
      'web/icons/Icon-maskable-192.png':
          'd19afeb0325ae704b207f882db0c7e94bbcb308853f746d3294fa3c429afdc09',
      'web/icons/Icon-maskable-512.png':
          '6022001df027356a547f9077848c22e22f42e180bb381350f783e2fc947c2e9e',
      'windows/runner/resources/app_icon.ico':
          'dc64f56a4597b02843c4ea74d9ba4f061b243f86148767f5ce05f5713747de05',
      'android/app/src/main/res/mipmap-mdpi/ic_launcher.png':
          '2f3f76ded7ed76f8c4b319583a36fbe1d489a070429c6304bf258b4b01dfac03',
      'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png':
          '47883f1ddbe6a4c771222ba164e080ad3c5f04e23e8fbd1b0f3a5c5357b9e18a',
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png':
          '30e0513a988d2446010ffb893205dbb8542236543ee4d43e87e7e2cbdb732bb0',
    };

    for (final entry in brandedAssets.entries) {
      final path = entry.key;
      expect(File(path).existsSync(), isTrue, reason: path);
      expect(_sha256(path), entry.value, reason: path);
    }

    final manifest =
        jsonDecode(File('web/manifest.json').readAsStringSync())
            as Map<String, Object?>;
    expect(manifest['name'], 'FINANCIEL PILOTE');
    expect(manifest['theme_color'], '#163A5F');
    expect(manifest['background_color'], '#F7F8F5');
    expect(manifest.values, isNot(contains('A new Flutter project.')));

    final index = File('web/index.html').readAsStringSync();
    expect(index, contains('FINANCIEL PILOTE'));
    expect(index, contains('#163A5F'));
    expect(index, isNot(contains('A new Flutter project.')));
  });
}
