import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:cipher_ai/core/services/voice/voice_recorder_service.dart';

class ChatInput extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final void Function(String localFilePath, int durationSeconds) onSendVoice;
  final PlatformFile? pendingAttachment;
  final void Function(PlatformFile file) onAttachFile;
  final VoidCallback onRemoveAttachment;

  const ChatInput({
    super.key,
    required this.controller,
    required this.onSend,
    required this.onSendVoice,
    this.pendingAttachment,
    required this.onAttachFile,
    required this.onRemoveAttachment,
  });

  @override
  State<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<ChatInput> {
  final VoiceRecorderService _recorderService = VoiceRecorderService();

  bool _isRecording = false;
  int _seconds = 0;
  Timer? _timer;

  Future<void> _startRecording() async {
    try {
      await _recorderService.start();
      setState(() {
        _isRecording = true;
        _seconds = 0;
      });

      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        setState(() => _seconds++);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Microphone error: $e")));
      }
    }
  }

  Future<void> _stopRecording({required bool send}) async {
    _timer?.cancel();
    final duration = _seconds;

    setState(() => _isRecording = false);

    if (!send) {
      await _recorderService.cancel();
      return;
    }

    final path = await _recorderService.stop();
    if (path != null) {
      widget.onSendVoice(path, duration);
    }
  }

  String get _formattedTime {
    final m = (_seconds ~/ 60).toString().padLeft(2, '0');
    final s = (_seconds % 60).toString().padLeft(2, '0');
    return "$m:$s";
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'docx', 'txt', 'md', 'csv', 'json'],
        withData: false,
      );

      final picked = result?.files.single;
      if (picked != null && picked.path != null) {
        widget.onAttachFile(picked);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Couldn't open file picker: $e")),
        );
      }
    }
  }

  void _showAttachmentMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _AttachOption(
                    icon: Icons.photo_outlined,
                    label: "Photos",
                    onTap: () => Navigator.pop(context),
                  ),
                  _AttachOption(
                    icon: Icons.camera_alt_outlined,
                    label: "Camera",
                    onTap: () => Navigator.pop(context),
                  ),
                  _AttachOption(
                    icon: Icons.insert_drive_file_outlined,
                    label: "Files",
                    onTap: () async {
                      Navigator.pop(context);
                      await _pickFile();
                    },
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _recorderService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              constraints: const BoxConstraints(minHeight: 58, maxHeight: 220),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(.94),
                borderRadius: BorderRadius.circular(30),
                boxShadow: const [
                  BoxShadow(
                    color: Color.fromRGBO(0, 0, 0, .08),
                    blurRadius: 20,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.pendingAttachment != null)
                    _PendingAttachmentChip(
                      fileName: widget.pendingAttachment!.name,
                      onRemove: widget.onRemoveAttachment,
                    ),
                  _isRecording ? _buildRecordingRow() : _buildTextRow(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        IconButton(
          onPressed: _showAttachmentMenu,
          icon: const Icon(Icons.add_rounded),
        ),
        Expanded(
          child: TextField(
            controller: widget.controller,
            minLines: 1,
            maxLines: 6,
            textAlignVertical: TextAlignVertical.center,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: "Ask cipher",
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.symmetric(vertical: 14),
            ),
            onSubmitted: (_) => widget.onSend(),
          ),
        ),
        IconButton(
          onPressed: _startRecording,
          icon: const Icon(Icons.mic_none_rounded),
        ),
        GestureDetector(
          onTap: widget.onSend,
          child: Container(
            width: 38,
            height: 38,
            margin: const EdgeInsets.only(right: 4),
            decoration: const BoxDecoration(
              color: Colors.black,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.arrow_upward_rounded,
              color: Colors.white,
              size: 18,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRecordingRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          IconButton(
            onPressed: () => _stopRecording(send: false),
            icon: const Icon(Icons.close_rounded, color: Colors.redAccent),
          ),
          Expanded(
            child: Row(
              children: [
                const _RecordingDot(),
                const SizedBox(width: 10),
                const _WaveformBars(),
                const SizedBox(width: 10),
                Text(
                  _formattedTime,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.black54,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => _stopRecording(send: true),
            child: Container(
              width: 38,
              height: 38,
              decoration: const BoxDecoration(
                color: Colors.black,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.arrow_upward_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PendingAttachmentChip extends StatelessWidget {
  final String fileName;
  final VoidCallback onRemove;

  const _PendingAttachmentChip({
    required this.fileName,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 2),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xffF2F2F3),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.insert_drive_file_outlined, size: 16),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: Text(
                  fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: onRemove,
                child: const Icon(Icons.close_rounded, size: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AttachOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _AttachOption({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: const Color(0xffF2F2F3),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(icon, size: 26),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

class _RecordingDot extends StatefulWidget {
  const _RecordingDot();

  @override
  State<_RecordingDot> createState() => _RecordingDotState();
}

class _RecordingDotState extends State<_RecordingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 1, end: 0.3).animate(_controller),
      child: Container(
        width: 10,
        height: 10,
        decoration: const BoxDecoration(
          color: Colors.redAccent,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _WaveformBars extends StatefulWidget {
  const _WaveformBars();

  @override
  State<_WaveformBars> createState() => _WaveformBarsState();
}

class _WaveformBarsState extends State<_WaveformBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 22,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(14, (i) {
              final phase = (_controller.value * 2 * math.pi) + (i * 0.6);
              final height = 4 + (18 * ((1 + math.sin(phase)) / 2));
              return Container(
                width: 3,
                height: height,
                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(2),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}
