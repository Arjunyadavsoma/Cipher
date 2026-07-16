import 'dart:convert';

import '../../../core/services/gmail/gmail_auth_service.dart';
import '../core/base_agent.dart';
import '../core/tool_manager.dart';
import '../models/agent_context_storage.dart';
import '../models/execution_context.dart';
import '../models/execution_result.dart';
import '../repositories/agent_memory_repository.dart';

/// Handles five things:
///   1. COMPOSE  - draft an email (does NOT send immediately - saves a
///                 pending draft and asks the user to confirm)
///   2. CONFIRM  - user says "send it" / "yes" -> actually dispatches the
///                 saved pending draft via Gmail
///   3. SEARCH_INBOX - user wants to find/recall a specific email or
///                 emails ("what was the email from Arjun") -> searches
///                 via Gmail's own query syntax, with fallbacks, and
///                 supports follow-ups ("the first one", "read it")
///   4. SUMMARIZE - user pastes/references email text and wants a summary
///   5. READ_INBOX - user asks to check/summarize their actual inbox ->
///                    fetches real recent emails via Gmail, then summarizes
class EmailAgent implements BaseAgent {
  @override
  String get id => 'email_agent';

  @override
  String get name => 'Email Agent';

  @override
  String get description =>
      'Handles writing, summarizing, sending emails, and reading/summarizing '
      'the user\'s inbox. Use for any request involving composing a '
      'professional email, summarizing an email or email thread, checking '
      'recent emails, or sending a message to a specific email address.';

  @override
  String get systemPrompt => '''
You are the Email Agent inside Mimir AI. Classify the user's message into
exactly one of these intents:

- COMPOSE: user wants to write and/or send a NEW email. Extract the
  recipient's email address if mentioned, a subject line, and a
  professional body.
- SEARCH_INBOX: user wants to find or recall a specific email or emails
  already in their inbox - e.g. "what was the email from Arjun", "find
  emails about the invoice", "show me all emails from Priya last week".
  This is about looking something up, not composing anything new.
- SUMMARIZE: user has pasted or referenced specific email content and
  wants a summary of it.
- READ_INBOX: user wants to check, review, or summarize their actual
  inbox/recent emails in general (no pasted content, no specific
  sender/topic to search for - they just want an overview).
- OTHER: anything else email-related that doesn't fit the above.

For SEARCH_INBOX, also extract:
- senderName: the person/sender mentioned, if any (a first name is fine,
  e.g. "arjun"), else ""
- keywords: subject/body search terms, if any, else "" (leave "" if the
  user only gave a sender name)
- dateHint: a date/time phrase if mentioned (e.g. "yesterday", "last
  week", "this month"), else ""
- scope: "latest" if they want just the most recent match (this is the
  default when unclear), "all" if they explicitly want every match, or
  "count:N" if they asked for a specific number (e.g. "the last 3")
- question: what they actually want to know about the email, in their
  own words (e.g. "what was it about"), else ""

Always respond with JSON only, no other text, in this exact shape:
{
  "intent": "compose" | "search_inbox" | "summarize" | "read_inbox" | "other",
  "recipientEmail": "<email address, or empty string if unknown>",
  "subject": "<subject line, or empty string>",
  "body": "<email body for compose, or summary text for summarize>",
  "responseText": "<short natural-language message to show the user>",
  "senderName": "<sender name for search_inbox, or empty string>",
  "keywords": "<search keywords for search_inbox, or empty string>",
  "dateHint": "<date phrase for search_inbox, or empty string>",
  "scope": "<latest | all | count:N, or empty string>",
  "question": "<what the user wants to know, or empty string>"
}
''';

  @override
  List<String> get tools => ['groq', 'email'];

  @override
  AgentContextStorage get contextStorage => AgentContextStorage.firestore;

  static const _confirmWords = [
    'send it',
    'yes send',
    'yes, send',
    'yes',
    'go ahead',
    'confirm',
    'please send',
    'send now',
  ];

  static const _cancelWords = [
    'cancel',
    'don\'t send',
    'discard',
    'never mind',
  ];

