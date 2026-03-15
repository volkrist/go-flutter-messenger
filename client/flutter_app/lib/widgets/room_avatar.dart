import 'package:flutter/material.dart';

class RoomAvatar extends StatelessWidget {
  const RoomAvatar({
    super.key,
    required this.name,
    this.size = 48,
    this.fontSize,
  });

  final String name;
  final double size;
  final double? fontSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final letter = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return CircleAvatar(
      radius: size / 2,
      backgroundColor: theme.colorScheme.primaryContainer.withValues(alpha: 0.9),
      child: Text(
        letter,
        style: theme.textTheme.titleMedium?.copyWith(
          color: theme.colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.w600,
          fontSize: fontSize ?? size * 0.4,
        ),
      ),
    );
  }
}
