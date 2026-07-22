import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cipher_ai/features/agents/core/base_agent.dart';
import 'package:cipher_ai/features/agents/models/execution_context.dart';
import 'package:cipher_ai/features/agents/models/execution_result.dart';
import 'package:cipher_ai/features/agents/services/api_key_pool_service.dart';

import 'services/interview_orchestrator.dart';
import 'services/firestore_knowledge_service.dart'; // 1. ADD THIS IMPORT
import 'engine/context_builder.dart';

class InterviewAgent extends BaseAgent {
  final InterviewOrchestrator _orchestrator = InterviewOrchestrator();
  final ContextBuilder _contextBuilder = ContextBuilder();
  final ApiKeyPoolService _apiKeyPool = ApiKeyPoolService.instance;
  final FirestoreKnowledgeService _firestore =
      FirestoreKnowledgeService(); // 2. ADD THIS LINE

  // ... rest of the class remains exactly the same
  @override
  String get id => 'interview_agent';

  @override
  String get name => 'interview_agent';

  @override
  String get description =>
      'Researches companies, builds a master knowledge base, and generates interview papers. Trigger with @interview.';

  @override
  String get systemPrompt =>
      'You are an Interview Intelligence Engine. You research companies, build a master knowledge base, and generate structured interview papers.';

  @override
  List<String> get tools => [];

  InterviewAgent();

  // Replace the execute method in interview_agent.dart with this:

  @override
  Future<AgentExecutionResult> execute(ExecutionContext context) async {
    String userQuery = context.message;
    String lowerQuery = userQuery.toLowerCase();

    // --- MOCK INTERVIEW LOGIC ---
    bool isMockActive = context.agentMemory?['mock_interview_active'] == true;
    if (isMockActive) {
      return await _evaluateMockAnswer(context);
    }

    // --- START MOCK INTERVIEW ---
    if (lowerQuery.contains('@mock')) {
      String companyName = _extractCompanyName(
        userQuery.replaceAll('@mock', '').trim(),
      );
      if (companyName.isEmpty) {
        return AgentExecutionResult(
          responseText:
              "Which company do you want to mock interview with? e.g., '@mock Google'",
          agentName: name,
        );
      }
      return await _startMockInterview(companyName);
    }

    // --- RESEARCH LOGIC ---
    String cleanQuery = lowerQuery.contains('@interview')
        ? userQuery.replaceAll('@interview', '')
        : userQuery;

    String companyName = _extractCompanyName(cleanQuery);
    if (companyName.isEmpty) {
      return AgentExecutionResult(
        responseText:
            "Please specify a company name. Example: '@interview Google'",
        agentName: name,
      );
    }

    // CHECK IF USER JUST WANTS TO VIEW EXISTING DATA
    List<String> viewKeywords = [
      'resource',
      'sources',
      'links',
      'show',
      'list',
      'what are',
      'give me',
    ];
    bool wantsToViewOnly = viewKeywords.any((kw) => lowerQuery.contains(kw));

    try {
      // Only run the heavy scraping pipeline if they didn't ask to just "view" things
      // OR if the database is completely empty for this company.
      if (!wantsToViewOnly) {
        await _orchestrator.ensureKnowledgeIsFresh(companyName, role: "SDE");
      }

      // Instantly fetch from Firestore
      Map<String, dynamic> contextData = await _contextBuilder.buildContext(
        companyName,
        userQuery,
      );
      String formattedContext = _formatContextAsPrompt(
        contextData,
        companyName,
      );

      // FALLBACK: If no data was found
      if (formattedContext.isEmpty ||
          (contextData['coding_questions'] == null ||
                  (contextData['coding_questions'] as List).isEmpty) &&
              (contextData['sources'] == null ||
                  (contextData['sources'] as List).isEmpty)) {
        return AgentExecutionResult(
          responseText:
              "I don't have any data for $companyName yet. Try typing '@interview $companyName' to force a web search.",
          agentName: name,
        );
      }

      String finalResponse = await _generateNaturalResponse(
        companyName,
        userQuery,
        formattedContext,
      );
      return AgentExecutionResult(responseText: finalResponse, agentName: name);
    } catch (e) {
      return AgentExecutionResult(
        responseText:
            "I'm having trouble researching $companyName right now. Please try again.",
        agentName: name,
      );
    }
  }

  /// Starts the mock interview by fetching a question from Firestore
  Future<AgentExecutionResult> _startMockInterview(String companyName) async {
    String companyId = companyName.toLowerCase().replaceAll(' ', '_');

    // Fetch 1 random coding question from Firestore
    List<Map<String, dynamic>> questions = await _firestore.getRandomQuestions(
      companyId,
      'coding_questions',
      1,
    );

    if (questions.isEmpty) {
      return AgentExecutionResult(
        responseText:
            "I don't have enough data for $companyName yet. Please run '@interview $companyName' first to build the knowledge base.",
        agentName: name,
      );
    }

    var q = questions.first;
    String questionText =
        "Let's start the mock interview for $companyName.\n\n**Question:** ${q['title']}\n**Topic:** ${q['topic']}\n**Difficulty:** ${q['difficulty']}\n\nTake your time. Type your approach or code, and I'll evaluate it. Type 'exit' to end the interview.";

    // Save the current question to memory so we can evaluate it next turn
    return AgentExecutionResult(
      responseText: questionText,
      agentName: name,
      updatedMemory: {
        'mock_interview_active': true,
        'current_company': companyName,
        'current_question_title': q['title'],
        'current_question_topic': q['topic'] ?? '',
      },
    );
  }

