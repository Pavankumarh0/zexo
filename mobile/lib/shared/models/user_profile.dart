/// The authenticated user's own profile (GET /users/me).
class UserProfile {
  const UserProfile({
    required this.id,
    this.displayName,
    this.bio,
    this.avatarUrl,
    this.interestTags = const [],
    this.isVisible = true,
    this.radiusM = 5000,
  });

  final String id;
  final String? displayName;
  final String? bio;
  final String? avatarUrl;
  final List<String> interestTags;
  final bool isVisible;
  final double radiusM;

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      displayName: json['display_name'] as String?,
      bio: json['bio'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      interestTags: (json['interest_tags'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      isVisible: json['is_visible'] as bool? ?? true,
      radiusM: (json['radius_m'] as num?)?.toDouble() ?? 5000,
    );
  }

  UserProfile copyWith({
    String? displayName,
    String? bio,
    String? avatarUrl,
    List<String>? interestTags,
    bool? isVisible,
    double? radiusM,
  }) {
    return UserProfile(
      id: id,
      displayName: displayName ?? this.displayName,
      bio: bio ?? this.bio,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      interestTags: interestTags ?? this.interestTags,
      isVisible: isVisible ?? this.isVisible,
      radiusM: radiusM ?? this.radiusM,
    );
  }
}

/// A public profile of another user (no contact or location fields).
class PublicUserProfile {
  const PublicUserProfile({
    required this.id,
    this.displayName,
    this.bio,
    this.avatarUrl,
    this.interestTags = const [],
  });

  final String id;
  final String? displayName;
  final String? bio;
  final String? avatarUrl;
  final List<String> interestTags;

  factory PublicUserProfile.fromJson(Map<String, dynamic> json) {
    return PublicUserProfile(
      id: json['id'] as String,
      displayName: json['display_name'] as String?,
      bio: json['bio'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      interestTags: (json['interest_tags'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}
