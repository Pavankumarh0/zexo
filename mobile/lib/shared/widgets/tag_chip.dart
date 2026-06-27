import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// An interest tag chip. Shared interests are highlighted in blue per the design.
class TagChip extends StatelessWidget {
  const TagChip({super.key, required this.label, this.shared = false});

  final String label;
  final bool shared;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = shared
        ? AppTheme.highlightBlue.withValues(alpha: 0.14)
        : scheme.surfaceContainerHighest;
    final fg = shared ? AppTheme.highlightBlue : scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: shared
            ? Border.all(color: AppTheme.highlightBlue.withValues(alpha: 0.4))
            : null,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: shared ? FontWeight.w700 : FontWeight.w500,
          color: fg,
        ),
      ),
    );
  }
}

/// A wrap of [TagChip]s, highlighting any tag present in [sharedTags].
class TagChipWrap extends StatelessWidget {
  const TagChipWrap({
    super.key,
    required this.tags,
    this.sharedTags = const [],
  });

  final List<String> tags;
  final List<String> sharedTags;

  @override
  Widget build(BuildContext context) {
    final sharedSet = sharedTags.toSet();
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final tag in tags)
          TagChip(label: tag, shared: sharedSet.contains(tag)),
      ],
    );
  }
}
