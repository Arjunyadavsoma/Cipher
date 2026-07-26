import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:googleapis/gmail/v1.dart' as gmail;

import '../../../core/services/gmail/gmail_auth_service.dart';
import '../models/tool.dart';

/// Real Gmail integration. Supports four operations via input['type']:
///   'send'   -> { to, subject, body, cc?, bcc?, threadId?, inReplyTo?,
///                 attachmentPaths? } -- attachmentPaths is a list of local
///               file paths; missing files are skipped (logged), not fatal
///   'fetch'  -> { maxResults } -> returns recent inbox messages (metadata only)
///   'search' -> { query, maxResults } -> Gmail search syntax (from:, subject:,
///               after:, etc.), returns matching messages newest-first
///   'get'    -> { id } -> full content (including plain-text body) of one
///               specific message, used to read a single search result in full
///
/// Throws GmailNotConnectedException if the user hasn't connected their
/// Gmail account yet - EmailAgent catches this and asks them to connect.
/// Throws EmailToolException for bad input or Gmail API failures, with a
/// message that's safe to surface to the agent/user directly.
class EmailTool implements Tool {
  @override
  String get name => 'email';

  /// Gmail allows up to 500 results per list() call; guard against callers
  /// accidentally requesting something absurd.
  static const int _maxAllowedResults = 500;

  /// How many per-message detail fetches we run in parallel when hydrating
  /// a list of message refs. Parallelizing (instead of the previous
  /// one-at-a-time loop) is a large latency win for fetch/search, while
  /// staying low enough to be gentle on Gmail's per-user rate limits.
  static const int _hydrateConcurrency = 5;

  @override
  Future<dynamic> execute(Map<String, dynamic> input) async {
    final client = await GmailAuthService.instance.getClient();
    if (client == null) {
      throw GmailNotConnectedException();
    }

    final api = gmail.GmailApi(client);
    final type = input['type'] as String? ?? 'send';

    try {
      switch (type) {
        case 'send':
          return await _send(api, input);
        case 'fetch':
          return await _fetch(api, input);
        case 'search':
          return await _search(api, input);
        case 'get':
          return await _get(api, input);
        default:
          throw EmailToolException("Unknown email tool operation: '$type'");
      }
    } on gmail.DetailedApiRequestError catch (e) {
      throw EmailToolException(_describeApiError(e));
    }
  }

  // ---------------------------------------------------------------------
  // send
  // ---------------------------------------------------------------------

  Future<String> _send(gmail.GmailApi api, Map<String, dynamic> input) async {
    final to = (input['to'] as String?)?.trim();
    if (to == null || to.isEmpty) {
      throw EmailToolException("email 'send' requires a non-empty 'to'.");
    }

    final subject = input['subject'] as String? ?? '';
    final body = input['body'] as String? ?? '';
    final cc = input['cc'] as String?;
    final bcc = input['bcc'] as String?;
    final threadId = input['threadId'] as String?;
    final inReplyTo = input['inReplyTo'] as String?;
    final attachmentPaths =
        (input['attachmentPaths'] as List?)?.cast<String>() ?? const [];

    final raw = await _buildRawMessage(
      to: to,
      subject: subject,
      body: body,
      cc: cc,
      bcc: bcc,
      inReplyTo: inReplyTo,
      attachmentPaths: attachmentPaths,
    );

    final message = gmail.Message()..raw = raw;
    if (threadId != null && threadId.isNotEmpty) {
      // Keeps the sent message in the same Gmail thread as the message
      // being replied to, rather than starting a new thread.
      message.threadId = threadId;
    }

    final sent = await api.users.messages.send(message, 'me');

    _log('Gmail send response -> id: ${sent.id}, threadId: ${sent.threadId}, '
        'labelIds: ${sent.labelIds}');

    if (sent.id == null) {
      throw EmailToolException(
          'Gmail API returned no message id - send likely did not complete.');
    }

    return 'sent';
  }

