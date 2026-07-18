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
}
