enum Sender { user, assistant }

enum MessageType { text, voice, file }

enum VoiceUploadStatus { uploading, uploaded, failed }

/// Mirrors VoiceUploadStatus's role but for the text-extraction step that
/// runs after a file is attached (parsing happens on-device, not uploaded
/// anywhere) - lets the file's chat bubble show "Reading file…" while
/// FileParserService works, then settle into a final state.
enum FileParseStatus { parsing, parsed, failed }

/// Same pattern again, for voice messages: transcription runs concurrently
/// with the Supabase audio upload, and is what actually gets sent to the
/// agent pipeline as the "message" - the audio upload is just for storage/
/// playback, not something the AI reads directly.
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

  // Set on an assistant message when the agent needs Gmail connected to
  // proceed (e.g. tried to send/read email with no account linked yet).
  // Renders an inline "Connect Google Account" button on this bubble.
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
    this.needsGmailConnect = false,
  });

  ChatMessage copyWith({
    String? audioUrl,
    VoiceUploadStatus? uploadStatus,
    String? transcribedText,
    TranscriptionStatus? transcriptionStatus,
    FileParseStatus? fileParseStatus,
    int? extractedCharCount,
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
      needsGmailConnect: needsGmailConnect,
    );
  }
}