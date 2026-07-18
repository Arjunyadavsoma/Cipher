class DsaQuestion {
  final String id;
  final String title;
  final String description;
  final String difficulty;
  final List<String> tags;
  final String url;
  final String? editorial;
  final List<String> hints;
  final String? solution;
  final String? timeComplexity;
  final String? spaceComplexity;

  DsaQuestion({
    required this.id,
    required this.title,
    required this.description,
    required this.difficulty,
    required this.tags,
    required this.url,
    this.editorial,
    this.hints = const [],
    this.solution,
    this.timeComplexity,
    this.spaceComplexity,
  });

  factory DsaQuestion.fromMap(Map<String, dynamic> map) {
    return DsaQuestion(
      id: map['id'] ?? '',
      title: map['title'] ?? 'Unknown',
      description: map['description'] ?? '',
      difficulty: map['difficulty'] ?? 'Easy',
      tags: List<String>.from(map['tags'] ?? []),
      url: map['url'] ?? '',
      editorial: map['editorial'],
      hints: List<String>.from(map['hints'] ?? []),
      solution: map['solution'],
      timeComplexity: map['timeComplexity'],
      spaceComplexity: map['spaceComplexity'],
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'description': description,
        'difficulty': difficulty,
        'tags': tags,
        'url': url,
        'editorial': editorial,
        'hints': hints,
        'solution': solution,
        'timeComplexity': timeComplexity,
        'spaceComplexity': spaceComplexity,
      };
}