  /// Builds the raw RFC 2822 message and returns it base64url-encoded for
  /// the Gmail API. With no attachments this is a single text/plain part
  /// (same as before); with [attachmentPaths] non-empty it becomes a
  /// multipart/mixed message with one part per attachment. A missing or
  /// unreadable attachment is skipped (and logged) rather than failing
  /// the whole send - better to deliver the email without one attachment
  /// than to silently drop the entire message.
  Future<String> _buildRawMessage({
    required String to,
    required String subject,
    required String body,
    String? cc,
    String? bcc,
    String? inReplyTo,
    List<String> attachmentPaths = const [],
  }) async {
    final headers = StringBuffer()
      ..write('MIME-Version: 1.0\r\n')
      ..write('To: $to\r\n');

    if (cc != null && cc.trim().isNotEmpty) {
      headers.write('Cc: ${cc.trim()}\r\n');
    }
    if (bcc != null && bcc.trim().isNotEmpty) {
      headers.write('Bcc: ${bcc.trim()}\r\n');
    }
    if (inReplyTo != null && inReplyTo.trim().isNotEmpty) {
      // Both headers are conventionally set to the Message-ID being
      // replied to; this is what makes mail clients (and Gmail itself)
      // render the message as part of the existing conversation.
      headers.write('In-Reply-To: ${inReplyTo.trim()}\r\n');
      headers.write('References: ${inReplyTo.trim()}\r\n');
    }
    headers.write('Subject: ${_encodeHeaderValue(subject)}\r\n');

    if (attachmentPaths.isEmpty) {
      headers
        ..write('Content-Type: text/plain; charset=utf-8\r\n')
        ..write('Content-Transfer-Encoding: base64\r\n')
        ..write('\r\n');

      final email =
          headers.toString() + _wrapBase64(base64.encode(utf8.encode(body)));
      return base64Url.encode(utf8.encode(email)).replaceAll('=', '');
    }

    final boundary = 'cipher_${DateTime.now().microsecondsSinceEpoch}';
    headers.write(
      'Content-Type: multipart/mixed; boundary="$boundary"\r\n\r\n',
    );

    final parts = StringBuffer()
      ..write('--$boundary\r\n')
      ..write('Content-Type: text/plain; charset=utf-8\r\n')
      ..write('Content-Transfer-Encoding: base64\r\n\r\n')
      ..write(_wrapBase64(base64.encode(utf8.encode(body))))
      ..write('\r\n');

    for (final path in attachmentPaths) {
      final file = File(path);
      if (!await file.exists()) {
        _log('Attachment not found, skipping: $path');
        continue;
      }

      final List<int> bytes;
      try {
        bytes = await file.readAsBytes();
      } catch (e) {
        _log('Failed to read attachment, skipping: $path ($e)');
        continue;
      }

      final filename = path.split(Platform.pathSeparator).last;
      final contentType = _guessContentType(filename);

      parts
        ..write('--$boundary\r\n')
        ..write('Content-Type: $contentType; name="$filename"\r\n')
        ..write('Content-Disposition: attachment; filename="$filename"\r\n')
        ..write('Content-Transfer-Encoding: base64\r\n\r\n')
        ..write(_wrapBase64(base64.encode(bytes)))
        ..write('\r\n');
    }
    parts.write('--$boundary--');

    final email = headers.toString() + parts.toString();
    return base64Url.encode(utf8.encode(email)).replaceAll('=', '');
  }

  /// Best-effort Content-Type guess from a file extension - we only have
  /// a local path to go on, no real metadata. Falls back to a generic
  /// binary type, which Gmail/mail clients still handle fine (just
  /// without a nice icon).
  String _guessContentType(String filename) {
    final dot = filename.lastIndexOf('.');
    final ext = dot == -1 ? '' : filename.substring(dot + 1).toLowerCase();
    const byExtension = {
      'pdf': 'application/pdf',
      'png': 'image/png',
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'gif': 'image/gif',
      'txt': 'text/plain',
      'csv': 'text/csv',
      'doc': 'application/msword',
      'docx':
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls': 'application/vnd.ms-excel',
      'xlsx':
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'zip': 'application/zip',
    };
    return byExtension[ext] ?? 'application/octet-stream';
  }

  /// RFC 2045 expects base64 body lines wrapped (76 chars is conventional);
  /// some mail relays reject or mangle unwrapped lines, which matters more
  /// once attachments make bodies much longer.
  String _wrapBase64(String encoded) {
    final buffer = StringBuffer();
    for (var i = 0; i < encoded.length; i += 76) {
      final end = i + 76 > encoded.length ? encoded.length : i + 76;
      buffer.write(encoded.substring(i, end));
      buffer.write('\r\n');
    }
    return buffer.toString();
  }

