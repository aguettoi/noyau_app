import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';

Future<void> initializeSupabase(AppConfig config) async {
  if (!config.isSupabaseConfigured) {
    return;
  }

  await Supabase.initialize(
    url: config.supabaseUrl,
    publishableKey: config.supabasePublishableKey,
  );
}
