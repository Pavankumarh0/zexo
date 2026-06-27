import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/location/location_controller.dart';
import '../../profile/data/profile_repository.dart';
import '../../../shared/models/event.dart';
import '../data/events_repository.dart';

/// Loads nearby events for the current location + the user's discovery radius.
final nearbyEventsProvider = FutureProvider<List<EventModel>>((ref) async {
  final fix = ref.watch(locationControllerProvider);
  if (fix == null) return const [];
  final profile = await ref.watch(myProfileProvider.future);
  return ref.watch(eventsRepositoryProvider).nearby(
        lat: fix.lat,
        lng: fix.lng,
        radiusM: profile.radiusM,
      );
});
