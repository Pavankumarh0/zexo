import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_config.dart';
import '../../onboarding/data/auth_repository.dart';
import '../../onboarding/application/onboarding_flag.dart';
import '../../profile/application/visibility_controller.dart';
import '../../profile/data/profile_repository.dart';

/// Settings: discovery radius, visibility, account actions, privacy policy.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(myProfileProvider);
    final isVisible = ref.watch(visibilityControllerProvider).valueOrNull ?? true;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load: $e')),
        data: (profile) => ListView(
          children: [
            const _SectionHeader('Discovery'),
            _RadiusTile(initialRadiusM: profile.radiusM),
            SwitchListTile(
              title: const Text('Visible in discovery'),
              subtitle: Text(
                isVisible
                    ? 'People nearby can find you'
                    : 'You are hidden from discovery',
              ),
              value: isVisible,
              onChanged: (v) =>
                  ref.read(visibilityControllerProvider.notifier).setVisible(v),
            ),
            const Divider(),
            const _SectionHeader('Account'),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Log out'),
              onTap: () => ref.read(authRepositoryProvider).signOut(),
            ),
            ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: const Text('Privacy policy'),
              onTap: () => context.push('/privacy'),
            ),
            ListTile(
              leading: Icon(
                Icons.delete_forever,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                'Delete account',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onTap: () => _confirmDelete(context, ref),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete account?'),
        content: const Text(
          'This permanently erases your profile, location history, chats, and '
          'RSVPs within 24 hours. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(profileRepositoryProvider).deleteAccount();
    await ref.read(onboardingFlagProvider.notifier).reset();
    await ref.read(authRepositoryProvider).signOut();
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              letterSpacing: 1,
            ),
      ),
    );
  }
}

/// Radius slider that persists the chosen value on change-end.
class _RadiusTile extends ConsumerStatefulWidget {
  const _RadiusTile({required this.initialRadiusM});
  final double initialRadiusM;

  @override
  ConsumerState<_RadiusTile> createState() => _RadiusTileState();
}

class _RadiusTileState extends ConsumerState<_RadiusTile> {
  late double _radiusM = widget.initialRadiusM;

  @override
  Widget build(BuildContext context) {
    final km = (_radiusM / 1000).toStringAsFixed(_radiusM < 1000 ? 1 : 0);
    return ListTile(
      title: Text('Discovery radius: $km km'),
      subtitle: Slider(
        value: _radiusM,
        min: AppConstants.radiusMinM,
        max: AppConstants.radiusMaxM,
        divisions: 99,
        label: '$km km',
        onChanged: (v) => setState(() => _radiusM = v),
        onChangeEnd: (v) async {
          await ref.read(profileRepositoryProvider).updateMe(radiusM: v);
          ref.invalidate(myProfileProvider);
        },
      ),
    );
  }
}
