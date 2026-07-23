import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:cipher_ai/core/services/groq/ai_provider.dart';

/// Status returned by the key tester
enum KeyTestStatus {
  untested,
  testing,
  working,
  suspended,
  deleted,
  error,
}

class ApiKeyPoolInfo {
  const ApiKeyPoolInfo({
    required this.totalKeys,
    required this.availableCount,
    required this.rateLimitedCount,
    required this.invalidCount,
  });

  final int totalKeys;
  final int availableCount;
  final int rateLimitedCount;
  final int invalidCount;

  bool get hasKeys => totalKeys > 0;
  bool get allUnavailable => totalKeys > 0 && availableCount == 0;
}

class ProviderPoolService {
  ProviderPoolService._internal();
  static final ProviderPoolService instance = ProviderPoolService._internal();

  final _db = FirebaseFirestore.instance;
  static const _keysCollection = 'apiKeys';
  static const _providersCollection = 'providers';
  static const _selectedProviderDoc = 'settings/selectedProvider';

  static const _rateLimitCooldown = Duration(minutes: 2);
  static const _suspensionDuration = Duration(days: 1);

  // ===================================================================
  // Provider list persistence
  // ===================================================================

  Future<List<AiProvider>> getProviders() async {
    try {
      final snapshot = await _db.collection(_providersCollection).get();
      final overrides = <String, AiProvider>{
        for (final doc in snapshot.docs)
          if (doc.data()['id'] != null) doc.id: AiProvider.fromJson(doc.data()),
      };

      final result = <AiProvider>[];
      final seenIds = <String>{};

      for (final builtIn in builtInProviders) {
        seenIds.add(builtIn.id);
        result.add(overrides[builtIn.id] ?? builtIn);
      }

      for (final entry in overrides.entries) {
        if (!seenIds.contains(entry.key)) {
          result.add(entry.value);
        }
      }

      return result;
    } catch (e) {
      return List.of(builtInProviders);
    }
  }

  Future<void> saveProvider(AiProvider provider) async {
    await _db
        .collection(_providersCollection)
        .doc(provider.id)
        .set(provider.toJson());
  }

  Future<void> deleteProvider(String providerId) async {
    final isBuiltIn = builtInProviders.any((p) => p.id == providerId);
    if (isBuiltIn) {
      throw Exception('Cannot delete built-in provider "$providerId"');
    }
    await _db.collection(_providersCollection).doc(providerId).delete();

    try {
      final keyDocs = await _db
          .collection(_keysCollection)
          .where('providerId', isEqualTo: providerId)
          .get();
      final batch = _db.batch();
      for (final doc in keyDocs.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } catch (_) {}
  }

  bool hasApiKey(AiProvider provider) {
    return getKeyCount(provider) > 0;
  }

  int getKeyCount(AiProvider provider) {
    try {
      // Synchronous check just for UI display purposes
      final raw = dotenv.env[provider.apiKeyEnvVar];
      if (raw == null || raw.trim().isEmpty) return 0;
      return raw.split(',').map((k) => k.trim()).where((k) => k.isNotEmpty).length;
    } catch (_) {
      return 0;
    }
  }

  // ===================================================================
  // Selected provider + model
  // ===================================================================

  Future<void> setSelected({
    required String providerId,
    required String modelId,
  }) async {
    await _db.doc(_selectedProviderDoc).set({
      'providerId': providerId,
      'modelId': modelId,
      'updatedAt': DateTime.now().toIso8601String(),
    }, SetOptions(merge: true));
  }

  Future<({String providerId, String modelId})?> getSelected() async {
    try {
      final doc = await _db.doc(_selectedProviderDoc).get();
      final data = doc.data();
      if (data == null) return null;
      final providerId = data['providerId'] as String?;
      final modelId = data['modelId'] as String?;
      if (providerId == null || modelId == null) return null;
      return (providerId: providerId, modelId: modelId);
    } catch (_) {
      return null;
    }
  }

  // ===================================================================
  // Key management helpers
  // ===================================================================

  /// Reads keys for [provider] from .env. 
  /// NOTE: Asynchronous because it filters out permanently deleted keys from Firebase.
  Future<List<String>> _keysFor(AiProvider provider) async {
    final raw = dotenv.env[provider.apiKeyEnvVar];
    if (raw == null || raw.trim().isEmpty) {
      throw Exception(
        'No API key found for ${provider.name} '
        '(expected .env variable "${provider.apiKeyEnvVar}")',
      );
    }
    
    final keys = raw
        .split(',')
        .map((k) => k.trim())
        .where((k) => k.isNotEmpty)
        .toList();
        
    if (keys.isEmpty) {
      throw Exception('No valid API keys for ${provider.name}');
    }

    // Filter out permanently deleted keys so they aren't used even if still in .env
    try {
      final snapshot = await _db
          .collection(_keysCollection)
          .where('providerId', isEqualTo: provider.id)
          .where('isPermanentlyDeleted', isEqualTo: true)
          .get();

      final deletedIds = snapshot.docs.map((doc) => doc.id).toSet();
      keys.removeWhere((k) => deletedIds.contains(_docId(provider.id, k)));
      
      if (keys.isEmpty) {
        throw Exception('All API keys for ${provider.name} are permanently deleted.');
      }
    } catch (_) {
      // Best effort: if Firestore fails, proceed with unfiltered keys
    }

    return keys;
  }

  String _docId(String providerId, String key) {
    final suffix = key.length > 8 ? key.substring(key.length - 8) : key;
    return '${providerId}__key_$suffix';
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is String) return DateTime.tryParse(value);
    if (value is Timestamp) return value.toDate();
    return null;
  }

