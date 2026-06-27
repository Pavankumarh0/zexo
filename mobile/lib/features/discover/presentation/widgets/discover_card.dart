import 'package:flutter/material.dart';

import '../../../../shared/models/discover_item.dart';
import '../../../../shared/widgets/distance_badge.dart';
import '../../../../shared/widgets/tag_chip.dart';

/// A single discovery feed card: avatar, name, distance badge, and interest tags
/// with shared interests highlighted.
class DiscoverCard extends StatelessWidget {
  const DiscoverCard({
    super.key,
    required this.item,
    required this.onConnect,
    required this.onTap,
  });

  final DiscoverItem item;
  final VoidCallback onConnect;
  final VoidCallback onTap;

  static String _initial(String name) =>
      name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '?';

  @override
  Widget build(BuildContext context) {
    final user = item.user;
    final name = user.displayName ?? 'Someone nearby';
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundImage: user.avatarUrl != null
                        ? NetworkImage(user.avatarUrl!)
                        : null,
                    child: user.avatarUrl == null
                        ? Text(_initial(name))
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: Theme.of(context).textTheme.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        DistanceBadge(distanceM: item.distanceM),
                      ],
                    ),
                  ),
                ],
              ),
              if (user.bio != null && user.bio!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  user.bio!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
              if (user.interestTags.isNotEmpty) ...[
                const SizedBox(height: 12),
                TagChipWrap(
                  tags: user.interestTags,
                  sharedTags: item.sharedTags,
                ),
              ],
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonalIcon(
                  onPressed: onConnect,
                  icon: const Icon(Icons.chat_bubble_outline, size: 18),
                  label: const Text('Connect'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