  /// Phrases that indicate the user is referring back to a previous inbox
  /// search ("the first one", "read it", "what did it say") rather than
  /// starting a new request. Deliberately a fixed phrase list rather than
  /// "any short message" - the same tradeoff as _confirmWords above: a
  /// plain word list is predictable and easy to extend, where a length
  /// heuristic would misfire on short-but-unrelated replies like "thanks".
  static const _searchFollowUpPhrases = [
    'first one',
    'the first',
    'second one',
    'the second',
    'third one',
    'the third',
    'last one',
    'the last',
    'oldest one',
    'next one',
    'the next',
    'newer one',
    'previous one',
    'the previous',
    'before that',
    'earlier one',
    'another one',
    'show me another',
    'read it',
    'read that',
    'read the',
    'open it',
    'open that',
    'full email',
    'full message',
    'what did it say',
    'what does it say',
    'what did they say',
  ];

  /// Used by AgentExecutor's sticky-routing check: if EmailAgent has
  /// pending search results waiting, a short reference like "the first
  /// one" has no context of its own for the classifier to work with and
  /// would otherwise get misrouted - same problem "send it" had for
  /// pendingDraft.
  static bool looksLikeSearchFollowUp(String message) {
    final lower = message.toLowerCase();
    return _searchFollowUpPhrases.any(lower.contains);
  }

  @override
  Future<AgentExecutionResult> execute(ExecutionContext context) async {
    final pendingDraft = context.agentMemory?['pendingDraft'] as Map?;

    if (pendingDraft != null) {
      final lower = context.message.toLowerCase();

      if (_cancelWords.any(lower.contains)) {
        await _clearPendingDraft(context);
        return AgentExecutionResult(
          responseText: "Okay, I've discarded that draft.",
          agentName: name,
        );
      }

      if (_confirmWords.any(lower.contains)) {
        return _dispatchPendingDraft(context, pendingDraft);
      }
    }

    final pendingSearch =
        context.agentMemory?['pendingSearchResults'] as Map?;

    if (pendingSearch != null && looksLikeSearchFollowUp(context.message)) {
      return _handleSearchFollowUp(context, pendingSearch);
    }

    final parsed = await _classify(context);
    final intent = parsed['intent'] as String? ?? 'other';

    switch (intent) {
      case 'compose':
        return _handleCompose(context, parsed);
      case 'search_inbox':
        return _handleSearchInbox(context, parsed);
      case 'read_inbox':
        return _handleReadInbox(context);
      case 'summarize':
        return AgentExecutionResult(
          responseText: (parsed['body'] as String?)?.trim().isNotEmpty == true
              ? parsed['body']
              : parsed['responseText'] ?? '',
          agentName: name,
          usedTools: const ['groq'],
        );
      default:
        return AgentExecutionResult(
          responseText: parsed['responseText'] as String? ?? '',
          agentName: name,
          usedTools: const ['groq'],
        );
    }
  }

  // ---------- COMPOSE ----------

  Future<AgentExecutionResult> _handleCompose(
    ExecutionContext context,
    Map<String, dynamic> parsed,
  ) async {
    final recipientEmail = (parsed['recipientEmail'] as String? ?? '').trim();
    final subject = (parsed['subject'] as String? ?? '').trim();
    final body = (parsed['body'] as String? ?? '').trim();

    if (recipientEmail.isEmpty) {
      final buffer = StringBuffer();
      if (subject.isNotEmpty) buffer.writeln("**Subject:** $subject");
      buffer.writeln();
      buffer.writeln(body);
      buffer.writeln();
      buffer.writeln(
        "_I don't have a recipient email address yet — reply with one and "
        "I'll get it ready to send._",
      );

      return AgentExecutionResult(
        responseText: buffer.toString().trim(),
        agentName: name,
        usedTools: const ['groq'],
      );
    }

    await AgentMemoryRepository.instance.saveAgentContext(
      userId: context.userId,
      agentId: id,
      storage: contextStorage,
      data: {
        'pendingDraft': {
          'to': recipientEmail,
          'subject': subject.isNotEmpty ? subject : 'Message from Mimir AI',
          'body': body,
        },
      },
    );

    final buffer = StringBuffer();
    buffer.writeln("**To:** $recipientEmail");
    buffer.writeln(
      "**Subject:** ${subject.isNotEmpty ? subject : 'Message from Mimir AI'}",
    );
    buffer.writeln();
    buffer.writeln(body);
    buffer.writeln();
    buffer.writeln(
      "_Reply **\"send it\"** to send this, or **\"cancel\"** to discard it._",
    );

    return AgentExecutionResult(
      responseText: buffer.toString().trim(),
      agentName: name,
      usedTools: const ['groq'],
      action: AgentAction(
        type: AgentActionType.sendEmail,
        data: {'to': recipientEmail, 'subject': subject, 'body': body},
      ),
    );
  }

