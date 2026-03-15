import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/message.dart';
import '../models/ws_event.dart';
import '../services/api_service.dart';
import '../services/chat_service.dart';
import '../utils/format_time.dart';
import '../widgets/chat_input.dart';
import '../widgets/connection_banner.dart';
import '../widgets/date_separator.dart';
import '../widgets/message_bubble.dart';
import 'chat_search_screen.dart';
import 'group_members_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.username,
    required this.roomId,
    required this.roomDisplayName,
    this.isPrivate = false,
    required this.chatService,
  });

  final String username;
  final int roomId;
  final String roomDisplayName;
  final bool isPrivate;
  final ChatService chatService;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  final _api = ApiService();
  final ImagePicker _imagePicker = ImagePicker();

  late String _roomDisplayName;

  bool _actionLoading = false;
  bool _loadingHistory = true;
  File? _selectedImage;
  bool _isUploadingImage = false;

  List<String> _onlineUsers = [];
  ChatMessage? _replyToMessage;

  /// For private chat: other participant's last seen (ISO string).
  /// Null if online or unknown.
  String? _lastSeen;

  String? _typingUser;
  Timer? _typingClearTimer;
  Timer? _typingSendTimer;
  bool _typingSent = false;

  StreamSubscription<WsEvent>? _eventSub;
  StreamSubscription<ConnectionStatus>? _statusSub;
  ConnectionStatus _connectionStatusValue = ConnectionStatus.connected;

  int? _highlightedMessageId;

  bool _isNearBottom = true;
  int _unseenMessagesCount = 0;

  @override
  void initState() {
    super.initState();
    _roomDisplayName = widget.roomDisplayName;
    _scrollController.addListener(_onScroll);
    _loadHistoryThenSubscribe();
  }

  Future<void> _loadHistoryThenSubscribe() async {
    _eventSub?.cancel();
    _statusSub?.cancel();

    if (mounted) {
      setState(() => _loadingHistory = true);
    }

    try {
      final list = await _api.getMessages(widget.roomId, widget.username);
      if (!mounted) return;

      setState(() {
        _messages
          ..clear()
          ..addAll(list);
        _loadingHistory = false;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom();
      });
      await _api.markMessagesRead(widget.roomId, widget.username);
    } catch (_) {
      if (mounted) {
        setState(() => _loadingHistory = false);
      }
    }

    if (!mounted) return;

    _eventSub = widget.chatService.events
        .where((e) => e.roomId == widget.roomId)
        .listen(_onWsEvent);

    _statusSub = widget.chatService.connectionStatus.listen((status) {
      if (!mounted) return;

      final wasReconnecting =
          _connectionStatusValue == ConnectionStatus.reconnecting;

      setState(() => _connectionStatusValue = status);

      if (wasReconnecting && status == ConnectionStatus.connected) {
        _refreshHistory();
      }
    });
  }

  Future<void> _refreshHistory() async {
    try {
      final list = await _api.getMessages(widget.roomId, widget.username);
      if (!mounted) return;

      setState(() {
        _messages
          ..clear()
          ..addAll(list);
      });

      _scrollToBottom();
      await _api.markMessagesRead(widget.roomId, widget.username);
    } catch (_) {}
  }

  void _onWsEvent(WsEvent event) {
    if (!mounted) return;

    if (event.type == 'message') {
      final id = event.payload['id'] is int
          ? event.payload['id'] as int
          : int.tryParse(event.payload['id']?.toString() ?? '') ?? 0;

      final replyToId = event.payload['reply_to_id'] is int
          ? event.payload['reply_to_id'] as int?
          : (event.payload['reply_to_id'] != null
              ? int.tryParse(event.payload['reply_to_id'].toString())
              : null);

      final editedAtRaw = event.payload['edited_at'];
      final editedAt = editedAtRaw is int
          ? editedAtRaw as int?
          : (editedAtRaw != null ? int.tryParse(editedAtRaw.toString()) : null);

      final ts = event.payload['timestamp'] as String? ?? '';
      final msg = ChatMessage(
        id: id,
        username: event.payload['username'] as String? ?? '',
        text: event.payload['text'] as String? ?? '',
        timestamp: ts.isNotEmpty ? (DateTime.tryParse(ts) ?? DateTime.now()) : DateTime.now(),
        isRead: false,
        replyToId: replyToId,
        imageUrl: event.payload['image_url'] as String?,
        editedAt: editedAt,
      );

      final isMyMessage = msg.username == widget.username;

      setState(() {
        _messages.add(msg);
      });

      if (!_isNearBottom && !isMyMessage) {
        setState(() => _unseenMessagesCount += 1);
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToBottom();
        });
      }

      if (msg.username != widget.username) {
        unawaited(_api.markMessagesRead(widget.roomId, widget.username));
      }
      return;
    }

    if (event.type == 'message_edited') {
      final payload = event.payload;
      final int? id = payload['message_id'] is int
          ? payload['message_id'] as int
          : int.tryParse(payload['message_id']?.toString() ?? '');
      if (id == null) return;
      final newText = payload['text'] as String? ?? '';
      final editedAtRaw = payload['edited_at'];
      final editedAt = editedAtRaw is int
          ? editedAtRaw as int?
          : (editedAtRaw != null ? int.tryParse(editedAtRaw.toString()) : null);
      final idx = _messages.indexWhere((m) => m.id == id);
      if (idx >= 0) {
        setState(() {
          _messages[idx] = _messages[idx].copyWith(text: newText, editedAt: editedAt);
        });
      }
      return;
    }

    if (event.type == 'message_deleted') {
      final payload = event.payload;
      final int? id = payload['message_id'] is int
          ? payload['message_id'] as int
          : int.tryParse(payload['message_id']?.toString() ?? '');
      if (id == null) return;
      final deletedAtRaw = payload['deleted_at'];
      final deletedAt = deletedAtRaw is int
          ? deletedAtRaw as int?
          : (deletedAtRaw != null ? int.tryParse(deletedAtRaw.toString()) : null);
      final idx = _messages.indexWhere((m) => m.id == id);
      if (idx >= 0) {
        setState(() {
          _messages[idx] = _messages[idx].copyWith(
            deletedAt: deletedAt,
            text: 'Message deleted',
          );
        });
      }
      return;
    }

    if (event.type == 'message_reactions') {
      final payload = event.payload;
      final int? id = payload['message_id'] is int
          ? payload['message_id'] as int
          : int.tryParse(payload['message_id']?.toString() ?? '');
      if (id == null) return;
      Map<String, int>? reactions;
      final r = payload['reactions'];
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
      final idx = _messages.indexWhere((m) => m.id == id);
      if (idx >= 0) {
        setState(() {
          _messages[idx] = _messages[idx].copyWith(reactions: reactions);
        });
      }
      return;
    }

    if (event.type == 'presence') {
      final users = (event.payload['users'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [];

      setState(() {
        _onlineUsers = users;
        if (widget.isPrivate &&
            users.where((u) => u != widget.username).isNotEmpty) {
          _lastSeen = null;
        }
      });
      return;
    }

    if (event.type == 'typing') {
      final username = event.payload['username'] as String? ?? '';
      final isTyping = event.payload['isTyping'] as bool? ?? false;

      if (username == widget.username) return;

      setState(() {
        _typingUser = isTyping ? username : null;
        _typingClearTimer?.cancel();

        if (isTyping) {
          _typingClearTimer = Timer(const Duration(seconds: 2), () {
            if (mounted) {
              setState(() => _typingUser = null);
            }
          });
        }
      });
      return;
    }

    if (event.type == 'last_seen' &&
        widget.isPrivate &&
        event.roomId == widget.roomId) {
      final username = event.payload['username'] as String? ?? '';
      final lastSeen = event.payload['lastSeen'] as String?;
      if (username != widget.username && lastSeen != null) {
        setState(() => _lastSeen = lastSeen);
      }
    }
  }

  Future<void> _scrollToBottom() async {
    if (!_scrollController.hasClients) return;

    await _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );

    if (!mounted) return;
    setState(() {
      _unseenMessagesCount = 0;
      _isNearBottom = true;
    });
  }

  Future<void> _pickImage() async {
    final picked = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked == null) return;
    if (!mounted) return;
    setState(() {
      _selectedImage = File(picked.path);
    });
  }

  Future<void> _sendMessage(String text) async {
    final trimmed = text.trim();
    final image = _selectedImage;

    if (trimmed.isEmpty && image == null) return;

    if (_typingSent) {
      widget.chatService.sendTyping(widget.roomId, false);
      _typingSent = false;
    }

    String? imageUrl;

    if (image != null) {
      setState(() => _isUploadingImage = true);

      try {
        imageUrl = await _api.uploadImage(image);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки изображения: $e')),
        );
        setState(() => _isUploadingImage = false);
        return;
      }

      if (!mounted) return;
      setState(() => _isUploadingImage = false);
    }

    widget.chatService.sendMessage(
      widget.roomId,
      trimmed,
      replyToId: _replyToMessage?.id,
      imageUrl: imageUrl,
    );

    if (!mounted) return;

    setState(() {
      _replyToMessage = null;
      _selectedImage = null;
    });
  }

  Future<void> _openSearch() async {
    final targetMessageId = await Navigator.push<int>(
      context,
      MaterialPageRoute<int>(
        builder: (_) => ChatSearchScreen(
          roomId: widget.roomId,
          roomDisplayName: _roomDisplayName,
        ),
      ),
    );
    if (targetMessageId != null && mounted) {
      _jumpToMessage(targetMessageId);
    }
  }

  Future<void> _jumpToMessage(int messageId) async {
    final index = _messages.indexWhere((m) => m.id == messageId);
    if (index == -1) return;

    const double estimatedItemHeight = 88;
    final double offset = index * estimatedItemHeight;

    if (!_scrollController.hasClients) return;
    await _scrollController.animateTo(
      offset.clamp(0.0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );

    if (!mounted) return;
    setState(() => _highlightedMessageId = messageId);

    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;
    setState(() {
      if (_highlightedMessageId == messageId) {
        _highlightedMessageId = null;
      }
    });
  }

  void _showMessageOptions(ChatMessage message, bool isMine) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _reaction(ctx, '👍', message),
                    _reaction(ctx, '❤️', message),
                    _reaction(ctx, '😂', message),
                    _reaction(ctx, '🔥', message),
                  ],
                ),
              ),
              if (isMine) ...[
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Edit'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _editMessage(message);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('Delete'),
                  onTap: () {
                    Navigator.pop(ctx);
                    widget.chatService.deleteMessage(widget.roomId, message.id);
                  },
                ),
              ] else ...[
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.reply),
                  title: const Text('Reply'),
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() => _replyToMessage = message);
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _reaction(BuildContext context, String emoji, ChatMessage m) {
    return GestureDetector(
      onTap: () {
        widget.chatService.sendReaction(widget.roomId, m.id, emoji);
        Navigator.pop(context);
      },
      child: Text(emoji, style: const TextStyle(fontSize: 26)),
    );
  }

  void _editMessage(ChatMessage message) async {
    final controller = TextEditingController(text: message.text);

    final newText = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Edit message'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => Navigator.of(ctx).pop(controller.text),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (newText == null || !mounted) return;

    widget.chatService.editMessage(widget.roomId, message.id, newText);
  }

  void _onTextChanged(String text) {
    if (_connectionStatusValue != ConnectionStatus.connected) return;

    _typingSendTimer?.cancel();
    final trimmed = text.trim();

    if (trimmed.isEmpty) {
      if (_typingSent) {
        widget.chatService.sendTyping(widget.roomId, false);
        _typingSent = false;
      }
      return;
    }

    _typingSendTimer = Timer(const Duration(milliseconds: 600), () {
      if (!_typingSent) {
        widget.chatService.sendTyping(widget.roomId, true);
        _typingSent = true;
      }
    });
  }

  @override
  void dispose() {
    _typingClearTimer?.cancel();
    _typingSendTimer?.cancel();

    if (_typingSent) {
      widget.chatService.sendTyping(widget.roomId, false);
    }

    _eventSub?.cancel();
    _statusSub?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;

    final position = _scrollController.position;
    final distanceToBottom = position.maxScrollExtent - position.pixels;
    final nearBottom = distanceToBottom < 120;

    if (nearBottom != _isNearBottom) {
      setState(() {
        _isNearBottom = nearBottom;
        if (nearBottom) {
          _unseenMessagesCount = 0;
        }
      });
    }
  }

  String get _appBarSubtitle {
    final others = _onlineUsers.where((u) => u != widget.username).toList();

    if (widget.isPrivate) {
      if (others.isNotEmpty) return 'online';
      if (_lastSeen != null && _lastSeen!.isNotEmpty) {
        return 'last seen ${formatTimeHHmm(_lastSeen!)}';
      }
      return '';
    }

    if (others.isNotEmpty) return '${others.length} online';
    return '';
  }

  PreferredSizeWidget _buildChatAppBar(BuildContext context, ThemeData theme) {
    final statusText = _appBarSubtitle;

    return AppBar(
      titleSpacing: 0,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _roomDisplayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (statusText.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              statusText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
      backgroundColor: theme.colorScheme.surface,
      foregroundColor: theme.colorScheme.onSurface,
      elevation: 0,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(
          color: theme.colorScheme.outline.withValues(alpha: 0.12),
          height: 1,
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.search),
          onPressed: _openSearch,
        ),
        if (!widget.isPrivate)
          PopupMenuButton<String>(
            onSelected: (value) {
              if (_actionLoading) return;

              switch (value) {
                case 'members':
                  _openMembers();
                  break;
                case 'rename':
                  _renameGroup();
                  break;
                case 'leave':
                  _leaveGroup();
                  break;
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'members',
                child: Text('Участники'),
              ),
              PopupMenuItem(
                value: 'rename',
                child: Text('Переименовать'),
              ),
              PopupMenuItem(
                value: 'leave',
                child: Text('Выйти из группы'),
              ),
            ],
          ),
      ],
    );
  }

  Future<void> _openMembers() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GroupMembersScreen(
          roomId: widget.roomId,
          roomName: _roomDisplayName,
        ),
      ),
    );
  }

  Future<void> _renameGroup() async {
    final controller = TextEditingController(text: _roomDisplayName);

    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Переименовать группу'),
          content: TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Название группы',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => Navigator.of(ctx).pop(controller.text.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
              child: const Text('Сохранить'),
            ),
          ],
        );
      },
    );

    if (newName == null || newName.isEmpty || newName == _roomDisplayName) {
      return;
    }

    setState(() {
      _actionLoading = true;
    });

    try {
      await _api.renameRoom(widget.roomId, newName);
      if (!mounted) return;

      setState(() {
        _roomDisplayName = newName;
        _actionLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Группа переименована')),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _actionLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    }
  }

  Future<void> _leaveGroup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Выйти из группы'),
        content: const Text('Ты действительно хочешь выйти из этой группы?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Выйти'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _actionLoading = true;
    });

    try {
      await _api.leaveRoom(widget.roomId, widget.username);
      if (!mounted) return;

      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _actionLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    }
  }

  String _dateLabel(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final messageDay = DateTime(date.year, date.month, date.day);

    if (messageDay == today) return 'Today';
    if (messageDay == yesterday) return 'Yesterday';

    return '${date.day}.${date.month}.${date.year}';
  }

  ConnectionStatus get _connectionStatus {
    if (_loadingHistory) return ConnectionStatus.connecting;
    return _connectionStatusValue;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loadingHistory) {
      return Scaffold(
        backgroundColor: theme.colorScheme.surface,
        appBar: _buildChatAppBar(context, theme),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: _buildChatAppBar(context, theme),
      body: Stack(
        children: [
          GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            behavior: HitTestBehavior.opaque,
            child: Column(
              children: [
                ConnectionBanner(status: _connectionStatus),
                Expanded(
              child: _messages.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 40),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.chat_bubble_outline_rounded,
                              size: 48,
                              color: theme.colorScheme.outline
                                  .withValues(alpha: 0.4),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No messages yet',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w500,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Send a message to start the conversation',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontSize: 15,
                                color: theme.colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.9),
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 12,
                      ),
                      itemCount: _messages.length,
                      itemBuilder: (context, i) {
                        final m = _messages[i];
                        final currentDate = DateTime(
                          m.timestamp.year,
                          m.timestamp.month,
                          m.timestamp.day,
                        );
                        bool showDate = false;
                        if (i == 0) {
                          showDate = true;
                        } else {
                          final prev = _messages[i - 1];
                          final prevDate = DateTime(
                            prev.timestamp.year,
                            prev.timestamp.month,
                            prev.timestamp.day,
                          );
                          if (prevDate != currentDate) {
                            showDate = true;
                          }
                        }
                        final isMine = m.username == widget.username;
                        final bubble = MessageBubble(
                          message: m,
                          isMine: isMine,
                          onLongPress: m.deletedAt != null
                              ? null
                              : () => _showMessageOptions(m, isMine),
                          isHighlighted: _highlightedMessageId == m.id,
                          onReplyTap: m.replyToId != null
                              ? () => _jumpToMessage(m.replyToId!)
                              : null,
                        );
                        if (showDate) {
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              DateSeparator(text: _dateLabel(m.timestamp)),
                              bubble,
                            ],
                          );
                        }
                        return bubble;
                      },
                    ),
            ),
            SizedBox(
              height: 24,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _typingUser != null && _typingUser!.isNotEmpty
                      ? Text(
                          '$_typingUser печатает...',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ),
            if (_replyToMessage != null)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _replyToMessage!.username,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _replyToMessage!.text,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        setState(() {
                          _replyToMessage = null;
                        });
                      },
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
            if (_selectedImage != null)
              Container(
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(
                        _selectedImage!,
                        height: 160,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        onPressed: () {
                          setState(() => _selectedImage = null);
                        },
                        icon: const Icon(Icons.close),
                      ),
                    ),
                  ],
                ),
              ),
            if (_isUploadingImage)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Center(child: CircularProgressIndicator()),
              ),
            ChatInput(
              onSend: (text) async => _sendMessage(text),
              onChanged: _onTextChanged,
              onPickImage: _isUploadingImage ? null : _pickImage,
              enabled: _connectionStatusValue == ConnectionStatus.connected && !_isUploadingImage,
              allowSendWithEmptyText: _selectedImage != null,
            ),
              ],
            ),
          ),
          if (!_isNearBottom || _unseenMessagesCount > 0)
            Positioned(
              right: 16,
              bottom: 80,
              child: _buildScrollToBottomButton(),
            ),
        ],
      ),
    );
  }

  Widget _buildScrollToBottomButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _scrollToBottom,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.keyboard_arrow_down),
              if (_unseenMessagesCount > 0) ...[
                const SizedBox(width: 6),
                Text(
                  _unseenMessagesCount > 99 ? '99+' : _unseenMessagesCount.toString(),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
