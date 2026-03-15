/// Unified WebSocket event envelope from the backend.
class WsEvent {
  final String type;
  final int roomId;
  final Map<String, dynamic> payload;

  const WsEvent({
    required this.type,
    required this.roomId,
    required this.payload,
  });

  factory WsEvent.fromJson(Map<String, dynamic> json) {
    final payload = json['payload'];
    return WsEvent(
      type: json['type'] as String? ?? '',
      roomId: (json['roomId'] is int)
          ? json['roomId'] as int
          : int.tryParse(json['roomId']?.toString() ?? '') ?? 0,
      payload: payload is Map<String, dynamic>
          ? Map<String, dynamic>.from(payload)
          : (payload is Map ? Map<String, dynamic>.from(payload as Map) : <String, dynamic>{}),
    );
  }
}
