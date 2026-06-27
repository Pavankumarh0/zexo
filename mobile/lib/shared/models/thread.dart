import 'user_profile.dart';

/// A chat thread summary (GET /threads).
class ThreadSummary {
  const ThreadSummary({
    required this.id,
    required this.peer,
    this.lastMessageAt,
    this.unreadCount = 0,
    this.expiresAt,
  });

  final String id;
  final PublicUserProfile peer;
  final DateTime? lastMessageAt;
  final int unreadCount;
  final DateTime? expiresAt;

  /// Time until the thread expires, or null if no expiry is set yet.
  Duration? timeLeft(DateTime now) {
    if (expiresAt == null) return null;
    final d = expiresAt!.difference(now);
    return d.isNegative ? Duration.zero : d;
  }

  factory ThreadSummary.fromJson(Map<String, dynamic> json) {
    return ThreadSummary(
      id: json['id'] as String,
      peer: PublicUserProfile.fromJson(json['peer'] as Map<String, dynamic>),
      lastMessageAt: json['last_message_at'] != null
          ? DateTime.parse(json['last_message_at'] as String)
          : null,
      unreadCount: json['unread_count'] as int? ?? 0,
      expiresAt: json['expires_at'] != null
          ? DateTime.parse(json['expires_at'] as String)
          : null,
    );
  }
}
