import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/distance_badge.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/tag_chip.dart';
import '../application/events_controller.dart';
import '../data/events_repository.dart';

/// Nearby events list with inline RSVP.
class EventsScreen extends ConsumerWidget {
  const EventsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(nearbyEventsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Events')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(nearbyEventsProvider),
        child: eventsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            children: [
              SizedBox(
                height: MediaQuery.of(context).size.height * 0.7,
                child: ErrorRetry(
                  message: e.toString(),
                  onRetry: () => ref.invalidate(nearbyEventsProvider),
                ),
              ),
            ],
          ),
          data: (events) {
            if (events.isEmpty) {
              return ListView(
                children: [
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.7,
                    child: const EmptyState(
                      icon: Icons.event_busy,
                      title: 'No events nearby',
                      message: 'Be the first to host one in your area.',
                    ),
                  ),
                ],
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: events.length,
              itemBuilder: (context, i) {
                final e = events[i];
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                e.title,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            if (e.distanceM != null)
                              DistanceBadge(distanceM: e.distanceM!),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${e.attendeeCount} going'
                          '${e.capacity != null ? ' / ${e.capacity}' : ''}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        if (e.tags.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          TagChipWrap(tags: e.tags),
                        ],
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: _RsvpButton(eventId: e.id, current: e.myRsvp),
                        ),
                      ],
                    ),
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

class _RsvpButton extends ConsumerStatefulWidget {
  const _RsvpButton({required this.eventId, this.current});
  final String eventId;
  final String? current;

  @override
  ConsumerState<_RsvpButton> createState() => _RsvpButtonState();
}

class _RsvpButtonState extends ConsumerState<_RsvpButton> {
  late String? _status = widget.current;
  bool _busy = false;

  Future<void> _set(String status) async {
    setState(() => _busy = true);
    try {
      await ref.read(eventsRepositoryProvider).rsvp(widget.eventId, status);
      setState(() => _status = status);
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

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<String>(
      segments: const [
        ButtonSegment(value: 'going', label: Text('Going')),
        ButtonSegment(value: 'maybe', label: Text('Maybe')),
        ButtonSegment(value: 'no', label: Text('No')),
      ],
      selected: {if (_status != null) _status!},
      emptySelectionAllowed: true,
      onSelectionChanged:
          _busy ? null : (sel) => sel.isEmpty ? null : _set(sel.first),
    );
  }
}
