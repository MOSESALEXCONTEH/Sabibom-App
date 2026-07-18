import 'package:flutter/material.dart';

import '../../domain/sabi_message.dart';

class SabiMessageBubble extends StatelessWidget {
  const SabiMessageBubble({required this.message, super.key});

  final SabiMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.author == SabiMessageAuthor.user;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: isUser ? const Color(0xFF5B3DF5) : const Color(0xFFF0ECFF),
            borderRadius: BorderRadius.circular(16).copyWith(
              bottomRight: isUser ? const Radius.circular(4) : null,
              bottomLeft: isUser ? null : const Radius.circular(4),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Text(
              message.text,
              style: TextStyle(
                color: isUser ? Colors.white : const Color(0xFF26223E),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
