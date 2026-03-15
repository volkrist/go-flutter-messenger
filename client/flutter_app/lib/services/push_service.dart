import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../firebase_options.dart';
import '../models/room.dart';
import '../models/user.dart';
import '../services/api_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

class PushService {
  PushService._();

  static final PushService instance = PushService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  bool _localInitialized = false;

  Future<List<Room>> Function()? _loadRooms;
  void Function(Room room)? _openChat;
  int? _pendingRoomId;

  static const AndroidNotificationChannel _androidChannel =
      AndroidNotificationChannel(
    'chat_messages',
    'Chat messages',
    description: 'Notifications for new chat messages',
    importance: Importance.high,
  );

  Future<void> init() async {
    if (_initialized) return;
    await _initLocalNotifications();
    await _requestPermissions();
    await _setupMessageHandlers();
    _initialized = true;
  }

  void bindContext({
    required User currentUser,
    required Future<List<Room>> Function() loadRooms,
    required void Function(Room room) openChat,
  }) {
    _loadRooms = loadRooms;
    _openChat = openChat;
    final pending = _pendingRoomId;
    if (pending != null) {
      _pendingRoomId = null;
      _openChatByRoomId(pending);
    }
  }

  /// Registers FCM token with backend. Call after login when JWT is saved.
  Future<void> registerTokenForUser(String username) async {
    String? token;
    for (var i = 0; i < 5; i++) {
      token = await _messaging.getToken();
      if (token != null && token.trim().isNotEmpty) break;
      await Future<void>.delayed(Duration(seconds: i == 0 ? 1 : 2));
    }
    if (token == null || token.trim().isEmpty) {
      debugPrint(
        'FCM: getToken() empty. Установи google-services.json, package name в Firebase, запуск на устройстве с Google Play.',
      );
      return;
    }
    try {
      await ApiService().registerDeviceToken(
        username: username,
        token: token,
        platform: Platform.isIOS ? 'ios' : 'android',
      );
      debugPrint('FCM: token зарегистрирован на сервере для $username');
    } catch (e, st) {
      debugPrint('FCM: регистрация на сервере не удалась: $e\n$st');
    }
    _messaging.onTokenRefresh.listen((newToken) async {
      if (newToken.trim().isEmpty) return;
      try {
        await ApiService().registerDeviceToken(
          username: username,
          token: newToken,
          platform: Platform.isIOS ? 'ios' : 'android',
        );
        debugPrint('FCM: обновлённый token отправлен на сервер');
      } catch (e) {
        debugPrint('FCM: refresh token send failed: $e');
      }
    });
  }

  Future<void> _requestPermissions() async {
    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    if (Platform.isIOS) {
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    }
  }

  Future<void> _initLocalNotifications() async {
    if (_localInitialized) return;
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) async {
        final payload = response.payload;
        if (payload == null || payload.isEmpty) return;
        final roomId = int.tryParse(payload);
        if (roomId == null) return;
        await _openChatByRoomId(roomId);
      },
    );
    if (Platform.isAndroid) {
      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_androidChannel);
    }
    _localInitialized = true;
  }

  Future<void> _setupMessageHandlers() async {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      await _showForegroundNotification(message);
    });
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) async {
      await _handleRemoteMessage(message);
    });
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      await _handleRemoteMessage(initialMessage);
    }
  }

  Future<void> _showForegroundNotification(RemoteMessage message) async {
    final roomId = message.data['room_id'];
    final sender = message.data['sender_username'] ?? 'Новое сообщение';
    final text = message.data['message_text'] ?? '';
    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'Сообщение от $sender',
      text,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'chat_messages',
          'Chat messages',
          channelDescription: 'Notifications for new chat messages',
          importance: Importance.max,
          priority: Priority.high,
        ),
      ),
      payload: roomId,
    );
  }

  Future<void> _handleRemoteMessage(RemoteMessage message) async {
    final roomIdRaw = message.data['room_id'];
    final roomId = int.tryParse(roomIdRaw ?? '');
    if (roomId == null) return;
    await _openChatByRoomId(roomId);
  }

  Future<void> _openChatByRoomId(int roomId) async {
    final loadRooms = _loadRooms;
    final openChat = _openChat;
    if (loadRooms == null || openChat == null) {
      _pendingRoomId = roomId;
      return;
    }

    List<Room> rooms;
    try {
      rooms = await loadRooms();
    } catch (_) {
      return;
    }
    Room? target;
    try {
      target = rooms.firstWhere((r) => r.id == roomId);
    } catch (_) {
      target = null;
    }
    if (target == null) return;
    openChat(target);
  }
}