  /// Encodes a header value per RFC 2047 if it contains non-ASCII
  /// characters (e.g. emoji or accented names in a subject line).
  /// Plain-ASCII subjects pass through unchanged.
  String _encodeHeaderValue(String value) {
    final isAscii = value.codeUnits.every((c) => c < 128);
    if (isAscii) return value;
    final encoded = base64.encode(utf8.encode(value));
    return '=?UTF-8?B?$encoded?=';
  }

  // ---------------------------------------------------------------------
  // fetch / search
  // ---------------------------------------------------------------------

  Future<List<Map<String, String>>> _fetch(
    gmail.GmailApi api,
    Map<String, dynamic> input,
  ) async {
    final maxResults = _clampMaxResults(input['maxResults'] as int? ?? 10);

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
    final query = (input['query'] as String? ?? '').trim();
    final maxResults = _clampMaxResults(input['maxResults'] as int? ?? 10);

    if (query.isEmpty) {
      throw EmailToolException("email 'search' requires a non-empty 'query'.");
    }

    final listResponse = await api.users.messages.list(
      'me',
      q: query,
      maxResults: maxResults,
    );

    final results = await _hydrateMetadata(api, listResponse.messages ?? []);
    _log('EmailTool.search("$query") -> ${results.length} result(s)');
    return results;
  }

  int _clampMaxResults(int requested) {
    if (requested <= 0) return 10;
    return requested > _maxAllowedResults ? _maxAllowedResults : requested;
  }

  /// Fetches one specific message in full (including a decoded plain-text
  /// body), used when the user wants to actually read a search result
  /// rather than just see its subject/snippet.
  Future<Map<String, String>> _get(
    gmail.GmailApi api,
    Map<String, dynamic> input,
  ) async {
    final id = (input['id'] as String?)?.trim();
    if (id == null || id.isEmpty) {
      throw EmailToolException("email 'get' requires a non-empty 'id'.");
    }

    final gmail.Message full;
    try {
      full = await api.users.messages.get('me', id, format: 'full');
    } on gmail.DetailedApiRequestError catch (e) {
      if (e.status == 404) {
        throw EmailToolException("No message found with id '$id'.");
      }
      rethrow;
    }

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
  /// fetches metadata (From/Subject/Date + snippet) for each one, in
  /// parallel batches of [_hydrateConcurrency] rather than one request
  /// at a time.
  Future<List<Map<String, String>>> _hydrateMetadata(
    gmail.GmailApi api,
    List<gmail.Message> messageRefs,
  ) async {
    final ids = messageRefs.where((m) => m.id != null).map((m) => m.id!).toList();
    final results = <Map<String, String>>[];

    for (var i = 0; i < ids.length; i += _hydrateConcurrency) {
      final chunk = ids.skip(i).take(_hydrateConcurrency);
      final chunkResults = await Future.wait(chunk.map((id) async {
        final full = await api.users.messages.get(
          'me',
          id,
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

        return {
          'id': id,
          'from': header('From'),
          'subject': header('Subject'),
          'date': header('Date'),
          'snippet': full.snippet ?? '',
        };
      }));
      results.addAll(chunkResults);
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
      try {
        return utf8.decode(
          base64Url.decode(_normalizeBase64(part.body!.data!)),
          allowMalformed: true,
        );
      } catch (_) {
        // Malformed base64 in a single part shouldn't take down the whole
        // read - fall through and keep looking at sibling parts.
      }
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

  // ---------------------------------------------------------------------
  // errors / logging
  // ---------------------------------------------------------------------

  String _describeApiError(gmail.DetailedApiRequestError e) {
    switch (e.status) {
      case 401:
        return 'Gmail authorization has expired or was revoked. '
            'Please reconnect your Gmail account.';
      case 403:
        return 'Gmail denied this request (insufficient permission or '
            'quota exceeded). Details: ${e.message}';
      case 429:
        return 'Gmail rate limit hit - please try again shortly.';
      default:
        return 'Gmail API error (${e.status}): ${e.message}';
    }
  }

  void _log(String message) {
    // dart:developer's log() is a no-op in release builds by default and
    // integrates with DevTools/observatory, unlike print() which always
    // writes to stdout and has no severity/filtering.
    dev.log(message, name: 'EmailTool');
  }
}

/// Thrown for bad tool input or translated Gmail API failures. The message
/// is written to be safe to show directly to the user/agent.
class EmailToolException implements Exception {
  final String message;
  EmailToolException(this.message);

  @override
  String toString() => message;
}