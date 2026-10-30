class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.body,
    required this.createdAt,
    this.replyTo,
    this.editedAt,
    this.imagePath,
  });
  final String id, senderId, body;
  final DateTime createdAt;
  final String? replyTo;
  final String? imagePath;
  final DateTime? editedAt;
  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    id: json['id'],
    senderId: json['sender_id'],
    body: json['body'],
    createdAt: DateTime.parse(json['created_at']),
    replyTo: json['reply_to'],
    imagePath: json['image_path'],
    editedAt: json['edited_at'] == null
        ? null
        : DateTime.parse(json['edited_at']),
  );
}
