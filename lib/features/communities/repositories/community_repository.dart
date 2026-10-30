import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../authentication/state/session.dart';
import '../models/room.dart';

const loungeId = '00000000-0000-4000-8000-000000000001';
final roomsProvider = FutureProvider.autoDispose<List<ChatRoom>>((ref) {
  final timer = Timer(const Duration(seconds: 15), () => ref.invalidateSelf());
  ref.onDispose(timer.cancel);
  return ref
      .watch(clientProvider)
      .from('rooms')
      .select()
      .order('created_at', ascending: false)
      .limit(100)
      .then((rows) => rows.map(ChatRoom.fromJson).toList());
});
final roomProvider = FutureProvider.autoDispose.family<ChatRoom?, String>((
  ref,
  id,
) async {
  final c = ref.watch(clientProvider);
  final json = await c.from('rooms').select().eq('id', id).maybeSingle();
  return json == null ? null : ChatRoom.fromJson(json);
});
final clockOffsetProvider = FutureProvider<Duration>((ref) async {
  final server = await ref.watch(clientProvider).rpc('server_time') as String;
  return DateTime.parse(server).difference(DateTime.now().toUtc());
});
