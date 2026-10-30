import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app.dart';
import 'core/config/environment.dart';
import 'features/notifications/repositories/push_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Environment.load();
  await FirebaseConfiguration.initialize();
  if (Environment.configured) {
    await Supabase.initialize(
      url: Environment.url,
      publishableKey: Environment.key,
    );
  }
  runApp(const ProviderScope(child: ChitChatApp()));
}