  Future<void> _ensureKeysSeeded(
    AiProvider provider,
    List<String> keys,
  ) async {
    final docIds = keys.map((k) => _docId(provider.id, k)).toSet();

    final snapshot = await _db
        .collection(_keysCollection)
        .where('providerId', isEqualTo: provider.id)
        .get();

    final existingIds = snapshot.docs.map((d) => d.id).toSet();
    final missing = docIds.difference(existingIds);

    if (missing.isEmpty) return;

    final batch = _db.batch();
    final now = DateTime.now().toIso8601String();
    for (final id in missing) {
      batch.set(_db.collection(_keysCollection).doc(id), {
        'providerId': provider.id,
        'usageCount': 0,
        'isRateLimited': false,
        'isInvalid': false,
        'isPermanentlyDeleted': false,
        'createdAt': now,
      });
    }
    await batch.commit();
  }

  // ===================================================================
  // Key rotation
  // ===================================================================

  Future<String> getNextKey(AiProvider provider) async {
    final keys = await _keysFor(provider);

    if (keys.length == 1) {
      final key = keys.first;
      try {
        await _ensureKeysSeeded(provider, keys);
        await _db
            .collection(_keysCollection)
            .doc(_docId(provider.id, key))
            .set({
          'providerId': provider.id,
          'usageCount': FieldValue.increment(1),
          'lastUsedAt': DateTime.now().toIso8601String(),
        }, SetOptions(merge: true));
      } catch (_) {}
      return key;
    }

    try {
      await _ensureKeysSeeded(provider, keys);
      return await _selectBestKey(provider, keys);
    } catch (_) {
      return keys.first;
    }
  }

