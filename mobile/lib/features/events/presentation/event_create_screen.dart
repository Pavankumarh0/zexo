import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_config.dart';
import '../../../core/location/location_controller.dart';
import '../../onboarding/application/onboarding_controller.dart';
import '../application/events_controller.dart';
import '../data/events_repository.dart';

/// Create a geofenced event at the user's current location. Enforces the 5-tag
/// cap and start-before-end ordering (mirroring the server validation).
class EventCreateScreen extends ConsumerStatefulWidget {
  const EventCreateScreen({super.key});

  @override
  ConsumerState<EventCreateScreen> createState() => _EventCreateScreenState();
}

class _EventCreateScreenState extends ConsumerState<EventCreateScreen> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _capacityCtrl = TextEditingController();
  final _selectedTags = <String>{};
  double _radiusM = 500;
  String _visibility = 'public';
  DateTime _startsAt = DateTime.now().add(const Duration(hours: 1));
  DateTime _endsAt = DateTime.now().add(const Duration(hours: 3));
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _capacityCtrl.dispose();
    super.dispose();
  }

  bool get _valid =>
      _titleCtrl.text.trim().isNotEmpty && _startsAt.isBefore(_endsAt);

  Future<void> _pickDateTime({required bool isStart}) async {
    final initial = isStart ? _startsAt : _endsAt;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return;
    final dt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() {
      if (isStart) {
        _startsAt = dt;
        if (!_startsAt.isBefore(_endsAt)) {
          _endsAt = _startsAt.add(const Duration(hours: 2));
        }
      } else {
        _endsAt = dt;
      }
    });
  }

  Future<void> _submit() async {
    final fix = ref.read(locationControllerProvider);
    if (fix == null) {
      setState(() => _error = 'Waiting for your location. Try again shortly.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(eventsRepositoryProvider).create(
            title: _titleCtrl.text.trim(),
            description: _descCtrl.text.trim(),
            lat: fix.lat,
            lng: fix.lng,
            radiusM: _radiusM,
            capacity: int.tryParse(_capacityCtrl.text.trim()),
            tags: _selectedTags.toList(),
            visibility: _visibility,
            startsAt: _startsAt,
            endsAt: _endsAt,
          );
      ref.invalidate(nearbyEventsProvider);
      if (mounted) context.pop();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toggleTag(String tag) {
    setState(() {
      if (_selectedTags.contains(tag)) {
        _selectedTags.remove(tag);
      } else if (_selectedTags.length < AppConstants.maxEventTags) {
        _selectedTags.add(tag);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Up to 5 tags per event.')),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final km = (_radiusM / 1000).toStringAsFixed(_radiusM < 1000 ? 2 : 1);
    return Scaffold(
      appBar: AppBar(title: const Text('Create event')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _titleCtrl,
            decoration: const InputDecoration(labelText: 'Title'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Description (optional)',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _capacityCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Capacity (optional)'),
          ),
          const SizedBox(height: 16),
          _DateTimeRow(
            label: 'Starts',
            value: _startsAt,
            onTap: () => _pickDateTime(isStart: true),
          ),
          _DateTimeRow(
            label: 'Ends',
            value: _endsAt,
            onTap: () => _pickDateTime(isStart: false),
          ),
          const SizedBox(height: 16),
          Text('Geofence radius: $km km'),
          Slider(
            value: _radiusM,
            min: 50,
            max: AppConstants.radiusMaxM,
            divisions: 100,
            label: '$km km',
            onChanged: (v) => setState(() => _radiusM = v),
          ),
          const SizedBox(height: 8),
          Text('Tags (${_selectedTags.length}/${AppConstants.maxEventTags})'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tag in kInterestCatalog)
                FilterChip(
                  label: Text(tag),
                  selected: _selectedTags.contains(tag),
                  onSelected: (_) => _toggleTag(tag),
                ),
            ],
          ),
          const SizedBox(height: 16),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'public', label: Text('Public')),
              ButtonSegment(value: 'invite-only', label: Text('Invite-only')),
            ],
            selected: {_visibility},
            onSelectionChanged: (s) => setState(() => _visibility = s.first),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: (_valid && !_saving) ? _submit : null,
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Create event'),
          ),
          const SizedBox(height: 8),
          Text(
            'The event is placed at your current location.',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _DateTimeRow extends StatelessWidget {
  const _DateTimeRow({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final DateTime value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = '${value.year}-${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')} '
        '${value.hour.toString().padLeft(2, '0')}:'
        '${value.minute.toString().padLeft(2, '0')}';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.schedule),
      title: Text(label),
      subtitle: Text(text),
      trailing: const Icon(Icons.edit_calendar),
      onTap: onTap,
    );
  }
}
