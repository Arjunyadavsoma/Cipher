import 'dart:convert';

import '../../../core/services/gmail/gmail_auth_service.dart';
import '../core/base_agent.dart';
import '../core/tool_manager.dart';
import '../models/agent_context_storage.dart';
import '../models/execution_context.dart';
import '../models/execution_result.dart';
import '../repositories/agent_memory_repository.dart';

/// Handles six things:
///   1. COMPOSE       - draft an email (does NOT send immediately - saves a
///                       pending draft and asks the user to confirm)
///   2. REVISE        - user asks to change a pending draft ("change the
///                       subject", "cc jane@x.com", "make it shorter")
///                       rather than confirming or cancelling it
///   3. CONFIRM       - user says "send it" / "yes" -> dispatches the
///                       saved pending draft via Gmail
///   4. SEARCH_INBOX  - user wants to find/recall a specific email or
///                       emails, with fallbacks and follow-up support
///   5. SUMMARIZE     - user pastes/references email text and wants a
///                       summary of it
///   6. READ_INBOX    - user asks to check/summarize their actual inbox
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
  recipient email address(es), cc/bcc if mentioned, a subject line, and a
  professional body.
- SEARCH_INBOX: user wants to find or recall a specific email or emails
  already in their inbox. This is about looking something up, not
  composing anything new.
- SUMMARIZE: user has pasted or referenced specific email content and
  wants a summary of it.
- READ_INBOX: user wants to check, review, or summarize their actual
  inbox/recent emails in general.
- OTHER: anything else email-related that doesn't fit the above.

For COMPOSE, also extract:
- recipientEmail: comma-separated if multiple, else "" if unknown
- ccEmails: comma-separated, else ""
- bccEmails: comma-separated, else ""
- subject: subject line, else ""
- body: A FULL, professional email body. You MUST ALWAYS generate a complete email body based on the user's request, even if the request is brief. Do not return an empty string for the body.
- priority: "urgent" | "normal" | "low" based on the request's tone/content
  (default "normal" unless the user signals urgency or low importance)

For SEARCH_INBOX, also extract:
- senderName: the person/sender mentioned, if any, else ""
- keywords: subject/body search terms, if any, else ""
- dateHint: a date/time phrase if mentioned, else ""
- scope: "latest" (default), "all", or "count:N"
- question: what they actually want to know about the email, else ""
- unreadOnly: true if they specifically asked for unread emails, else false
- hasAttachment: true if they specifically asked for emails with
  attachments, else false

Always respond with JSON only, no other text, in this exact shape:
{
  "intent": "compose" | "search_inbox" | "summarize" | "read_inbox" | "other",
  "recipientEmail": "<comma-separated addresses, or empty string>",
  "ccEmails": "<comma-separated addresses, or empty string>",
  "bccEmails": "<comma-separated addresses, or empty string>",
  "subject": "<subject line, or empty string>",
  "body": "<email body for compose, or summary text for summarize>",
  "priority": "urgent" | "normal" | "low",
  "responseText": "<short natural-language message to show the user>",
  "senderName": "<sender name for search_inbox, or empty string>",
  "keywords": "<search keywords for search_inbox, or empty string>",
  "dateHint": "<date phrase for search_inbox, or empty string>",
  "scope": "<latest | all | count:N, or empty string>",
  "question": "<what the user wants to know, or empty string>",
  "unreadOnly": true | false,
  "hasAttachment": true | false
}
''';

  /// Dedicated prompt for revising an already-pending draft. Kept
  /// separate from the main [systemPrompt] rather than overloaded onto
  /// it - a revision call needs the current draft as grounding context
  /// and a narrower output shape, and mixing that into the general
  /// classifier schema would make both harder to reason about.
  String get _revisionSystemPrompt => '''
You are the Email Agent inside Mimir AI, revising a draft that is already
pending. You will be given the current draft and the user's requested
change. Apply ONLY the requested change - carry every other field over
unchanged from the current draft.

