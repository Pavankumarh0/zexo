import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/event.dart';
import '../../../shared/widgets/tag_chip.dart';
import '../application/events_controller.dart';
import '../data/events_repository.dart';

/// Event detail with description, time window, attendee count, and RSVP.
class EventDetailScreen extends ConsumerWidget {
  const EventDetailScreen({super.key, required this.eventId});

  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(eventByIdProvider(eventId));
    return Scaffold(
      appBar: AppBar(title: const Text('Event')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load: $e')),
        data: (event) => _EventBody(event: event),
      ),
    );
  }
}

class _EventBody extends ConsumerStatefulWidget {
  const _EventBody({required this.event});
  final EventModel event;

  @override
  ConsumerState<_EventBody> createState() => _EventBodyState();
}

class _EventBodyState extends ConsumerState<_EventBody> {
  late String? _status = widget.event.myRsvp;
  bool _busy = false;

  Future<void> _rsvp(String status) async {
    setState(() => _busy = true);
    try {
      await ref.read(eventsRepositoryProvider).rsvp(widget.event.id, status);
      setState(() => _status = status);
      ref.invalidate(eventByIdProvider(widget.event.id));
      ref.invalidate(nearbyEventsProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('RSVP failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _fmt(DateTime dt) {
    final d = dt.toLocal();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.event;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(e.title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Row(
          children: [
            const Icon(Icons.people_outline, size: 18),
            const SizedBox(width: 6),
            Text(
              '${e.attendeeCount} going'
              '${e.capacity != null ? ' / ${e.capacity}' : ''}',
            ),
          ],
        ),
        const SizedBox(height: 12),
        _InfoRow(icon: Icons.play_arrow, label: 'Starts', value: _fmt(e.startsAt)),
        _InfoRow(icon: Icons.stop, label: 'Ends', value: _fmt(e.endsAt)),
        _InfoRow(
          icon: Icons.my_location,
          label: 'Geofence',
          value: '${(e.radiusM / 1000).toStringAsFixed(2)} km radius',
        ),
        if (e.description != null && e.description!.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(e.description!),
        ],
        if (e.tags.isNotEmpty) ...[
          const SizedBox(height: 16),
          TagChipWrap(tags: e.tags),
        ],
        const SizedBox(height: 24),
        Text('Your RSVP', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'going', label: Text('Going')),
            ButtonSegment(value: 'maybe', label: Text('Maybe')),
            ButtonSegment(value: 'no', label: Text('No')),
          ],
          selected: {if (_status != null) _status!},
          emptySelectionAllowed: true,
          onSelectionChanged: _busy
              ? null
              : (sel) => sel.isEmpty ? null : _rsvp(sel.first),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w600)),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
