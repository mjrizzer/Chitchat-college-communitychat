import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../authentication/state/session.dart';

abstract final class FirebaseConfiguration {
  static const enabled = bool.fromEnvironment('FIREBASE_ENABLED');
  static const options = FirebaseOptions(
    apiKey: String.fromEnvironment('FIREBASE_API_KEY'),
    appId: String.fromEnvironment('FIREBASE_APP_ID'),
    messagingSenderId: String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID'),
    projectId: String.fromEnvironment('FIREBASE_PROJECT_ID'),
  );
  static String? failure;
  static Future<void> initialize() async {
    if (!enabled) {
      return;
    }
    try {
      await Firebase.initializeApp(options: options);
      FirebaseMessaging.onBackgroundMessage(backgroundMessage);
    } catch (_) {
      failure = 'Firebase could not start. Check the public Firebase build configuration.';
    }
  }
}

@pragma('vm:entry-point')
Future<void> backgroundMessage(RemoteMessage message) async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(options: FirebaseConfiguration.options);
  }
  // Android displays the generic notification payload. Private content is fetched
  // only after foreground navigation, authenticated through Supabase RLS.
}

final pushServiceProvider = Provider<PushService>((ref) {
  final service = PushService(ref.watch(clientProvider));
  ref.onDispose(service.dispose);
  ref.listen(authProvider, (_, next) {
    if (next.asData?.value.session != null) {
      unawaited(service.syncSafely());
    }
  });
  return service;
});

class PushService {
  PushService(this.client);
  final SupabaseClient client;
  StreamSubscription<String>? refresh;
  String? token;
  String? failure;
  bool get available =>
      FirebaseConfiguration.enabled && FirebaseConfiguration.failure == null;
  Future<void> enable() async {
    if (!available) {
      throw StateError(
        FirebaseConfiguration.failure ??
            'Firebase is not configured in this build.',
      );
    }
    final settings = await FirebaseMessaging.instance.requestPermission();
    if (settings.authorizationStatus != AuthorizationStatus.authorized &&
        settings.authorizationStatus != AuthorizationStatus.provisional) {
      throw StateError('Notifications are disabled in Android settings.');
    }
    await FirebaseMessaging.instance.setAutoInitEnabled(true);
    await sync();
  }

  Future<void> syncSafely() async {
    try {
      await sync();
      failure = null;
    } catch (_) {
      failure = 'Could not register this device. Retry Enable notifications.';
    }
  }

  Future<void> sync() async {
    if (!available || client.auth.currentUser == null) {
      return;
    }
    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    if (settings.authorizationStatus != AuthorizationStatus.authorized &&
        settings.authorizationStatus != AuthorizationStatus.provisional) {
      return;
    }
    final p = await client
        .from('profiles')
        .select('push_enabled')
        .eq('id', client.auth.currentUser!.id)
        .single();
    if (p['push_enabled'] != true) {
      return;
    }
    refresh ??= FirebaseMessaging.instance.onRegistered.listen(
      (t) => unawaited(registerSafely(t)),
    );
    await FirebaseMessaging.instance.register();
  }

  Future<void> register(String next) async {
    if (client.auth.currentUser == null) {
      return;
    }
    if (token != null && token != next) {
      await client.rpc('unregister_device', params: {'p_token': token});
    }
    await client.rpc('register_device', params: {'p_token': next});
    token = next;
    await (await SharedPreferences.getInstance()).setString(
      'chitchat_device_fid',
      next,
    );
  }

  Future<void> registerSafely(String next) async {
    try {
      await register(next);
    } catch (_) {
      failure = 'Token refresh failed; retry notification registration.';
    }
  }

  Future<void> disable() async {
    await refresh?.cancel();
    refresh = null;
    if (available) {
      final prefs = await SharedPreferences.getInstance();
      final current = token ?? prefs.getString('chitchat_device_fid');
      if (current != null && client.auth.currentUser != null) {
        await client.rpc('unregister_device', params: {'p_token': current});
      }
      await FirebaseMessaging.instance.setAutoInitEnabled(false);
      await FirebaseMessaging.instance.unregister();
      await prefs.remove('chitchat_device_fid');
    }
    token = null;
  }

  Future<void> signOut() async {
    await disable();
    await client.auth.signOut();
  }

  void dispose() {
    unawaited(refresh?.cancel());
  }
}

class PushListener extends ConsumerStatefulWidget {
  const PushListener({super.key, required this.router, required this.child});
  final GoRouter router;
  final Widget child;
  @override
  ConsumerState<PushListener> createState() => _PushListenerState();
}

class _PushListenerState extends ConsumerState<PushListener> {
  StreamSubscription<RemoteMessage>? foreground, opened;
  @override
  void initState() {
    super.initState();
    if (FirebaseConfiguration.enabled &&
        FirebaseConfiguration.failure == null) {
      foreground = FirebaseMessaging.onMessage.listen((m) {
        if (mounted && ref.read(clientProvider).auth.currentUser != null) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(
              content: const Text('New activity in ChitChat'),
              action: SnackBarAction(
                label: 'Open',
                onPressed: () => navigate(m),
              ),
            ),
          );
        }
      });
      opened = FirebaseMessaging.onMessageOpenedApp.listen(navigate);
      unawaited(
        FirebaseMessaging.instance.getInitialMessage().then((m) {
          if (m != null && mounted) {
            WidgetsBinding.instance.addPostFrameCallback((_) => navigate(m));
          }
        }),
      );
      unawaited(ref.read(pushServiceProvider).syncSafely());
    }
  }

  void navigate(RemoteMessage m) {
    if (!mounted || ref.read(clientProvider).auth.currentUser == null) {
      return;
    }
    final channel = m.data['room_id'];
    final uuid = RegExp(r'^[0-9a-fA-F-]{36}$');
    if (channel != null && uuid.hasMatch(channel)) {
      widget.router.go('/chat/$channel');
    } else {
      widget.router.go('/');
    }
  }

  @override
  void dispose() {
    unawaited(foreground?.cancel());
    unawaited(opened?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