  /// Evaluates the user's answer using Groq
  Future<AgentExecutionResult> _evaluateMockAnswer(
    ExecutionContext context,
  ) async {
    String userAnswer = context.message;

    // Check if user wants to exit
    if (userAnswer.toLowerCase() == 'exit') {
      return AgentExecutionResult(
        responseText: "Mock interview ended. Good luck with your preparation!",
        agentName: name,
        updatedMemory: {
          'mock_interview_active': false, // Turn off memory state
          'current_question_title': null,
        },
      );
    }

    String questionTitle = context.agentMemory?['current_question_title'] ?? '';
    String topic = context.agentMemory?['current_question_topic'] ?? '';

    try {
      final String apiKey = await _apiKeyPool.getNextKey();

      final response = await http.post(
        Uri.parse('https://api.groq.com/openai/v1/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': 'llama-3.1-8b-instant',
          'messages': [
            {
              'role': 'system',
              'content':
                  'You are a strict but encouraging technical interviewer. The candidate just answered a question. Evaluate their answer. Provide feedback on correctness, time complexity, and edge cases. Ask a follow-up question to deepen the discussion. Keep it concise.',
            },
            {
              'role': 'user',
              'content':
                  'Interview Question: $questionTitle (Topic: $topic)\n\nCandidate\'s Answer:\n$userAnswer',
            },
          ],
          'temperature': 0.4,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        await _apiKeyPool.reportSuccess(apiKey);
        String feedback = data['choices'][0]['message']['content'].trim();

        return AgentExecutionResult(
          responseText: feedback,
          agentName: name,
          // Keep mock interview active for continued back-and-forth!
          updatedMemory: context.agentMemory,
        );
      } else {
        await _apiKeyPool.reportFailure(apiKey, error: response.body);
        return AgentExecutionResult.failure(
          agentName: name,
          errorMessage: "Evaluation failed.",
        );
      }
    } catch (e) {
      return AgentExecutionResult.failure(
        agentName: name,
        errorMessage: "Error: $e",
      );
    }
  }

  /// Calls Groq LLM to convert the raw JSON context into a readable chat response
  Future<String> _generateNaturalResponse(
    String company,
    String userQuery,
    String contextData,
  ) async {
    try {
      final String apiKey = await _apiKeyPool.getNextKey();

      final response = await http.post(
        Uri.parse('https://api.groq.com/openai/v1/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': 'llama-3.1-8b-instant',
          'messages': [
            {
              'role': 'system',
              'content':
                  'You are an expert interview assistant. The user asked a question about company interviews. You have retrieved structured data from a database. Write a helpful, concise, and friendly response answering the user\'s question using ONLY the provided data. Format lists nicely.',
            },
            {
              'role': 'user',
              'content':
                  'User Question: $userQuery\n\nRetrieved Data for $company:\n$contextData',
            },
          ],
          'temperature': 0.5,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        await _apiKeyPool.reportSuccess(apiKey);
        return data['choices'][0]['message']['content'].trim();
      } else {
        await _apiKeyPool.reportFailure(apiKey, error: response.body);
        // Fallback to raw context if LLM fails
        return "Here is the data I found for $company:\n\n$contextData";
      }
    } catch (e) {
      // Fallback to raw context if LLM call throws an error
      return "Here is the data I found for $company:\n\n$contextData";
    }
  }

  String _extractCompanyName(String query) {
    String cleanQuery = query.toLowerCase().replaceAll('@interview', '').trim();
    if (cleanQuery.isNotEmpty) {
      return cleanQuery[0].toUpperCase() + cleanQuery.substring(1);
    }
    return '';
  }

  String _formatContextAsPrompt(Map<String, dynamic> context, String company) {
    StringBuffer sb = StringBuffer();
    sb.writeln("Company: $company");

    if (context.containsKey('coding_questions') &&
        (context['coding_questions'] as List).isNotEmpty) {
      sb.writeln("\nFrequently Asked Coding Questions:");
      for (var q in context['coding_questions']) {
        sb.writeln(
          "- ${q['title']} (Topic: ${q['topic']}, Frequency: ${q['frequency']})",
        );

        // If the question has an image, render it as Markdown so the chat UI displays it!
        if (q['image_url'] != null && q['image_url'].isNotEmpty) {
          sb.writeln("  ![Question Image](${q['image_url']})");
        }
      }
    }

    if (context.containsKey('sources') &&
        (context['sources'] as List).isNotEmpty) {
      sb.writeln("\nReference Resources (Scraped Links):");
      for (var s in context['sources']) {
        sb.writeln("- ${s['url']} (${s['type']})");
      }
    }

    return sb.toString();
  }
}
