import 'chat_message.dart';

List<ChatMessage> mergeMessages(
  Iterable<ChatMessage> older,
  Iterable<ChatMessage> pending,
  Iterable<ChatMessage> authoritative,
) {
  final result = <String, ChatMessage>{
    for (final m in older) m.id: m,
    for (final m in pending) m.id: m,
    for (final m in authoritative) m.id: m,
  };
  return result.values.toList()..sort((a, b) {
    final time = b.createdAt.compareTo(a.createdAt);
    return time == 0 ? b.id.compareTo(a.id) : time;
  });
}
