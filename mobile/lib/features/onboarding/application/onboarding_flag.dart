import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kOnboardingCompleteKey = 'onboarding_complete';

/// Tracks whether the user has finished post-auth onboarding (profile + location
/// permission). Backed by SharedPreferences so it survives restarts.
class OnboardingFlag extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kOnboardingCompleteKey) ?? false;
  }

  Future<void> complete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kOnboardingCompleteKey, true);
    state = const AsyncData(true);
  }

  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kOnboardingCompleteKey);
    state = const AsyncData(false);
  }
}

final onboardingFlagProvider =
    AsyncNotifierProvider<OnboardingFlag, bool>(OnboardingFlag.new);
