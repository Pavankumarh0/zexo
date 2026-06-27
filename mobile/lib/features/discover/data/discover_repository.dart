import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/providers.dart';
import '../../../shared/models/discover_item.dart';

/// Discovery feed + map API access (GET /discover, /discover/map).
class DiscoverRepository {
  DiscoverRepository(this._api);

  final ApiClient _api;

  Future<DiscoverFeed> feed({
    required double lat,
    required double lng,
    required double radiusM,
    List<String>? tags,
    String? cursor,
    int limit = 20,
  }) async {
    final json = await _api.getJson('/discover', query: {
      'lat': lat,
      'lng': lng,
      'radius': radiusM,
      if (tags != null && tags.isNotEmpty) 'tags': tags,
      if (cursor != null) 'cursor': cursor,
      'limit': limit,
    });
    return DiscoverFeed.fromJson(json);
  }

  Future<Map<String, dynamic>> map(String bbox) {
    return _api.getJson('/discover/map', query: {'bbox': bbox});
  }
}

final discoverRepositoryProvider = Provider<DiscoverRepository>((ref) {
  return DiscoverRepository(ref.watch(apiClientProvider));
});
