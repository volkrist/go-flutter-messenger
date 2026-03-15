import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/room.dart';
import '../models/user.dart';
import '../models/ws_event.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';
import '../services/push_service.dart';
import '../utils/format_time.dart';
import '../utils/app_router.dart';
import '../widgets/chat_list_item.dart';
import 'chat_screen.dart';
import 'profile_screen.dart';
import 'settings_screen.dart';
import 'user_search_screen.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key, required this.currentUser});

  final User currentUser;

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final _api = ApiService();
  final _authService = AuthService();
  final _chatService = ChatService();
  final TextEditingController _searchController = TextEditingController();

  late User _currentUser;
  List<Room> _rooms = [];
  bool _loading = true;
  String? _error;
  String _searchQuery = '';

  /// Set when a chat is open so unread is not incremented for that room. Cleared when returning to list.
  int? _activeRoomId;
  StreamSubscription<WsEvent>? _eventSub;
  StreamSubscription<ConnectionStatus>? _statusSub;
  ConnectionStatus? _lastConnectionStatus;
  bool _pushInitialized = false;

  @override
  void initState() {
    super.initState();
    _currentUser = widget.currentUser;
    WidgetsBinding.instance.addPostFrameCallback((_) => _initConnection());
  }

  Future<List<Room>> _loadRoomsForPush() async {
    await _loadRooms();
    return _rooms;
  }

  Future<void> _initPushIfNeeded() async {
    if (_pushInitialized) return;

    PushService.instance.bindContext(
      currentUser: _currentUser,
      loadRooms: _loadRoomsForPush,
      openChat: _openChatFromPush,
    );

    try {
      await PushService.instance.registerTokenForUser(_currentUser.username);
      _pushInitialized = true;
    } catch (e) {
      debugPrint('push init error: $e');
    }
  }

  void _openChatFromPush(Room room) {
    if (!mounted) return;
    setState(() {
      _activeRoomId = room.id;
      final idx = _rooms.indexWhere((r) => r.id == room.id);
      if (idx >= 0) _rooms[idx] = _rooms[idx].copyWith(unreadCount: 0);
    });
    rootNavigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          username: _currentUser.username,
          roomId: room.id,
          roomDisplayName: room.name,
          isPrivate: room.isPrivate,
          chatService: _chatService,
        ),
      ),
    ).then((_) {
      if (mounted) {
        setState(() => _activeRoomId = null);
        _loadRooms();
      }
    });
  }

  Future<void> _initConnection() async {
    final token = await _authService.getSavedToken();
    if (token == null || token.isEmpty || !mounted) return;
    _chatService.connectWithToken(token);
    _eventSub = _chatService.events.listen(_onWsEvent);
    _statusSub = _chatService.connectionStatus.listen(_onConnectionStatus);
    // FCM до загрузки чатов — токен не зависит от API чатов
    if (mounted) await _initPushIfNeeded();
    if (mounted) await _loadRooms();
  }

  void _onConnectionStatus(ConnectionStatus status) {
    if (!mounted) return;
    if (_lastConnectionStatus == ConnectionStatus.reconnecting && status == ConnectionStatus.connected) {
      _loadRooms();
    }
    setState(() => _lastConnectionStatus = status);
  }

  String _formatRoomTime(Room room) => formatTimeHHmm(room.lastMessageTimestamp);

  String _normalize(String value) {
    return value.trim().toLowerCase();
  }

  List<Room> _filterRooms(List<Room> rooms) {
    final query = _normalize(_searchQuery);
    if (query.isEmpty) return rooms;

    return rooms.where((room) {
      final name = _normalize(room.name);
      final lastMessage = _normalize(room.lastMessageText);
      final otherUsername = _normalize(room.otherUsername);
      return name.contains(query) ||
          lastMessage.contains(query) ||
          otherUsername.contains(query);
    }).toList();
  }

  Future<void> _openCreateChatSheet() async {
    final theme = Theme.of(context);

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.person_outline),
                  ),
                  title: const Text('Приватный чат'),
                  subtitle: const Text('Создать чат один на один'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _createPrivateChat();
                  },
                ),
                ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.groups_outlined),
                  ),
                  title: const Text('Групповой чат'),
                  subtitle: const Text('Создать чат для нескольких участников'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _createGroupChat();
                  },
                ),
                const SizedBox(height: 8),
                Divider(color: theme.dividerColor, height: 1),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _eventSub?.cancel();
    _statusSub?.cancel();
    _chatService.disconnect();
    super.dispose();
  }

  void _onWsEvent(WsEvent event) {
    if (!mounted) return;
    if (event.type == 'message') {
      final text = event.payload['text'] as String? ?? '';
      final timestamp = event.payload['timestamp'] as String? ?? '';
      if (text.isEmpty) return;
      setState(() {
        _updateRoomLastMessage(
          event.roomId,
          text,
          timestamp,
          incrementUnread: event.roomId != _activeRoomId,
        );
      });
      return;
    }
    if (event.type == 'presence') {
      final users = (event.payload['users'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
      // Exclude current user: for private = 0 or 1 (other participant), for group = others in room.
      final others = users.where((u) => u != _currentUser.username).length;
      setState(() => _updateRoomOnlineCount(event.roomId, others));
    }
  }

  void _updateRoomLastMessage(int roomId, String text, String timestamp, {required bool incrementUnread}) {
    final idx = _rooms.indexWhere((r) => r.id == roomId);
    if (idx < 0) return;
    final r = _rooms[idx];
    _rooms[idx] = r.copyWith(
      lastMessageText: text,
      lastMessageTimestamp: timestamp,
      unreadCount: incrementUnread ? r.unreadCount + 1 : r.unreadCount,
    );
    _rooms.sort((a, b) => b.lastMessageTimestamp.compareTo(a.lastMessageTimestamp));
  }

  void _updateRoomOnlineCount(int roomId, int count) {
    final idx = _rooms.indexWhere((r) => r.id == roomId);
    if (idx < 0) return;
    _rooms[idx] = _rooms[idx].copyWith(onlineCount: count);
  }

  Future<void> _loadRooms() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _api.getRooms(_currentUser.username);
      if (!mounted) return;
      final prev = _rooms;
      final merged = list.map((r) {
        Room? old;
        for (final o in prev) {
          if (o.id == r.id) {
            old = o;
            break;
          }
        }
        if (old == null) return r;
        return r.copyWith(onlineCount: old.onlineCount);
      }).toList();
      setState(() {
        _rooms = merged;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _createGroupChat() async {
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final c = TextEditingController();
        return AlertDialog(
          title: const Text('New group chat'),
          content: TextField(
            controller: c,
            decoration: const InputDecoration(
              labelText: 'Chat name',
              hintText: 'e.g. General, Work, Friends',
              border: OutlineInputBorder(),
            ),
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            onSubmitted: (_) => Navigator.of(ctx).pop(c.text.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(c.text.trim()),
              child: const Text('Create'),
            ),
          ],
        );
      },
    );
    if (name == null || name.isEmpty) return;

    try {
      final room = await _api.createGroupRoom(name, _currentUser.username);
      if (!mounted) return;

      await _loadRooms();
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chat created')),
      );

      _openChat(room);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _createPrivateChat() async {
    final room = await Navigator.of(context).push<Room>(
      MaterialPageRoute(
        builder: (_) => UserSearchScreen(
          currentUser: _currentUser,
        ),
      ),
    );

    if (room == null || !mounted) return;

    await _loadRooms();
    if (!mounted) return;
    _openChat(room);
  }

  void _openChat(Room room) {
    setState(() {
      _activeRoomId = room.id;
      final idx = _rooms.indexWhere((r) => r.id == room.id);
      if (idx >= 0) _rooms[idx] = _rooms[idx].copyWith(unreadCount: 0);
    });
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          username: _currentUser.username,
          roomId: room.id,
          roomDisplayName: room.name,
          isPrivate: room.isPrivate,
          chatService: _chatService,
        ),
      ),
    ).then((_) {
      if (mounted) {
        setState(() => _activeRoomId = null);
        _loadRooms();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filteredRooms = _filterRooms(_rooms);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Chats'),
            if (_lastConnectionStatus != null &&
                _lastConnectionStatus != ConnectionStatus.connected)
              Text(
                'Переподключение...',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline_rounded),
            onPressed: () async {
              final updatedUser = await Navigator.of(context).push<User>(
                MaterialPageRoute(
                  builder: (_) => ProfileScreen(
                    currentUser: _currentUser,
                    onLogout: () {
                      _chatService.disconnect();
                    },
                  ),
                ),
              );
              if (updatedUser != null && mounted) {
                setState(() => _currentUser = updatedUser);
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () async {
              final updatedUser = await Navigator.of(context).push<User>(
                MaterialPageRoute(
                  builder: (_) => SettingsScreen(
                    currentUser: _currentUser,
                    onLogout: () {
                      _chatService.disconnect();
                    },
                  ),
                ),
              );
              if (updatedUser != null && mounted) {
                setState(() => _currentUser = updatedUser);
              }
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            color: theme.colorScheme.outline.withValues(alpha: 0.12),
            height: 1,
          ),
        ),
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.opaque,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 20),
                          FilledButton(
                            onPressed: _loadRooms,
                            style: FilledButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  )
                : _rooms.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.chat_bubble_outline_rounded,
                                size: 56,
                                color: theme.colorScheme.outline,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Пока нет чатов',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Создай приватный или групповой чат, чтобы начать общение.',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: _openCreateChatSheet,
                                child: const Text('Создать чат'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadRooms,
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                              child: TextField(
                                controller: _searchController,
                                onChanged: (value) {
                                  setState(() {
                                    _searchQuery = value;
                                  });
                                },
                                decoration: InputDecoration(
                                  hintText: 'Поиск по чатам',
                                  prefixIcon: const Icon(Icons.search),
                                  suffixIcon: _searchQuery.isNotEmpty
                                      ? IconButton(
                                          icon: const Icon(Icons.close),
                                          onPressed: () {
                                            _searchController.clear();
                                            setState(() {
                                              _searchQuery = '';
                                            });
                                          },
                                        )
                                      : null,
                                ),
                              ),
                            ),
                            Expanded(
                              child: filteredRooms.isEmpty
                                  ? ListView(
                                      physics:
                                          const AlwaysScrollableScrollPhysics(),
                                      children: [
                                        SizedBox(
                                          height:
                                              MediaQuery.of(context).size.height *
                                                  0.28,
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 24,
                                          ),
                                          child: Column(
                                            children: [
                                              Icon(
                                                Icons.search_off_rounded,
                                                size: 56,
                                                color: theme.colorScheme.outline,
                                              ),
                                              const SizedBox(height: 16),
                                              Text(
                                                'Ничего не найдено',
                                                style: theme.textTheme.titleMedium
                                                    ?.copyWith(
                                                      fontWeight: FontWeight.w700,
                                                    ),
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                'Попробуй изменить запрос или очистить поиск.',
                                                textAlign: TextAlign.center,
                                                style: theme.textTheme.bodyMedium
                                                    ?.copyWith(
                                                      color: theme.colorScheme
                                                          .onSurfaceVariant,
                                                    ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    )
                                  : ListView.builder(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 8,
                                      ),
                                      itemCount: filteredRooms.length,
                                      itemBuilder: (context, i) {
                                        final room = filteredRooms[i];
                                        return Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 4,
                                          ),
                                          child: Card(
                                            child: ChatListItem(
                                              title: room.name,
                                              subtitle:
                                                  room.lastMessageText.isNotEmpty
                                                      ? room.lastMessageText
                                                      : 'Нет сообщений',
                                              timeText: _formatRoomTime(room),
                                              unreadCount: room.unreadCount,
                                              isOnline: room.onlineCount > 0,
                                              secondaryStatus: room.isPrivate
                                                  ? (room.onlineCount > 0
                                                      ? 'online'
                                                      : 'offline')
                                                  : '${room.onlineCount} online',
                                              onTap: () => _openChat(room),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                            ),
                          ],
                        ),
                      ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openCreateChatSheet,
        child: const Icon(Icons.add),
      ),
    );
  }
}
