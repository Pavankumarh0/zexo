import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/location/location_controller.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../chat/data/threads_repository.dart';
import '../../profile/application/visibility_controller.dart';
import '../application/discover_controller.dart';
import 'widgets/discover_card.dart';

/// The discovery cards feed. Auto-refreshes on >200m movement, supports
/// pull-to-refresh and infinite scroll, and exposes the invisible-mode toggle.
class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key});

  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen> {
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 300) {
      ref.read(discoverControllerProvider.notifier).loadMore();
    }
  }

  Future<void> _connect(String peerId) async {
    try {
      final threadId =
          await ref.read(threadsRepositoryProvider).openThread(peerId);
      if (mounted) context.push('/thread/$threadId');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not start chat: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Auto-refresh the feed when a new location fix moves us > 200m.
    ref.listen<LocationFix?>(locationControllerProvider, (prev, next) {
      if (next != null) {
        ref.read(discoverControllerProvider.notifier).maybeRefreshOnMove(next);
      }
    });

    final feed = ref.watch(discoverControllerProvider);
    final visibility = ref.watch(visibilityControllerProvider);
    final isVisible = visibility.valueOrNull ?? true;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Discover'),
        actions: [
          IconButton(
            tooltip: isVisible ? 'You are visible' : 'You are invisible',
            icon: Icon(isVisible ? Icons.visibility : Icons.visibility_off),
            onPressed: () =>
                ref.read(visibilityControllerProvider.notifier).toggle(),
          ),
          IconButton(
            tooltip: 'Map view',
            icon: const Icon(Icons.map_outlined),
            onPressed: () => context.push('/map'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () =>
            ref.read(discoverControllerProvider.notifier).refresh(),
        child: feed.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            children: [
              SizedBox(
                height: MediaQuery.of(context).size.height * 0.7,
                child: ErrorRetry(
                  message: e.toString(),
                  onRetry: () =>
                      ref.read(discoverControllerProvider.notifier).refresh(),
                ),
              ),
            ],
          ),
          data: (items) {
            if (items.isEmpty) {
              return ListView(
                children: [
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.7,
                    child: const EmptyState(
                      icon: Icons.person_search,
                      title: 'No one nearby yet',
                      message:
                          'Try widening your discovery radius in Settings, '
                          'or check back as you move around.',
                    ),
                  ),
                ],
              );
            }
            return ListView.builder(
              controller: _scrollCtrl,
              padding: const EdgeInsets.all(12),
              itemCount: items.length,
              itemBuilder: (context, i) {
                final item = items[i];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: DiscoverCard(
                    item: item,
                    onConnect: () => _connect(item.user.id),
                    onTap: () => context.push('/user/${item.user.id}'),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