  Future<String> _selectBestKey(
    AiProvider provider,
    List<String> keys,
  ) async {
    final snapshot = await _db
        .collection(_keysCollection)
        .where('providerId', isEqualTo: provider.id)
        .get();

    final now = DateTime.now();

    final usageCounts = <String, int>{};
    final rateLimited = <String, bool>{};
    final invalid = <String, bool>{};
    final cooldowns = <String, DateTime?>{};

    for (final doc in snapshot.docs) {
      final data = doc.data();
      usageCounts[doc.id] = (data['usageCount'] as num?)?.toInt() ?? 0;
      rateLimited[doc.id] = data['isRateLimited'] as bool? ?? false;
      invalid[doc.id] = data['isInvalid'] as bool? ?? false;
      cooldowns[doc.id] = _parseDate(data['cooldownUntil']);
    }

    final usable = <String>[];
    for (final key in keys) {
      final id = _docId(provider.id, key);
      if (invalid[id] ?? false) continue;
      final isLimited = rateLimited[id] ?? false;
      if (isLimited) {
        final cooldown = cooldowns[id];
        if (cooldown != null && now.isBefore(cooldown)) continue;
      }
      usable.add(key);
    }

    final candidates = usable.isNotEmpty ? usable : keys;

    candidates.sort((a, b) {
      final aCount = usageCounts[_docId(provider.id, a)] ?? 0;
      final bCount = usageCounts[_docId(provider.id, b)] ?? 0;
      return aCount.compareTo(bCount);
    });

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

  // ===================================================================
  // Success / failure reporting
  // ===================================================================

  Future<void> reportSuccess(AiProvider provider, String key) async {
    try {
      await _db
          .collection(_keysCollection)
          .doc(_docId(provider.id, key))
          .set({
        'isRateLimited': false,
        'isInvalid': false,
        'lastSuccessAt': DateTime.now().toIso8601String(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<void> reportFailure(
    AiProvider provider,
    String key, {
    required String error,
    int? statusCode,
  }) async {
    final code = statusCode;
    final lowerError = error.toLowerCase();

    final isRateLimit = code == 429 ||
        lowerError.contains('429') ||
        lowerError.contains('rate limit') ||
        lowerError.contains('rate_limit') ||
        lowerError.contains('too many requests');

    final isAuthFailure = code == 401 ||
        code == 403 ||
        lowerError.contains('401') ||
        lowerError.contains('403') ||
        lowerError.contains('invalid api key') ||
        lowerError.contains('invalid_api_key') ||
        lowerError.contains('unauthorized') ||
        lowerError.contains('forbidden') ||
        lowerError.contains('authentication');

    try {
      if (isRateLimit) {
        await _db
            .collection(_keysCollection)
            .doc(_docId(provider.id, key))
            .set({
          'providerId': provider.id,
          'isRateLimited': true,
          'cooldownUntil':
              DateTime.now().add(_rateLimitCooldown).toIso8601String(),
          'lastError': error,
        }, SetOptions(merge: true));
        return;
      }

      if (isAuthFailure) {
        await _db
            .collection(_keysCollection)
            .doc(_docId(provider.id, key))
            .set({
          'providerId': provider.id,
          'isInvalid': true,
          'lastError': error,
          'invalidatedAt': DateTime.now().toIso8601String(),
        }, SetOptions(merge: true));
      }
    } catch (_) {}
  }

  // ===================================================================
  // Key Testing & Management (New)
  // ===================================================================

  /// Fetches raw keys for UI display (filters out permanently deleted)
  Future<List<String>> getRawKeysForUi(AiProvider provider) async {
    try {
      return await _keysFor(provider);
    } catch (_) {
      return [];
    }
  }

  /// Tests an API key by sending a minimal request. 
  /// - If it works: clears flags.
  /// - If it fails (Day 1): Suspends for 1 day.
  /// - If it fails (Day 2+): Permanently deletes from Firebase and .env
  Future<KeyTestStatus> testKey(AiProvider provider, AiModel model, String key) async {
    final docId = _docId(provider.id, key);
    
    // 1. Check existing status in Firestore
    DateTime? suspendedUntil;
    try {
      final docSnap = await _db.collection(_keysCollection).doc(docId).get();
      if (docSnap.exists) {
        final data = docSnap.data()!;
        if (data['isPermanentlyDeleted'] == true) return KeyTestStatus.deleted;
        suspendedUntil = _parseDate(data['suspendedUntil']);
        
        // If currently suspended and time hasn't passed, don't test yet
        if (suspendedUntil != null && DateTime.now().isBefore(suspendedUntil)) {
          return KeyTestStatus.suspended;
        }
      }
    } catch (_) {}

    // 2. Perform the API Test
    final bool isWorking = await _performApiTest(provider, model, key);
    final now = DateTime.now();

    try {
      if (isWorking) {
        // Reset all flags on success
        await _db.collection(_keysCollection).doc(docId).set({
          'providerId': provider.id,
          'isRateLimited': false,
          'isInvalid': false,
          'suspendedUntil': null,
          'lastTestedAt': now.toIso8601String(),
          'lastSuccessAt': now.toIso8601String(),
        }, SetOptions(merge: true));
        return KeyTestStatus.working;
      } else {
        // It failed
        if (suspendedUntil == null) {
          // Day 1 Failure -> Suspend for 1 day
          await _db.collection(_keysCollection).doc(docId).set({
            'providerId': provider.id,
            'suspendedUntil': now.add(_suspensionDuration).toIso8601String(),
            'lastTestedAt': now.toIso8601String(),
            'lastError': 'Test failed (Day 1)',
          }, SetOptions(merge: true));
          return KeyTestStatus.suspended;
        } else {
          // Day 2+ Failure -> Permanently Delete
          await _deleteKeyPermanently(provider, key);
          return KeyTestStatus.deleted;
        }
      }
    } catch (_) {
      return KeyTestStatus.error;
    }
  }

  Future<bool> _performApiTest(AiProvider provider, AiModel model, String key) async {
    try {
      final response = await http.post(
        Uri.parse(provider.baseUrl),
        headers: {
          "Authorization": "Bearer $key",
          "Content-Type": "application/json",
        },
        body: jsonEncode({
          "model": model.id,
          "messages": [{"role": "user", "content": "1"}],
          "max_tokens": 1, // Keep it as cheap as possible
        }),
      ).timeout(const Duration(seconds: 15));

      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<void> _deleteKeyPermanently(AiProvider provider, String key) async {
    final docId = _docId(provider.id, key);
    
    // 1. Mark as permanently deleted in Firestore
    try {
      await _db.collection(_keysCollection).doc(docId).set({
        'providerId': provider.id,
        'isPermanentlyDeleted': true,
        'isInvalid': true,
        'deletedAt': DateTime.now().toIso8601String(),
      }, SetOptions(merge: true));
    } catch (_) {}

    // 2. Remove from in-memory dotenv map
    final raw = dotenv.env[provider.apiKeyEnvVar] ?? '';
    final keys = raw.split(',').map((k) => k.trim()).where((k) => k.isNotEmpty).toList();
    keys.remove(key);
    
    final newRaw = keys.join(',');
    dotenv.env[provider.apiKeyEnvVar] = newRaw;

    // 3. Attempt to update the physical .env file (works on desktop/mobile)
    if (!kIsWeb) {
      try {
        final file = File('.env');
        if (file.existsSync()) {
          final lines = file.readAsLinesSync();
          final updatedLines = <String>[];
          for (var line in lines) {
            if (line.startsWith('${provider.apiKeyEnvVar}=')) {
              updatedLines.add('${provider.apiKeyEnvVar}=$newRaw');
            } else {
              updatedLines.add(line);
            }
          }
          file.writeAsStringSync(updatedLines.join('\n'));
        }
      } catch (_) {
        // Silently fail if file system isn't writable (e.g. mobile app sandbox)
      }
    }
  }
}