import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/environment.dart';
import '../core/routing/router.dart';
import '../core/theme/app_theme.dart';
import '../core/config/setup_screen.dart';
import '../features/notifications/repositories/push_service.dart';

final themeModeProvider = NotifierProvider<ThemeModeState, ThemeMode>(
  ThemeModeState.new,
);

class ThemeModeState extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.system;
  void set(ThemeMode mode) => state = mode;
}

class ChitChatApp extends ConsumerWidget {
  const ChitChatApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(configurationRevisionProvider);
    final light = AppTheme.build(Brightness.light);
    final dark = AppTheme.build(Brightness.dark);
    if (!Environment.configured) {
      return MaterialApp(
        title: 'ChitChat',
        theme: light,
        darkTheme: dark,
        home: const SetupScreen(),
      );
    }
    return MaterialApp.router(
      title: 'ChitChat',
      debugShowCheckedModeBanner: false,
      theme: light,
      darkTheme: dark,
      themeMode: ref.watch(themeModeProvider),
      routerConfig: ref.watch(routerProvider),
      builder: (context, child) => PushListener(
        router: ref.watch(routerProvider),
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}
