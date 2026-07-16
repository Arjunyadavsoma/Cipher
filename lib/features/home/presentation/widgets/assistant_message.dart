import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../models/chat_message.dart';

class AssistantMessage extends StatelessWidget {
  final ChatMessage message;
  final VoidCallback? onConnectGmail;

  const AssistantMessage({
    super.key,
    required this.message,
    this.onConnectGmail,
  });
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: MarkdownBody(
        selectable: true,
        data: message.text,
        styleSheet: MarkdownStyleSheet(
          p: const TextStyle(
            fontSize: 16,
            height: 1.6,
          ),
          h1: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
          h2: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
          code: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 14,
          ),
          codeblockDecoration: BoxDecoration(
            color: const Color(0xffF5F5F7),
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}