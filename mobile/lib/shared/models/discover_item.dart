import 'user_profile.dart';

/// One ranked entry in the discovery feed (GET /discover).
class DiscoverItem {
  const DiscoverItem({
    required this.user,
    required this.distanceM,
    required this.sharedTags,
    required this.score,
  });

  final PublicUserProfile user;
  final double distanceM;
  final List<String> sharedTags;
  final double score;

  factory DiscoverItem.fromJson(Map<String, dynamic> json) {
    return DiscoverItem(
      user: PublicUserProfile.fromJson(json['user'] as Map<String, dynamic>),
      distanceM: (json['distance_m'] as num).toDouble(),
      sharedTags: (json['shared_tags'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      score: (json['score'] as num).toDouble(),
    );
  }
}

/// A page of discovery results with an opaque cursor for the next page.
class DiscoverFeed {
  const DiscoverFeed({required this.items, this.nextCursor});

  final List<DiscoverItem> items;
  final String? nextCursor;

  factory DiscoverFeed.fromJson(Map<String, dynamic> json) {
    return DiscoverFeed(
      items: (json['items'] as List<dynamic>? ?? [])
          .map((e) => DiscoverItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      nextCursor: json['next_cursor'] as String?,
    );
  }
}
