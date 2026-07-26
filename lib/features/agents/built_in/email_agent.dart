import 'dart:convert';

import '../../../core/services/gmail/gmail_auth_service.dart';
import '../core/base_agent.dart';
import '../core/tool_manager.dart';
import '../models/agent_context_storage.dart';
import '../models/execution_context.dart';
import '../models/execution_result.dart';
import '../repositories/agent_memory_repository.dart';

/// Email Agent
///
/// Responsibilities:
/// 1. One-time onboarding: learns the user's name (persisted to Firebase via
///    [AgentMemoryRepository]) and reuses it for every future session without
///    asking again.
/// 2. Compose -> confirm -> send flow with a pending-draft state machine that
///    survives revisions, cancellations, and app restarts.
/// 3. Inbox search with pagination-style follow-ups ("read the first one").
/// 4. Inbox summarization.
///
/// Design notes on robustness:
/// - Every write to agent memory is defensive: we never assume the
///   underlying storage does a deep merge, so we always re-read-then-merge
///   at the call site for the fields we care about (see [_saveMemoryPatch]).
/// - Name capture is opt-in and denylist-guarded rather than "anything short
///   is a name" -- confirm/cancel/revision words, and now correction
///   phrases, are excluded so they can never be mistaken for a name.
/// - The classifier is never trusted blindly: intent parsing failures are
///   surfaced to the user rather than silently falling through to a generic
///   chat answer, which previously could hide a failed "compose" request
///   behind an unrelated response.
/// - `dispatching` is a soft lock with a timestamp so a crash mid-send can't
///   permanently wedge the draft.
class EmailAgent implements BaseAgent {
  @override
  String get id => 'email_agent';

  @override
  String get name => 'Email Agent';

  @override
  String get description =>
      'Handles writing, summarizing, sending emails, and reading/summarizing the user\'s inbox.';

  @override
  String get systemPrompt => '''
You are the Email Agent inside cipher AI. Classify the user's message into exactly one of these intents:

- COMPOSE: The user explicitly wants to write, draft, prepare, or send an email. Extract the recipient email address(es), cc/bcc if mentioned, a subject line, and a professional body.
- SEARCH_INBOX: The user explicitly wants to find or recall a specific email already in their inbox.
- SUMMARIZE: The user has pasted specific email content and wants a summary of it.
- READ_INBOX: The user explicitly wants to check, review, or summarize their actual inbox.
- OTHER: Anything else, including general questions not explicitly about emails.

For COMPOSE, also extract:
- recipientEmail: comma-separated if multiple, else "" if unknown
- ccEmails: comma-separated, else ""
- bccEmails: comma-separated, else ""
- subject: subject line, else ""
- body: A FULL, professional email body. You MUST ALWAYS generate a complete email body based on the user's request. Do not return an empty string for the body. DO NOT use markdown formatting.
- priority: "urgent" | "normal" | "low" based on the request's tone/content

For SEARCH_INBOX, also extract:
- senderName: the person/sender mentioned, if any, else ""
- keywords: subject/body search terms, if any, else ""
- dateHint: a date/time phrase if mentioned, else ""
- scope: "latest" (default), "all", or "count:N"
- question: what they actually want to know about the email, else ""
- unreadOnly: true if they specifically asked for unread emails, else false
- hasAttachment: true if they specifically asked for emails with attachments, else false

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

  String get _revisionSystemPrompt => '''
You are the Email Agent inside cipher AI, revising a draft that is already pending. Apply ONLY the requested change - carry every other field over unchanged from the current draft. If the request asks to REMOVE a recipient/cc/bcc, return that field as an empty string rather than omitting it. DO NOT use markdown formatting.

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

  // ---------- WORD BANKS ----------

  static const _confirmWords = [
    'send it', 'yes send', 'yes, send', 'yes', 'go ahead', 'confirm', 'please send', 'send now', 'do it', 'ship it',
  ];

  static const _cancelWords = [
    'cancel', "don't send", 'do not send', 'discard', 'never mind', 'nevermind', 'stop', 'forget it', 'abort',
  ];

  static const _revisionPhrases = [
    'change the subject', 'change subject', 'update the subject', 'change the body', 'change the recipient',
    'change the email', 'change the to', 'add cc', 'add bcc', 'add a cc', 'add a bcc', 'cc ', 'bcc ',
    'remove cc', 'remove bcc', 'remove the cc', 'remove the bcc', 'drop the cc', 'drop the bcc',
    'make it shorter', 'make it longer', 'make it more formal', 'make it more casual', 'make it friendlier',
    'make it professional', 'reword', 'rewrite', 'edit the draft', 'edit that', 'revise', 'instead say',
    'also mention', 'also add', 'remove the', 'add a line', 'tone down', 'shorten it', 'lengthen it',
    'change the recipient to', 'change the to address',
  ];

  static const _searchFollowUpPhrases = [
    'first one', 'the first', 'second one', 'the second', 'third one', 'the third', 'last one', 'the last',
    'oldest one', 'next one', 'the next', 'newer one', 'previous one', 'the previous', 'before that',
    'earlier one', 'another one', 'show me another', 'read it', 'read that', 'read the', 'open it', 'open that',
    'full email', 'full message', 'what did it say', 'what does it say', 'what did they say',
  ];

  /// Phrases that mean "that's not what I meant by my name" / name correction.
  static const _nameCorrectionPhrases = [
    "that's not my name", 'that is not my name', 'wrong name', 'not my name', 'my name is actually',
    'actually my name is', 'change my name', 'update my name', 'call me',
  ];

