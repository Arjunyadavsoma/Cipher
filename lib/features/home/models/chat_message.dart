enum Sender { user, assistant }

// Added image and video types
enum MessageType { text, voice, file, image, video }

enum VoiceUploadStatus { uploading, uploaded, failed }
enum FileParseStatus { parsing, parsed, failed }
enum TranscriptionStatus { transcribing, transcribed, failed }

class ChatMessage {
  final String id;
  final String text;
  final Sender sender;
  final DateTime time;
  final MessageType type;

  // Voice-message-specific fields
  final String? localAudioPath;
  final String? audioUrl;
  final int? durationSeconds;
  final VoiceUploadStatus? uploadStatus;
  final String? transcribedText;
  final TranscriptionStatus? transcriptionStatus;

  // File-attachment-specific fields
  final String? fileName;
  final String? fileExtension;
  final FileParseStatus? fileParseStatus;
  final int? extractedCharCount;

  // NEW: Media generation fields
  final String? imageUrl;
  final String? videoUrl;

  final bool needsGmailConnect;

  ChatMessage({
    required this.id,
    required this.text,
    required this.sender,
    required this.time,
    this.type = MessageType.text,
    this.localAudioPath,
    this.audioUrl,
    this.durationSeconds,
    this.uploadStatus,
    this.transcribedText,
    this.transcriptionStatus,
    this.fileName,
    this.fileExtension,
    this.fileParseStatus,
    this.extractedCharCount,
    this.imageUrl,
    this.videoUrl,
    this.needsGmailConnect = false,
  });

  ChatMessage copyWith({
    String? audioUrl,
    VoiceUploadStatus? uploadStatus,
    String? transcribedText,
    TranscriptionStatus? transcriptionStatus,
    FileParseStatus? fileParseStatus,
    int? extractedCharCount,
    String? imageUrl,
    String? videoUrl,
  }) {
    return ChatMessage(
      id: id,
      text: text,
      sender: sender,
      time: time,
      type: type,
      localAudioPath: localAudioPath,
      audioUrl: audioUrl ?? this.audioUrl,
      durationSeconds: durationSeconds,
      uploadStatus: uploadStatus ?? this.uploadStatus,
      transcribedText: transcribedText ?? this.transcribedText,
      transcriptionStatus: transcriptionStatus ?? this.transcriptionStatus,
      fileName: fileName,
      fileExtension: fileExtension,
      fileParseStatus: fileParseStatus ?? this.fileParseStatus,
      extractedCharCount: extractedCharCount ?? this.extractedCharCount,
      imageUrl: imageUrl ?? this.imageUrl,
      videoUrl: videoUrl ?? this.videoUrl,
      needsGmailConnect: needsGmailConnect,
    );
  }
}