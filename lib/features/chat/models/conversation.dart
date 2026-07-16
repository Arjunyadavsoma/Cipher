class Conversation {
  final String id;
  final String title;

  const Conversation({
    required this.id,
    required this.title,
  });

  factory Conversation.fromMap(
      String id,
      Map<String, dynamic> json,
      ) {
    return Conversation(
      id: id,
      title: json["title"] ?? "New Chat",
    );
  }
}