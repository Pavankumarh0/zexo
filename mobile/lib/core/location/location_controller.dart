import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../providers.dart';
import '../../features/profile/data/profile_repository.dart';
import 'location_service.dart';

final locationServiceProvider = Provider<LocationService>((ref) {
  return LocationService();
});

/// Holds the latest known [LocationFix] and drives 30s foreground polling,
/// pushing each fix to the backend (which fuzzes ±150m before storage).
///
/// Polling pauses automatically when the provider is disposed (no listeners),
/// satisfying "paused when app is closed" at the provider-lifecycle level.
class LocationController extends Notifier<LocationFix?> {
  Timer? _timer;

  @override
  LocationFix? build() {
    ref.onDispose(() => _timer?.cancel());
    // Kick off an immediate fix then start polling.
    Future.microtask(refresh);
    _timer = Timer.periodic(
      AppConstants.pollIntervalForeground,
      (_) => refresh(),
    );
    return null;
  }

  LocationService get _service => ref.read(locationServiceProvider);

  Future<void> refresh() async {
    final fix = await _service.getCurrent();
    if (fix == null) return;
    state = fix;
    // Best-effort push; ignore transient network errors.
    try {
      await ref.read(profileRepositoryProvider).updateLocation(
            lat: fix.lat,
            lng: fix.lng,
            accuracyM: fix.accuracyM,
            source: fix.source == LocationSource.city ? 'city' : 'gps',
          );
    } catch (_) {
      // Swallowed: the next poll will retry.
    }
  }
}

final locationControllerProvider =
    NotifierProvider<LocationController, LocationFix?>(LocationController.new);

/// True only after auth + a Supabase session exists, used to guard polling.
final canPollLocationProvider = Provider<bool>((ref) {
  return ref.watch(isAuthenticatedProvider);
});
