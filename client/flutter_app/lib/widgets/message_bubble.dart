import 'package:flutter/material.dart';

import '../config.dart';
import '../models/message.dart';
import '../screens/image_viewer_screen.dart';

class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMine;
  final VoidCallback? onLongPress;
  final bool isHighlighted;
  final VoidCallback? onReplyTap;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    this.onLongPress,
    this.isHighlighted = false,
    this.onReplyTap,
  });

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  /// Единая точка: backend может вернуть полный URL (http://localhost:8080/uploads/...)
  /// или путь (/uploads/...). Полный URL с localhost подменяем на backendHttpUrl для эмулятора.
  String get _imageUrl {
    final url = message.imageUrl!;
    if (url.startsWith('http')) {
      if (url.contains('localhost')) {
        final path = Uri.parse(url).path;
        return backendHttpUrl + path;
      }
      return url;
    }
    return backendHttpUrl + (url.startsWith('/') ? url : '/$url');
  }

  @override
  Widget build(BuildContext context) {
    if (message.deletedAt != null) {
      return Align(
        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          padding: const EdgeInsets.all(10),
          child: Text(
            'Message deleted',
            style: TextStyle(
              fontStyle: FontStyle.italic,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
              fontSize: 14,
            ),
          ),
        ),
      );
    }

    final scheme = Theme.of(context).colorScheme;

    final bubbleColor = isHighlighted
        ? scheme.primary.withValues(alpha: 0.18)
        : (isMine ? scheme.primaryContainer : scheme.surfaceContainerHighest);
    final textColor = isMine ? scheme.onPrimaryContainer : scheme.onSurface;

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 280),
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment:
                isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (!isMine) ...[
                Text(
                  message.username,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: textColor.withValues(alpha: 0.75),
                  ),
                ),
                const SizedBox(height: 4),
              ],
              if (message.replyToId != null) ...[
                GestureDetector(
                  onTap: onReplyTap,
                  child: Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'Reply',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: textColor.withValues(alpha: 0.8),
                      ),
                    ),
                  ),
                ),
              ],
              if (message.imageUrl != null && message.imageUrl!.isNotEmpty) ...[
                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => ImageViewerScreen(imageUrl: _imageUrl),
                      ),
                    );
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      _imageUrl,
                      width: 220,
                      height: 220,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 220,
                        height: 220,
                        alignment: Alignment.center,
                        color: Colors.black.withValues(alpha: 0.05),
                        child: const Text('Image unavailable'),
                      ),
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return SizedBox(
                          width: 220,
                          height: 220,
                          child: const Center(
                            child: CircularProgressIndicator(),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                if (message.text.trim().isNotEmpty) const SizedBox(height: 8),
              ],
              if (message.text.trim().isNotEmpty)
                SelectableText(
                  message.text,
                  style: TextStyle(
                    fontSize: 15,
                    color: textColor,
                  ),
                ),
              const SizedBox(height: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _formatTime(message.timestamp),
                    style: TextStyle(
                      fontSize: 11,
                      color: textColor.withValues(alpha: 0.7),
                    ),
                  ),
                  if (message.editedAt != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Text(
                        'edited',
                        style: TextStyle(
                          fontSize: 10,
                          color: textColor.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                  if (isMine) ...[
                    const SizedBox(width: 6),
                    Text(
                      message.isRead ? '✓✓' : '✓',
                      style: TextStyle(
                        fontSize: 11,
                        color: textColor.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ],
              ),
              if (message.reactions != null && message.reactions!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: message.reactions!.entries.map((e) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${e.key} ${e.value}',
                        style: TextStyle(
                          fontSize: 12,
                          color: textColor.withValues(alpha: 0.8),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
