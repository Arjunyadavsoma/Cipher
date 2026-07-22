import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:cipher_ai/core/services/groq/ai_provider.dart';

/// Generalizes ApiKeyPoolService to work across multiple providers, not
/// just Groq. The key-selection strategy (least-used-first, rate-limit
/// cooldown, auth-failure quarantine) is unchanged from the original -
/// only the Firestore collection layout changed, to add a provider
/// dimension: apiKeys/{providerId}__{keySuffix} instead of
/// apiKeys/{keySuffix}. This keeps each provider's usage counters
/// independent, so a Groq key on cooldown doesn't affect ModelScope
/// selection.
///
/// This also owns persistence of the *provider list itself* (base URL,
/// model choices, whether the user added it manually) so the settings
/// screen has somewhere to read from and write to. Provider configs
/// live in Firestore under providers/{providerId}; API keys stay in
/// .env as before (never in Firestore), matching the existing app's
/// choice not to store secrets in the database.
class ProviderPoolService {
  ProviderPoolService._internal();

  static final ProviderPoolService instance = ProviderPoolService._internal();

  final _db = FirebaseFirestore.instance;
  static const _keysCollection = 'apiKeys';
  static const _providersCollection = 'providers';
  static const _selectedProviderDoc = 'settings/selectedProvider';

  // ---------------------------------------------------------------------
  // Provider list persistence
  // ---------------------------------------------------------------------

  /// Returns the full provider list: the 4 built-ins merged with
  /// whatever the user has added/edited in Firestore. Built-ins are
  /// defined in code (builtInProviders) rather than seeded into
  /// Firestore, so an app update that adds a new built-in model doesn't
  /// require a data migration - only user edits to a built-in (e.g.
  /// changing its model list) get persisted as an override.
  Future<List<AiProvider>> getProviders() async {
    final snapshot = await _db.collection(_providersCollection).get();
    final overrides = <String, AiProvider>{
      for (final doc in snapshot.docs) doc.id: AiProvider.fromJson(doc.data()),
    };

    final result = <AiProvider>[];
    final seenIds = <String>{};

    for (final builtIn in builtInProviders) {
      seenIds.add(builtIn.id);
      result.add(overrides[builtIn.id] ?? builtIn);
    }

    // Anything in Firestore that isn't one of the 4 built-in ids is a
    // user-added provider.
    for (final entry in overrides.entries) {
      if (!seenIds.contains(entry.key)) {
        result.add(entry.value);
      }
    }

    return result;
  }

  /// Adds a new user-defined provider, or overwrites an existing one
  /// (built-in or not) with edited fields. Does NOT touch .env - the
  /// user is expected to add the corresponding key there under
  /// provider.apiKeyEnvVar before the provider will actually work; see
  /// hasApiKey() for checking that from the settings screen.
  Future<void> saveProvider(AiProvider provider) async {
    await _db
        .collection(_providersCollection)
        .doc(provider.id)
        .set(provider.toJson());
  }

  /// Removes a user-added provider. Built-ins can't be removed this way
  /// (the settings screen should not offer a delete action for them) -
  /// enforced here too, defensively, in case that gets called anyway.
  Future<void> deleteProvider(String providerId) async {
    final isBuiltIn = builtInProviders.any((p) => p.id == providerId);
    if (isBuiltIn) {
      throw Exception('Cannot delete built-in provider "$providerId"');
    }
    await _db.collection(_providersCollection).doc(providerId).delete();
  }

  /// Whether .env currently has a non-empty value for this provider's
  /// key variable. Used by the settings screen to show a "no key set"
  /// warning instead of only discovering it's missing when a chat
  /// request fails.
  bool hasApiKey(AiProvider provider) {
    final value = dotenv.env[provider.apiKeyEnvVar];
    return value != null && value.trim().isNotEmpty;
  }

  // ---------------------------------------------------------------------
  // Selected provider + model (what the chat screen currently uses)
  // ---------------------------------------------------------------------

  /// Persists which provider/model combination is active, so it
  /// survives app restarts. Stored as a single small doc rather than
  /// per-device local storage since the user may want this synced
  /// across devices the same way the API key pool already is.
  Future<void> setSelected({
    required String providerId,
    required String modelId,
  }) async {
    await _db.doc(_selectedProviderDoc).set({
      'providerId': providerId,
      'modelId': modelId,
    });
  }

  /// Returns the currently selected (providerId, modelId), or null if
  /// nothing has been selected yet - callers should fall back to a
  /// sensible default (e.g. Groq + llama-3.3-70b-versatile) in that
  /// case rather than treating it as an error.
  Future<({String providerId, String modelId})?> getSelected() async {
    final doc = await _db.doc(_selectedProviderDoc).get();
    final data = doc.data();
    if (data == null) return null;
    final providerId = data['providerId'] as String?;
    final modelId = data['modelId'] as String?;
    if (providerId == null || modelId == null) return null;
    return (providerId: providerId, modelId: modelId);
  }

