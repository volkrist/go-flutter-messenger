import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../config.dart';
import '../models/ws_event.dart';

/// Connection status for UI (e.g. banner, resync trigger).
enum ConnectionStatus {
  connecting,
  connected,
  disconnected,
  reconnecting,
}

/// Single WebSocket per user. All rooms are served through one connection.
/// Supports auto-reconnect on drop; manual disconnect() stops reconnect.
class ChatService {
  ChatService({String? wsBaseUrl}) : wsBaseUrl = wsBaseUrl ?? backendWsUrl;
  final String wsBaseUrl;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  String? _currentToken;
  bool _manuallyDisconnected = false;
  bool _isConnecting = false;
  Timer? _reconnectTimer;

  final StreamController<WsEvent> _controller = StreamController<WsEvent>.broadcast();
  final StreamController<ConnectionStatus> _statusController = StreamController<ConnectionStatus>.broadcast();

  Stream<WsEvent> get events => _controller.stream;
  Stream<ConnectionStatus> get connectionStatus => _statusController.stream;

  /// Connects with [token]. No-op if already connected with the same token or connection in progress (avoids duplicate socket).
  void connectWithToken(String token) {
    if (_isConnecting) return;
    if (_channel != null && _currentToken == token) return;
    disconnect();
    _manuallyDisconnected = false;
    _currentToken = token;
    _doConnect();
  }

  void _doConnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _isConnecting = true;
    _statusController.add(ConnectionStatus.connecting);
    final token = _currentToken!;
    final uri = Uri.parse('$wsBaseUrl/ws').replace(
      queryParameters: {'token': token},
    );
    _channel = WebSocketChannel.connect(uri);
    _sub = _channel!.stream.listen(
      (data) {
        try {
          final json = jsonDecode(data as String) as Map<String, dynamic>;
          _controller.add(WsEvent.fromJson(json));
        } catch (_) {}
      },
      onError: (Object e) {
        _controller.addError(e);
        _onConnectionLost();
      },
      onDone: () => _onConnectionLost(),
      cancelOnError: false,
    );
    _statusController.add(ConnectionStatus.connected);
    _isConnecting = false;
  }

  void _onConnectionLost() {
    _sub?.cancel();
    _channel?.sink.close();
    _channel = null;
    _sub = null;
    _isConnecting = false;
    if (_manuallyDisconnected || _currentToken == null) {
      _currentToken = null;
      _statusController.add(ConnectionStatus.disconnected);
      return;
    }
    _statusController.add(ConnectionStatus.reconnecting);
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 2), () {
      _reconnectTimer = null;
      if (_manuallyDisconnected || _currentToken == null) return;
      _doConnect();
    });
  }

  void sendMessage(
    int roomId,
    String text, {
    int? replyToId,
    String? imageUrl,
  }) {
    final payload = <String, dynamic>{'text': text};

    if (replyToId != null) {
      payload['reply_to_id'] = replyToId;
    }

    if (imageUrl != null && imageUrl.isNotEmpty) {
      payload['image_url'] = imageUrl;
    }

    _channel?.sink.add(jsonEncode({
      'type': 'message',
      'roomId': roomId,
      'payload': payload,
    }));
  }

  void editMessage(int roomId, int messageId, String text) {
    _channel?.sink.add(jsonEncode({
      'type': 'message_edit',
      'roomId': roomId,
      'payload': {
        'message_id': messageId,
        'text': text,
      },
    }));
  }

  void deleteMessage(int roomId, int messageId) {
    _channel?.sink.add(jsonEncode({
      'type': 'message_delete',
      'roomId': roomId,
      'payload': {'message_id': messageId},
    }));
  }

  void sendReaction(int roomId, int messageId, String reaction) {
    _channel?.sink.add(jsonEncode({
      'type': 'message_reaction',
      'roomId': roomId,
      'payload': {
        'message_id': messageId,
        'reaction': reaction,
      },
    }));
  }

  void sendTyping(int roomId, bool isTyping) {
    final event = {
      'type': 'typing',
      'roomId': roomId,
      'payload': {'isTyping': isTyping},
    };
    _channel?.sink.add(jsonEncode(event));
  }

  /// Stops the connection and any reconnect. Does not start reconnect.
  void disconnect() {
    _manuallyDisconnected = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _isConnecting = false;
    _sub?.cancel();
    _channel?.sink.close();
    _channel = null;
    _sub = null;
    _currentToken = null;
    _statusController.add(ConnectionStatus.disconnected);
  }
}
