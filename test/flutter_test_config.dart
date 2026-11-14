import 'dart:async';
import 'flutter_test_config_stub.dart'
    if (dart.library.io) 'flutter_test_config_io.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  configureGoldenComparator();
  await testMain();
}
