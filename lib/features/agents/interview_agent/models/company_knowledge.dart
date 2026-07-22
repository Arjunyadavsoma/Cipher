import 'package:uuid/uuid.dart';

const _uuid = Uuid();

class CompanyKnowledge {
  Metadata metadata;
  About about;
  HiringProcess hiringProcess;
  List<InterviewExperience> experiences;
  List<CodingQuestion> codingQuestions;
  List<SystemDesign> systemDesign;
  List<Behavioral> behavioral;
  Statistics statistics;
  List<Source> sources;
  KnowledgeGraph knowledgeGraph;

  CompanyKnowledge({
    required this.metadata,
    required this.about,
    required this.hiringProcess,
    required this.experiences,
    required this.codingQuestions,
    required this.systemDesign,
    required this.behavioral,
    required this.statistics,
    required this.sources,
    required this.knowledgeGraph,
  });

  factory CompanyKnowledge.empty(String companyId, String companyName) {
    return CompanyKnowledge(
      metadata: Metadata(companyId: companyId, companyName: companyName),
      about: About(),
      hiringProcess: HiringProcess(),
      experiences: [],
      codingQuestions: [],
      systemDesign: [],
      behavioral: [],
      statistics: Statistics(),
      sources: [],
      knowledgeGraph: KnowledgeGraph(),
    );
  }

  factory CompanyKnowledge.fromJson(Map<String, dynamic> json) {
    return CompanyKnowledge(
      metadata: Metadata.fromJson(json['metadata'] ?? {}),
      about: About.fromJson(json['about'] ?? {}),
      hiringProcess: HiringProcess.fromJson(json['hiring_process'] ?? {}),
      experiences: (json['experiences'] as List? ?? []).map((e) => InterviewExperience.fromJson(e)).toList(),
      codingQuestions: (json['coding_questions'] as List? ?? []).map((e) => CodingQuestion.fromJson(e)).toList(),
      systemDesign: (json['system_design'] as List? ?? []).map((e) => SystemDesign.fromJson(e)).toList(),
      behavioral: (json['behavioral'] as List? ?? []).map((e) => Behavioral.fromJson(e)).toList(),
      statistics: Statistics.fromJson(json['statistics'] ?? {}),
      sources: (json['sources'] as List? ?? []).map((e) => Source.fromJson(e)).toList(),
      knowledgeGraph: KnowledgeGraph.fromJson(json['knowledge_graph'] ?? {}),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'metadata': metadata.toJson(),
      'about': about.toJson(),
      'hiring_process': hiringProcess.toJson(),
      'experiences': experiences.map((e) => e.toJson()).toList(),
      'coding_questions': codingQuestions.map((e) => e.toJson()).toList(),
      'system_design': systemDesign.map((e) => e.toJson()).toList(),
      'behavioral': behavioral.map((e) => e.toJson()).toList(),
      'statistics': statistics.toJson(),
      'sources': sources.map((e) => e.toJson()).toList(),
      'knowledge_graph': knowledgeGraph.toJson(),
    };
  }
}

// --- Layer 1: Metadata ---
class Metadata {
  String companyId;
  String companyName;
  String industry;
  String lastUpdated;
  double confidence;

  Metadata({
    required this.companyId,
    required this.companyName,
    this.industry = '',
    this.lastUpdated = '',
    this.confidence = 0.0,
  });

  factory Metadata.fromJson(Map<String, dynamic> json) => Metadata(
        companyId: json['company_id'] ?? '',
        companyName: json['company_name'] ?? '',
        industry: json['industry'] ?? '',
        lastUpdated: json['last_updated'] ?? '',
        confidence: (json['confidence'] ?? 0.0).toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'company_id': companyId,
        'company_name': companyName,
        'industry': industry,
        'last_updated': lastUpdated,
        'confidence': confidence,
      };
}

// --- Layer 2: About ---
class About {
  String history;
  List<String> products;
  String culture;
  List<String> values;
  List<String> engineeringFocus;
  List<String> techStack;

