import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/models/thread.dart';
import '../../../shared/widgets/empty_state.dart';
import '../data/threads_repository.dart';

/// List of active chat threads with expiry countdown chips and unread badges.
class ChatListScreen extends ConsumerWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final threadsAsync = ref.watch(threadsListProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Chats')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(threadsListProvider),
        child: threadsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            children: [
              SizedBox(
                height: MediaQuery.of(context).size.height * 0.7,
                child: ErrorRetry(
                  message: e.toString(),
                  onRetry: () => ref.invalidate(threadsListProvider),
                ),
              ),
            ],
          ),
          data: (threads) {
            if (threads.isEmpty) {
              return ListView(
                children: [
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.7,
                    child: EmptyState(
                      icon: Icons.forum_outlined,
                      title: 'No conversations yet',
                      message: 'Connect with someone nearby to start chatting.',
                      actionLabel: 'Discover people',
                      onAction: () => context.go('/discover'),
                    ),
                  ),
                ],
              );
            }
            return ListView.separated(
              itemCount: threads.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) => _ThreadTile(thread: threads[i]),
            );
          },
        ),
      ),
    );
  }
}

class _ThreadTile extends StatelessWidget {
  const _ThreadTile({required this.thread});
  final ThreadSummary thread;

  static String _fmtCountdown(Duration d) {
    if (d.inHours >= 1) return '${d.inHours}h left';
    if (d.inMinutes >= 1) return '${d.inMinutes}m left';
    return 'Expiring';
  }

  @override
  Widget build(BuildContext context) {
    final name = thread.peer.displayName ?? 'Someone';
    final left = thread.timeLeft(DateTime.now());
    return ListTile(
      leading: CircleAvatar(
        backgroundImage: thread.peer.avatarUrl != null
            ? NetworkImage(thread.peer.avatarUrl!)
            : null,
        child: thread.peer.avatarUrl == null
            ? Text(name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '?')
            : null,
      ),
      title: Text(name),
      subtitle: left != null
          ? Row(
              children: [
                const Icon(Icons.timer_outlined, size: 14),
                const SizedBox(width: 4),
                Text(_fmtCountdown(left)),
              ],
            )
          : null,
      trailing: thread.unreadCount > 0
          ? Badge(label: Text('${thread.unreadCount}'))
          : const Icon(Icons.chevron_right),
      onTap: () => context.push('/thread/${thread.id}'),
    );
  }
}
