import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/chat/presentation/chat_list_screen.dart';
import '../../features/chat/presentation/chat_thread_screen.dart';
import '../../features/discover/presentation/discover_map_screen.dart';
import '../../features/discover/presentation/discover_screen.dart';
import '../../features/events/presentation/events_screen.dart';
import '../../features/onboarding/application/onboarding_flag.dart';
import '../../features/onboarding/presentation/auth_screen.dart';
import '../../features/onboarding/presentation/location_permission_screen.dart';
import '../../features/onboarding/presentation/profile_setup_screen.dart';
import '../../features/profile/presentation/user_profile_screen.dart';
import '../../features/settings/presentation/privacy_policy_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../providers.dart';
import 'go_router_refresh_stream.dart';

final _rootKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  final supabase = ref.watch(supabaseProvider);
  final refresh = GoRouterRefreshStream(supabase.auth.onAuthStateChange);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/discover',
    refreshListenable: refresh,
    redirect: (context, state) {
      final loggedIn = supabase.auth.currentSession != null;
      final onboarded = ref.read(onboardingFlagProvider).valueOrNull ?? false;
      final loc = state.matchedLocation;
      final inOnboarding = loc.startsWith('/onboarding');

      // Not signed in → force the auth screen.
      if (!loggedIn) {
        return loc == '/onboarding' ? null : '/onboarding';
      }

      // Signed in but profile/location not completed → onboarding sub-steps.
      if (loggedIn && !onboarded) {
        if (loc == '/onboarding/profile' || loc == '/onboarding/location') {
          return null;
        }
        return '/onboarding/profile';
      }

      // Signed in + onboarded but still on an onboarding/auth route → home.
      if (loggedIn && onboarded && inOnboarding) {
        return '/discover';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/onboarding',
        builder: (_, __) => const AuthScreen(),
        routes: [
          GoRoute(
            path: 'profile',
            builder: (_, __) => const ProfileSetupScreen(),
          ),
          GoRoute(
            path: 'location',
            builder: (_, __) => const LocationPermissionScreen(),
          ),
        ],
      ),

      // Full-screen detail routes (pushed over the shell).
      GoRoute(
        path: '/thread/:id',
        parentNavigatorKey: _rootKey,
        builder: (_, state) =>
            ChatThreadScreen(threadId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/user/:id',
        parentNavigatorKey: _rootKey,
        builder: (_, state) =>
            UserProfileScreen(userId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/map',
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const DiscoverMapScreen(),
      ),
      GoRoute(
        path: '/privacy',
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const PrivacyPolicyScreen(),
      ),

      // Bottom-navigation shell.
      StatefulShellRoute.indexedStack(
        builder: (_, __, shell) => _ShellScaffold(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/discover', builder: (_, __) => const DiscoverScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/events', builder: (_, __) => const EventsScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/chats', builder: (_, __) => const ChatListScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
            ],
          ),
        ],
      ),
    ],
  );
});

/// Scaffold hosting the indexed-stack shell + bottom navigation bar.
class _ShellScaffold extends StatelessWidget {
  const _ShellScaffold({required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) => shell.goBranch(
          i,
          initialLocation: i == shell.currentIndex,
        ),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore),
            label: 'Discover',
          ),
          NavigationDestination(
            icon: Icon(Icons.event_outlined),
            selectedIcon: Icon(Icons.event),
            label: 'Events',
          ),
          NavigationDestination(
            icon: Icon(Icons.forum_outlined),
            selectedIcon: Icon(Icons.forum),
            label: 'Chats',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