  About({
    this.history = '',
    this.products = const [],
    this.culture = '',
    this.values = const [],
    this.engineeringFocus = const [],
    this.techStack = const [],
  });

  factory About.fromJson(Map<String, dynamic> json) => About(
        history: json['history'] ?? '',
        products: List<String>.from(json['products'] ?? []),
        culture: json['culture'] ?? '',
        values: List<String>.from(json['values'] ?? []),
        engineeringFocus: List<String>.from(json['engineering_focus'] ?? []),
        techStack: List<String>.from(json['tech_stack'] ?? []),
      );

  Map<String, dynamic> toJson() => {
        'history': history,
        'products': products,
        'culture': culture,
        'values': values,
        'engineering_focus': engineeringFocus,
        'tech_stack': techStack,
      };
}

// --- Layer 3: Hiring Process ---
class HiringProcess {
  Map<String, dynamic> oa;
  List<Map<String, dynamic>> technicalRounds;
  Map<String, dynamic> systemDesign;
  Map<String, dynamic> behavioral;
  Map<String, dynamic> hr;

  HiringProcess({
    this.oa = const {},
    this.technicalRounds = const [],
    this.systemDesign = const {},
    this.behavioral = const {},
    this.hr = const {},
  });

  factory HiringProcess.fromJson(Map<String, dynamic> json) => HiringProcess(
        oa: json['oa'] ?? {},
        technicalRounds: List<Map<String, dynamic>>.from(json['technical_rounds'] ?? []),
        systemDesign: json['system_design'] ?? {},
        behavioral: json['behavioral'] ?? {},
        hr: json['hr'] ?? {},
      );

  Map<String, dynamic> toJson() => {
        'oa': oa,
        'technical_rounds': technicalRounds,
        'system_design': systemDesign,
        'behavioral': behavioral,
        'hr': hr,
      };
}

// --- Layer 4: Interview Experiences ---
class InterviewExperience {
  String experienceId;
  String role;
  String country;
  int year;
  String result;
  String source;
  List<String> rounds;
  String difficulty;
  String summary;

  InterviewExperience({
    required this.experienceId,
    required this.role,
    required this.country,
    required this.year,
    required this.result,
    required this.source,
    this.rounds = const [],
    this.difficulty = '',
    this.summary = '',
  });

  factory InterviewExperience.fromJson(Map<String, dynamic> json) => InterviewExperience(
        experienceId: json['experience_id'] ?? _uuid.v4(),
        role: json['role'] ?? '',
        country: json['country'] ?? '',
        year: json['year'] ?? DateTime.now().year,
        result: json['result'] ?? '',
        source: json['source'] ?? '',
        rounds: List<String>.from(json['rounds'] ?? []),
        difficulty: json['difficulty'] ?? '',
        summary: json['summary'] ?? '',
      );

  Map<String, dynamic> toJson() => {
        'experience_id': experienceId,
        'role': role,
        'country': country,
        'year': year,
        'result': result,
        'source': source,
        'rounds': rounds,
        'difficulty': difficulty,
        'summary': summary,
      };
}

// --- Layer 5: Coding Questions ---
class CodingQuestion {
  String id;
  String title;
  String topic;
  String difficulty;
  int frequency;
  List<String> companies;
  List<String> sources;
  double confidence;
  String imageUrl; // <-- ADD THIS

  CodingQuestion({
    required this.id,
    required this.title,
    required this.topic,
    required this.difficulty,
    this.frequency = 1,
    List<String>? companies,
    List<String>? sources,
    this.confidence = 0.5,
    this.imageUrl = '', // <-- ADD THIS
  })  : companies = companies ?? [],
        sources = sources ?? [];

