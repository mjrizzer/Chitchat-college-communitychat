import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../authentication/state/session.dart';
import '../models/chat_message.dart';

final chatRepositoryProvider = Provider(
  (ref) => ChatRepository(ref.watch(clientProvider)),
);
final messagesProvider = StreamProvider.autoDispose
    .family<List<ChatMessage>, String>(
      (ref, id) => ref.watch(chatRepositoryProvider).watch(id),
    );
final senderProvider = FutureProvider.autoDispose.family<String, String>(
  (ref, id) async =>
      (await ref
          .watch(clientProvider)
          .from('profiles')
          .select('name')
          .eq('id', id)
          .maybeSingle())?['name'] ??
      'Guest',
);

class ChatRepository {
  ChatRepository(this.client);
  final SupabaseClient client;
  Stream<List<ChatMessage>> watch(String room) => client
      .from('messages')
      .stream(primaryKey: ['id'])
      .eq('room_id', room)
      .order('created_at', ascending: false)
      .limit(50)
      .map((rows) => rows.map(ChatMessage.fromJson).toList());
  Future<List<ChatMessage>> older(String room, ChatMessage before) async =>
      (await client
              .from('messages')
              .select()
              .eq('room_id', room)
              .or(
                'created_at.lt.${before.createdAt.toUtc().toIso8601String()},and(created_at.eq.${before.createdAt.toUtc().toIso8601String()},id.lt.${before.id})',
              )
              .order('created_at', ascending: false)
              .order('id', ascending: false)
              .limit(50))
          .map(ChatMessage.fromJson)
          .toList();
  Future<void> send(String room, ChatMessage message) async {
    final existing = await client
        .from('messages')
        .select('id,room_id,sender_id,body')
        .eq('id', message.id)
        .maybeSingle();
    if (existing != null) {
      if (existing['room_id'] != room ||
          existing['sender_id'] != client.auth.currentUser!.id ||
          existing['body'] != message.body) {
        throw StateError('Message identifier conflict.');
      }
      return;
    }
    try {
      await client.from('messages').insert({
        'id': message.id,
        'room_id': room,
        'body': message.body,
      });
    } on PostgrestException catch (e) {
      if (e.code != '23505') {
        rethrow;
      }
      final confirmed = await client
          .from('messages')
          .select('sender_id,body,room_id')
          .eq('id', message.id)
          .single();
      if (confirmed['sender_id'] != message.senderId ||
          confirmed['body'] != message.body ||
          confirmed['room_id'] != room) {
        rethrow;
      }
    }
  }
}
