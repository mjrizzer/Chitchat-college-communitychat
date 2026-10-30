import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/authentication/state/session.dart';
import '../../features/authentication/presentation/auth_screen.dart';
import '../../features/communities/presentation/communities_screen.dart';
import '../../features/communities/presentation/create_community_screen.dart';
import '../../features/chat/presentation/chat_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/moderation/presentation/blocked_users_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  bool recovery = false;
  ref.listen(authProvider, (_, next) {
    if (next.asData?.value.event == AuthChangeEvent.passwordRecovery) {
      recovery = true;
    }
    if (ref.read(clientProvider).auth.currentUser == null) {
      recovery = false;
    }
    refresh.value++;
  });
  final router = GoRouter(
    refreshListenable: refresh,
    redirect: (_, state) {
      final user = ref.read(clientProvider).auth.currentUser;
      if (user == null) {
        return state.uri.path == '/auth' ? null : '/auth';
      }
      if (recovery) {
        return state.uri.path == '/reset-password' ? null : '/reset-password';
      }
      if ([
        '/auth',
        '/auth/callback',
        '/reset-password',
      ].contains(state.uri.path)) {
        return '/';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/blocked', builder: (_, _) => const BlockedUsersScreen()),
      GoRoute(path: '/', builder: (_, _) => const CommunitiesScreen()),
      GoRoute(path: '/auth', builder: (_, _) => const AuthScreen()),
      GoRoute(
        path: '/auth/callback',
        builder: (_, _) =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
      ),
      GoRoute(
        path: '/reset-password',
        builder: (_, _) => const AuthScreen(recovery: true),
      ),
      GoRoute(path: '/spill', builder: (_, _) => const CreateCommunityScreen()),
      GoRoute(
        path: '/chat/:id',
        builder: (_, s) => ChatScreen(s.pathParameters['id']!),
      ),
      GoRoute(path: '/settings', builder: (_, _) => const ProfileScreen()),
    ],
  );
  ref.onDispose(() {
    router.dispose();
    refresh.dispose();
  });
  return router;
});
