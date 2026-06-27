/// A chat message (persisted with a 24h TTL on the server).
class Message {
  const Message({
    required this.id,
    required this.threadId,
    required this.senderId,
    required this.body,
    this.readAt,
    required this.expiresAt,
    required this.createdAt,
  });

  final String id;
  final String threadId;
  final String senderId;
  final String body;
  final DateTime? readAt;
  final DateTime expiresAt;
  final DateTime createdAt;

  bool get isRead => readAt != null;

  /// Fraction of life remaining in [0, 1]; used to fade bubbles near expiry.
  double remainingLifeFraction(DateTime now) {
    final total = expiresAt.difference(createdAt).inSeconds;
    if (total <= 0) return 0;
    final left = expiresAt.difference(now).inSeconds;
    return (left / total).clamp(0.0, 1.0);
  }

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'] as String,
      threadId: json['thread_id'] as String,
      senderId: json['sender_id'] as String,
      body: json['body'] as String,
      readAt: json['read_at'] != null
          ? DateTime.parse(json['read_at'] as String)
          : null,
      expiresAt: DateTime.parse(json['expires_at'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
