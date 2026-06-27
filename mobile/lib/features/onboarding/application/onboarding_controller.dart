import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_repository.dart';

/// State for the Google sign-in screen.
class OnboardingState {
  const OnboardingState({this.submitting = false, this.error});

  final bool submitting;
  final String? error;

  OnboardingState copyWith({
    bool? submitting,
    String? error,
    bool clearError = false,
  }) {
    return OnboardingState(
      submitting: submitting ?? this.submitting,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class OnboardingController extends Notifier<OnboardingState> {
  @override
  OnboardingState build() => const OnboardingState();

  AuthRepository get _auth => ref.read(authRepositoryProvider);

  /// Triggers Google sign-in. Returns true when a session is established,
  /// false if the user cancelled. Errors are surfaced via [state.error].
  Future<bool> signInWithGoogle() async {
    state = state.copyWith(submitting: true, clearError: true);
    try {
      final res = await _auth.signInWithGoogle();
      state = state.copyWith(submitting: false);
      return res?.session != null;
    } catch (e) {
      state = state.copyWith(submitting: false, error: _readable(e));
      return false;
    }
  }

  String _readable(Object e) {
    final msg = e.toString();
    return msg.length > 160 ? 'Could not sign in. Please try again.' : msg;
  }
}

final onboardingControllerProvider =
    NotifierProvider<OnboardingController, OnboardingState>(
  OnboardingController.new,
);

/// A small curated catalog of interest tags for selection during onboarding.
const kInterestCatalog = <String>[
  'music',
  'jazz',
  'film',
  'climbing',
  'running',
  'coffee',
  'art',
  'gaming',
  'food',
  'travel',
  'photography',
  'tech',
  'books',
  'yoga',
  'cycling',
  'dancing',
  'startups',
  'design',
  'football',
  'hiking',
];