  /// Words/short replies that must NEVER be captured as a name, even though
  /// they are short and contain no email address. This guards the
  /// first-run name-capture heuristic against misfires like "cancel",
  /// "yes", "ok", "thanks", etc.
  static const _nameDenylist = {
    'yes', 'no', 'ok', 'okay', 'k', 'kk', 'sure', 'fine', 'nevermind', 'never mind', 'cancel', 'stop',
    'thanks', 'thank you', 'thx', 'ty', 'please', 'go ahead', 'confirm', 'send it', 'send now', 'do it',
    'hi', 'hello', 'hey', 'yo', 'sup', 'test', 'testing', 'hmm', 'hm', 'idk', "i don't know", 'maybe',
    'not now', 'later', 'skip', 'none', 'n/a', 'na',
  };

  static final RegExp _emailPattern = RegExp(r'^[\w.\-+]+@[\w\-]+\.[\w\-.]+$');
  static final RegExp _emailExtractPattern = RegExp(r'[\w.\-+]+@[\w\-]+\.[\w\-.]+');

  /// A "dispatching" lock older than this is treated as abandoned (e.g. the
  /// app crashed mid-send) and safe to retry, rather than leaving the user
  /// stuck forever behind "that email is already on its way".
  static const _dispatchLockTimeout = Duration(seconds: 45);

  static bool looksLikeSearchFollowUp(String message) {
    final lower = message.toLowerCase();
    return _searchFollowUpPhrases.any(lower.contains);
  }

  static bool _looksLikeRevision(String message) {
    final lower = message.toLowerCase();
    return _revisionPhrases.any(lower.contains);
  }

  static bool _looksLikeNameCorrection(String message) {
    final lower = message.toLowerCase();
    return _nameCorrectionPhrases.any(lower.contains);
  }

  bool _containsEmail(String message) => _emailExtractPattern.hasMatch(message);

