class ChatMessage {
  final int id;
  final String username;
  final String text;
  final DateTime timestamp;
  final bool isRead;
  final int? replyToId;
  final String? imageUrl;
  final int? editedAt;
  final int? deletedAt;
  final Map<String, int>? reactions;

  ChatMessage({
    required this.id,
    required this.username,
    required this.text,
    required this.timestamp,
    required this.isRead,
    this.replyToId,
    this.imageUrl,
    this.editedAt,
    this.deletedAt,
    this.reactions,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final ts = json['timestamp'];
    final editedAt = json['edited_at'];
    final deletedAt = json['deleted_at'];
    Map<String, int>? reactions;
    final r = json['reactions'];
    if (r is Map) {
      reactions = <String, int>{};
      for (final e in (r as Map).entries) {
        final v = e.value;
        if (v is int) {
          reactions[e.key.toString()] = v;
        } else if (v != null) {
          final n = int.tryParse(v.toString());
          if (n != null) reactions[e.key.toString()] = n;
        }
      }
    }
    return ChatMessage(
      id: json['id'] as int? ?? 0,
      username: json['username'] as String? ?? '',
      text: (json['text'] as String?) ?? '',
      timestamp: ts != null && ts.toString().trim().isNotEmpty
          ? DateTime.tryParse(ts.toString()) ?? DateTime.now()
          : DateTime.now(),
      isRead: (json['is_read'] as bool?) ?? false,
      replyToId: json['reply_to_id'] as int?,
      imageUrl: json['image_url'] as String?,
      editedAt: editedAt is int
          ? editedAt
          : (editedAt != null ? int.tryParse(editedAt.toString()) : null),
      deletedAt: deletedAt is int
          ? deletedAt
          : (deletedAt != null ? int.tryParse(deletedAt.toString()) : null),
      reactions: reactions,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'text': text,
      'timestamp': timestamp.toIso8601String(),
      'is_read': isRead,
      'reply_to_id': replyToId,
      'image_url': imageUrl,
      'edited_at': editedAt,
      'deleted_at': deletedAt,
      if (reactions != null) 'reactions': reactions,
    };
  }

  ChatMessage copyWith({
    int? id,
    String? username,
    String? text,
    DateTime? timestamp,
    bool? isRead,
    int? replyToId,
    String? imageUrl,
    int? editedAt,
    int? deletedAt,
    Map<String, int>? reactions,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      username: username ?? this.username,
      text: text ?? this.text,
      timestamp: timestamp ?? this.timestamp,
      isRead: isRead ?? this.isRead,
      replyToId: replyToId ?? this.replyToId,
      imageUrl: imageUrl ?? this.imageUrl,
      editedAt: editedAt ?? this.editedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      reactions: reactions ?? this.reactions,
    );
  }
}
