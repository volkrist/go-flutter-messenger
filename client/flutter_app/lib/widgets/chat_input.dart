import 'package:flutter/material.dart';

class ChatInput extends StatefulWidget {
  final Future<void> Function(String text) onSend;
  final ValueChanged<String>? onChanged;
  final Future<void> Function()? onPickImage;
  final bool enabled;
  final bool allowSendWithEmptyText;

  const ChatInput({
    super.key,
    required this.onSend,
    this.onChanged,
    this.onPickImage,
    this.enabled = true,
    this.allowSendWithEmptyText = false,
  });

  @override
  State<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<ChatInput> {
  final TextEditingController _controller = TextEditingController();
  bool _sending = false;

  bool get _canSend =>
      widget.enabled &&
      !_sending &&
      (_controller.text.trim().isNotEmpty || widget.allowSendWithEmptyText);

  Future<void> _handleSend() async {
    final text = _controller.text.trim();
    if (!_canSend || _sending) return;
    if (text.isEmpty && !widget.allowSendWithEmptyText) return;

    setState(() {
      _sending = true;
    });

    try {
      await widget.onSend(text);
      _controller.clear();
      widget.onChanged?.call('');
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            IconButton(
              onPressed: widget.enabled ? widget.onPickImage : null,
              icon: const Icon(Icons.image_outlined),
            ),
            Expanded(
              child: TextField(
                controller: _controller,
                enabled: widget.enabled && !_sending,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.newline,
                onChanged: (value) {
                  setState(() {});
                  widget.onChanged?.call(value);
                },
                decoration: const InputDecoration(
                  hintText: 'Сообщение',
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: _canSend ? _handleSend : null,
              icon: _sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_rounded),
            ),
          ],
        ),
      ),
    );
  }
}
