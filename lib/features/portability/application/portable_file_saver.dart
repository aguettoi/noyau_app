import '../domain/portability_models.dart';
import 'portable_file_saver_stub.dart'
    if (dart.library.js_interop) 'portable_file_saver_web.dart'
    as platform;

Future<void> savePortableFile(PortableFile file) => platform.save(file);
