import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/location/location_controller.dart';
import '../../../core/location/location_service.dart';
import '../../profile/data/profile_repository.dart';
import '../../../shared/models/discover_item.dart';
import '../data/discover_repository.dart';

/// Drives the ranked discovery feed: initial load, cursor pagination, and
/// auto-refresh when the user moves more than 200m from the last fetch position.
class DiscoverController extends AsyncNotifier<List<DiscoverItem>> {
  String? _cursor;
  LocationFix? _lastFix;
  bool _loadingMore = false;

  @override
  Future<List<DiscoverItem>> build() async {
    final fix = ref.read(locationControllerProvider);
    if (fix == null) return const [];
    return _fetchFirstPage(fix);
  }

  Future<double> _radius() async {
    final profile = await ref.read(myProfileProvider.future);
    return profile.radiusM;
  }

  Future<List<DiscoverItem>> _fetchFirstPage(LocationFix fix) async {
    final radiusM = await _radius();
    final feed = await ref.read(discoverRepositoryProvider).feed(
          lat: fix.lat,
          lng: fix.lng,
          radiusM: radiusM,
        );
    _cursor = feed.nextCursor;
    _lastFix = fix;
    return feed.items;
  }

  /// Pull-to-refresh / manual refresh for the current position.
  Future<void> refresh() async {
    final fix = ref.read(locationControllerProvider);
    if (fix == null) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _fetchFirstPage(fix));
  }

  /// Called when a new location fix arrives; refetches only if moved > 200m.
  Future<void> maybeRefreshOnMove(LocationFix fix) async {
    final last = _lastFix;
    if (last == null) {
      await refresh();
      return;
    }
    final moved = ref.read(locationServiceProvider).distanceBetween(last, fix);
    if (moved > AppConstants.feedRefreshDeltaM) {
      await refresh();
    }
  }

  bool get hasMore => _cursor != null;

  /// Append the next page using the opaque cursor.
  Future<void> loadMore() async {
    final fix = _lastFix;
    if (_cursor == null || _loadingMore || fix == null) return;
    _loadingMore = true;
    try {
      final radiusM = await _radius();
      final feed = await ref.read(discoverRepositoryProvider).feed(
            lat: fix.lat,
            lng: fix.lng,
            radiusM: radiusM,
            cursor: _cursor,
          );
      _cursor = feed.nextCursor;
      final current = state.valueOrNull ?? const <DiscoverItem>[];
      state = AsyncData([...current, ...feed.items]);
    } finally {
      _loadingMore = false;
    }
  }
}

final discoverControllerProvider =
    AsyncNotifierProvider<DiscoverController, List<DiscoverItem>>(
  DiscoverController.new,
);
