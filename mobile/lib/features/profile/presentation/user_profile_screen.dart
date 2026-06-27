import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/tag_chip.dart';
import '../../chat/data/threads_repository.dart';
import '../data/profile_repository.dart';

/// Public profile of another user, with Connect and Block actions.
class UserProfileScreen extends ConsumerWidget {
  const UserProfileScreen({super.key, required this.userId});

  final String userId;

  Future<void> _connect(BuildContext context, WidgetRef ref) async {
    final threadId = await ref.read(threadsRepositoryProvider).openThread(userId);
    if (context.mounted) context.push('/thread/$threadId');
  }

  Future<void> _block(BuildContext context, WidgetRef ref) async {
    await ref.read(profileRepositoryProvider).block(userId, report: false);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User blocked.')),
      );
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(publicProfileProvider(userId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'block') _block(context, ref);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'block', child: Text('Block & report')),
            ],
          ),
        ],
      ),
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load: $e')),
        data: (user) {
          final name = user.displayName ?? 'Someone';
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Center(
                child: CircleAvatar(
                  radius: 48,
                  backgroundImage: user.avatarUrl != null
                      ? NetworkImage(user.avatarUrl!)
                      : null,
                  child: user.avatarUrl == null
                      ? Text(
                          name.isNotEmpty
                              ? name.substring(0, 1).toUpperCase()
                              : '?',
                          style: const TextStyle(fontSize: 32),
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  name,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              if (user.bio != null && user.bio!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(user.bio!, textAlign: TextAlign.center),
              ],
              if (user.interestTags.isNotEmpty) ...[
                const SizedBox(height: 20),
                TagChipWrap(tags: user.interestTags),
              ],
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: () => _connect(context, ref),
                icon: const Icon(Icons.chat_bubble_outline),
                label: const Text('Connect'),
              ),
            ],
          );
        },
      ),
    );
  }
}
