import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cipher_ai/app/features/rss/controller/rss_controller.dart';

/// Exposes `RssController` to the UI layer, mirroring
/// `providers/agent_provider.dart`'s wiring of `AgentService`.
///
/// `userId` needs to come from your existing auth state
/// (`firebase_auth`, per pubspec.yaml) — wire this up wherever the
/// rest of the app reads the current user. Left as a placeholder
/// argument here rather than guessed at, since the auth provider
/// wasn't in the manifest you shared.
final rssControllerProvider =
    ChangeNotifierProvider.family<RssController, String>((ref, userId) {
      return RssController(userId: userId);
    });
