import 'package:flutter/material.dart';

class EmptyChats extends StatelessWidget {
  const EmptyChats({
    super.key,
    required this.onCreateChat,
    this.onCreatePrivateChat,
  });

  final VoidCallback onCreateChat;
  final VoidCallback? onCreatePrivateChat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 44),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.4),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.chat_bubble_outline_rounded,
                size: 56,
                color: theme.colorScheme.outline.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 32),
            Text(
              'No chats yet',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: 20,
                color: theme.colorScheme.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Create a chat to start a conversation',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontSize: 15,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 36),
            FilledButton.icon(
              onPressed: onCreateChat,
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text('Create group chat'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
            ),
            if (onCreatePrivateChat != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: onCreatePrivateChat,
                icon: const Icon(Icons.person_add_rounded, size: 20),
                label: const Text('New private chat'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
