import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cipher_ai/core/services/background_task_service.dart';
import 'package:cipher_ai/core/services/file_parser/file_parser_service.dart';
import 'package:cipher_ai/core/services/gmail/gmail_auth_service.dart';
import 'package:cipher_ai/core/services/notification_service.dart';
import 'package:cipher_ai/core/services/share/share_intent_service.dart';
import 'package:cipher_ai/core/services/supabase/voice_upload_service.dart';
import 'package:cipher_ai/features/agents/services/agent_service.dart';
import 'package:cipher_ai/features/agents/models/execution_result.dart';
import 'package:cipher_ai/features/chat/services/transcription_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat_message.dart';

final homeControllerProvider = ChangeNotifierProvider<HomeController>((ref) {
  return HomeController();
});

class HomeController extends ChangeNotifier {
  final TextEditingController textController = TextEditingController();
  final ScrollController scrollController = ScrollController();

  final List<ChatMessage> messages = [];

  Future<void> initUserBackgroundTasks(String userId) async {
    await BackgroundTaskService.instance.scheduleDailyDsaFetch(userId);
  }

  bool isTyping = false;
  bool isSending = false;
  bool showSuggestions = true;
  bool isDrawerOpen = false;
  bool needsGmailConnect = false;
  bool showGmailIntroDialog = false;
  bool _isChatScreenActive = false;

  static const _gmailIntroShownKey = 'gmail_intro_shown';

  PlatformFile? pendingAttachment;
  String? conversationId;

  bool get hasConversation => messages.isNotEmpty;

  final AgentService _agentService = AgentService.instance;
  StreamSubscription<IncomingShare>? _shareSub;

  HomeController() {
    _listenForSharedContent();
  }

  void setChatScreenActive(bool isActive) {
    _isChatScreenActive = isActive;
  }

  // ---------- SHARE-TO-APP ----------
  void _listenForSharedContent() {
    _shareSub = ShareIntentService.instance.stream.listen(_applyIncomingShare);
    ShareIntentService.instance.consumeInitial().then((share) {
      if (share != null) _applyIncomingShare(share);
    });
  }

  void _applyIncomingShare(IncomingShare share) {
    startNewChat();
    if (share.text != null) {
      textController.text = share.text!;
      textController.selection = TextSelection.collapsed(
        offset: textController.text.length,
      );
    } else if (share.file != null) {
      attachFile(share.file!);
    }
    showSuggestions = false;
    notifyListeners();
  }

  // ---------- TEXT MESSAGE FLOW ----------
  Future<void> sendMessage() async {
    if (isSending) return;

    final text = textController.text.trim();
    final attachment = pendingAttachment;
    if (text.isEmpty && attachment == null) return;

    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      messages.add(
        ChatMessage(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          text: "You need to be signed in to chat.",
          sender: Sender.assistant,
          time: DateTime.now(),
        ),
      );
      notifyListeners();
      return;
    }

    conversationId ??= DateTime.now().microsecondsSinceEpoch.toString();

    isSending = true;
    isTyping = true;
    showSuggestions = false;

    final messageId = DateTime.now().microsecondsSinceEpoch.toString();
    final extension = attachment != null ? _extensionOf(attachment.name) : null;

    final userMessage = ChatMessage(
      id: messageId,
      text: text,
      sender: Sender.user,
      time: DateTime.now(),
      type: attachment != null ? MessageType.file : MessageType.text,
      fileName: attachment?.name,
      fileExtension: extension,
      fileParseStatus: attachment != null ? FileParseStatus.parsing : null,
    );

    messages.add(userMessage);
    pendingAttachment = null;
    textController.clear();
    notifyListeners();
    _scrollToBottom();

    var pipelineMessage = text;

