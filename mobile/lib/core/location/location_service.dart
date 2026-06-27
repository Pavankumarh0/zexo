import 'package:geolocator/geolocator.dart';

/// The source tier of a resolved position (Requirement 3.4 two-tier fallback).
enum LocationSource { gps, city, unknown }

class LocationFix {
  const LocationFix({
    required this.lat,
    required this.lng,
    required this.accuracyM,
    required this.source,
  });

  final double lat;
  final double lng;
  final double accuracyM;
  final LocationSource source;
}

/// Wraps geolocator for permission handling and a two-tier (precise GPS →
/// city-level) position resolution. Raw coordinates are only ever sent to the
/// backend, which fuzzes them ±150m before storage.
class LocationService {
  Future<LocationPermission> checkPermission() => Geolocator.checkPermission();

  Future<bool> isServiceEnabled() => Geolocator.isLocationServiceEnabled();

  Future<LocationPermission> requestPermission() =>
      Geolocator.requestPermission();

  /// Whether we currently hold precise/approximate location permission.
  Future<bool> hasPermission() async {
    final p = await Geolocator.checkPermission();
    return p == LocationPermission.always || p == LocationPermission.whileInUse;
  }

  /// Resolve the best available position. Falls back from precise GPS to a
  /// lower-accuracy (city-level) fix when a high-accuracy fix is unavailable.
  Future<LocationFix?> getCurrent() async {
    if (!await hasPermission()) return null;
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      return _fix(pos, LocationSource.gps);
    } catch (_) {
      // Fall back to a coarse/last-known position (city tier).
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) return _fix(last, LocationSource.city);
      return null;
    }
  }

  LocationFix _fix(Position pos, LocationSource source) {
    return LocationFix(
      lat: pos.latitude,
      lng: pos.longitude,
      accuracyM: pos.accuracy,
      source: source,
    );
  }

  /// Metres between two fixes (used to decide when to refresh the feed).
  double distanceBetween(LocationFix a, LocationFix b) {
    return Geolocator.distanceBetween(a.lat, a.lng, b.lat, b.lng);
  }
}
