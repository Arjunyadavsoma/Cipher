import 'package:flutter/material.dart';

import '../../models/chat_message.dart';

class MessageBubble extends StatelessWidget {
  final ChatMessage message;

  const MessageBubble({
    super.key,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * .78,
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(
            vertical: 8,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 14,
          ),
          decoration: BoxDecoration(
            color: const Color(0xffF2F2F4),
            borderRadius: BorderRadius.circular(26),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (message.type == MessageType.file) ...[
                _FileAttachmentCard(message: message),
                if (message.text.isNotEmpty) const SizedBox(height: 10),
              ],
              if (message.type == MessageType.voice) ...[
                _VoiceAttachmentCard(message: message),
              ],
              if (message.text.isNotEmpty)
                SelectableText(
                  message.text,
                  style: const TextStyle(
                    fontSize: 16,
                    height: 1.55,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FileAttachmentCard extends StatelessWidget {
  final ChatMessage message;

  const _FileAttachmentCard({required this.message});

  IconData get _icon {
    switch (message.fileExtension) {
      case 'pdf':
        return Icons.picture_as_pdf_outlined;
      case 'docx':
        return Icons.description_outlined;
      case 'csv':
        return Icons.table_chart_outlined;
      case 'json':
        return Icons.data_object_outlined;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }

  String get _statusLabel {
    switch (message.fileParseStatus) {
      case FileParseStatus.parsing:
        return "Reading file…";
      case FileParseStatus.parsed:
        final count = message.extractedCharCount;
        return count != null
            ? "${count.toString()} characters extracted"
            : "File read";
      case FileParseStatus.failed:
        return "Couldn't read this file";
      case null:
        return "";
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_icon, size: 26),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  message.fileName ?? "Attachment",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (_statusLabel.isNotEmpty)
                  Text(
                    _statusLabel,
                    style: TextStyle(
                      fontSize: 12,
                      color: message.fileParseStatus == FileParseStatus.failed
                          ? Colors.redAccent
                          : Colors.black54,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VoiceAttachmentCard extends StatelessWidget {
  final ChatMessage message;

  const _VoiceAttachmentCard({required this.message});

  String get _durationLabel {
    final seconds = message.durationSeconds ?? 0;
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return "$m:$s";
  }

  String get _transcriptionLabel {
    switch (message.transcriptionStatus) {
      case TranscriptionStatus.transcribing:
        return "Transcribing…";
      case TranscriptionStatus.transcribed:
        return "";
      case TranscriptionStatus.failed:
        return "Couldn't transcribe this recording";
      case null:
        return "";
    }
  }

  String get _uploadLabel {
    switch (message.uploadStatus) {
      case VoiceUploadStatus.uploading:
        return "Saving audio…";
      case VoiceUploadStatus.uploaded:
        return "";
      case VoiceUploadStatus.failed:
        return "Audio not saved";
      case null:
        return "";
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTranscribing =
        message.transcriptionStatus == TranscriptionStatus.transcribing;
    final transcriptFailed =
        message.transcriptionStatus == TranscriptionStatus.failed;
    final uploadFailed = message.uploadStatus == VoiceUploadStatus.failed;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                  color: Color(0xffF2F2F4),
                  shape: BoxShape.circle,
                ),
                child: isTranscribing
                    ? const Padding(
                        padding: EdgeInsets.all(8),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.mic_none_rounded, size: 18),
              ),
              const SizedBox(width: 10),
              Text(
                _durationLabel,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (_uploadLabel.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(
                  _uploadLabel,
                  style: TextStyle(
                    fontSize: 12,
                    color: uploadFailed ? Colors.redAccent : Colors.black45,
                  ),
                ),
              ],
            ],
          ),

          // Transcript / status text
          if (isTranscribing) ...[
            const SizedBox(height: 8),
            const Text(
              "Transcribing…",
              style: TextStyle(fontSize: 14, color: Colors.black54),
            ),
          ] else if (transcriptFailed) ...[
            const SizedBox(height: 8),
            Text(
              _transcriptionLabel,
              style: const TextStyle(fontSize: 14, color: Colors.redAccent),
            ),
          ] else if ((message.transcribedText ?? '').isNotEmpty) ...[
            const SizedBox(height: 10),
            SelectableText(
              message.transcribedText!,
              style: const TextStyle(fontSize: 16, height: 1.5),
            ),
          ],
        ],
      ),
    );
  }
}