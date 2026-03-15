import 'dart:async';
import 'package:flutter/material.dart';
import '../models/room.dart';
import '../models/user.dart';
import '../services/api_service.dart';

class UserSearchScreen extends StatefulWidget {
  const UserSearchScreen({
    super.key,
    required this.currentUser,
  });

  final User currentUser;

  @override
  State<UserSearchScreen> createState() => _UserSearchScreenState();
}

class _UserSearchScreenState extends State<UserSearchScreen> {
  final _api = ApiService();
  final _searchController = TextEditingController();

  Timer? _debounce;
  List<User> _users = [];
  bool _loading = false;
  String _query = '';
  String? _error;
  String? _openingUsername;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();

    setState(() {
      _query = value;
      _error = null;
    });

    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _users = [];
        _loading = false;
      });
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 350), () {
      _searchUsers(trimmed);
    });
  }

  Future<void> _searchUsers(String query) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final users = await _api.searchUsers(query, widget.currentUser.username);
      if (!mounted) return;

      if (_query.trim() != query.trim()) return;

      setState(() {
        _users = users;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _users = [];
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _openPrivateChat(User user) async {
    setState(() {
      _openingUsername = user.username;
    });

    try {
      final room = await _api.createPrivateRoom(
        widget.currentUser.username,
        user.username,
      );

      if (!mounted) return;
      Navigator.of(context).pop(room);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
      setState(() {
        _openingUsername = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trimmedQuery = _query.trim();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Поиск пользователей'),
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.opaque,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                textInputAction: TextInputAction.search,
                autocorrect: false,
                decoration: InputDecoration(
                  hintText: 'Имя или username',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: trimmedQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _debounce?.cancel();
                            _searchController.clear();
                            setState(() {
                              _query = '';
                              _users = [];
                              _loading = false;
                              _error = null;
                            });
                          },
                        )
                      : null,
                ),
                onChanged: _onQueryChanged,
              ),
            ),
            Expanded(
              child: _buildBody(theme, trimmedQuery),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(ThemeData theme, String trimmedQuery) {
    if (trimmedQuery.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.person_search_outlined,
                size: 56,
                color: theme.colorScheme.outline,
              ),
              const SizedBox(height: 16),
              Text(
                'Начни вводить имя пользователя',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Найди пользователя и открой приватный чат.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => _searchUsers(trimmedQuery),
                child: const Text('Повторить'),
              ),
            ],
          ),
        ),
      );
    }

    if (_users.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.search_off_rounded,
                size: 56,
                color: theme.colorScheme.outline,
              ),
              const SizedBox(height: 16),
              Text(
                'Пользователи не найдены',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Попробуй изменить запрос.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      itemCount: _users.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final user = _users[index];
        final isOpening = _openingUsername == user.username;

        return Card(
          child: ListTile(
            leading: CircleAvatar(
              child: Text(
                user.displayName.isNotEmpty
                    ? user.displayName[0].toUpperCase()
                    : user.username.isNotEmpty
                        ? user.username[0].toUpperCase()
                        : '?',
              ),
            ),
            title: Text(user.displayName),
            subtitle: Text('@${user.username}'),
            trailing: isOpening
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.chevron_right),
            onTap: isOpening ? null : () => _openPrivateChat(user),
          ),
        );
      },
    );
  }
}
