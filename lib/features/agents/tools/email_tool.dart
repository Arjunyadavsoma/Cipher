import 'dart:convert';

import 'package:googleapis/gmail/v1.dart' as gmail;

import '../../../core/services/gmail/gmail_auth_service.dart';
import '../models/tool.dart';

/// Real Gmail integration. Supports four operations via input['type']:
///   'send'   -> { to, subject, body }
///   'fetch'  -> { maxResults } -> returns recent inbox messages (metadata only)
///   'search' -> { query, maxResults } -> Gmail search syntax (from:, subject:,
///               after:, etc.), returns matching messages newest-first
///   'get'    -> { id } -> full content (including plain-text body) of one
///               specific message, used to read a single search result in full
///
/// Throws GmailNotConnectedException if the user hasn't connected their
/// Gmail account yet - EmailAgent catches this and asks them to connect.
class EmailTool implements Tool {
  @override
  String get name => 'email';

  @override
  Future<dynamic> execute(Map<String, dynamic> input) async {
    final client = await GmailAuthService.instance.getClient();
    if (client == null) {
      throw GmailNotConnectedException();
    }

    final api = gmail.GmailApi(client);
    final type = input['type'] as String? ?? 'send';

    switch (type) {
      case 'send':
        return _send(api, input);
      case 'fetch':
        return _fetch(api, input);
      case 'search':
        return _search(api, input);
      case 'get':
        return _get(api, input);
      default:
        throw Exception("Unknown email tool operation: $type");
    }
  }

  Future<String> _send(gmail.GmailApi api, Map<String, dynamic> input) async {
    final to = input['to'] as String;
    final subject = input['subject'] as String? ?? '';
    final body = input['body'] as String? ?? '';

    final raw = _buildRawMessage(to: to, subject: subject, body: body);
    final message = gmail.Message()..raw = raw;

    final sent = await api.users.messages.send(message, 'me');

    // ignore: avoid_print
    print('Gmail send response -> id: ${sent.id}, threadId: ${sent.threadId}, '
        'labelIds: ${sent.labelIds}');

    if (sent.id == null) {
      throw Exception(
          'Gmail API returned no message id - send likely did not complete.');
    }

    return 'sent';
  }

  String _buildRawMessage({
    required String to,
    required String subject,
    required String body,
  }) {
    final email = 'MIME-Version: 1.0\r\n'
        'To: $to\r\n'
        'Subject: $subject\r\n'
        'Content-Type: text/plain; charset=utf-8\r\n'
        '\r\n'
        '$body';

    return base64Url.encode(utf8.encode(email)).replaceAll('=', '');
  }

  Future<List<Map<String, String>>> _fetch(
    gmail.GmailApi api,
    Map<String, dynamic> input,
  ) async {
    final maxResults = input['maxResults'] as int? ?? 10;

    final listResponse = await api.users.messages.list(
      'me',
      maxResults: maxResults,
    );

    return _hydrateMetadata(api, listResponse.messages ?? []);
  }

  /// Server-side Gmail search using Gmail's own query syntax, e.g.
  /// "from:arjun", "subject:invoice after:2026/07/01". Results come back
  /// newest-first already, which is what most "what was the email from X"
  /// requests want.
  Future<List<Map<String, String>>> _search(
    gmail.GmailApi api,
    Map<String, dynamic> input,
  ) async {
    final query = input['query'] as String? ?? '';
    final maxResults = input['maxResults'] as int? ?? 10;

    if (query.trim().isEmpty) return [];

    final listResponse = await api.users.messages.list(
      'me',
      q: query,
      maxResults: maxResults,
    );

    final results = await _hydrateMetadata(api, listResponse.messages ?? []);
    // ignore: avoid_print
    print('EmailTool.search("$query") -> ${results.length} result(s)');
    return results;
  }

  /// Fetches one specific message in full (including a decoded plain-text
  /// body), used when the user wants to actually read a search result
  /// rather than just see its subject/snippet.
  Future<Map<String, String>> _get(
    gmail.GmailApi api,
    Map<String, dynamic> input,
  ) async {
    final id = input['id'] as String;

    final full = await api.users.messages.get(
      'me',
      id,
      format: 'full',
    );

    final headers = full.payload?.headers ?? [];
    String header(String name) {
      for (final h in headers) {
        if (h.name == name) return h.value ?? '';
      }
      return '';
    }

    return {
      'id': id,
      'from': header('From'),
      'subject': header('Subject'),
      'date': header('Date'),
      'snippet': full.snippet ?? '',
      'body': _extractPlainTextBody(full.payload) ?? full.snippet ?? '',
    };
  }

  /// Shared by _fetch/_search: given message refs from a list() call,
  /// fetches metadata (From/Subject/Date + snippet) for each one.
  Future<List<Map<String, String>>> _hydrateMetadata(
    gmail.GmailApi api,
    List<gmail.Message> messageRefs,
  ) async {
    final results = <Map<String, String>>[];

    for (final ref in messageRefs) {
      if (ref.id == null) continue;

      final full = await api.users.messages.get(
        'me',
        ref.id!,
        format: 'metadata',
        metadataHeaders: ['From', 'Subject', 'Date'],
      );

      final headers = full.payload?.headers ?? [];

      String header(String name) {
        for (final h in headers) {
          if (h.name == name) return h.value ?? '';
        }
        return '';
      }

      results.add({
        'id': ref.id!,
        'from': header('From'),
        'subject': header('Subject'),
        'date': header('Date'),
        'snippet': full.snippet ?? '',
      });
    }

    return results;
  }

  /// Walks a Gmail message payload's MIME parts (it's a tree - multipart
  /// messages nest text/plain and text/html as siblings, sometimes several
  /// levels deep for mixed attachments) looking for a text/plain part, and
  /// base64url-decodes it. Falls back to null (caller uses the snippet)
  /// if the message has no plain-text part at all (rare, but some HTML-only
  /// newsletters omit it).
  String? _extractPlainTextBody(gmail.MessagePart? part) {
    if (part == null) return null;

    if (part.mimeType == 'text/plain' && part.body?.data != null) {
      return utf8.decode(
        base64Url.decode(_normalizeBase64(part.body!.data!)),
        allowMalformed: true,
      );
    }

    for (final child in part.parts ?? const <gmail.MessagePart>[]) {
      final result = _extractPlainTextBody(child);
      if (result != null) return result;
    }

    return null;
  }

  String _normalizeBase64(String data) {
    final padded = data.padRight((data.length + 3) ~/ 4 * 4, '=');
    return padded;
  }
}