import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/sabi_message.dart';

class SabiMessageBubble extends StatelessWidget {
  const SabiMessageBubble({
    required this.message,
    required this.onCopy,
    this.isCopied = false,
    this.onEdit,
    super.key,
  });

  final SabiMessage message;
  final VoidCallback onCopy;
  final bool isCopied;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final isUser = message.author == SabiMessageAuthor.user;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Column(
          crossAxisAlignment: isUser
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: <Widget>[
            DecoratedBox(
              decoration: BoxDecoration(
                color: isUser ? const Color(0xFF5B3DF5) : context.brandTint,
                borderRadius: BorderRadius.circular(16).copyWith(
                  bottomRight: isUser ? const Radius.circular(4) : null,
                  bottomLeft: isUser ? null : const Radius.circular(4),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Text(
                  message.text,
                  style: TextStyle(
                    color: isUser ? Colors.white : context.textColor,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  _formatStamp(message.createdAt),
                  style: TextStyle(fontSize: 11, color: context.mutedTextColor),
                ),
                const SizedBox(width: 4),
                IconButton(
                  onPressed: onCopy,
                  tooltip: isCopied ? 'Copied' : 'Copy message',
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints.tightFor(
                    width: 32,
                    height: 32,
                  ),
                  icon: Icon(
                    isCopied ? Icons.check_circle : Icons.copy_outlined,
                    size: 16,
                    color: isCopied ? Colors.green : null,
                  ),
                ),
                if (onEdit != null)
                  IconButton(
                    onPressed: onEdit,
                    tooltip: 'Edit message',
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints.tightFor(
                      width: 32,
                      height: 32,
                    ),
                    icon: const Icon(Icons.edit_outlined, size: 16),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatStamp(DateTime value) {
    final local = value.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(local.year, local.month, local.day);
    final time = DateFormat.jm().format(local);
    if (day == today) return 'Today · $time';
    if (day == today.subtract(const Duration(days: 1))) {
      return 'Yesterday · $time';
    }
    return '${DateFormat('d MMM yyyy').format(local)} · $time';
  }
}
