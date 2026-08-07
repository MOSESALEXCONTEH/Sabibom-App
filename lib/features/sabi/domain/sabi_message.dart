enum SabiMessageAuthor { user, assistant }

class SabiMessage {
  const SabiMessage({
    required this.id,
    required this.author,
    required this.text,
    required this.createdAt,
  });

  final String id;
  final SabiMessageAuthor author;
  final String text;
  final DateTime createdAt;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'author': author.name,
        'text': text,
        'createdAt': createdAt.toIso8601String(),
      };

  factory SabiMessage.fromJson(Map<String, dynamic> json) {
    final authorRaw = json['author'] as String? ?? 'assistant';
    return SabiMessage(
      id: json['id'] as String? ?? 'msg-${DateTime.now().microsecondsSinceEpoch}',
      author: authorRaw == 'user'
          ? SabiMessageAuthor.user
          : SabiMessageAuthor.assistant,
      text: json['text'] as String? ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}
