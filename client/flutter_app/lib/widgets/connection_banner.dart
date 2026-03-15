import 'package:flutter/material.dart';

import '../services/chat_service.dart';

class ConnectionBanner extends StatelessWidget {
  const ConnectionBanner({
    super.key,
    required this.status,
  });

  final ConnectionStatus status;

  @override
  Widget build(BuildContext context) {
    if (status == ConnectionStatus.connected) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final isConnecting = status == ConnectionStatus.connecting || status == ConnectionStatus.reconnecting;
    final message = status == ConnectionStatus.reconnecting
        ? 'Reconnecting…'
        : (status == ConnectionStatus.connecting ? 'Connecting…' : 'Disconnected');
    final color = isConnecting
        ? theme.colorScheme.primary
        : theme.colorScheme.error;

    return Material(
      color: color.withValues(alpha: 0.12),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: isConnecting
                    ? CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(color),
                      )
                    : Icon(Icons.cloud_off_rounded, size: 14, color: color),
              ),
              const SizedBox(width: 8),
              Text(
                message,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
