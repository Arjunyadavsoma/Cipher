import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Manages the pool of Groq API keys. Selection strategy: least-used-first,
/// with usage counters persisted in Firestore so the pool stays balanced
/// across app restarts and devices. Keys that hit a rate limit are put on
/// cooldown and skipped until it expires. Keys that fail authentication
/// entirely (invalid/revoked) are quarantined indefinitely, since retrying
/// them will never succeed.
class ApiKeyPoolService {
  ApiKeyPoolService._internal();

  static final ApiKeyPoolService instance = ApiKeyPoolService._internal();

  final _db = FirebaseFirestore.instance;
  static const _collection = 'apiKeys';

  /// Reads keys from .env. Supports either:
  ///   GROQ_API_KEYS=key1,key2,key3   (comma-separated - use this once you
  ///                                    add the other ~30 keys)
  ///   GROQ_API_KEY=key1              (single key - current setup)
  List<String> get _keys {
    final multi = dotenv.env['GROQ_API_KEYS'];
    if (multi != null && multi.trim().isNotEmpty) {
      return multi
          .split(',')
          .map((k) => k.trim())
          .where((k) => k.isNotEmpty)
          .toList();
    }

    final single = dotenv.env['GROQ_API_KEY'];
    if (single != null && single.trim().isNotEmpty) {
      return [single.trim()];
    }

    throw Exception(
      "No Groq API keys found in .env (set GROQ_API_KEY or GROQ_API_KEYS)",
    );
  }

  Future<String> getNextKey() async {
    final keys = _keys;

    // Only one key configured - nothing to rotate, skip the Firestore
    // lookup entirely and just track usage for when more keys are added.
    if (keys.length == 1) {
      final key = keys.first;
      await _db.collection(_collection).doc(_keyId(key)).set({
        'usageCount': FieldValue.increment(1),
        'lastUsedAt': DateTime.now().toIso8601String(),
      }, SetOptions(merge: true));
      return key;
    }

    final snapshot = await _db.collection(_collection).get();

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
      cooldowns[doc.id] =
          cooldownStr != null ? DateTime.tryParse(cooldownStr) : null;
    }

    final now = DateTime.now();

    final availableKeys = keys.where((k) {
      final id = _keyId(k);

      // Invalid keys never come back on their own - unlike a rate limit,
      // there's no cooldown that fixes a revoked/wrong key. Only way out
      // of quarantine is a manual reportSuccess() (i.e. the key actually
      // works again) or removing it from .env.
      if (invalid[id] ?? false) return false;

      final isLimited = rateLimited[id] ?? false;
      if (!isLimited) return true;
      final cooldown = cooldowns[id];
      return cooldown != null && now.isAfter(cooldown);
    }).toList();

    // If literally every key is quarantined (all invalid, or all still
    // cooling down), fall back to the full list rather than throwing -
    // a guessed retry is better than a hard failure, and reportFailure
    // will just re-quarantine whichever one fails again.
    final candidates = availableKeys.isNotEmpty ? availableKeys : keys;

    candidates.sort(
      (a, b) =>
          (usageCounts[_keyId(a)] ?? 0).compareTo(usageCounts[_keyId(b)] ?? 0),
    );

    final selectedKey = candidates.first;

    await _db.collection(_collection).doc(_keyId(selectedKey)).set({
      'usageCount': FieldValue.increment(1),
      'lastUsedAt': now.toIso8601String(),
    }, SetOptions(merge: true));

    return selectedKey;
  }

  Future<void> reportSuccess(String key) async {
    await _db.collection(_collection).doc(_keyId(key)).set({
      'isRateLimited': false,
      'isInvalid': false,
    }, SetOptions(merge: true));
  }

  Future<void> reportFailure(String key, {required String error}) async {
    final lowerError = error.toLowerCase();
    final isRateLimit = error.contains('429') || lowerError.contains('rate limit');
    final isAuthFailure = error.contains('401') ||
        lowerError.contains('invalid api key') ||
        lowerError.contains('unauthorized') ||
        lowerError.contains('invalid_api_key');

    if (isRateLimit) {
      await _db.collection(_collection).doc(_keyId(key)).set({
        'isRateLimited': true,
        'cooldownUntil':
            DateTime.now().add(const Duration(minutes: 2)).toIso8601String(),
      }, SetOptions(merge: true));
      return;
    }

    if (isAuthFailure) {
      // No cooldown here on purpose - an invalid key doesn't become valid
      // after a fixed wait. It stays quarantined until reportSuccess()
      // proves it works (e.g. after you swap in a corrected key under
      // the same .env slot) - see _keyId note below on why that's safe.
      await _db.collection(_collection).doc(_keyId(key)).set({
        'isInvalid': true,
        'lastError': error,
        'invalidatedAt': DateTime.now().toIso8601String(),
      }, SetOptions(merge: true));
    }
  }

  /// Uses a short suffix of the key as the Firestore doc ID instead of the
  /// raw key, so full API keys never appear in Firestore document paths
  /// or logs.
  ///
  /// NOTE: if you replace a bad key in .env with a corrected one that
  /// happens to share the same last 6 characters, it will inherit that
  /// old key's quarantine doc. Vanishingly unlikely by chance, but if you
  /// ever swap keys and one mysteriously stays "invalid", check for this.
  String _keyId(String key) {
    final suffix = key.length > 6 ? key.substring(key.length - 6) : key;
    return 'key_$suffix';
  }
}