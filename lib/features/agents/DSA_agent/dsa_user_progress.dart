class DsaUserProgress {
  int totalSolved;
  final int currentStreak;
  final int longestStreak;
  final Map<String, int> difficultySolved; // {Easy: 10, Medium: 5, Hard: 2}
  final Map<String, int> tagDistribution;  // {Arrays: 15, Graphs: 2}

  DsaUserProgress({
    this.totalSolved = 0,
    this.currentStreak = 0,
    this.longestStreak = 0,
    this.difficultySolved = const {},
    this.tagDistribution = const {},
  });

  factory DsaUserProgress.fromMap(Map<String, dynamic> map) {
    return DsaUserProgress(
      totalSolved: map['totalSolved'] ?? 0,
      currentStreak: map['currentStreak'] ?? 0,
      longestStreak: map['longestStreak'] ?? 0,
      difficultySolved: Map<String, int>.from(map['difficultySolved'] ?? {}),
      tagDistribution: Map<String, int>.from(map['tagDistribution'] ?? {}),
    );
  }

  Map<String, dynamic> toMap() => {
        'totalSolved': totalSolved,
        'currentStreak': currentStreak,
        'longestStreak': longestStreak,
        'difficultySolved': difficultySolved,
        'tagDistribution': tagDistribution,
      };
}