import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../../core/location/location_service.dart';
import '../application/onboarding_flag.dart';

/// Explains why Zexo needs location, then requests OS permission. Users who
/// decline can still proceed with city-level discovery (two-tier fallback).
class LocationPermissionScreen extends ConsumerStatefulWidget {
  const LocationPermissionScreen({super.key});

  @override
  ConsumerState<LocationPermissionScreen> createState() =>
      _LocationPermissionScreenState();
}

class _LocationPermissionScreenState
    extends ConsumerState<LocationPermissionScreen> {
  final _location = LocationService();
  bool _busy = false;

  Future<void> _request() async {
    setState(() => _busy = true);
    try {
      final p = await _location.requestPermission();
      if (p == LocationPermission.deniedForever) {
        await Geolocator.openAppSettings();
      }
    } finally {
      await _finish();
    }
  }

  Future<void> _finish() async {
    await ref.read(onboardingFlagProvider.notifier).complete();
    if (mounted) context.go('/discover');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Location')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Spacer(),
            Icon(Icons.explore, size: 96, color: scheme.primary),
            const SizedBox(height: 24),
            Text(
              'Discover what is near you',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Zexo uses your location to surface nearby people and events. '
              'Your exact position is never stored — coordinates are blurred by '
              'about 150 metres before they ever leave your device boundary.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const Spacer(),
            FilledButton(
              onPressed: _busy ? null : _request,
              child: _busy
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Allow location'),
            ),
            TextButton(
              onPressed: _busy ? null : _finish,
              child: const Text('Not now (use approximate area)'),
            ),
          ],
        ),
      ),
    );
  }
}