    if (attachment != null &&
        (attachment.path != null || attachment.bytes != null)) {
      final parsed = await FileParserService.instance.extractText(
        filePath: attachment.path,
        bytes: attachment.bytes,
        fileName: attachment.name,
      );

      final index = messages.indexWhere((m) => m.id == messageId);

      if (parsed.hasError) {
        if (index != -1) {
          messages[index] = messages[index].copyWith(
            fileParseStatus: FileParseStatus.failed,
          );
        }
        pipelineMessage = text.isNotEmpty
            ? text
            : "The user attached a file named \"${attachment.name}\" but it "
                  "couldn't be read: ${parsed.error}. Let them know why, "
                  "briefly.";
      } else {
        if (index != -1) {
          messages[index] = messages[index].copyWith(
            fileParseStatus: FileParseStatus.parsed,
            extractedCharCount: parsed.text.length,
          );
        }

        final caption = text.isNotEmpty
            ? text
            : "Summarize this document and highlight the key points.";

        final buffer = StringBuffer();
        buffer.writeln(
          "The user attached a file named \"${attachment.name}\".",
        );
        if (parsed.truncated) {
          buffer.writeln(
            "(Note: this file was long - only the first "
            "${parsed.text.length} characters are included below.)",
          );
        }
        buffer.writeln();
        buffer.writeln("--- File content start ---");
        buffer.writeln(parsed.text);
        buffer.writeln("--- File content end ---");
        buffer.writeln();
        buffer.writeln("User's request: $caption");

        pipelineMessage = buffer.toString();
      }
      notifyListeners();
    } else if (attachment != null) {
      final index = messages.indexWhere((m) => m.id == messageId);
      if (index != -1) {
        messages[index] = messages[index].copyWith(
          fileParseStatus: FileParseStatus.failed,
        );
      }
      pipelineMessage = text.isNotEmpty
          ? text
          : "The user attached a file named \"${attachment.name}\" but the "
                "app couldn't access its contents. Let them know they may "
                "need to try picking it again.";
      notifyListeners();
    }

    try {
      final result = await _agentService.processMessage(
        userId: userId,
        chatId: conversationId!,
        message: pipelineMessage,
      );

      _processAssistantResult(result);

      final needsConnect = result.action?.type == AgentActionType.connectGmail;
      if (needsConnect) {
        needsGmailConnect = true;
        await _maybeShowGmailIntro();
      }
    } catch (e) {
      debugPrint("sendMessage error: $e");
      messages.add(
        ChatMessage(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          text: "Something went wrong.\n\n$e",
          sender: Sender.assistant,
          time: DateTime.now(),
        ),
      );
    }

