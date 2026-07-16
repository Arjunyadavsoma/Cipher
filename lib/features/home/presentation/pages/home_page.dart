import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../controller/home_controller.dart';
import '../widgets/chat_input.dart';
import '../widgets/conversation_view.dart';
import '../widgets/drawer_view.dart';
import '../widgets/suggestion_cards.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  @override
  void initState() {
    super.initState();
    // Tell controller the screen is active
    ref.read(homeControllerProvider.notifier).setChatScreenActive(true);
  }

  @override
  void dispose() {
    // Tell controller the screen is closed/minimized
    ref.read(homeControllerProvider.notifier).setChatScreenActive(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(homeControllerProvider);

    if (controller.showGmailIntroDialog) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!controller.showGmailIntroDialog) return;
        controller.dismissGmailIntroDialog();
        _showGmailIntroDialog(context, controller);
      });
    }

    return Scaffold(
      backgroundColor: const Color(0xffF7F7F8),
      drawer: const Drawer(
        child: DrawerView(),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 450),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.05),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                );
              },
              child: controller.hasConversation
                  ? ConversationView(
                      key: const ValueKey("chat"),
                      messages: controller.messages,
                      isTyping: controller.isTyping,
                      controller: controller.scrollController,
                      onConnectGmail: controller.connectGmail,
                    )
                  : const _EmptyHome(key: ValueKey("empty")),
            ),

            // Top Bar
            Positioned(
              top: 8,
              left: 12,
              right: 12,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Builder(
                    builder: (context) {
                      return IconButton(
                        icon: const Icon(Icons.menu_rounded, size: 32),
                        onPressed: () {
                          Scaffold.of(context).openDrawer();
                        },
                      );
                    },
                  ),
                  const Text(
                    "Mimir_ai",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit_square, size: 26),
                    onPressed: controller.startNewChat,
                  ),
                ],
              ),
            ),

            // Bottom Chat Area
            Align(
              alignment: Alignment.bottomCenter,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: controller.showSuggestions
                        ? const SuggestionCards()
                        : const SizedBox.shrink(),
                  ),
                  ChatInput(
                    controller: controller.textController,
                    onSend: controller.sendMessage,
                    onSendVoice: (path, duration) => controller.sendVoiceMessage(
                      localFilePath: path,
                      durationSeconds: duration,
                    ),
                    pendingAttachment: controller.pendingAttachment,
                    onAttachFile: controller.attachFile,
                    onRemoveAttachment: controller.removeAttachment,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void _showGmailIntroDialog(BuildContext context, HomeController controller) {
  showDialog(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text("Connect your Google account"),
      content: const Text(
        "Mimir can draft and send emails for you, but it needs your "
        "permission to access Gmail first. It only sends what you "
        "explicitly ask it to send, and only after you connect your "
        "Google account.",
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text("Not now"),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.of(dialogContext).pop();
            controller.connectGmail();
          },
          child: const Text("Connect Google Account"),
        ),
      ],
    ),
  );
}

class _EmptyHome extends StatelessWidget {
  const _EmptyHome({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 40),
        child: Text(
          "What can I help with?",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.8,
          ),
        ),
      ),
    );
  }
}