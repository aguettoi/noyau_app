import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/noyau_app.dart';
import 'core/config/app_config.dart';
import 'core/data/supabase_bootstrap.dart';
import 'core/platform/native_notification_adapter.dart';
import 'core/platform/platform_link_adapter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeSupabase(const AppConfig.fromEnvironment());
  runApp(const ProviderScope(child: NoyauApp()));
  unawaited(
    NativeNotificationAdapter.instance.initialize().catchError((_) {}),
  );
  unawaited(PlatformLinkAdapter.instance.initialize().catchError((_) {}));
}
