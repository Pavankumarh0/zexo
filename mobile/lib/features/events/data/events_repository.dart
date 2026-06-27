import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/providers.dart';
import '../../../shared/models/event.dart';

/// Event API access (GET/POST /events, RSVP).
class EventsRepository {
  EventsRepository(this._api);

  final ApiClient _api;

  Future<List<EventModel>> nearby({
    required double lat,
    required double lng,
    required double radiusM,
    List<String>? tags,
    String? cursor,
  }) async {
    final json = await _api.getJson('/events', query: {
      'lat': lat,
      'lng': lng,
      'radius': radiusM,
      if (tags != null && tags.isNotEmpty) 'tags': tags,
      if (cursor != null) 'cursor': cursor,
    });
    final items = json['items'] as List<dynamic>? ?? [];
    return items
        .map((e) => EventModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<EventModel> getById(String id) async {
    final json = await _api.getJson('/events/$id');
    return EventModel.fromJson(json);
  }

  Future<EventModel> create({
    required String title,
    String? description,
    required double lat,
    required double lng,
    required double radiusM,
    int? capacity,
    required List<String> tags,
    required String visibility,
    required DateTime startsAt,
    required DateTime endsAt,
  }) async {
    final json = await _api.postJson('/events', body: {
      'title': title,
      if (description != null && description.isNotEmpty) 'description': description,
      'lat': lat,
      'lng': lng,
      'radius_m': radiusM,
      if (capacity != null) 'capacity': capacity,
      'tags': tags,
      'visibility': visibility,
      'starts_at': startsAt.toUtc().toIso8601String(),
      'ends_at': endsAt.toUtc().toIso8601String(),
    });
    return EventModel.fromJson(json);
  }

  Future<void> rsvp(String eventId, String status) async {
    await _api.postJson('/events/$eventId/rsvp', body: {'status': status});
  }
}

final eventsRepositoryProvider = Provider<EventsRepository>((ref) {
  return EventsRepository(ref.watch(apiClientProvider));
});