  // ---------- CONFIRM / SEND ----------

  Future<AgentExecutionResult> _dispatchPendingDraft(
    ExecutionContext context,
    Map pendingDraft,
  ) async {
    try {
      await ToolManager.instance.executeTool('email', {
        'type': 'send',
        'to': pendingDraft['to'],
        'subject': pendingDraft['subject'],
        'body': pendingDraft['body'],
      });

      await _clearPendingDraft(context);

      return AgentExecutionResult(
        responseText:
            "Sent! Your email to ${pendingDraft['to']} is on its way.",
        agentName: name,
        usedTools: const ['email'],
      );
    } on GmailNotConnectedException {
      return AgentExecutionResult(
        responseText:
            "I have your draft ready, but I need access to your Gmail "
            "account first. Please connect Gmail, then say \"send it\" "
            "again.",
        agentName: name,
        action: const AgentAction(type: AgentActionType.connectGmail),
      );
    } catch (e) {
      return AgentExecutionResult(
        responseText: "I couldn't send that email — $e",
        agentName: name,
        success: false,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> _clearPendingDraft(ExecutionContext context) async {
    await AgentMemoryRepository.instance.saveAgentContext(
      userId: context.userId,
      agentId: id,
      storage: contextStorage,
      data: {'pendingDraft': null},
    );
  }

  // ---------- SEARCH INBOX ----------

  /// How many search matches we cap "all" scope at - protects both Gmail
  /// API usage and the chat UI from a 200-message wall of text. If there
  /// are more, we say so and let the user narrow the search instead.
  static const _maxSearchResults = 20;

  Future<AgentExecutionResult> _handleSearchInbox(
    ExecutionContext context,
    Map<String, dynamic> parsed,
  ) async {
    final senderName = (parsed['senderName'] as String? ?? '').trim();
    final keywords = (parsed['keywords'] as String? ?? '').trim();
    final dateHint = (parsed['dateHint'] as String? ?? '').trim();
    final scope = (parsed['scope'] as String? ?? 'latest').trim();
    final question = (parsed['question'] as String? ?? '').trim();

    if (senderName.isEmpty && keywords.isEmpty && dateHint.isEmpty) {
      return AgentExecutionResult(
        responseText: "Who or what should I search your inbox for?",
        agentName: name,
      );
    }

    List<Map<String, String>> matches = [];

    try {
      // Primary attempt: proper Gmail search syntax (from:/after:/before:).
      final query = _buildGmailQuery(senderName, keywords, dateHint);
      matches = await ToolManager.instance.executeTool('email', {
            'type': 'search',
            'query': query,
            'maxResults': _maxSearchResults,
          })
          as List<Map<String, String>>;

      // Fallback 1: "from:" didn't match anything (e.g. sender field
      // formatted differently than the name given) - retry as plain text.
      if (matches.isEmpty && senderName.isNotEmpty) {
        final plainQuery = [senderName, keywords].where((s) => s.isNotEmpty)
            .join(' ');
        matches = await ToolManager.instance.executeTool('email', {
              'type': 'search',
              'query': plainQuery,
              'maxResults': _maxSearchResults,
            })
            as List<Map<String, String>>;
      }

      // Fallback 2: still nothing - scan recent inbox metadata directly
      // and match client-side, in case the term is unusual enough that
      // Gmail's own search didn't catch it.
      if (matches.isEmpty) {
        final recent = await ToolManager.instance.executeTool('email', {
              'type': 'fetch',
              'maxResults': 50,
            })
            as List<Map<String, String>>;

        final needle = [senderName, keywords]
            .where((s) => s.isNotEmpty)
            .join(' ')
            .toLowerCase();

        if (needle.isNotEmpty) {
          matches = recent.where((m) {
            final haystack =
                '${m['from']} ${m['subject']} ${m['snippet']}'.toLowerCase();
            return needle.split(' ').every(haystack.contains);
          }).toList();
        }
      }
    } on GmailNotConnectedException {
      return AgentExecutionResult(
        responseText:
            "I need access to your Gmail account to search your inbox. "
            "Please connect Gmail first.",
        agentName: name,
        action: const AgentAction(type: AgentActionType.connectGmail),
      );
    } catch (e) {
      return AgentExecutionResult(
        responseText: "I couldn't search your inbox — $e",
        agentName: name,
        success: false,
        errorMessage: e.toString(),
      );
    }

    if (matches.isEmpty) {
      final who = [senderName, keywords].where((s) => s.isNotEmpty).join(' ');
      return AgentExecutionResult(
        responseText: "I didn't find anything matching \"$who\" in your "
            "inbox.",
        agentName: name,
        usedTools: const ['email'],
      );
    }

    // Selection: how many of the (already newest-first) matches to act on.
    int selectedCount;
    if (scope == 'all') {
      selectedCount = matches.length;
    } else if (scope.startsWith('count:')) {
      selectedCount =
          int.tryParse(scope.substring('count:'.length)) ?? 1;
    } else {
      selectedCount = 1; // "latest" or unrecognized -> just the newest
    }
    selectedCount = selectedCount.clamp(1, matches.length);

    // Persist the full match list (not just what's shown) so follow-ups
    // like "the one before that" can navigate further into it.
    await AgentMemoryRepository.instance.saveAgentContext(
      userId: context.userId,
      agentId: id,
      storage: contextStorage,
      data: {
        'pendingSearchResults': {
          'results': matches,
          'lastShownIndex': selectedCount - 1,
        },
      },
    );

    // A single match with an actual question -> fetch the full body and
    // answer it directly, rather than just listing metadata.
    if (selectedCount == 1 && question.isNotEmpty) {
      return _readAndAnswer(context, matches.first, question);
    }

    return AgentExecutionResult(
      responseText: _formatSearchResults(
        matches.take(selectedCount).toList(),
        totalFound: matches.length,
      ),
      agentName: name,
      usedTools: const ['email'],
    );
  }

  /// Handles a short reference to a previous search ("the first one",
  /// "read it", "what did it say") using the match list saved by
  /// _handleSearchInbox - no new Gmail search, no re-classification.
  Future<AgentExecutionResult> _handleSearchFollowUp(
    ExecutionContext context,
    Map pendingSearch,
  ) async {
    final matches = (pendingSearch['results'] as List)
        .cast<Map>()
        .map((m) => m.cast<String, String>())
        .toList();
    final lastShownIndex = pendingSearch['lastShownIndex'] as int? ?? 0;

    if (matches.isEmpty) {
      return AgentExecutionResult(
        responseText: "I don't have a previous search to refer back to — "
            "what would you like me to look for?",
        agentName: name,
      );
    }

    final lower = context.message.toLowerCase();
    int targetIndex = lastShownIndex;

    if (lower.contains('first')) {
      targetIndex = 0;
    } else if (lower.contains('second')) {
      targetIndex = 1;
    } else if (lower.contains('third')) {
      targetIndex = 2;
    } else if (lower.contains('last') || lower.contains('oldest')) {
      targetIndex = matches.length - 1;
    } else if (lower.contains('before') ||
        lower.contains('previous') ||
        lower.contains('earlier')) {
      targetIndex = lastShownIndex + 1; // older - list is newest-first
    } else if (lower.contains('next') ||
        lower.contains('after') ||
        lower.contains('another') ||
        lower.contains('newer')) {
      targetIndex = lastShownIndex - 1; // newer
    }

    if (targetIndex < 0) {
      return AgentExecutionResult(
        responseText: "That's already the most recent one I found.",
        agentName: name,
      );
    }
    if (targetIndex >= matches.length) {
      return AgentExecutionResult(
        responseText: "That's the oldest one I found - there isn't an "
            "earlier match.",
        agentName: name,
      );
    }

    await AgentMemoryRepository.instance.saveAgentContext(
      userId: context.userId,
      agentId: id,
      storage: contextStorage,
      data: {
        'pendingSearchResults': {
          'results': matches,
          'lastShownIndex': targetIndex,
        },
      },
    );

    final target = matches[targetIndex];

    final wantsContent = lower.contains('read') ||
        lower.contains('open') ||
        lower.contains('say') ||
        lower.contains('about') ||
        lower.contains('full') ||
        lower.contains('content');

    if (wantsContent) {
      return _readAndAnswer(context, target, context.message);
    }

    return AgentExecutionResult(
      responseText: _formatSearchResults([target], totalFound: matches.length),
      agentName: name,
      usedTools: const ['email'],
    );
  }

  /// Fetches one message in full and asks Groq to answer the user's
  /// question using only its content.
  Future<AgentExecutionResult> _readAndAnswer(
    ExecutionContext context,
    Map<String, String> matchMeta,
    String question,
  ) async {
    try {
      final full = await ToolManager.instance.executeTool('email', {
            'type': 'get',
            'id': matchMeta['id'],
          })
          as Map<String, String>;

      final answer = await ToolManager.instance.executeTool('groq', {
            'systemPrompt': 'You are the Email Agent. Answer the user\'s '
                'question using only the content of this one email. Be '
                'concise and direct.',
            'message': "Email from: ${full['from']}\n"
                "Subject: ${full['subject']}\n"
                "Date: ${full['date']}\n\n"
                "${full['body']}\n\n"
                "Question: $question",
            'history': const [],
          })
          as String;

      return AgentExecutionResult(
        responseText: answer,
        agentName: name,
        usedTools: const ['email', 'groq'],
      );
    } on GmailNotConnectedException {
      return AgentExecutionResult(
        responseText:
            "I need access to your Gmail account to read that email. "
            "Please connect Gmail first.",
        agentName: name,
        action: const AgentAction(type: AgentActionType.connectGmail),
      );
    } catch (e) {
      return AgentExecutionResult(
        responseText: "I couldn't open that email — $e",
        agentName: name,
        success: false,
        errorMessage: e.toString(),
      );
    }
  }

  String _formatSearchResults(
    List<Map<String, String>> shown, {
    required int totalFound,
  }) {
    final buffer = StringBuffer();

    if (shown.length == 1) {
      final m = shown.first;
      buffer.writeln("**From:** ${m['from']}");
      buffer.writeln("**Subject:** ${m['subject']}");
      buffer.writeln("**Date:** ${m['date']}");
      buffer.writeln();
      buffer.writeln(m['snippet']);
    } else {
      buffer.writeln("Found $totalFound matching email(s)"
          "${totalFound > shown.length ? ', showing the ${shown.length} most recent' : ''}:");
      buffer.writeln();
      for (final m in shown) {
        buffer.writeln("- **${m['subject']}** from ${m['from']} (${m['date']})");
      }
      buffer.writeln();
      buffer.writeln("_Reply with \"the first one\", \"read it\", etc. to "
          "see one in full._");
    }

    return buffer.toString().trim();
  }

  String _buildGmailQuery(String senderName, String keywords, String dateHint) {
    final parts = <String>[];

    if (senderName.isNotEmpty) parts.add('from:$senderName');
    if (keywords.isNotEmpty) parts.add(keywords);

    final dateRange = _resolveDateRange(dateHint);
    if (dateRange.isNotEmpty) parts.add(dateRange);

    return parts.join(' ').trim();
  }

  /// Translates a small set of common relative-date phrases into Gmail's
  /// after:/before: query operators (format: yyyy/MM/dd). Anything it
  /// doesn't recognize is dropped rather than guessed at, so an odd phrase
  /// just falls back to searching by sender/keywords alone instead of
  /// silently applying a wrong date filter.
  String _resolveDateRange(String hint) {
    if (hint.isEmpty) return '';
    final lower = hint.toLowerCase();
    final now = DateTime.now();

    String fmt(DateTime d) =>
        '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

    if (lower.contains('today')) {
      return 'after:${fmt(now.subtract(const Duration(days: 1)))}';
    }
    if (lower.contains('yesterday')) {
      return 'after:${fmt(now.subtract(const Duration(days: 2)))} '
          'before:${fmt(now)}';
    }
    if (lower.contains('this week')) {
      final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
      return 'after:${fmt(startOfWeek)}';
    }
    if (lower.contains('last week')) {
      final startOfThisWeek = now.subtract(Duration(days: now.weekday - 1));
      final startOfLastWeek = startOfThisWeek.subtract(const Duration(days: 7));
      return 'after:${fmt(startOfLastWeek)} before:${fmt(startOfThisWeek)}';
    }
    if (lower.contains('this month')) {
      return 'after:${fmt(DateTime(now.year, now.month, 1))}';
    }
    if (lower.contains('last month')) {
      final startOfThisMonth = DateTime(now.year, now.month, 1);
      final startOfLastMonth = DateTime(now.year, now.month - 1, 1);
      return 'after:${fmt(startOfLastMonth)} before:${fmt(startOfThisMonth)}';
    }

    return '';
  }

  // ---------- READ INBOX ----------

  Future<AgentExecutionResult> _handleReadInbox(
    ExecutionContext context,
  ) async {
    List<Map<String, String>> emails;

    try {
      emails =
          (await ToolManager.instance.executeTool('email', {
                'type': 'fetch',
                'maxResults': 10,
              }))
              as List<Map<String, String>>;
    } on GmailNotConnectedException {
      return AgentExecutionResult(
        responseText:
            "I need access to your Gmail account to check your inbox. "
            "Please connect Gmail first.",
        agentName: name,
        action: const AgentAction(type: AgentActionType.connectGmail),
      );
    } catch (e) {
      return AgentExecutionResult(
        responseText: "I couldn't fetch your inbox — $e",
        agentName: name,
        success: false,
        errorMessage: e.toString(),
      );
    }

    if (emails.isEmpty) {
      return AgentExecutionResult(
        responseText: "Your inbox looks empty — nothing recent to summarize.",
        agentName: name,
        usedTools: const ['email'],
      );
    }

    final emailsText = emails
        .map(
          (e) =>
              "From: ${e['from']}\nSubject: ${e['subject']}\nDate: ${e['date']}\nSnippet: ${e['snippet']}",
        )
        .join('\n\n');

    final summaryPrompt =
        "Summarize these recent emails for the user. "
        "Group related ones, call out anything urgent or needing a reply, "
        "and keep it concise.\n\n$emailsText";

    final summary =
        await ToolManager.instance.executeTool('groq', {
              'systemPrompt':
                  'You are the Email Agent. Summarize inbox emails clearly and concisely.',
              'message': summaryPrompt,
              'history': const [],
            })
            as String;

    return AgentExecutionResult(
      responseText: summary,
      agentName: name,
      usedTools: const ['email', 'groq'],
    );
  }

  // ---------- CLASSIFICATION ----------

  Future<Map<String, dynamic>> _classify(ExecutionContext context) async {
    final history = context.recentMessages
        .map((m) => m.toGroqFormat())
        .toList();

    final rawResponse =
        await ToolManager.instance.executeTool('groq', {
              'systemPrompt': systemPrompt,
              'message': _buildPrompt(context),
              'history': history,
            })
            as String;

    return _parseJson(rawResponse);
  }

  String _buildPrompt(ExecutionContext context) {
    final buffer = StringBuffer();
    if (context.alwaysContext.isNotEmpty) {
      buffer.writeln(context.alwaysContext);
      buffer.writeln();
    }
    if (context.rollingSummary.isNotEmpty) {
      buffer.writeln("Conversation so far: ${context.rollingSummary}");
      buffer.writeln();
    }
    buffer.write(context.message);
    return buffer.toString();
  }

  Map<String, dynamic> _parseJson(String text) {
    try {
      final start = text.indexOf('{');
      final end = text.lastIndexOf('}');
      if (start == -1 || end == -1) return {};
      return jsonDecode(text.substring(start, end + 1)) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }
}