  factory CodingQuestion.fromJson(Map<String, dynamic> json) => CodingQuestion(
        id: json['id'] ?? _uuid.v4(),
        title: json['title'] ?? '',
        topic: json['topic'] ?? 'Unknown',
        difficulty: json['difficulty'] ?? 'Medium',
        frequency: json['frequency'] ?? 1,
        companies: List<String>.from(json['companies'] ?? []),
        sources: List<String>.from(json['sources'] ?? []),
        confidence: (json['confidence'] ?? 0.5).toDouble(),
        imageUrl: json['image_url'] ?? '', // <-- ADD THIS
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'topic': topic,
        'difficulty': difficulty,
        'frequency': frequency,
        'companies': companies,
        'sources': sources,
        'confidence': confidence,
        'image_url': imageUrl, // <-- ADD THIS
      };
}

// --- Layer 6: System Design ---
class SystemDesign {
  String id;
  String problem;
  int frequency;
  String difficulty;
  String role;

  SystemDesign({
    required this.id,
    required this.problem,
    this.frequency = 1,
    this.difficulty = 'Hard',
    this.role = '',
  });

  factory SystemDesign.fromJson(Map<String, dynamic> json) => SystemDesign(
        id: json['id'] ?? _uuid.v4(),
        problem: json['problem'] ?? '',
        frequency: json['frequency'] ?? 1,
        difficulty: json['difficulty'] ?? 'Hard',
        role: json['role'] ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'problem': problem,
        'frequency': frequency,
        'difficulty': difficulty,
        'role': role,
      };
}

// --- Layer 7: Behavioral ---
class Behavioral {
  String id;
  String question;
  int frequency;
  String leadershipPrinciple;

  Behavioral({
    required this.id,
    required this.question,
    this.frequency = 1,
    this.leadershipPrinciple = '',
  });

  factory Behavioral.fromJson(Map<String, dynamic> json) => Behavioral(
        id: json['id'] ?? _uuid.v4(),
        question: json['question'] ?? '',
        frequency: json['frequency'] ?? 1,
        leadershipPrinciple: json['leadership_principle'] ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'question': question,
        'frequency': frequency,
        'leadership_principle': leadershipPrinciple,
      };
}

// --- Layer 8: Statistics ---
class Statistics {
  int coding;
  int behavioral;
  int experiences;
  int sources;
  double confidence;

  Statistics({
    this.coding = 0,
    this.behavioral = 0,
    this.experiences = 0,
    this.sources = 0,
    this.confidence = 0.0,
  });

  factory Statistics.fromJson(Map<String, dynamic> json) => Statistics(
        coding: json['coding'] ?? 0,
        behavioral: json['behavioral'] ?? 0,
        experiences: json['experiences'] ?? 0,
        sources: json['sources'] ?? 0,
        confidence: (json['confidence'] ?? 0.0).toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'coding': coding,
        'behavioral': behavioral,
        'experiences': experiences,
        'sources': sources,
        'confidence': confidence,
      };
}

// --- Layer 9: Sources ---
class Source {
  String id;
  String url;
  String type;
  String retrieved;
  int quality;
  bool processed;

  Source({
    required this.id,
    required this.url,
    required this.type,
    required this.retrieved,
    this.quality = 50,
    this.processed = true,
  });

  factory Source.fromJson(Map<String, dynamic> json) => Source(
        id: json['id'] ?? _uuid.v4(),
        url: json['url'] ?? '',
        type: json['type'] ?? '',
        retrieved: json['retrieved'] ?? '',
        quality: json['quality'] ?? 50,
        processed: json['processed'] ?? true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'type': type,
        'retrieved': retrieved,
        'quality': quality,
        'processed': processed,
      };
}

// --- Layer 10: Knowledge Graph ---
class KnowledgeGraph {
  Map<String, List<String>> topics;

  KnowledgeGraph({Map<String, List<String>>? topics}) : topics = topics ?? {};

  factory KnowledgeGraph.fromJson(Map<String, dynamic> json) {
    return KnowledgeGraph(
      topics: Map<String, List<String>>.from(
        (json).map((k, v) => MapEntry(k, List<String>.from(v))),
      ),
    );
  }

  Map<String, dynamic> toJson() => topics;
}