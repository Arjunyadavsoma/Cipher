import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:cipher_ai/core/services/voice/voice_recorder_service.dart';

// ---------------------------------------------------------------------------
// Agent mention metadata
// ---------------------------------------------------------------------------
class _AgentMention {
  final String keyword; // e.g. "image"  -> inserted as "@image "
  final String displayName;
  final String description;
  final IconData icon;
  final Color tint;

  const _AgentMention({
    required this.keyword,
    required this.displayName,
    required this.description,
    required this.icon,
    required this.tint,
  });
}

const List<_AgentMention> _kAgentMentions = [
  _AgentMention(
    keyword: 'image',
    displayName: 'Image Agent',
    description: 'Image generation & editing',
    icon: Icons.auto_awesome_outlined,
    tint: Color(0xFF8B5CF6),
  ),
  _AgentMention(
    keyword: 'video',
    displayName: 'Video Agent',
    description: 'Video generation',
    icon: Icons.play_circle_outline,
    tint: Color(0xFFEC4899),
  ),
  _AgentMention(
    keyword: 'dsa',
    displayName: 'DSA Agent',
    description: 'Daily DSA, practice & progress',
    icon: Icons.code_rounded,
    tint: Color(0xFF22C55E),
  ),
  _AgentMention(
    keyword: 'interview',
    displayName: 'Interview Agent',
    description: 'Interview prep & research',
    icon: Icons.work_outline_rounded,
    tint: Color(0xFF3B82F6),
  ),
  _AgentMention(
    keyword: 'mock',
    displayName: 'Mock Interview',
    description: 'Start a mock interview session',
    icon: Icons.quiz_outlined,
    tint: Color(0xFF3B82F6),
  ),
  _AgentMention(
    keyword: 'news',
    displayName: 'News Agent',
    description: 'News & RSS retrieval',
    icon: Icons.article_outlined,
    tint: Color(0xFFF59E0B),
  ),
  _AgentMention(
    keyword: 'email',
    displayName: 'Email Agent',
    description: 'Email drafting & Gmail',
    icon: Icons.mail_outline_rounded,
    tint: Color(0xFFEF4444),
  ),
  _AgentMention(
    keyword: 'research',
    displayName: 'Research Agent',
    description: 'Academic papers & literature',
    icon: Icons.school_outlined,
    tint: Color(0xFF14B8A6),
  ),
];

