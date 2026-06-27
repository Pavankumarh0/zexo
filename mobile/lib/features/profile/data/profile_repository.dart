import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/providers.dart';
import '../../../shared/models/user_profile.dart';

/// Profile, location, and visibility API access (GET/PUT /users/*).
class ProfileRepository {
  ProfileRepository(this._api);

  final ApiClient _api;

  Future<UserProfile> getMe() async {
    final json = await _api.getJson('/users/me');
    return UserProfile.fromJson(json);
  }

  Future<PublicUserProfile> getPublicProfile(String userId) async {
    final json = await _api.getJson('/users/$userId');
    return PublicUserProfile.fromJson(json);
  }

  Future<UserProfile> updateMe({
    String? displayName,
    String? bio,
    String? avatarUrl,
    List<String>? interestTags,
    double? radiusM,
  }) async {
    final body = <String, dynamic>{
      if (displayName != null) 'display_name': displayName,
      if (bio != null) 'bio': bio,
      if (avatarUrl != null) 'avatar_url': avatarUrl,
      if (interestTags != null) 'interest_tags': interestTags,
      if (radiusM != null) 'radius_m': radiusM,
    };
    final json = await _api.putJson('/users/me', body: body);
    return UserProfile.fromJson(json);
  }

  /// Push fuzzed-server-side coordinates; the server applies the ±150m offset.
  Future<void> updateLocation({
    required double lat,
    required double lng,
    double? accuracyM,
    String source = 'gps',
  }) async {
    await _api.putJson('/users/location', body: {
      'lat': lat,
      'lng': lng,
      if (accuracyM != null) 'accuracy_m': accuracyM,
      'source': source,
    });
  }

  Future<bool> setVisibility(bool isVisible) async {
    final json = await _api.putJson(
      '/users/visibility',
      body: {'is_visible': isVisible},
    );
    return json['is_visible'] as bool? ?? isVisible;
  }

  Future<void> deleteAccount() => _api.delete('/users/me');

  Future<void> block(String userId, {bool report = false, String? reason}) async {
    await _api.postJson(
      '/users/$userId/block',
      body: {'report': report, if (reason != null) 'reason': reason},
    );
  }
}

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepository(ref.watch(apiClientProvider));
});

/// The current user's profile, refreshable after edits.
final myProfileProvider = FutureProvider<UserProfile>((ref) {
  return ref.watch(profileRepositoryProvider).getMe();
});

/// A public profile by id (for the profile detail screen).
final publicProfileProvider =
    FutureProvider.family<PublicUserProfile, String>((ref, userId) {
  return ref.watch(profileRepositoryProvider).getPublicProfile(userId);
});
