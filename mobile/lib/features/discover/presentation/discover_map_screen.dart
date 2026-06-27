import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Map view of nearby people and events.
///
/// The Mapbox GL widget (fuzzy dot clusters, radius ring, tap-to-peek sheet) is
/// wired in here once a Mapbox token is provided via --dart-define=MAPBOX_TOKEN.
/// Until then this is a placeholder that keeps the app navigable.
class DiscoverMapScreen extends StatelessWidget {
  const DiscoverMapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Map'),
        leading: IconButton(
          icon: const Icon(Icons.view_agenda_outlined),
          tooltip: 'Card view',
          onPressed: () => context.pop(),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.map_outlined, size: 72, color: scheme.outline),
              const SizedBox(height: 16),
              Text(
                'Map view',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Provide a Mapbox token (MAPBOX_TOKEN) to enable the live map '
                'with fuzzy dot clusters and your discovery-radius ring.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
