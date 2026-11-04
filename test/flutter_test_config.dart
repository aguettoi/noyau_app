import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final comparator = goldenFileComparator;
  if (Platform.isWindows && comparator is LocalFileComparator) {
    goldenFileComparator = _WindowsRetryingGoldenComparator(comparator.basedir);
  }
  await testMain();
}

/// Windows can briefly retain a read lock on PNGs after another Flutter test
/// process exits. Retrying the same immutable read keeps golden expectations
/// strict while avoiding a false failure caused solely by ERROR_ACCESS_DENIED.
class _WindowsRetryingGoldenComparator extends LocalFileComparator {
  _WindowsRetryingGoldenComparator(Uri basedir)
    : super(basedir.resolve('flutter_test_config.dart'));

  @override
  Future<List<int>> getGoldenBytes(Uri golden) async {
    Object? lastError;
    for (var attempt = 0; attempt < 8; attempt += 1) {
      try {
        return await super.getGoldenBytes(golden);
      } on FileSystemException catch (error) {
        lastError = error;
        if (error.osError?.errorCode != 5) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 40 * (attempt + 1)));
      }
    }
    throw lastError!;
  }
}
