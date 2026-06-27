import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_config.dart';
import '../../profile/data/profile_repository.dart';
import '../application/onboarding_controller.dart';

/// Collects display name, bio, interest tags (max 10), and discovery radius.
class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  final _nameCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _selectedTags = <String>{};
  double _radiusM = AppConstants.radiusDefaultM;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  bool get _canSave => _nameCtrl.text.trim().isNotEmpty && !_saving;

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(profileRepositoryProvider).updateMe(
            displayName: _nameCtrl.text.trim(),
            bio: _bioCtrl.text.trim(),
            interestTags: _selectedTags.toList(),
            radiusM: _radiusM,
          );
      ref.invalidate(myProfileProvider);
      if (mounted) context.go('/onboarding/location');
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
      } else if (_selectedTags.length < AppConstants.maxUserTags) {
        _selectedTags.add(tag);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You can pick up to 10 interests.')),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final radiusKm = (_radiusM / 1000).toStringAsFixed(_radiusM < 1000 ? 1 : 0);
    return Scaffold(
      appBar: AppBar(title: const Text('Set up your profile')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(labelText: 'Display name'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _bioCtrl,
            maxLines: 3,
            maxLength: 500,
            decoration: const InputDecoration(
              labelText: 'Bio (optional)',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Interests (${_selectedTags.length}/${AppConstants.maxUserTags})',
            style: Theme.of(context).textTheme.titleMedium,
          ),
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
          const SizedBox(height: 24),
          Text(
            'Discovery radius: $radiusKm km',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Slider(
            value: _radiusM,
            min: AppConstants.radiusMinM,
            max: AppConstants.radiusMaxM,
            divisions: 99,
            label: '$radiusKm km',
            onChanged: (v) => setState(() => _radiusM = v),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _canSave ? _save : null,
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Continue'),
          ),
        ],
      ),
    );
  }
}
