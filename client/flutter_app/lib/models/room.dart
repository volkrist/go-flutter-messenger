class Room {
  final int id;
  final String name;
  final String type;
  final String createdAt;
  final String lastMessageText;
  final String lastMessageTimestamp;
  final String otherUsername;
  final int unreadCount;
  final int onlineCount;

  const Room({
    required this.id,
    required this.name,
    required this.type,
    required this.createdAt,
    required this.lastMessageText,
    required this.lastMessageTimestamp,
    this.otherUsername = '',
    this.unreadCount = 0,
    this.onlineCount = 0,
  });

  bool get isPrivate => type == 'private';

  factory Room.fromJson(Map<String, dynamic> json) {
    return Room(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      type: json['type'] as String? ?? 'group',
      createdAt: json['created_at'] as String? ?? '',
      lastMessageText: json['last_message_text'] as String? ?? '',
      lastMessageTimestamp: json['last_message_timestamp'] as String? ?? '',
      otherUsername: json['other_username'] as String? ?? '',
      unreadCount: json['unread_count'] as int? ?? 0,
      onlineCount: 0,
    );
  }

  Room copyWith({
    String? lastMessageText,
    String? lastMessageTimestamp,
    int? unreadCount,
    int? onlineCount,
  }) {
    return Room(
      id: id,
      name: name,
      type: type,
      createdAt: createdAt,
      lastMessageText: lastMessageText ?? this.lastMessageText,
      lastMessageTimestamp: lastMessageTimestamp ?? this.lastMessageTimestamp,
      otherUsername: otherUsername,
      unreadCount: unreadCount ?? this.unreadCount,
      onlineCount: onlineCount ?? this.onlineCount,
    );
  }
}
