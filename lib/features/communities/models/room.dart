class ChatRoom {
  const ChatRoom({
    required this.id,
    required this.name,
    required this.isLounge,
    this.expiresAt,
  });
  final String id, name;
  final bool isLounge;
  final DateTime? expiresAt;
  factory ChatRoom.fromJson(Map<String, dynamic> json) => ChatRoom(
    id: json['id'],
    name: json['name'],
    isLounge: json['is_lounge'],
    expiresAt: json['expires_at'] == null
        ? null
        : DateTime.parse(json['expires_at']),
  );
}