Return JSON only, no other text, in this exact shape:
{
  "recipientEmail": "<comma-separated addresses>",
  "ccEmails": "<comma-separated addresses, or empty string>",
  "bccEmails": "<comma-separated addresses, or empty string>",
  "subject": "<subject line>",
  "body": "<email body>",
  "priority": "urgent" | "normal" | "low"
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

  /// Phrases indicating the user wants to edit a pending draft rather
  /// than confirm/cancel it or start something unrelated. Same
  /// fixed-list tradeoff as _confirmWords/_cancelWords: predictable,
  /// easy to extend, no false positives on short unrelated replies.
  static const _revisionPhrases = [
    'change the subject',
    'change subject',
    'update the subject',
    'change the body',
    'change the recipient',
    'change the email',
    'change the to',
    'add cc',
    'add bcc',
    'add a cc',
    'cc ',
    'bcc ',
    'make it shorter',
    'make it longer',
    'make it more formal',
    'make it more casual',
    'make it friendlier',
    'make it professional',
    'reword',
    'rewrite',
    'edit the draft',
    'edit that',
    'revise',
    'instead say',
    'also mention',
    'also add',
    'remove the',
    'add a line',
    'tone down',
    'shorten it',
    'lengthen it',
  ];

  /// Phrases that indicate the user is referring back to a previous inbox
  /// search rather than starting a new request.
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

  /// Loose email format check - good enough to catch typos and stray
  /// text before they get saved into a draft or sent to Gmail's API,
  /// not meant to be a full RFC 5322 validator.
  static final RegExp _emailPattern =
      RegExp(r'^[\w.\-+]+@[\w\-]+\.[\w\-.]+$');

  static bool looksLikeSearchFollowUp(String message) {
    final lower = message.toLowerCase();
    return _searchFollowUpPhrases.any(lower.contains);
  }

  static bool _looksLikeRevision(String message) {
    final lower = message.toLowerCase();
    return _revisionPhrases.any(lower.contains);
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

      if (pendingDraft['dispatching'] == true) {
        // A send is already in flight for this draft - don't let a
        // second "send it" (e.g. an accidental double-tap) trigger a
        // second Gmail send while the first is still resolving.
        return AgentExecutionResult(
          responseText: "That email is already on its way — one moment.",
          agentName: name,
        );
      }

      if (_confirmWords.any(lower.contains)) {
        return _dispatchPendingDraft(context, pendingDraft);
      }

      if (_looksLikeRevision(context.message)) {
        return _handleRevision(context, pendingDraft);
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
    final toRaw = (parsed['recipientEmail'] as String? ?? '').trim();
    final ccRaw = (parsed['ccEmails'] as String? ?? '').trim();
    final bccRaw = (parsed['bccEmails'] as String? ?? '').trim();
    var subject = (parsed['subject'] as String? ?? '').trim();
    var body = (parsed['body'] as String? ?? '').trim();
    final priority = _normalizePriority(parsed['priority'] as String?);

    // Fallback: If the LLM ignored the prompt and failed to write a body, 
    // explicitly ask it to generate one based on the subject and original request.
    if (body.isEmpty) {
      body = await _generateEmailBody(context, subject);
    }
    
    // If it still fails, use a placeholder so the draft isn't completely blank.
    if (body.isEmpty) {
      body = "(Please enter your email body here)";
    }

    if (toRaw.isEmpty) {
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

    final invalid = <String>[];
    final to = _validateEmails(toRaw, invalid);
    final cc = _validateEmails(ccRaw, invalid);
    final bcc = _validateEmails(bccRaw, invalid);

    if (invalid.isNotEmpty) {
      return AgentExecutionResult(
        responseText:
            "This doesn't look like a valid email address: "
            "\"${invalid.join(', ')}\". Mind double-checking it?",
        agentName: name,
      );
    }

    if (to.isEmpty) {
      return AgentExecutionResult(
        responseText:
            "I need at least one valid recipient address to draft this.",
        agentName: name,
      );
    }

    await AgentMemoryRepository.instance.saveAgentContext(
      userId: context.userId,
      agentId: id,
      storage: contextStorage,
      data: {
        'pendingDraft': {
          'to': to.join(', '),
          'cc': cc.join(', '),
          'bcc': bcc.join(', '),
          'subject': subject.isNotEmpty ? subject : 'Message from Mimir AI',
          'body': body,
          'priority': priority,
          'attachmentPaths': context.attachments,
          'dispatching': false,
        },
      },
    );

    return AgentExecutionResult(
      responseText: _formatDraftPreview(
        to: to.join(', '),
        cc: cc.join(', '),
        bcc: bcc.join(', '),
        subject: subject.isNotEmpty ? subject : 'Message from Mimir AI',
        body: body,
        priority: priority,
        attachmentCount: context.attachments.length,
      ),
      agentName: name,
      usedTools: const ['groq'],
      action: AgentAction(
        type: AgentActionType.sendEmail,
        data: {
          'to': to.join(', '),
          'cc': cc.join(', '),
          'bcc': bcc.join(', '),
          'subject': subject,
          'body': body,
          'priority': priority,
        },
      ),
    );
  }

  /// Helper specifically used to force body generation if the main 
  /// classification call returned an empty body string.
  Future<String> _generateEmailBody(ExecutionContext context, String subject) async {
    try {
      final prompt = "The user requested an email but the body was missing. "
          "Subject: ${subject.isNotEmpty ? subject : 'N/A'}\n"
          "User's original request: ${context.message}\n\n"
          "Write a complete, professional email body for this. Return ONLY the body text.";
      
      final response = await ToolManager.instance.executeTool('groq', {
        'systemPrompt': 'You are a professional email writing assistant. Write a complete email body based on the provided context. Return only the body text.',
        'message': prompt,
        'history': const [],
      }) as String;
      
      return response.trim();
    } catch (_) {
      return '';
    }
  }

  // ---------- REVISE ----------

  Future<AgentExecutionResult> _handleRevision(
    ExecutionContext context,
    Map pendingDraft,
  ) async {
    Map<String, dynamic> parsed;
    try {
      parsed = await _classifyRevision(context, pendingDraft);
    } catch (e) {
      return AgentExecutionResult(
        responseText:
            "I had trouble applying that change — mind rephrasing it?",
        agentName: name,
        success: false,
        errorMessage: e.toString(),
      );
    }

    if (parsed.isEmpty) {
      return AgentExecutionResult(
        responseText:
            "I had trouble applying that change — mind rephrasing it?",
        agentName: name,
      );
    }

    final invalid = <String>[];
    final toRaw = (parsed['recipientEmail'] as String? ??
            pendingDraft['to'] as String? ?? '')
        .trim();
    final ccRaw =
        (parsed['ccEmails'] as String? ?? pendingDraft['cc'] as String? ?? '')
            .trim();
    final bccRaw = (parsed['bccEmails'] as String? ??
            pendingDraft['bcc'] as String? ?? '')
        .trim();

    final to = _validateEmails(toRaw, invalid);
    final cc = _validateEmails(ccRaw, invalid);
    final bcc = _validateEmails(bccRaw, invalid);

    if (invalid.isNotEmpty) {
      return AgentExecutionResult(
        responseText:
            "This doesn't look like a valid email address: "
            "\"${invalid.join(', ')}\" — the rest of your draft is still "
            "saved as it was.",
        agentName: name,
      );
    }

    final subject = (parsed['subject'] as String?)?.trim().isNotEmpty == true
        ? parsed['subject'] as String
        : pendingDraft['subject'] as String? ?? '';
    var body = (parsed['body'] as String?)?.trim().isNotEmpty == true
        ? parsed['body'] as String
        : pendingDraft['body'] as String? ?? '';
    final priority = _normalizePriority(
      parsed['priority'] as String? ?? pendingDraft['priority'] as String?,
    );

    // Fallback for revisions too
    if (body.isEmpty) {
      body = await _generateEmailBody(context, subject);
    }
    if (body.isEmpty) {
      body = "(Please enter your email body here)";
    }

    final updatedDraft = {
      'to': to.join(', '),
      'cc': cc.join(', '),
      'bcc': bcc.join(', '),
      'subject': subject,
      'body': body,
      'priority': priority,
      'attachmentPaths': pendingDraft['attachmentPaths'] ?? const [],
      'dispatching': false,
    };

    await AgentMemoryRepository.instance.saveAgentContext(
      userId: context.userId,
      agentId: id,
      storage: contextStorage,
      data: {'pendingDraft': updatedDraft},
    );

    final attachmentCount =
        (updatedDraft['attachmentPaths'] as List?)?.length ?? 0;

    return AgentExecutionResult(
      responseText: "Updated the draft:\n\n${_formatDraftPreview(
        to: updatedDraft['to'] as String,
        cc: updatedDraft['cc'] as String,
        bcc: updatedDraft['bcc'] as String,
        subject: updatedDraft['subject'] as String,
        body: updatedDraft['body'] as String,
        priority: priority,
        attachmentCount: attachmentCount,
      )}",
      agentName: name,
      usedTools: const ['groq'],
    );
  }

  Future<Map<String, dynamic>> _classifyRevision(
    ExecutionContext context,
    Map pendingDraft,
  ) async {
    final currentDraft = "Current draft:\n"
        "To: ${pendingDraft['to']}\n"
        "Cc: ${pendingDraft['cc'] ?? ''}\n"
        "Bcc: ${pendingDraft['bcc'] ?? ''}\n"
        "Subject: ${pendingDraft['subject']}\n"
        "Priority: ${pendingDraft['priority'] ?? 'normal'}\n\n"
        "Body:\n${pendingDraft['body']}";

    final rawResponse = await ToolManager.instance.executeTool('groq', {
      'systemPrompt': _revisionSystemPrompt,
      'message': "$currentDraft\n\n"
          "Requested change: ${context.message}",
      'history': const [],
    }) as String;

    return _parseJson(rawResponse);
  }

  // ---------- CONFIRM / SEND ----------

  Future<AgentExecutionResult> _dispatchPendingDraft(
    ExecutionContext context,
    Map pendingDraft,
  ) async {
    // Mark as dispatching before the network call so a second "send it"
    // arriving while this one is still in flight is caught by the guard
    // in execute() rather than triggering a duplicate Gmail send.
    await AgentMemoryRepository.instance.saveAgentContext(
      userId: context.userId,
      agentId: id,
      storage: contextStorage,
      data: {
        'pendingDraft': {...pendingDraft, 'dispatching': true},
      },
    );

    try {
      await ToolManager.instance.executeTool('email', {
        'type': 'send',
        'to': pendingDraft['to'],
        'cc': pendingDraft['cc'] ?? '',
        'bcc': pendingDraft['bcc'] ?? '',
        'subject': pendingDraft['subject'],
        'body': pendingDraft['body'],
        'attachmentPaths': pendingDraft['attachmentPaths'] ?? const [],
      });

      await _clearPendingDraft(context);

      return AgentExecutionResult(
        responseText:
            "Sent! Your email to ${pendingDraft['to']} is on its way.",
        agentName: name,
        usedTools: const ['email'],
      );
    } on GmailNotConnectedException {
      // Reset the dispatching flag - the draft is still valid, it just
      // couldn't go out yet.
      await AgentMemoryRepository.instance.saveAgentContext(
        userId: context.userId,
        agentId: id,
        storage: contextStorage,
        data: {
          'pendingDraft': {...pendingDraft, 'dispatching': false},
        },
      );
      return AgentExecutionResult(
        responseText:
            "I have your draft ready, but I need access to your Gmail "
            "account first. Please connect Gmail, then say \"send it\" "
            "again.",
        agentName: name,
        action: const AgentAction(type: AgentActionType.connectGmail),
      );
    } catch (e) {
      await AgentMemoryRepository.instance.saveAgentContext(
        userId: context.userId,
        agentId: id,
        storage: contextStorage,
        data: {
          'pendingDraft': {...pendingDraft, 'dispatching': false},
        },
      );
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
    final unreadOnly = parsed['unreadOnly'] as bool? ?? false;
    final hasAttachment = parsed['hasAttachment'] as bool? ?? false;

    if (senderName.isEmpty &&
        keywords.isEmpty &&
        dateHint.isEmpty &&
        !unreadOnly &&
        !hasAttachment) {
      return AgentExecutionResult(
        responseText: "Who or what should I search your inbox for?",
        agentName: name,
      );
    }

    List<Map<String, String>> matches = [];

    try {
      final query = _buildGmailQuery(
        senderName,
        keywords,
        dateHint,
        unreadOnly: unreadOnly,
        hasAttachment: hasAttachment,
      );
      matches = await ToolManager.instance.executeTool('email', {
            'type': 'search',
            'query': query,
            'maxResults': _maxSearchResults,
          })
          as List<Map<String, String>>;

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

      if (matches.isEmpty) {
        final recent = await ToolManager.instance.executeTool('email', {
              'type': 'fetch',
              'maxResults': 50,
              'unreadOnly': unreadOnly,
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
        } else {
          matches = recent;
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
        responseText: "I didn't find anything matching "
            "\"${who.isNotEmpty ? who : 'that'}\" in your inbox.",
        agentName: name,
        usedTools: const ['email'],
      );
    }

    int selectedCount;
    if (scope == 'all') {
      selectedCount = matches.length;
    } else if (scope.startsWith('count:')) {
      selectedCount =
          int.tryParse(scope.substring('count:'.length)) ?? 1;
    } else {
      selectedCount = 1;
    }
    selectedCount = selectedCount.clamp(1, matches.length);

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
      targetIndex = lastShownIndex + 1;
    } else if (lower.contains('next') ||
        lower.contains('after') ||
        lower.contains('another') ||
        lower.contains('newer')) {
      targetIndex = lastShownIndex - 1;
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

  // ---------- FORMATTING ----------

  String _formatDraftPreview({
    required String to,
    required String cc,
    required String bcc,
    required String subject,
    required String body,
    required String priority,
    required int attachmentCount,
  }) {
    final buffer = StringBuffer();
    final badge = _priorityBadge(priority);
    if (badge.isNotEmpty) buffer.writeln(badge);
    buffer.writeln("**To:** $to");
    if (cc.isNotEmpty) buffer.writeln("**Cc:** $cc");
    if (bcc.isNotEmpty) buffer.writeln("**Bcc:** $bcc");
    buffer.writeln("**Subject:** $subject");
    if (attachmentCount > 0) {
      buffer.writeln(
        "**Attachments:** $attachmentCount file"
        "${attachmentCount == 1 ? '' : 's'}",
      );
    }
    buffer.writeln();
    buffer.writeln(body);
    buffer.writeln();
    buffer.writeln(
      "_Reply **\"send it\"** to send this, **\"cancel\"** to discard it, "
      "or tell me what to change._",
    );
    return buffer.toString().trim();
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

  String _priorityBadge(String priority) {
    switch (priority) {
      case 'urgent':
        return '🔴 **Urgent**';
      case 'low':
        return '🔵 Low priority';
      default:
        return '';
    }
  }

  String _normalizePriority(String? raw) {
    final value = (raw ?? 'normal').trim().toLowerCase();
    return {'urgent', 'normal', 'low'}.contains(value) ? value : 'normal';
  }

  /// Splits a comma/semicolon-separated address list, trims each entry,
  /// and validates it against [_emailPattern]. Any address that fails
  /// validation is appended to [invalidOut] instead of being included
  /// in the returned list, so callers can surface exactly which address
  /// needs fixing rather than rejecting the whole field.
  List<String> _validateEmails(String raw, List<String> invalidOut) {
    if (raw.trim().isEmpty) return [];

    final candidates = raw
        .split(RegExp(r'[,;]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty);

    final valid = <String>[];
    for (final candidate in candidates) {
      if (_emailPattern.hasMatch(candidate)) {
        valid.add(candidate);
      } else {
        invalidOut.add(candidate);
      }
    }
    return valid;
  }

  String _buildGmailQuery(
    String senderName,
    String keywords,
    String dateHint, {
    bool unreadOnly = false,
    bool hasAttachment = false,
  }) {
    final parts = <String>[];

    if (senderName.isNotEmpty) parts.add('from:$senderName');
    if (keywords.isNotEmpty) parts.add(keywords);
    if (unreadOnly) parts.add('is:unread');
    if (hasAttachment) parts.add('has:attachment');

    final dateRange = _resolveDateRange(dateHint);
    if (dateRange.isNotEmpty) parts.add(dateRange);

    return parts.join(' ').trim();
  }

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

    var parsed = _parseJson(rawResponse);

    // One retry on unparseable JSON - a single malformed response
    // shouldn't silently fall through to "other" and drop what may
    // have been a perfectly clear compose/search request. Mirrors
    // GroqTool's own retry-on-failure pattern rather than introducing
    // a new resilience convention.
    if (parsed.isEmpty) {
      final retryResponse =
          await ToolManager.instance.executeTool('groq', {
                'systemPrompt': systemPrompt,
                'message': _buildPrompt(context),
                'history': history,
              })
              as String;
      parsed = _parseJson(retryResponse);
    }

    return parsed;
  }

  String _buildPrompt(ExecutionContext context) {
    final buffer = StringBuffer();
    if (context.alwaysContext.isNotEmpty) {
      buffer.writeln(context.alwaysContext);
      buffer.writeln();
    }
    // Knowledge-retrieval context (job title, writing-style preferences,
    // signature-relevant facts, etc.) - lets composed emails reflect
    // what's actually known about the user instead of a generic voice.
    if (context.domainContext.isNotEmpty) {
      buffer.writeln(context.domainContext);
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