  // ---------------------------------------------------------------------
  // Key rotation (per-provider). Logic mirrors ApiKeyPoolService as
  // closely as possible - see that file's comments for the reasoning
  // behind cooldown durations, the "fall back to full list" behavior
  // when everything is quarantined, etc. The only real change is every
  // Firestore doc id is now prefixed with the provider id.
  // ---------------------------------------------------------------------

  /// Reads keys for [provider] from .env. Like the original
  /// ApiKeyPoolService, supports a single-key env var
  /// (provider.apiKeyEnvVar, e.g. GROQ_API_KEY) today. A comma-separated
  /// multi-key variant isn't wired up per-provider yet since none of
  /// the 4 current providers need key rotation - this is here so
  /// getNextKey below has the same "only one key, skip Firestore
  /// lookup" fast path the original had, and so multi-key support can
  /// be added later (e.g. GROQ_API_KEYS) without changing callers.
  List<String> _keysFor(AiProvider provider) {
    final single = dotenv.env[provider.apiKeyEnvVar];
    if (single != null && single.trim().isNotEmpty) {
      return [single.trim()];
    }
    throw Exception(
      'No API key found for ${provider.name} '
      '(expected .env variable "${provider.apiKeyEnvVar}")',
    );
  }

  String _docId(String providerId, String key) {
    final suffix = key.length > 6 ? key.substring(key.length - 6) : key;
    return '${providerId}__key_$suffix';
  }

  Future<String> getNextKey(AiProvider provider) async {
    final keys = _keysFor(provider);

    if (keys.length == 1) {
      final key = keys.first;
      await _db.collection(_keysCollection).doc(_docId(provider.id, key)).set({
        'usageCount': FieldValue.increment(1),
        'lastUsedAt': DateTime.now().toIso8601String(),
      }, SetOptions(merge: true));
      return key;
    }

    final snapshot = await _db
        .collection(_keysCollection)
        .where('providerId', isEqualTo: provider.id)
        .get();

    final usageCounts = <String, int>{};
    final rateLimited = <String, bool>{};
    final cooldowns = <String, DateTime?>{};
    final invalid = <String, bool>{};

    for (final doc in snapshot.docs) {
      final data = doc.data();
      usageCounts[doc.id] = data['usageCount'] ?? 0;
      rateLimited[doc.id] = data['isRateLimited'] ?? false;
      invalid[doc.id] = data['isInvalid'] ?? false;
      final cooldownStr = data['cooldownUntil'] as String?;
      cooldowns[doc.id] = cooldownStr != null
          ? DateTime.tryParse(cooldownStr)
          : null;
    }

    final now = DateTime.now();

    final availableKeys = keys.where((k) {
      final id = _docId(provider.id, k);
      if (invalid[id] ?? false) return false;
      final isLimited = rateLimited[id] ?? false;
      if (!isLimited) return true;
      final cooldown = cooldowns[id];
      return cooldown != null && now.isAfter(cooldown);
    }).toList();

    final candidates = availableKeys.isNotEmpty ? availableKeys : keys;

    candidates.sort(
      (a, b) => (usageCounts[_docId(provider.id, a)] ?? 0).compareTo(
        usageCounts[_docId(provider.id, b)] ?? 0,
      ),
    );

    final selectedKey = candidates.first;

    await _db
        .collection(_keysCollection)
        .doc(_docId(provider.id, selectedKey))
        .set({
          'providerId': provider.id,
          'usageCount': FieldValue.increment(1),
          'lastUsedAt': now.toIso8601String(),
        }, SetOptions(merge: true));

    return selectedKey;
  }

  Future<void> reportSuccess(AiProvider provider, String key) async {
    await _db.collection(_keysCollection).doc(_docId(provider.id, key)).set({
      'isRateLimited': false,
      'isInvalid': false,
    }, SetOptions(merge: true));
  }

  Future<void> reportFailure(
    AiProvider provider,
    String key, {
    required String error,
  }) async {
    final lowerError = error.toLowerCase();
    final isRateLimit =
        error.contains('429') || lowerError.contains('rate limit');
    final isAuthFailure =
        error.contains('401') ||
        lowerError.contains('invalid api key') ||
        lowerError.contains('unauthorized') ||
        lowerError.contains('invalid_api_key');

    if (isRateLimit) {
      await _db.collection(_keysCollection).doc(_docId(provider.id, key)).set({
        'isRateLimited': true,
        'cooldownUntil': DateTime.now()
            .add(const Duration(minutes: 2))
            .toIso8601String(),
      }, SetOptions(merge: true));
      return;
    }

    if (isAuthFailure) {
      await _db.collection(_keysCollection).doc(_docId(provider.id, key)).set({
        'isInvalid': true,
        'lastError': error,
        'invalidatedAt': DateTime.now().toIso8601String(),
      }, SetOptions(merge: true));
    }
  }
}
