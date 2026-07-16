import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

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
      child: _buildContent(),
    );
  }

  Widget _buildContent() {
    // Render Image Natively
    if (message.type == MessageType.image && message.imageUrl != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.network(
              message.imageUrl!,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return Container(
                  height: 200,
                  width: double.infinity,
                  color: const Color(0xffF5F5F7),
                  child: const Center(child: CircularProgressIndicator()),
                );
              },
              errorBuilder: (context, error, stackTrace) {
                return const Text('Failed to load image.');
              },
            ),
          ),
          // Show any accompanying text that wasn't the image markdown
          if (message.text.isNotEmpty && !message.text.startsWith('!['))
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: MarkdownBody(
                selectable: true,
                data: message.text,
                styleSheet: _markdownStyle(),
              ),
            ),
        ],
      );
    }

    // Render Video Natively
    if (message.type == MessageType.video && message.videoUrl != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Your video has been generated! 🎬",
            style: _markdownStyle().p,
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: () {
              launchUrl(Uri.parse(message.videoUrl!));
            },
            icon: const Icon(Icons.play_circle_fill),
            label: const Text("Watch Video"),
          ),
        ],
      );
    }

    // Render normal text
    return MarkdownBody(
      selectable: true,
      data: message.text,
      styleSheet: _markdownStyle(),
    );
  }

  // Extracted style sheet for reuse
  MarkdownStyleSheet _markdownStyle() {
    return MarkdownStyleSheet(
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
    );
  }
}