// ---------------------------------------------------------------------------
// ChatInput
// ---------------------------------------------------------------------------
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
  final LayerLink _inputLayerLink = LayerLink();

  bool _isRecording = false;
  int _seconds = 0;
  Timer? _timer;

  // ----- Mention popup state -----
  OverlayEntry? _mentionOverlay;
  int _mentionStartIndex = -1;
  List<_AgentMention> _filteredMentions = const [];

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  // ---------------------------------------------------------------------------
  // Mention detection
  // ---------------------------------------------------------------------------
  void _onTextChanged() {
    final text = widget.controller.text;
    final selection = widget.controller.selection;

    if (!mounted) return;

    if (!selection.isValid || !selection.isCollapsed) {
      _hideMentionOverlay();
      return;
    }

    final cursor = selection.baseOffset;
    if (cursor <= 0 || cursor > text.length) {
      _hideMentionOverlay();
      return;
    }

    final beforeCursor = text.substring(0, cursor);
    final atIndex = beforeCursor.lastIndexOf('@');

    if (atIndex == -1) {
      _hideMentionOverlay();
      return;
    }

    // The @ must be at the start of the text or right after whitespace
    if (atIndex > 0) {
      final prevChar = beforeCursor[atIndex - 1];
      if (prevChar != ' ' && prevChar != '\n' && prevChar != '\t') {
        _hideMentionOverlay();
        return;
      }
    }

    final query = beforeCursor.substring(atIndex + 1);

    // A space ends the mention
    if (query.contains(RegExp(r'\s'))) {
      _hideMentionOverlay();
      return;
    }

    // Only allow simple characters
    if (query.isNotEmpty && !RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(query)) {
      _hideMentionOverlay();
      return;
    }

    // Trigger only after 3+ letters (per your requirement)
    if (query.length < 3) {
      _hideMentionOverlay();
      return;
    }

    final lowerQuery = query.toLowerCase();
    final matches = _kAgentMentions.where((m) {
      return m.keyword.toLowerCase().contains(lowerQuery) ||
          m.displayName.toLowerCase().contains(lowerQuery);
    }).toList();

    if (matches.isEmpty) {
      _hideMentionOverlay();
      return;
    }

    _mentionStartIndex = atIndex;
    _filteredMentions = matches;

    if (_mentionOverlay == null) {
      _showMentionOverlay();
    } else {
      _mentionOverlay!.markNeedsBuild();
    }
  }

  void _showMentionOverlay() {
    if (!mounted) return;
    _mentionOverlay = OverlayEntry(
      builder: (context) => _MentionSuggestionList(
        layerLink: _inputLayerLink,
        suggestions: _filteredMentions,
        onTap: _selectMention,
      ),
    );
    Overlay.of(context).insert(_mentionOverlay!);
  }

  void _hideMentionOverlay() {
    _mentionOverlay?.remove();
    _mentionOverlay = null;
    _mentionStartIndex = -1;
  }

    void _selectMention(_AgentMention mention) {
    final text = widget.controller.text;
    final selection = widget.controller.selection;
    final cursor = selection.baseOffset;

    // Hide first so the listener that fires during text update doesn't
    // try to rebuild a stale overlay.
    _mentionOverlay?.remove();
    _mentionOverlay = null;

    if (_mentionStartIndex < 0 || _mentionStartIndex >= cursor) {
      _mentionStartIndex = -1;
      return;
    }

    final replacement = '@${mention.keyword} ';
    final newText =
        text.substring(0, _mentionStartIndex) + replacement + text.substring(cursor);

    _mentionStartIndex = -1;

    widget.controller.text = newText;
    // Simpler & correct: cursor lands right after the inserted "@keyword "
    widget.controller.selection = TextSelection.collapsed(
      offset: newText.indexOf(replacement) + replacement.length,
    );
    
    // FIX: Removed FocusScope.of(context).requestFocus(FocusNode()); 
    // The TextField naturally keeps focus when we update the controller programmatically.
  }

  // ---------------------------------------------------------------------------
  // Recording
  // ---------------------------------------------------------------------------
  Future<void> _startRecording() async {
    try {
      await _recorderService.start();
      _hideMentionOverlay();
      setState(() {
        _isRecording = true;
        _seconds = 0;
      });

      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        setState(() => _seconds++);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Microphone error: $e")));
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

  // ---------------------------------------------------------------------------
  // File picking
  // ---------------------------------------------------------------------------
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
    _hideMentionOverlay();
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
    _hideMentionOverlay();
    widget.controller.removeListener(_onTextChanged);
    _timer?.cancel();
    _recorderService.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------
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
          // CompositedTransformTarget lets the suggestion popup anchor
          // itself to the top-left of the TextField.
          child: CompositedTransformTarget(
            link: _inputLayerLink,
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
              onSubmitted: (_) {
                _hideMentionOverlay();
                widget.onSend();
              },
            ),
          ),
        ),
        IconButton(
          onPressed: _startRecording,
          icon: const Icon(Icons.mic_none_rounded),
        ),
        GestureDetector(
          onTap: () {
            _hideMentionOverlay();
            widget.onSend();
          },
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

// ---------------------------------------------------------------------------
// Mention suggestion popup
// ---------------------------------------------------------------------------
class _MentionSuggestionList extends StatelessWidget {
  final LayerLink layerLink;
  final List<_AgentMention> suggestions;
  final void Function(_AgentMention) onTap;

  const _MentionSuggestionList({
    required this.layerLink,
    required this.suggestions,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: CompositedTransformFollower(
        link: layerLink,
        targetAnchor: Alignment.topLeft,
        followerAnchor: Alignment.bottomLeft,
        offset: const Offset(12, -10),
        child: Material(
          color: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 340, maxHeight: 300),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.black.withOpacity(.06)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(.12),
                  blurRadius: 28,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
                  child: Text(
                    "Agents",
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: .6,
                      color: Colors.black.withOpacity(.45),
                    ),
                  ),
                ),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 4),
                    itemCount: suggestions.length,
                    itemBuilder: (context, index) {
                      final m = suggestions[index];
                      return _MentionTile(mention: m, onTap: () => onTap(m));
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MentionTile extends StatelessWidget {
  final _AgentMention mention;
  final VoidCallback onTap;

  const _MentionTile({required this.mention, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: mention.tint.withOpacity(.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(mention.icon, size: 20, color: mention.tint),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RichText(
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      text: TextSpan(
                        style: DefaultTextStyle.of(context).style,
                        children: [
                          TextSpan(
                            text: '@${mention.keyword}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: Colors.black,
                            ),
                          ),
                          const TextSpan(text: '  '),
                          TextSpan(
                            text: mention.displayName,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.black.withOpacity(.5),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      mention.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Colors.black.withOpacity(.45),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Existing widgets (unchanged)
// ---------------------------------------------------------------------------
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