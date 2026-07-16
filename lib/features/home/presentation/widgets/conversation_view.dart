import 'package:flutter/material.dart';

import '../../models/chat_message.dart';
import 'assistant_message.dart';
import 'message_bubble.dart';
import 'typing_indicator.dart';

class ConversationView extends StatelessWidget {
  final List<ChatMessage> messages;
  final bool isTyping;
  final ScrollController controller;
  final VoidCallback? onConnectGmail;

  const ConversationView({
    super.key,
    required this.messages,
    required this.isTyping,
    required this.controller,
    this.onConnectGmail,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: controller,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 90, 20, 130),
      itemCount: messages.length + (isTyping ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == messages.length) {
          return const _AnimatedEntry(
            key: ValueKey("typing"),
            child: TypingIndicator(),
          );
        }

        final message = messages[index];

        final bubble = message.sender == Sender.user
            ? MessageBubble(message: message)
            : AssistantMessage(message: message, onConnectGmail: onConnectGmail);

        return _AnimatedEntry(
          key: ValueKey(message.id),
          child: bubble,
        );
      },
    );
  }
}

class _AnimatedEntry extends StatefulWidget {
  final Widget child;

  const _AnimatedEntry({super.key, required this.child});

  @override
  State<_AnimatedEntry> createState() => _AnimatedEntryState();
}

class _AnimatedEntryState extends State<_AnimatedEntry>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );

    _fade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
    );

    _slide = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 1.0, curve: Curves.easeOutCubic),
      ),
    );

    _scale = Tween<double>(begin: 0.94, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 1.0, curve: Curves.easeOutBack),
      ),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: _fade.value,
          child: Transform.translate(
            offset: Offset(
              0,
              _slide.value.dy * 40,
            ),
            child: Transform.scale(
              scale: _scale.value,
              alignment: Alignment.bottomCenter,
              child: child,
            ),
          ),
        );
      },
      child: widget.child,
    );
  }
}