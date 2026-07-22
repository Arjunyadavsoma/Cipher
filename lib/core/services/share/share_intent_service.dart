import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

/// What the rest of the app actually needs from something shared in from
/// another app: either a piece of text, or a file - never both, since the
/// composer only has one text field and one attachment slot today.
class IncomingShare {
  final String? text;
  final PlatformFile? file;

  const IncomingShare._({this.text, this.file});

  factory IncomingShare.text(String text) => IncomingShare._(text: text);
  factory IncomingShare.file(PlatformFile file) => IncomingShare._(file: file);
}

/// Thin wrapper around `receive_sharing_intent`.
///
/// That plugin hands back a `SharedMediaFile`, whose `path` field doubles
/// as either a real file path OR the shared text/url string itself,
/// depending on `type`. This class hides that distinction and always
/// gives the rest of the app the simpler [IncomingShare] shape instead.
///
/// Handles both ways Android delivers a share:
///  - cold start: the app was closed and got launched BY the share
///    (user tapped "cipher AI" in the "Share via..." sheet) -> [consumeInitial]
///  - warm start: the app was already running and received a new share
///    while alive -> [stream]
class ShareIntentService {
  ShareIntentService._internal();
  static final ShareIntentService instance = ShareIntentService._internal();

  /// Fires whenever a new share arrives while the app is already running
  /// - e.g. the user is mid-conversation and shares a second PDF in from
  /// a file manager or another app.
  Stream<IncomingShare> get stream => ReceiveSharingIntent.instance
      .getMediaStream()
      .map(_firstShareOrNull)
      .where((share) => share != null)
      .cast<IncomingShare>();

  /// Call once, as soon as something is listening (e.g. from
  /// HomeController's constructor), to pick up whatever share LAUNCHED
  /// the app while it was closed. Resolves to null if the app was opened
  /// normally. Always resets the plugin's cache afterwards so the same
  /// share doesn't get replayed on the next hot reload or app restart.
  Future<IncomingShare?> consumeInitial() async {
    final files = await ReceiveSharingIntent.instance.getInitialMedia();
    final share = _firstShareOrNull(files);
    ReceiveSharingIntent.instance.reset();
    return share;
  }

  /// Only the first shared item is used - the composer only supports one
  /// pending attachment at a time today. (Worth revisiting if you want
  /// multi-file shares later.)
  IncomingShare? _firstShareOrNull(List<SharedMediaFile> files) {
    if (files.isEmpty) return null;
    final shared = files.first;

    // For text/url shares, the plugin puts the actual string content in
    // `path` - there's no separate text field on SharedMediaFile.
    if (shared.type == SharedMediaType.text ||
        shared.type == SharedMediaType.url) {
      final text = shared.path.trim();
      return text.isEmpty ? null : IncomingShare.text(text);
    }

    // Everything else (file, image, video, ...) is a real local path -
    // the plugin already copies shared content into a cache file, so
    // (unlike file_picker on Android) this path is never null.
    final file = File(shared.path);
    if (!file.existsSync()) return null;

    return IncomingShare.file(
      PlatformFile(
        name: shared.path.split(Platform.pathSeparator).last,
        size: file.lengthSync(),
        path: shared.path,
      ),
    );
  }
}
