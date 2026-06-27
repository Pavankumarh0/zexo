import 'package:flutter/material.dart';

/// A compact badge showing a human-friendly distance (e.g. "320 m", "1.2 km").
class DistanceBadge extends StatelessWidget {
  const DistanceBadge({super.key, required this.distanceM});

  final double distanceM;

  static String format(double meters) {
    if (meters < 1000) return '${meters.round()} m';
    final km = meters / 1000;
    return '${km.toStringAsFixed(km < 10 ? 1 : 0)} km';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.near_me, size: 14, color: scheme.onSecondaryContainer),
          const SizedBox(width: 4),
          Text(
            format(distanceM),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: scheme.onSecondaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}
