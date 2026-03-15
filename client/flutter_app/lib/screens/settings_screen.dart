import 'package:flutter/material.dart';

import '../models/user.dart';
import '../services/app_settings_service.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';
import 'profile_screen.dart';

class SettingsScreen extends StatefulWidget {
  final User currentUser;
  final VoidCallback? onLogout;

  const SettingsScreen({
    super.key,
    required this.currentUser,
    this.onLogout,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _appSettingsService = AppSettingsService();

  late User _currentUser;
  bool _notificationsEnabled = true;
  bool _settingsLoading = true;

  @override
  void initState() {
    super.initState();
    _currentUser = widget.currentUser;
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final notificationsEnabled =
        await _appSettingsService.getNotificationsEnabled();

    if (!mounted) return;

    setState(() {
      _notificationsEnabled = notificationsEnabled;
      _settingsLoading = false;
    });
  }

  Future<void> _toggleNotifications(bool value) async {
    setState(() {
      _notificationsEnabled = value;
    });

    await _appSettingsService.setNotificationsEnabled(value);
  }

  Future<void> _logout(BuildContext context) async {
    final authService = AuthService();
    await authService.logout();
    widget.onLogout?.call();

    if (!context.mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  Future<void> _openProfile() async {
    final updatedUser = await Navigator.of(context).push<User>(
      MaterialPageRoute(
        builder: (_) => ProfileScreen(
          currentUser: _currentUser,
          onLogout: widget.onLogout,
        ),
      ),
    );

    if (updatedUser != null && mounted) {
      setState(() {
        _currentUser = updatedUser;
      });
    }
  }

  void _showSimpleInfo({
    required String title,
    required String content,
  }) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.of(context).pop(_currentUser);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Настройки'),
        ),
        body: ListView(
          children: [
            const SizedBox(height: 8),

            ListTile(
              leading: CircleAvatar(
                child: Text(
                  _currentUser.displayName.isNotEmpty
                      ? _currentUser.displayName[0].toUpperCase()
                      : '?',
                ),
              ),
              title: Text(_currentUser.displayName),
              subtitle: Text('@${_currentUser.username}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _openProfile,
            ),

            const Divider(height: 1),

            _settingsLoading
                ? ListTile(
                    leading: const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    title: const Text('Уведомления'),
                    subtitle: const Text('Загрузка настроек...'),
                  )
                : SwitchListTile(
                    value: _notificationsEnabled,
                    onChanged: _toggleNotifications,
                    title: const Text('Уведомления'),
                    subtitle: const Text('Локальные уведомления приложения'),
                  ),

            const Divider(height: 1),

            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('О приложении'),
              subtitle: const Text('Версия и краткая информация'),
              onTap: () {
                _showSimpleInfo(
                  title: 'О приложении',
                  content: 'Messenger\nВерсия 0.1.0\nЛичный мессенджер для общения.',
                );
              },
            ),

            ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: const Text('Privacy Policy'),
              onTap: () {
                _showSimpleInfo(
                  title: 'Privacy Policy',
                  content: 'Пока черновой экран. Позже сюда можно добавить реальный текст политики конфиденциальности или открыть отдельную страницу.',
                );
              },
            ),

            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('Terms of Use'),
              onTap: () {
                _showSimpleInfo(
                  title: 'Terms of Use',
                  content: 'Пока черновой экран. Позже сюда можно добавить реальные условия использования.',
                );
              },
            ),

            const SizedBox(height: 24),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.error,
                  foregroundColor: theme.colorScheme.onError,
                ),
                onPressed: () => _logout(context),
                child: const Text('Выйти'),
              ),
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
