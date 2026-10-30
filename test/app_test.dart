import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:chitchat/app/app.dart';
import 'package:chitchat/core/config/environment.dart';
import 'package:chitchat/core/widgets/common.dart';
import 'package:chitchat/features/authentication/state/session.dart';
import 'package:chitchat/features/communities/models/room.dart';
import 'package:chitchat/features/communities/repositories/community_repository.dart';
import 'package:chitchat/features/chat/models/chat_message.dart';
import 'package:chitchat/features/chat/models/message_merge.dart';

void main() {
  tearDown(() {
    Environment.url = '';
    Environment.key = '';
  });
  testWidgets('Unconfigured app opens functional setup screen', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ChitChatApp()));
    expect(find.text('Welcome to ChitChat'), findsOneWidget);
    await tester.tap(find.text('Connect & continue'));
    await tester.pump();
    expect(find.text('Enter your HTTPS Supabase URL'), findsOneWidget);
    expect(find.textContaining('Never a secret key'), findsOneWidget);
  });
  test('Public configuration refuses service credentials', () {
    String jwt(String role) =>
        'head.${base64Url.encode(utf8.encode(jsonEncode({'role': role})))}.signature';
    expect(
      Environment.isPublicKey('sb_secret_never_put_this_in_an_app'),
      isFalse,
    );
    expect(Environment.isPublicKey(jwt('service_role')), isFalse);
    expect(Environment.isPublicKey(jwt('anon')), isTrue);
    expect(Environment.isPublicKey('malformed'), isFalse);
  });
  test(
    'Authoritative realtime message replaces optimistic ID exactly once',
    () {
      final pending = ChatMessage(
        id: 'same',
        senderId: 'a',
        body: 'hello',
        createdAt: DateTime.utc(2026),
      );
      final server = ChatMessage(
        id: 'same',
        senderId: 'a',
        body: 'hello',
        createdAt: DateTime.utc(2026, 1, 1, 0, 0, 5),
      );
      final merged = mergeMessages([pending], [pending], [server]);
      expect(merged, hasLength(1));
      expect(merged.single.createdAt, server.createdAt);
    },
  );
  test('Pagination overlap deduplicates IDs and orders deterministically', () {
    ChatMessage m(String id) => ChatMessage(
      id: id,
      senderId: 'a',
      body: id,
      createdAt: DateTime.utc(2026),
    );
    expect(
      mergeMessages([m('a'), m('b')], [], [m('b'), m('c')]).map((m) => m.id),
      ['c', 'b', 'a'],
    );
  });
  test('Initial avatars handle unicode and blank names', () {
    expect(initials(' Maya Patel '), 'MP');
    expect(initials(''), '?');
    expect(initials('👩🏽‍💻 Student'), '👩🏽‍💻S');
  });
  testWidgets(
    'Guest navigation offers lounge, Spill the Chaya and name settings',
    (tester) async {
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-public-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      await client.auth.setInitialSession(
        jsonEncode({
          'access_token': 'test-token',
          'token_type': 'bearer',
          'refresh_token': 'test-refresh',
          'expires_in': 3600,
          'user': {
            'id': '10000000-0000-4000-8000-000000000001',
            'app_metadata': {},
            'user_metadata': {},
            'aud': 'authenticated',
            'created_at': '2026-01-01T00:00:00Z',
            'is_anonymous': true,
          },
        }),
      );
      Environment.url = 'https://example.supabase.co';
      Environment.key = 'test';
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            clientProvider.overrideWithValue(client),
            authProvider.overrideWith((ref) => const Stream.empty()),
            roomsProvider.overrideWith(
              (ref) async => const [
                ChatRoom(id: loungeId, name: 'Community chat', isLounge: true),
              ],
            ),
            profileProvider.overrideWith(
              (ref) async => {'name': 'Guest', 'push_enabled': true},
            ),
          ],
          child: const ChitChatApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Community chat'), findsOneWidget);
      await tester.tap(find.text('Spill the Chaya'));
      await tester.pumpAndSettle();
      expect(find.text('Create & start chatting'), findsOneWidget);
      await tester.tap(find.text('Create & start chatting'));
      await tester.pump();
      expect(find.text('Use at least 3 characters'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Your name and notifications'));
      await tester.pumpAndSettle();
      expect(find.text('Change display name'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      unawaited(client.dispose());
    },
  );
}
