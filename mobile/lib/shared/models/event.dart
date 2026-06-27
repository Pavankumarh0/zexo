/// A local event (GET /events/:id, list items).
class EventModel {
  const EventModel({
    required this.id,
    required this.creatorId,
    required this.title,
    this.description,
    required this.lat,
    required this.lng,
    required this.radiusM,
    this.capacity,
    this.tags = const [],
    required this.visibility,
    required this.startsAt,
    required this.endsAt,
    this.isArchived = false,
    this.attendeeCount = 0,
    this.distanceM,
    this.myRsvp,
  });

  final String id;
  final String creatorId;
  final String title;
  final String? description;
  final double lat;
  final double lng;
  final double radiusM;
  final int? capacity;
  final List<String> tags;
  final String visibility;
  final DateTime startsAt;
  final DateTime endsAt;
  final bool isArchived;
  final int attendeeCount;
  final double? distanceM;
  final String? myRsvp;

  factory EventModel.fromJson(Map<String, dynamic> json) {
    return EventModel(
      id: json['id'] as String,
      creatorId: json['creator_id'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      radiusM: (json['radius_m'] as num).toDouble(),
      capacity: json['capacity'] as int?,
      tags: (json['tags'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      visibility: json['visibility'] as String? ?? 'public',
      startsAt: DateTime.parse(json['starts_at'] as String),
      endsAt: DateTime.parse(json['ends_at'] as String),
      isArchived: json['is_archived'] as bool? ?? false,
      attendeeCount: json['attendee_count'] as int? ?? 0,
      distanceM: (json['distance_m'] as num?)?.toDouble(),
      myRsvp: json['my_rsvp'] as String?,
    );
  }
}