    isTyping = false;
    isSending = false;
    notifyListeners();
    _scrollToBottom();
  }

  // ---------- VOICE MESSAGE FLOW ----------
  Future<void> sendVoiceMessage({
    required String localFilePath,
    required int durationSeconds,
  }) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      messages.add(
        ChatMessage(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          text: "You need to be signed in to chat.",
          sender: Sender.assistant,
          time: DateTime.now(),
        ),
      );
      notifyListeners();
      return;
    }

    conversationId ??= DateTime.now().microsecondsSinceEpoch.toString();
    final messageId = DateTime.now().microsecondsSinceEpoch.toString();

    final voiceMessage = ChatMessage(
      id: messageId,
      text: "",
      sender: Sender.user,
      time: DateTime.now(),
      type: MessageType.voice,
      localAudioPath: localFilePath,
      durationSeconds: durationSeconds,
      uploadStatus: VoiceUploadStatus.uploading,
      transcriptionStatus: TranscriptionStatus.transcribing,
    );

    messages.add(voiceMessage);
    showSuggestions = false;
    isTyping = true;
    notifyListeners();
    _scrollToBottom();

    String? uploadedUrl;
    String? transcript;

    await Future.wait([
      VoiceUploadService.uploadRecording(localFilePath)
          .then((url) {
            uploadedUrl = url;
          })
          .catchError((e) {
            debugPrint("Voice upload error: $e");
          }),
      TranscriptionService.instance
          .transcribeFile(localFilePath)
          .then((text) {
            transcript = text;
          })
          .catchError((e) {
            debugPrint("Transcription error: $e");
          }),
    ]);

    final index = messages.indexWhere((m) => m.id == messageId);
    if (index != -1) {
      messages[index] = messages[index].copyWith(
        audioUrl: uploadedUrl,
        uploadStatus: uploadedUrl != null
            ? VoiceUploadStatus.uploaded
            : VoiceUploadStatus.failed,
        transcribedText: transcript,
        transcriptionStatus: transcript != null
            ? TranscriptionStatus.transcribed
            : TranscriptionStatus.failed,
      );
    }
    notifyListeners();

    if (transcript == null || transcript!.trim().isEmpty) {
      isTyping = false;
      messages.add(
        ChatMessage(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          text:
              "I couldn't understand that recording - could you try "
              "again, or type your message instead?",
          sender: Sender.assistant,
          time: DateTime.now(),
        ),
      );
      notifyListeners();
      _scrollToBottom();
      return;
    }

    try {
      final result = await _agentService.processMessage(
        userId: userId,
        chatId: conversationId!,
        message: transcript!,
      );

      _processAssistantResult(result);

      final needsConnect = result.action?.type == AgentActionType.connectGmail;
      if (needsConnect) {
        needsGmailConnect = true;
        await _maybeShowGmailIntro();
      }
    } catch (e) {
      debugPrint("sendVoiceMessage agent error: $e");
      messages.add(
        ChatMessage(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          text: "Something went wrong.\n\n$e",
          sender: Sender.assistant,
          time: DateTime.now(),
        ),
      );
    }

    isTyping = false;
    notifyListeners();
    _scrollToBottom();
  }

  // ---------- HELPER TO PROCESS MEDIA & NOTIFICATIONS ----------
  void _processAssistantResult(AgentExecutionResult result) {
    String extractedImageUrl = '';
    String extractedVideoUrl = '';

    final imageRegex = RegExp(r'!\[.*?\]\((.*?)\)');
    final match = imageRegex.firstMatch(result.responseText);
    if (match != null) {
      extractedImageUrl = match.group(1)!;
    }

    final videoRegex = RegExp(r'\[Watch Video\]\((.*?)\)');
    final videoMatch = videoRegex.firstMatch(result.responseText);
    if (videoMatch != null) {
      extractedVideoUrl = videoMatch.group(1)!;
    }

    MessageType msgType = MessageType.text;
    if (extractedImageUrl.isNotEmpty) {
      msgType = MessageType.image;
    } else if (extractedVideoUrl.isNotEmpty) {
      msgType = MessageType.video;
    }

    messages.add(
      ChatMessage(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        text: result.responseText,
        sender: Sender.assistant,
        time: DateTime.now(),
        needsGmailConnect: result.action?.type == AgentActionType.connectGmail,
        type: msgType,
        imageUrl: extractedImageUrl,
        videoUrl: extractedVideoUrl,
      ),
    );

    if (!_isChatScreenActive) {
      String notifTitle = "cipher AI";
      String notifBody = "Response received.";
      if (msgType == MessageType.image) {
        notifTitle = "Image Generated!";
        notifBody = "Your generated image is ready to view.";
      } else if (msgType == MessageType.video) {
        notifTitle = "Video Generated!";
        notifBody = "Your generated video is ready to view.";
      }

      NotificationService.showLocalNotification(
        title: notifTitle,
        body: notifBody,
      );
    }
  }

  // ---------- ATTACHMENTS ----------
  void attachFile(PlatformFile file) {
    pendingAttachment = file;
    notifyListeners();
  }

  void removeAttachment() {
    pendingAttachment = null;
    notifyListeners();
  }

  String _extensionOf(String fileName) {
    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex == -1 || dotIndex == fileName.length - 1) return '';
    return fileName.substring(dotIndex + 1).toLowerCase();
  }

  // ---------- MISC ----------
  void startNewChat() {
    messages.clear();
    conversationId = null;
    showSuggestions = true;
    isTyping = false;
    notifyListeners();
  }

  Future<void> _maybeShowGmailIntro() async {
    final prefs = await SharedPreferences.getInstance();
    final alreadyShown = prefs.getBool(_gmailIntroShownKey) ?? false;
    if (alreadyShown) return;

    await prefs.setBool(_gmailIntroShownKey, true);
    showGmailIntroDialog = true;
    notifyListeners();
  }

  void dismissGmailIntroDialog() {
    showGmailIntroDialog = false;
    notifyListeners();
  }

  Future<void> testGmailConnection() async {
    final result = await GmailAuthService.instance.testConnection();
    messages.add(
      ChatMessage(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        text: "**Gmail connectivity test:**\n\n$result",
        sender: Sender.assistant,
        time: DateTime.now(),
      ),
    );
    notifyListeners();
    _scrollToBottom();
  }

  Future<void> connectGmail() async {
    try {
      final account = await GmailAuthService.instance.connect();
      if (account != null) {
        needsGmailConnect = false;
        messages.add(
          ChatMessage(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            text:
                "Gmail connected (${account.email}). You can try that "
                "again now.",
            sender: Sender.assistant,
            time: DateTime.now(),
          ),
        );
      } else {
        messages.add(
          ChatMessage(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            text: "Gmail sign-in was cancelled or didn't complete.",
            sender: Sender.assistant,
            time: DateTime.now(),
          ),
        );
      }
    } catch (e) {
      debugPrint("connectGmail error: $e");
      messages.add(
        ChatMessage(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          text: "Gmail sign-in failed: $e",
          sender: Sender.assistant,
          time: DateTime.now(),
        ),
      );
    }
    notifyListeners();
    _scrollToBottom();
  }

  void toggleDrawer() {
    isDrawerOpen = !isDrawerOpen;
    notifyListeners();
  }

  void openDrawer() {
    isDrawerOpen = true;
    notifyListeners();
  }

  void closeDrawer() {
    isDrawerOpen = false;
    notifyListeners();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!scrollController.hasClients) return;
      scrollController.animateTo(
        scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _shareSub?.cancel();
    textController.dispose();
    scrollController.dispose();
    super.dispose();
  }
}