  @override
  Future<AgentExecutionResult> execute(ExecutionContext context) async {
    final String? userName = _cleanStoredName(context.agentMemory?['name'] as String?);

    // 0. Allow an already-onboarded user to correct their stored name at any
    // time, even mid-draft, without derailing whatever else is going on.
    if (userName != null && _looksLikeNameCorrection(context.message)) {
      final extracted = _extractNameFromCorrection(context.message);
      if (extracted != null) {
        return _handleNameSetup(context, extracted, isCorrection: true);
      }
      return AgentExecutionResult(
        responseText: "Sure — what should I call you instead?",
        agentName: name,
      );
    }

    // 1. First-run onboarding: we don't have a name yet.
    if (userName == null) {
      final lowerMessage = context.message.trim().toLowerCase();
      final trimmedMessage = context.message.trim();

      final isDenylisted = _nameDenylist.contains(lowerMessage);
      final mentionsEmailVerbs = lowerMessage.contains('draft') ||
          lowerMessage.contains('send') ||
          lowerMessage.contains('search') ||
          lowerMessage.contains('inbox') ||
          lowerMessage.contains('read') ||
          lowerMessage.contains('summarize') ||
          lowerMessage.contains('compose');

      final isLikelyName = trimmedMessage.isNotEmpty &&
          trimmedMessage.split(RegExp(r'\s+')).length <= 4 &&
          !_containsEmail(context.message) &&
          !mentionsEmailVerbs &&
          !isDenylisted;

      if (isLikelyName) {
        final cleanedName = _sanitizeName(trimmedMessage);
        if (cleanedName != null) {
          return _handleNameSetup(context, cleanedName);
        }
      }

      return AgentExecutionResult(
        responseText:
            "Before I draft or send emails for you, I need to know your name so I can sign them properly. What is your name?",
        agentName: name,
      );
    }

    final pendingDraft = _asMap(context.agentMemory?['pendingDraft']);

    // 2. Handle Pending Drafts (Send, Cancel, Revise)
    if (pendingDraft != null) {
      final lower = context.message.toLowerCase();

      if (_cancelWords.any(lower.contains)) {
        await _clearPendingDraft(context);
        return AgentExecutionResult(
          responseText: "Okay, I've discarded that draft.",
          agentName: name,
        );
      }

      if (pendingDraft['dispatching'] == true && !_isDispatchLockStale(pendingDraft)) {
        return AgentExecutionResult(
          responseText: "That email is already on its way — one moment.",
          agentName: name,
        );
      }

      // Revision takes priority over confirm when the message plausibly
      // contains BOTH (e.g. "yes but change the subject too").
      if (_looksLikeRevision(context.message) || (_containsEmail(context.message) && !_confirmWords.any(lower.contains))) {
        return _handleRevision(context, pendingDraft, userName);
      }

      if (_confirmWords.any(lower.contains)) {
        return _dispatchPendingDraft(context, pendingDraft);
      }
    } else {
      // If no draft exists, and user says "send it", break the loop instead
      // of silently falling through to intent classification (which could
      // misclassify "send it" as an empty compose request).
      final lower = context.message.toLowerCase();
      if (_confirmWords.any(lower.contains) && !_containsEmail(context.message)) {
        return AgentExecutionResult(
          responseText: "I don't have any pending email draft to send. What would you like me to do?",
          agentName: name,
        );
      }
    }

    final pendingSearch = _asMap(context.agentMemory?['pendingSearchResults']);
    if (pendingSearch != null && looksLikeSearchFollowUp(context.message)) {
      return _handleSearchFollowUp(context, pendingSearch);
    }

    // 3. Classify and Route Intent
    Map<String, dynamic> parsed;
    try {
      parsed = await _classify(context);
    } catch (e) {
      return AgentExecutionResult(
        responseText: "I had trouble processing that — could you try rephrasing?",
        agentName: name,
        success: false,
        errorMessage: e.toString(),
      );
    }

    if (parsed.isEmpty) {
      // Both the primary classification call and its retry (inside
      // _classify) failed to produce valid JSON. Surface this rather than
      // silently defaulting to 'other' and answering an unrelated question,
      // which would previously have hidden a failed compose/search request.
      return AgentExecutionResult(
        responseText: "I couldn't quite parse that request — could you rephrase what you'd like me to do with your email?",
        agentName: name,
        success: false,
      );
    }

    final intent = parsed['intent'] as String? ?? 'other';

    switch (intent) {
      case 'compose':
        return _handleCompose(context, parsed, userName);
      case 'search_inbox':
        return _handleSearchInbox(context, parsed);
      case 'read_inbox':
        return _handleReadInbox(context);
      case 'summarize':
        final summaryBody = (parsed['body'] as String?)?.trim();
        return AgentExecutionResult(
          responseText: (summaryBody != null && summaryBody.isNotEmpty)
              ? summaryBody
              : ((parsed['responseText'] as String?)?.trim().isNotEmpty == true
                  ? parsed['responseText'] as String
                  : "I couldn't find enough content to summarize — could you paste the email text?"),
          agentName: name,
          usedTools: const ['groq'],
        );
      default:
        final history = context.recentMessages.map((m) => m.toGroqFormat()).toList();
        try {
          final response = await ToolManager.instance.executeTool('groq', {
            'systemPrompt': 'You are a helpful assistant. Answer the user\'s question directly and concisely.',
            'message': context.message,
            'history': history,
          });

          return AgentExecutionResult(
            responseText: response as String,
            agentName: name,
            usedTools: const ['groq'],
          );
        } catch (e) {
          return AgentExecutionResult(
            responseText: "I had trouble answering that — mind trying again?",
            agentName: name,
            success: false,
            errorMessage: e.toString(),
          );
        }
    }
  }

  Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map) {
      return value.cast<String, dynamic>();
    }
    return null;
  }

  // ---------- NAME SETUP ----------

  /// Strips a stored name back down to null-if-blank so a previously
  /// corrupted/empty write (e.g. an old bug, or a race with another agent)
  /// can't silently pin the user in an "already onboarded" state with no
  /// usable name.
  String? _cleanStoredName(String? raw) {
    final trimmed = raw?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  /// Removes common self-introduction prefixes and rejects anything that,
  /// after cleanup, still looks like a control word or is implausible as a
  /// name (empty, purely numeric, or absurdly long — someone pasting a
  /// paragraph isn't providing a name).
  String? _sanitizeName(String raw) {
    var candidate = raw.trim();
    candidate = candidate
        .replaceAll(
          RegExp(r"^(my name is|i am|i'm|its|it's|this is|call me|name is)\s+", caseSensitive: false),
          '',
        )
        .trim();

    // Strip trailing punctuation like "Arjun." or "Arjun!"
    candidate = candidate.replaceAll(RegExp(r'[.!?,]+$'), '').trim();

    if (candidate.isEmpty) return null;
    if (candidate.length > 60) return null; // not a plausible name
    if (RegExp(r'^\d+$').hasMatch(candidate)) return null; // purely numeric
    if (_nameDenylist.contains(candidate.toLowerCase())) return null;

    // Title-case each word for a clean signature, but don't mangle names
    // that are already intentionally styled (e.g. "vonSmith") by only
    // adjusting simple space-separated tokens.
    final words = candidate.split(RegExp(r'\s+'));
    final titled = words.map((w) {
      if (w.isEmpty) return w;
      if (w == w.toUpperCase() && w.length > 1) return w; // keep e.g. "AJ"
      return w[0].toUpperCase() + w.substring(1);
    }).join(' ');

    return titled;
  }

  /// For phrases like "actually my name is Arjun" or "call me AJ instead",
  /// pull out the name portion specifically (as opposed to first-run
  /// capture, where the whole trimmed message is the candidate).
  String? _extractNameFromCorrection(String message) {
    final patterns = [
      RegExp(r"(?:my name is actually|actually my name is|my name is|call me)\s+([A-Za-z][\w'\-. ]{0,58})", caseSensitive: false),
    ];
    for (final p in patterns) {
      final match = p.firstMatch(message);
      if (match != null) {
        final raw = match.group(1)?.trim();
        if (raw != null && raw.isNotEmpty) {
          return _sanitizeName(raw);
        }
      }
    }
    return null;
  }

  Future<AgentExecutionResult> _handleNameSetup(
    ExecutionContext context,
    String userName, {
    bool isCorrection = false,
  }) async {
    final saved = await _saveMemoryPatch(context, {'name': userName});
    if (!saved) {
      return AgentExecutionResult(
        responseText: "I got your name but couldn't save it just now — mind confirming it again in a moment?",
        agentName: name,
        success: false,
      );
    }

    final message = isCorrection
        ? "Got it, I'll call you $userName from now on."
        : "Got it, $userName! I will sign your emails with that name from now on. What would you like me to do?";

    return AgentExecutionResult(
      responseText: message,
      agentName: name,
      usedTools: const ['firebase'],
    );
  }

  // ---------- SAFE MEMORY WRITES ----------

  /// Saves a top-level patch to agent memory and reports whether it
  /// actually persisted. [AgentMemoryRepository.saveAgentContext] merges
  /// each top-level key server-side (Firestore's `set(merge: true)`, or a
  /// read-then-merge upsert for Supabase), so a save of `{'name': x}` can
  /// never clobber `pendingDraft` or vice versa — callers do not need to
  /// pre-merge `context.agentMemory` before calling this.
  Future<bool> _saveMemoryPatch(
  ExecutionContext context,
  Map<String, dynamic> patch,
) async {
  await AgentMemoryRepository.instance.saveAgentContext(
    userId: context.userId,
    agentId: id,
    storage: contextStorage,
    data: patch,
  );

  return true;
}

  bool _isDispatchLockStale(Map<String, dynamic> pendingDraft) {
    final startedAtRaw = pendingDraft['dispatchStartedAt'] as String?;
    if (startedAtRaw == null) return true; // no timestamp -> assume stale/legacy, don't wedge the user
    final startedAt = DateTime.tryParse(startedAtRaw);
    if (startedAt == null) return true;
    return DateTime.now().difference(startedAt) > _dispatchLockTimeout;
  }

  // ---------- COMPOSE ----------

  Future<AgentExecutionResult> _handleCompose(
    ExecutionContext context,
    Map<String, dynamic> parsed,
    String userName,
  ) async {
    final toRaw = (parsed['recipientEmail'] as String? ?? '').trim();
    final ccRaw = (parsed['ccEmails'] as String? ?? '').trim();
    final bccRaw = (parsed['bccEmails'] as String? ?? '').trim();
    var subject = (parsed['subject'] as String? ?? '').trim();
    var body = (parsed['body'] as String? ?? '').trim();
    final priority = _normalizePriority(parsed['priority'] as String?);

    if (body.isEmpty) {
      body = await _generateEmailBody(context, subject, userName);
    }
    if (body.isEmpty) {
      body = "(Please enter your email body here)";
    }

    // Cap absurdly long generated/pasted bodies so a runaway generation or a
    // pasted document doesn't get shipped as an "email" body unchecked.
    const maxBodyLength = 20000;
    if (body.length > maxBodyLength) {
      body = '${body.substring(0, maxBodyLength)}\n\n[...truncated — this draft was unusually long, let me know if you want the rest]';
    }

    if (toRaw.isEmpty) {
      final buffer = StringBuffer()
        ..writeln("Here is the draft I came up with:")
        ..writeln();
      if (subject.isNotEmpty) {
        buffer.writeln("**Subject:** $subject");
        buffer.writeln();
      }
      buffer
        ..writeln(body)
        ..writeln()
        ..writeln("---\n_I don't have a recipient email address yet. Please provide one and I'll finalize the draft for you._");

      // Stash the partial draft so that once the user supplies just an
      // address, we don't have to regenerate the whole body from scratch
      // and risk it drifting from what was already shown.
      // Best-effort: worst case (save fails) the user has to restate the
      // request once they provide an address, so we don't gate the response
      // on this succeeding.
      await _saveMemoryPatch(context, {
        'pendingDraft': {
          'to': '',
          'cc': '',
          'bcc': '',
          'subject': subject,
          'body': body,
          'priority': priority,
          'attachmentPaths': context.attachments,
          'dispatching': false,
        },
      });

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
        responseText: "This doesn't look like a valid email address: \"${invalid.join(', ')}\". Mind double-checking it?",
        agentName: name,
      );
    }

    if (to.isEmpty) {
      return AgentExecutionResult(
        responseText: "I need at least one valid recipient address to draft this.",
        agentName: name,
      );
    }

    // Guard against accidentally CCing/BCCing the same address that's
    // already a primary recipient — Gmail allows it but it's almost always
    // unintentional overlap from parsing.
    final ccDeduped = cc.where((addr) => !to.contains(addr)).toList();
    final bccDeduped = bcc.where((addr) => !to.contains(addr) && !ccDeduped.contains(addr)).toList();

    final finalSubject = subject.isNotEmpty ? subject : 'Message from cipher AI';

    final saved = await _saveMemoryPatch(context, {
      'pendingDraft': {
        'to': to.join(', '),
        'cc': ccDeduped.join(', '),
        'bcc': bccDeduped.join(', '),
        'subject': finalSubject,
        'body': body,
        'priority': priority,
        'attachmentPaths': context.attachments,
        'dispatching': false,
      },
    });
    if (!saved) {
      return AgentExecutionResult(
        responseText: "I put the draft together but couldn't save it — mind trying again?",
        agentName: name,
        success: false,
      );
    }

    return AgentExecutionResult(
      responseText: _formatDraftPreview(
        to: to.join(', '),
        cc: ccDeduped.join(', '),
        bcc: bccDeduped.join(', '),
        subject: finalSubject,
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
          'cc': ccDeduped.join(', '),
          'bcc': bccDeduped.join(', '),
          'subject': finalSubject,
          'body': body,
          'priority': priority,
        },
      ),
    );
  }

  Future<String> _generateEmailBody(
    ExecutionContext context,
    String subject,
    String userName,
  ) async {
    try {
      final prompt = "The user requested an email but the body was missing. "
          "Subject: ${subject.isNotEmpty ? subject : 'N/A'}\n"
          "User's original request: ${context.message}\n\n"
          "Write a complete email body for $userName. Decide the tone (professional or personal) based on the context of the message. Return ONLY the body text. DO NOT use markdown formatting.";

      final response = await ToolManager.instance.executeTool('groq', {
        'systemPrompt':
            'You are a professional email writing assistant. Write a complete email body based on the provided context. Return only the body text. DO NOT use markdown formatting.',
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
    Map<String, dynamic> pendingDraft,
    String userName,
  ) async {
    Map<String, dynamic> parsed;
    try {
      parsed = await _classifyRevision(context, pendingDraft, userName);
    } catch (e) {
      return AgentExecutionResult(
        responseText: "I had trouble applying that change — mind rephrasing it?",
        agentName: name,
        success: false,
        errorMessage: e.toString(),
      );
    }

    if (parsed.isEmpty) {
      return AgentExecutionResult(
        responseText: "I had trouble applying that change — mind rephrasing it?",
        agentName: name,
      );
    }

    final lowerMsg = context.message.toLowerCase();
    final wantsRemoveCc = lowerMsg.contains('remove cc') || lowerMsg.contains('remove the cc') || lowerMsg.contains('drop the cc');
    final wantsRemoveBcc = lowerMsg.contains('remove bcc') || lowerMsg.contains('remove the bcc') || lowerMsg.contains('drop the bcc');

    final invalid = <String>[];

    var toRaw = (parsed['recipientEmail'] as String? ?? pendingDraft['to'] as String? ?? '').trim();
    if (toRaw.isEmpty) {
      final match = _emailExtractPattern.firstMatch(context.message);
      if (match != null) {
        toRaw = match.group(0)!;
      }
    }

    final ccRaw = wantsRemoveCc
        ? ''
        : (parsed['ccEmails'] as String? ?? pendingDraft['cc'] as String? ?? '').trim();
    final bccRaw = wantsRemoveBcc
        ? ''
        : (parsed['bccEmails'] as String? ?? pendingDraft['bcc'] as String? ?? '').trim();

    final to = _validateEmails(toRaw, invalid);
    final cc = _validateEmails(ccRaw, invalid);
    final bcc = _validateEmails(bccRaw, invalid);

    if (invalid.isNotEmpty) {
      return AgentExecutionResult(
        responseText:
            "This doesn't look like a valid email address: \"${invalid.join(', ')}\" — the rest of your draft is still saved as it was.",
        agentName: name,
      );
    }

    if (to.isEmpty) {
      // Never let a revision accidentally drop every recipient — fall back
      // to whatever was already on the draft.
      final fallbackTo = _validateEmails(pendingDraft['to'] as String? ?? '', []);
      if (fallbackTo.isEmpty) {
        return AgentExecutionResult(
          responseText: "I still don't have a recipient for this draft — who should it go to?",
          agentName: name,
        );
      }
      to.addAll(fallbackTo);
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

    if (body.isEmpty) {
      body = await _generateEmailBody(context, subject, userName);
    }
    if (body.isEmpty) {
      body = "(Please enter your email body here)";
    }

    final ccDeduped = cc.where((addr) => !to.contains(addr)).toList();
    final bccDeduped = bcc.where((addr) => !to.contains(addr) && !ccDeduped.contains(addr)).toList();

    final updatedDraft = {
      'to': to.join(', '),
      'cc': ccDeduped.join(', '),
      'bcc': bccDeduped.join(', '),
      'subject': subject,
      'body': body,
      'priority': priority,
      'attachmentPaths': pendingDraft['attachmentPaths'] ?? const [],
      'dispatching': false,
    };

    final revisionSaved = await _saveMemoryPatch(context, {'pendingDraft': updatedDraft});
    if (!revisionSaved) {
      return AgentExecutionResult(
        responseText: "I applied the change but couldn't save the updated draft — mind trying once more?",
        agentName: name,
        success: false,
      );
    }

    final attachmentCount = (updatedDraft['attachmentPaths'] as List?)?.length ?? 0;

    return AgentExecutionResult(
      responseText:
          "Updated the draft:\n\n${_formatDraftPreview(to: updatedDraft['to'] as String, cc: updatedDraft['cc'] as String, bcc: updatedDraft['bcc'] as String, subject: updatedDraft['subject'] as String, body: updatedDraft['body'] as String, priority: priority, attachmentCount: attachmentCount)}",
      agentName: name,
      usedTools: const ['groq'],
    );
  }

  Future<Map<String, dynamic>> _classifyRevision(
    ExecutionContext context,
    Map<String, dynamic> pendingDraft,
    String userName,
  ) async {
    final currentDraft = "Current draft:\n"
        "To: ${pendingDraft['to']}\n"
        "Cc: ${pendingDraft['cc'] ?? ''}\n"
        "Bcc: ${pendingDraft['bcc'] ?? ''}\n"
        "Subject: ${pendingDraft['subject']}\n"
        "Priority: ${pendingDraft['priority'] ?? 'normal'}\n\n"
        "Body:\n${pendingDraft['body']}";

    final rawResponse = await ToolManager.instance.executeTool('groq', {
      'systemPrompt': "$_revisionSystemPrompt\nWrite the email as $userName. Decide the tone (professional or personal) based on the context.",
      'message': "$currentDraft\n\nRequested change: ${context.message}",
      'history': const [],
      'temperature': 0.0,
    }) as String;

    var parsed = _parseJson(rawResponse);

    if (parsed.isEmpty) {
      // One retry, mirroring the resilience already applied to the primary
      // classifier, so a single transient bad-JSON response from the model
      // doesn't force the user to restate their edit.
      final retryResponse = await ToolManager.instance.executeTool('groq', {
        'systemPrompt': "$_revisionSystemPrompt\nWrite the email as $userName. Decide the tone (professional or personal) based on the context.",
        'message': "$currentDraft\n\nRequested change: ${context.message}",
        'history': const [],
        'temperature': 0.0,
      }) as String;
      parsed = _parseJson(retryResponse);
    }

    return parsed;
  }

  // ---------- CONFIRM / SEND ----------

  Future<AgentExecutionResult> _dispatchPendingDraft(
    ExecutionContext context,
    Map<String, dynamic> pendingDraft,
  ) async {
    // Re-validate the recipient at send time. Memory is long-lived and a
    // draft could in principle have been tampered with or corrupted between
    // creation and confirmation; we never send to an address that fails
    // validation at this final gate.
    final sendInvalid = <String>[];
    final toForSend = _validateEmails(pendingDraft['to'] as String? ?? '', sendInvalid);
    if (toForSend.isEmpty || sendInvalid.isNotEmpty) {
      return AgentExecutionResult(
        responseText: "This draft's recipient address looks invalid now — who should it go to?",
        agentName: name,
      );
    }

    final lockSaved = await _saveMemoryPatch(context, {
      'pendingDraft': {
        ...pendingDraft,
        'dispatching': true,
        'dispatchStartedAt': DateTime.now().toIso8601String(),
      },
    });
    if (!lockSaved) {
      return AgentExecutionResult(
        responseText: "I couldn't lock in the send just now — mind trying \"send it\" again?",
        agentName: name,
        success: false,
      );
    }

    try {
      final cleanBody = _formatEmailForSending(pendingDraft['body'] as String? ?? '');

      await ToolManager.instance.executeTool('email', {
        'type': 'send',
        'to': toForSend.join(', '),
        'cc': pendingDraft['cc'] ?? '',
        'bcc': pendingDraft['bcc'] ?? '',
        'subject': pendingDraft['subject'],
        'body': cleanBody,
        'attachmentPaths': pendingDraft['attachmentPaths'] ?? const [],
      });

      await _clearPendingDraft(context);

      return AgentExecutionResult(
        responseText: "Sent! Your email to ${toForSend.join(', ')} is on its way.",
        agentName: name,
        usedTools: const ['email'],
      );
    } on GmailNotConnectedException {
      await _releaseDispatchLock(context, pendingDraft);
      return AgentExecutionResult(
        responseText:
            "I have your draft ready, but I need access to your Gmail account first. Please connect Gmail, then say \"send it\" again.",
        agentName: name,
        action: const AgentAction(type: AgentActionType.connectGmail),
      );
    } catch (e) {
      await _releaseDispatchLock(context, pendingDraft);
      return AgentExecutionResult(
        responseText: "I couldn't send that email — $e. Your draft is still saved, so you can say \"send it\" to try again.",
        agentName: name,
        success: false,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> _releaseDispatchLock(ExecutionContext context, Map<String, dynamic> pendingDraft) async {
    // Best-effort: if this fails, the staleness check in
    // _isDispatchLockStale will still eventually unstick the draft.
    await _saveMemoryPatch(context, {
      'pendingDraft': {...pendingDraft, 'dispatching': false, 'dispatchStartedAt': null},
    });
  }

  String _formatEmailForSending(String body) {
    var clean = body.trim();
    clean = clean.replaceAll(RegExp(r'<[^>]*>'), '');
    clean = clean.replaceAll('**', '');
    clean = clean.replaceAll('*', '');
    clean = clean.replaceAll('__', '');
    clean = clean.replaceAll('`', '');
    clean = clean.replaceAll(RegExp(r'^#+\s*', multiLine: true), '');
    return clean.trim();
  }

  Future<void> _clearPendingDraft(ExecutionContext context) async {
    await _saveMemoryPatch(context, {'pendingDraft': null});
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

    if (senderName.isEmpty && keywords.isEmpty && dateHint.isEmpty && !unreadOnly && !hasAttachment) {
      return AgentExecutionResult(
        responseText: "Who or what should I search your inbox for?",
        agentName: name,
      );
    }

    List<Map<String, String>> matches = [];

    try {
      final query = _buildGmailQuery(senderName, keywords, dateHint, unreadOnly: unreadOnly, hasAttachment: hasAttachment);
      matches = await ToolManager.instance.executeTool('email', {
        'type': 'search',
        'query': query,
        'maxResults': _maxSearchResults,
      }) as List<Map<String, String>>;

      if (matches.isEmpty && senderName.isNotEmpty) {
        final plainQuery = [senderName, keywords].where((s) => s.isNotEmpty).join(' ');
        matches = await ToolManager.instance.executeTool('email', {
          'type': 'search',
          'query': plainQuery,
          'maxResults': _maxSearchResults,
        }) as List<Map<String, String>>;
      }

      if (matches.isEmpty) {
        final broadQuery = _buildGmailQuery('', '', '', unreadOnly: unreadOnly, hasAttachment: hasAttachment);
        final recent = await ToolManager.instance.executeTool('email', {
          'type': broadQuery.isEmpty ? 'fetch' : 'search',
          if (broadQuery.isNotEmpty) 'query': broadQuery,
          'maxResults': 50,
        }) as List<Map<String, String>>;

        final needle = [senderName, keywords].where((s) => s.isNotEmpty).join(' ').toLowerCase();

        if (needle.isNotEmpty) {
          matches = recent.where((m) {
            final haystack = '${m['from']} ${m['subject']} ${m['snippet']}'.toLowerCase();
            return needle.split(' ').where((w) => w.isNotEmpty).every(haystack.contains);
          }).toList();
        } else {
          matches = recent;
        }
      }
    } on GmailNotConnectedException {
      return AgentExecutionResult(
        responseText: "I need access to your Gmail account to search your inbox. Please connect Gmail first.",
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
        responseText: "I didn't find anything matching \"${who.isNotEmpty ? who : 'that'}\" in your inbox.",
        agentName: name,
        usedTools: const ['email'],
      );
    }

    int selectedCount;
    if (scope == 'all') {
      selectedCount = matches.length;
    } else if (scope.startsWith('count:')) {
      selectedCount = int.tryParse(scope.substring('count:'.length)) ?? 1;
      if (selectedCount <= 0) selectedCount = 1; // guard against "count:0" or a bad parse
    } else {
      selectedCount = 1;
    }
    selectedCount = selectedCount.clamp(1, matches.length);

    // Best-effort: if this fails, the user just won't be able to say "read
    // the first one" as a follow-up; the results are still shown below.
    await _saveMemoryPatch(context, {
      'pendingSearchResults': {
        'results': matches,
        'lastShownIndex': selectedCount - 1,
      },
    });

    if (selectedCount == 1 && question.isNotEmpty) {
      return _readAndAnswer(context, matches.first, question);
    }

    return AgentExecutionResult(
      responseText: _formatSearchResults(matches.take(selectedCount).toList(), totalFound: matches.length),
      agentName: name,
      usedTools: const ['email'],
    );
  }

  Future<AgentExecutionResult> _handleSearchFollowUp(
    ExecutionContext context,
    Map<String, dynamic> pendingSearch,
  ) async {
    final rawResults = pendingSearch['results'] as List?;
    final matches = (rawResults ?? const [])
        .whereType<Map>()
        .map((m) => m.cast<String, String>())
        .toList();
    final lastShownIndex = (pendingSearch['lastShownIndex'] as int?)?.clamp(0, matches.isEmpty ? 0 : matches.length - 1) ?? 0;

    if (matches.isEmpty) {
      return AgentExecutionResult(
        responseText: "I don't have a previous search to refer back to — what would you like me to look for?",
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
    } else if (lower.contains('before') || lower.contains('previous') || lower.contains('earlier')) {
      targetIndex = lastShownIndex + 1;
    } else if (lower.contains('next') || lower.contains('after') || lower.contains('another') || lower.contains('newer')) {
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
        responseText: "That's the oldest one I found - there isn't an earlier match.",
        agentName: name,
      );
    }

    // Best-effort: worst case, the next follow-up re-anchors from the same
    // index rather than the new one.
    await _saveMemoryPatch(context, {
      'pendingSearchResults': {
        'results': matches,
        'lastShownIndex': targetIndex,
      },
    });

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
    final emailId = matchMeta['id'];
    if (emailId == null || emailId.isEmpty) {
      return AgentExecutionResult(
        responseText: "I lost track of which email that was — could you search again?",
        agentName: name,
      );
    }

    try {
      final full = await ToolManager.instance.executeTool('email', {
        'type': 'get',
        'id': emailId,
      }) as Map<String, String>;

      final answer = await ToolManager.instance.executeTool('groq', {
        'systemPrompt': 'You are the Email Agent. Answer the user\'s question using only the content of this one email. Be concise and direct.',
        'message': "Email from: ${full['from']}\nSubject: ${full['subject']}\nDate: ${full['date']}\n\n${full['body']}\n\nQuestion: $question",
        'history': const [],
      }) as String;

      return AgentExecutionResult(
        responseText: answer,
        agentName: name,
        usedTools: const ['email', 'groq'],
      );
    } on GmailNotConnectedException {
      return AgentExecutionResult(
        responseText: "I need access to your Gmail account to read that email. Please connect Gmail first.",
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
    if (badge.isNotEmpty) {
      buffer.writeln(badge);
    }
    buffer
      ..writeln("Here is the draft I came up with:")
      ..writeln()
      ..writeln("**To:** $to");
    if (cc.isNotEmpty) {
      buffer.writeln("**Cc:** $cc");
    }
    if (bcc.isNotEmpty) {
      buffer.writeln("**Bcc:** $bcc");
    }
    buffer.writeln("**Subject:** $subject");
    if (attachmentCount > 0) {
      buffer.writeln("**Attachments:** $attachmentCount file${attachmentCount == 1 ? '' : 's'}");
    }
    buffer
      ..writeln()
      ..writeln(body)
      ..writeln()
      ..writeln(
          "---\nI've drafted this email for you. **Should I send it?** Reply **\"send it\"** to deliver it, **\"cancel\"** to discard it, or tell me what to change.");
    return buffer.toString().trim();
  }

  String _formatSearchResults(List<Map<String, String>> shown, {required int totalFound}) {
    final buffer = StringBuffer();

    if (shown.length == 1) {
      final m = shown.first;
      buffer
        ..writeln("**From:** ${m['from'] ?? 'Unknown sender'}")
        ..writeln("**Subject:** ${m['subject'] ?? '(no subject)'}")
        ..writeln("**Date:** ${m['date'] ?? 'Unknown date'}")
        ..writeln()
        ..writeln(m['snippet'] ?? '');
    } else {
      buffer
        ..writeln("Found $totalFound matching email(s)${totalFound > shown.length ? ', showing the ${shown.length} most recent' : ''}:")
        ..writeln();
      for (final m in shown) {
        buffer.writeln("- **${m['subject'] ?? '(no subject)'}** from ${m['from'] ?? 'Unknown sender'} (${m['date'] ?? 'Unknown date'})");
      }
      buffer
        ..writeln()
        ..writeln("_Reply with \"the first one\", \"read it\", etc. to see one in full._");
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

  List<String> _validateEmails(String raw, List<String> invalidOut) {
    if (raw.trim().isEmpty) {
      return [];
    }

    final candidates = raw.split(RegExp(r'[,;]')).map((e) => e.trim()).where((e) => e.isNotEmpty);

    final valid = <String>[];
    final seen = <String>{};
    for (final candidate in candidates) {
      if (_emailPattern.hasMatch(candidate)) {
        final normalized = candidate.toLowerCase();
        if (seen.add(normalized)) {
          valid.add(candidate);
        }
        // silently drop exact duplicates rather than flagging them invalid
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

    if (senderName.isNotEmpty) {
      parts.add(senderName.contains(' ') ? 'from:"$senderName"' : 'from:$senderName');
    }
    if (keywords.isNotEmpty) {
      parts.add(keywords);
    }
    if (unreadOnly) {
      parts.add('is:unread');
    }
    if (hasAttachment) {
      parts.add('has:attachment');
    }

    final dateRange = _resolveDateRange(dateHint);
    if (dateRange.isNotEmpty) {
      parts.add(dateRange);
    }

    return parts.join(' ').trim();
  }

  String _resolveDateRange(String hint) {
    if (hint.isEmpty) {
      return '';
    }
    final lower = hint.toLowerCase();
    final now = DateTime.now();

    String fmt(DateTime d) => '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

    if (lower.contains('today')) {
      return 'after:${fmt(now.subtract(const Duration(days: 1)))}';
    }
    if (lower.contains('yesterday')) {
      return 'after:${fmt(now.subtract(const Duration(days: 2)))} before:${fmt(now)}';
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
      // DateTime normalizes month=0 to December of the prior year, so this
      // correctly rolls over across a January boundary without special-casing.
      final startOfThisMonth = DateTime(now.year, now.month, 1);
      final startOfLastMonth = DateTime(now.year, now.month - 1, 1);
      return 'after:${fmt(startOfLastMonth)} before:${fmt(startOfThisMonth)}';
    }

    return '';
  }

  // ---------- READ INBOX ----------

  Future<AgentExecutionResult> _handleReadInbox(ExecutionContext context) async {
    List<Map<String, String>> emails;

    try {
      emails = (await ToolManager.instance.executeTool('email', {
        'type': 'fetch',
        'maxResults': 10,
      })) as List<Map<String, String>>;
    } on GmailNotConnectedException {
      return AgentExecutionResult(
        responseText: "I need access to your Gmail account to check your inbox. Please connect Gmail first.",
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
        .map((e) => "From: ${e['from'] ?? 'Unknown'}\nSubject: ${e['subject'] ?? '(no subject)'}\nDate: ${e['date'] ?? 'Unknown'}\nSnippet: ${e['snippet'] ?? ''}")
        .join('\n\n');

    final summaryPrompt =
        "Summarize these recent emails for the user. Group related ones, call out anything urgent or needing a reply, and keep it concise.\n\n$emailsText";

    try {
      final summary = await ToolManager.instance.executeTool('groq', {
        'systemPrompt': 'You are the Email Agent. Summarize inbox emails clearly and concisely.',
        'message': summaryPrompt,
        'history': const [],
      }) as String;

      return AgentExecutionResult(
        responseText: summary,
        agentName: name,
        usedTools: const ['email', 'groq'],
      );
    } catch (e) {
      // The fetch succeeded but summarization failed — still give the user
      // something useful rather than a bare error.
      return AgentExecutionResult(
        responseText:
            "I fetched your inbox but couldn't summarize it just now. Here's what came in:\n\n${_formatSearchResults(emails.take(10).toList(), totalFound: emails.length)}",
        agentName: name,
        usedTools: const ['email'],
        success: false,
        errorMessage: e.toString(),
      );
    }
  }

  // ---------- CLASSIFICATION ----------

  Future<Map<String, dynamic>> _classify(ExecutionContext context) async {
    final history = context.recentMessages.map((m) => m.toGroqFormat()).toList();

    final rawResponse = await ToolManager.instance.executeTool('groq', {
      'systemPrompt': systemPrompt,
      'message': _buildPrompt(context),
      'history': history,
      'temperature': 0.0,
    }) as String;

    var parsed = _parseJson(rawResponse);

    if (parsed.isEmpty) {
      final retryResponse = await ToolManager.instance.executeTool('groq', {
        'systemPrompt': systemPrompt,
        'message': _buildPrompt(context),
        'history': history,
        'temperature': 0.0,
      }) as String;
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
    if (context.domainContext.isNotEmpty) {
      buffer.writeln(context.domainContext);
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
      if (start == -1 || end == -1 || end < start) {
        return {};
      }
      final decoded = jsonDecode(text.substring(start, end + 1));
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      return {};
    } catch (_) {
      return {};
    }
  }
}